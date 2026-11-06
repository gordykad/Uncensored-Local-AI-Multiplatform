import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'model_classifier.dart';

import '../models/ai_model_info.dart';
import '../models/download_state.dart';
import 'background_download_service.dart';
import 'wakelock_service.dart';

/// Manages model catalog, downloads, and local file discovery.
class ModelManager extends GetxService {
  final catalog = <AiModelInfo>[].obs;
  final downloadedModels =
      <String>[].obs; // filenames on-disk (list for reactivity)

  // ── Download tracking (single reactive object) ─────────────
  final activeDownloads = <String, DownloadState>{}.obs;
  final tick = 0.obs; // force UI refresh counter

  http.Client? _httpClient;
  late String _modelsDir;

  Future<ModelManager> init() async {
    _modelsDir = await _getModelsDir();
    await _loadCatalog();
    await scanDownloaded();
    _adoptOrphanFiles();
    if (Platform.isIOS) await _adoptBackgroundDownloads();
    // Ticket 25: one-time classification pass over the existing
    // library (untagged custom records only), off the startup path.
    unawaited(classifyLibraryOnce());
    return this;
  }

  /// Resolve models directory.
  Future<String> _getModelsDir() async {
    // Only check USB path on desktop platforms
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      try {
        final execDir = Platform.resolvedExecutable;
        final usbShared = p.join(
          p.dirname(p.dirname(execDir)),
          'Shared',
          'models',
        );
        if (await Directory(usbShared).exists()) {
          return usbShared;
        }
      } catch (_) {
        // Ignore errors resolving executable path
      }
    }

    // Fall back to app documents
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = p.join(appDir.path, 'PortableAI', 'models');
    await Directory(modelsDir).create(recursive: true);
    return modelsDir;
  }

  String get modelsDir => _modelsDir;

  /// Force all Obx listeners to rebuild.
  void _notifyUI() {
    tick.value++;
  }

  /// Load the embedded model catalog from assets + persisted custom models.
  Future<void> _loadCatalog() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/models_catalog.json');
      final list = jsonDecode(jsonStr) as List;
      catalog.value = list
          .map((j) => AiModelInfo.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Catalog couldn't load — will be empty
    }

    // Load persisted custom models
    try {
      final box = Hive.box('models_meta');
      final customList =
          box.get('custom_models', defaultValue: <dynamic>[]) as List;
      for (final raw in customList) {
        final model = AiModelInfo.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
        // Don't add duplicates
        if (!catalog.any((m) => m.id == model.id)) {
          catalog.add(model);
        }
      }
    } catch (_) {}

    // Ticket 25: Kai's hand-filed collections for catalog models
    // (per-device tag overrides) ride on top of the shipped tags.
    try {
      final box = Hive.box('models_meta');
      final overrides = Map<String, dynamic>.from(
        box.get('tag_overrides', defaultValue: <String, dynamic>{}) as Map,
      );
      for (var i = 0; i < catalog.length; i++) {
        final o = overrides[catalog[i].filename];
        if (o is Map && !catalog[i].isCustom) {
          final m = Map<String, dynamic>.from(o);
          catalog[i] = catalog[i].copyWith(
            tags: (m['tags'] as List?)?.map((e) => e.toString()).toList(),
            tagsSource: m['tagsSource'] as String? ?? 'manual',
            label: m['label'] as String?,
          );
        }
      }
    } catch (_) {}
  }

  /// Register any .gguf on disk that has no catalog record as a
  /// custom model. Heals the records the 1.15 label bug dropped
  /// (file present, record gone) and adopts files copied in by
  /// hand. Runs after the catalog + custom load, before the
  /// classification pass, so adoptees get classified too.
  void _adoptOrphanFiles() {
    var adopted = false;
    for (final filename in downloadedModels) {
      if (catalog.any((m) => m.filename == filename)) continue;
      var sizeGb = 0.0;
      try {
        sizeGb = File(p.join(_modelsDir, filename)).lengthSync() / 1073741824;
      } catch (_) {}
      catalog.add(
        AiModelInfo(
          id: 'custom_adopted_$filename',
          name: filename.replaceAll(
            RegExp(r'\.gguf$', caseSensitive: false),
            '',
          ),
          filename: filename,
          url: 'local',
          sizeGb: sizeGb,
          minRamGb: 0,
          label: 'CUSTOM',
          badge: 'LOCAL',
          systemPrompt: 'You are a helpful AI assistant.',
        ),
      );
      adopted = true;
    }
    if (adopted) _persistCustomModels();
  }

  /// Scan the models directory for downloaded .gguf files.
  Future<void> scanDownloaded() async {
    final dir = Directory(_modelsDir);
    if (!await dir.exists()) return;

    final files = await dir
        .list()
        .where((f) => f is File && f.path.endsWith('.gguf'))
        .map((f) => p.basename(f.path))
        .toList();

    downloadedModels.value = files;
  }

  String getModelPath(AiModelInfo model) => p.join(_modelsDir, model.filename);
  String getModelPathByFilename(String filename) =>
      p.join(_modelsDir, filename);
  bool isModelDownloaded(AiModelInfo model) =>
      downloadedModels.contains(model.filename);

  /// Is this model currently downloading?
  bool isDownloading(String filename) {
    return activeDownloads.containsKey(filename) &&
        activeDownloads[filename]!.isActive;
  }

  /// Get the download state for a model (or null).
  DownloadState? getDownloadState(String filename) {
    return activeDownloads[filename];
  }

  // ── Background downloads (ticket 05, iOS) ──────────────────
  // The transfer itself runs in the native background URLSession;
  // Dart only mirrors its status into DownloadState for the UI and
  // resolves the future downloadModel() is awaiting.
  final _bgTimers = <String, Timer>{};
  final _bgDone = <String, void Function(String? error)>{};
  final _bgLastBytes = <String, int>{};
  final _bgLastTick = <String, DateTime>{};

  /// Adopt transfers the native session kept running while the app
  /// was suspended or killed (called from init on iOS).
  Future<void> _adoptBackgroundDownloads() async {
    final statuses = await BackgroundDownloadService.allStatuses();
    for (final entry in statuses.entries) {
      final status = entry.value['status'] as String? ?? 'none';
      if (status == 'completed' || status == 'failed') {
        // A completed file is already in the models dir and was
        // picked up by scanDownloaded; just clear the bookkeeping.
        await BackgroundDownloadService.ack(entry.key);
      } else if (status == 'downloading') {
        activeDownloads[entry.key] = DownloadState(
          filename: entry.key,
          totalBytes: (entry.value['total'] as num?)?.toDouble() ?? 0,
          receivedBytes: (entry.value['received'] as num?)?.toDouble() ?? 0,
        );
        _startBackgroundPoll(entry.key);
      }
    }
    if (statuses.isNotEmpty) _notifyUI();
  }

  Future<void> _downloadModelBackground(AiModelInfo model) async {
    if (!BackgroundDownloadService.isImportScopeUrl(model.url)) {
      throw const FormatException(
        'Model downloads are limited to Hugging Face and GitHub links.',
      );
    }

    try {
      Get.find<WakelockService>().enableForDownload(modelName: model.name);
    } catch (_) {}

    activeDownloads[model.filename] = DownloadState(
      filename: model.filename,
      totalBytes: model.sizeGb * 1024 * 1024 * 1024,
    );
    _notifyUI();

    final completer = Completer<void>();
    _bgDone[model.filename] = (error) {
      if (completer.isCompleted) return;
      if (error != null) {
        completer.completeError(Exception(error));
      } else {
        completer.complete();
      }
    };

    await BackgroundDownloadService.start(
      url: model.url,
      filename: model.filename,
      destDir: _modelsDir,
      displayName: model.name,
    );
    _startBackgroundPoll(model.filename);
    await completer.future;
  }

  void _startBackgroundPoll(String filename) {
    _bgLastBytes[filename] =
        activeDownloads[filename]?.receivedBytes.toInt() ?? 0;
    _bgLastTick[filename] = DateTime.now();
    _bgTimers[filename] = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_pollBackgroundOnce(filename));
    });
  }

  Future<void> _pollBackgroundOnce(String filename) async {
    final st = await BackgroundDownloadService.status(filename);
    if (st == null) return;
    final status = st['status'] as String? ?? 'none';
    final state = activeDownloads[filename];

    if (status == 'downloading') {
      final received = (st['received'] as num?)?.toInt() ?? 0;
      final total = (st['total'] as num?)?.toInt() ?? 0;
      if (state != null) {
        final now = DateTime.now();
        final lastAt = _bgLastTick[filename];
        final lastBytes = _bgLastBytes[filename] ?? 0;
        if (lastAt != null) {
          final dt = now.difference(lastAt).inMilliseconds / 1000;
          if (dt > 0) {
            state.speedBytesPerSec = (received - lastBytes) / dt;
          }
        }
        _bgLastTick[filename] = now;
        _bgLastBytes[filename] = received;
        state.receivedBytes = received.toDouble();
        if (total > 0) state.totalBytes = total.toDouble();
      }
      _notifyUI();
      return;
    }

    // Terminal: completed, failed, or vanished (external cancel).
    _bgTimers.remove(filename)?.cancel();
    _bgLastBytes.remove(filename);
    _bgLastTick.remove(filename);
    await BackgroundDownloadService.ack(filename);

    String? error;
    if (status == 'completed') {
      await scanDownloaded();
      // Models added by link classify at add time, when the file
      // does not exist yet; the header refine belongs here.
      unawaited(refineCustomModel(filename));
    } else if (status == 'failed') {
      error = (st['error'] as String?) ?? 'Download failed';
    } else {
      // Vanished (external cancel, task purged): never a success.
      error = 'Download did not complete';
    }
    if (state != null) state.isActive = false;
    activeDownloads.remove(filename);
    _notifyUI();

    final done = _bgDone.remove(filename);
    done?.call(error);

    if (activeDownloads.isEmpty) {
      try {
        await Get.find<WakelockService>().disable();
      } catch (_) {}
    }
  }

  /// Download a model with real-time speed tracking.
  /// Enables wake lock + foreground service to keep download alive.
  Future<void> downloadModel(AiModelInfo model) async {
    if (isDownloading(model.filename)) return;

    // Ticket 05: on iOS the system carries the transfer (background
    // URLSession) so it survives the app being suspended or closed.
    if (Platform.isIOS) {
      await _downloadModelBackground(model);
      return;
    }

    // Enable wake lock + foreground service for download (fire and forget so UI updates instantly)
    WakelockService? wakelockService;
    try {
      wakelockService = Get.find<WakelockService>();
      wakelockService.enableForDownload(modelName: model.name);
    } catch (e) {
      debugPrint('WakelockService not available: $e');
    }

    // Initialize download state instantly
    activeDownloads[model.filename] = DownloadState(
      filename: model.filename,
      totalBytes: model.sizeGb * 1024 * 1024 * 1024,
    );
    _notifyUI();

    final filePath = getModelPath(model);
    final partFile = File('$filePath.part');

    try {
      _httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(model.url));

      // Support resume
      int existingBytes = 0;
      if (await partFile.exists()) {
        existingBytes = await partFile.length();
        request.headers['Range'] = 'bytes=$existingBytes-';
      }

      final response = await _httpClient!.send(request);
      final contentLength = response.contentLength ?? 0;
      final totalBytes = (existingBytes + contentLength).toDouble();

      // Update total from actual HTTP response
      final state = activeDownloads[model.filename]!;
      state.totalBytes = totalBytes > 0 ? totalBytes : state.totalBytes;
      state.receivedBytes = existingBytes.toDouble();

      final sink = partFile.openWrite(
        mode: existingBytes > 0 ? FileMode.append : FileMode.write,
      );

      int receivedBytes = existingBytes;
      final stopwatch = Stopwatch()..start();
      int lastSpeedCheck = 0;
      int lastSpeedBytes = existingBytes;

      await for (final chunk in response.stream) {
        // Check if cancelled
        if (state.isCancelled) break;

        sink.add(chunk);
        receivedBytes += chunk.length;
        state.receivedBytes = receivedBytes.toDouble();

        // Calculate speed every 500ms
        if (stopwatch.elapsedMilliseconds - lastSpeedCheck > 500) {
          final elapsed =
              (stopwatch.elapsedMilliseconds - lastSpeedCheck) / 1000;
          final bytesDelta = receivedBytes - lastSpeedBytes;
          state.speedBytesPerSec = bytesDelta / elapsed;
          lastSpeedCheck = stopwatch.elapsedMilliseconds;
          lastSpeedBytes = receivedBytes;
          _notifyUI(); // trigger rebuild

          // Update foreground notification with progress
          if (wakelockService != null && state.totalBytes > 0) {
            final progress = state.receivedBytes / state.totalBytes;
            final speedMb = (state.speedBytesPerSec / (1024 * 1024))
                .toStringAsFixed(1);
            wakelockService.updateDownloadProgress(
              modelName: model.name,
              progress: progress,
              speedText: '$speedMb MB/s',
            );
          }
        }
      }

      await sink.flush();
      await sink.close();

      if (!state.isCancelled) {
        // Rename .part to final
        await partFile.rename(filePath);
        if (!downloadedModels.contains(model.filename)) {
          downloadedModels.add(model.filename);
        }
      }

      state.isActive = false;
      activeDownloads.remove(model.filename);
      _notifyUI();
    } catch (e) {
      activeDownloads[model.filename]?.isActive = false;
      activeDownloads.remove(model.filename);
      _notifyUI();
      rethrow;
    } finally {
      _httpClient?.close();
      _httpClient = null;

      // Disable wake lock if no other downloads are active
      if (activeDownloads.isEmpty) {
        try {
          await wakelockService?.disable();
        } catch (_) {}
      }
    }
  }

  /// Cancel an active download.
  void cancelDownload(String filename) {
    // Ticket 05: cancel the native background task on iOS.
    if (Platform.isIOS && _bgTimers.containsKey(filename)) {
      unawaited(BackgroundDownloadService.cancel(filename));
      _bgTimers.remove(filename)?.cancel();
      _bgLastBytes.remove(filename);
      _bgLastTick.remove(filename);
      activeDownloads.remove(filename);
      _notifyUI();
      final done = _bgDone.remove(filename);
      done?.call('Download cancelled');
      return;
    }
    if (activeDownloads.containsKey(filename)) {
      activeDownloads[filename]!.isCancelled = true;
      activeDownloads[filename]!.isActive = false;
    }
    _httpClient?.close();
    _httpClient = null;
    activeDownloads.remove(filename);
    _notifyUI();
  }

  /// Delete a downloaded model.
  Future<void> deleteModel(String filename) async {
    final file = File(p.join(_modelsDir, filename));
    if (await file.exists()) {
      await file.delete();
    }
    downloadedModels.remove(filename);
  }

  /// Move a model file from cache to the models directory (instant on most file systems).
  Future<void> moveModel(String sourcePath, String filename) async {
    final destPath = p.join(_modelsDir, filename);
    if (sourcePath == destPath) return;

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    // Try to move the file instantly (rename)
    try {
      await sourceFile.rename(destPath);
    } catch (e) {
      // Fallback to copy if rename fails (e.g. across different partitions)
      await sourceFile.copy(destPath);
      await sourceFile.delete();
    }

    if (!downloadedModels.contains(filename)) {
      downloadedModels.add(filename);
    }
  }

  /// Import a model directly from a stream (useful to bypass FilePicker caching on Android/iOS).
  Future<void> importModelFromStream({
    required String filename,
    required Stream<List<int>> stream,
    required int totalBytes,
    Function(double)? onProgress,
    bool Function()? checkCancelled,
  }) async {
    final destPath = p.join(_modelsDir, filename);
    final destFile = File(destPath);

    final sink = destFile.openWrite();
    int copiedBytes = 0;
    bool wasCancelled = false;

    try {
      final mappedStream = stream.map((chunk) {
        if (checkCancelled?.call() == true) {
          throw const FormatException('CANCELLED');
        }
        copiedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(copiedBytes / totalBytes);
        }
        return chunk;
      });
      await sink.addStream(mappedStream);
    } on FormatException catch (e) {
      if (e.message == 'CANCELLED') {
        wasCancelled = true;
      } else {
        rethrow;
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (wasCancelled) {
      if (await destFile.exists()) {
        await destFile.delete();
      }
      return;
    }

    if (!downloadedModels.contains(filename)) {
      downloadedModels.add(filename);
    }
  }

  /// Import a model file from external path with progress tracking.
  Future<void> importModel(
    String sourcePath, {
    Function(double)? onProgress,
    bool Function()? checkCancelled,
  }) async {
    final filename = p.basename(sourcePath);
    final destPath = p.join(_modelsDir, filename);

    if (sourcePath != destPath) {
      final sourceFile = File(sourcePath);
      final destFile = File(destPath);

      final totalBytes = await sourceFile.length();
      if (totalBytes == 0) return;

      final sourceStream = sourceFile.openRead();
      final sink = destFile.openWrite();

      int copiedBytes = 0;
      bool wasCancelled = false;

      try {
        final mappedStream = sourceStream.map((chunk) {
          if (checkCancelled?.call() == true) {
            throw const FormatException('CANCELLED');
          }
          copiedBytes += chunk.length;
          onProgress?.call(copiedBytes / totalBytes);
          return chunk;
        });
        await sink.addStream(mappedStream);
      } on FormatException catch (e) {
        if (e.message == 'CANCELLED') {
          wasCancelled = true;
        } else {
          rethrow;
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (wasCancelled) {
        if (await destFile.exists()) {
          await destFile.delete();
        }
        return;
      }
    }

    if (!downloadedModels.contains(filename)) {
      downloadedModels.add(filename);
    }
  }

  /// Add custom model to catalog and persist it. Ticket 25: the
  /// record is classified on arrival (filename heuristics now, a
  /// GGUF header refine pass right after via refineCustomModel).
  void addCustomModel(AiModelInfo model) {
    catalog.add(ModelClassifier.apply(model));
    _persistCustomModels();
    refineCustomModel(model.filename);
  }

  /// Ticket 25 refine pass: read the model's own GGUF header and
  /// re-derive its clean name + tags from real metadata. Runs on
  /// arrival and once over the existing library at startup.
  /// Manual records are never touched; fully local, no network.
  Future<void> refineCustomModel(String filename) async {
    final idx = catalog.indexWhere((m) => m.filename == filename);
    if (idx == -1) return;
    final model = catalog[idx];
    if (!model.isCustom || model.tagsSource == 'manual') return;
    final file = File(p.join(_modelsDir, filename));
    if (!await file.exists()) return;
    final header = await readGgufHeader(file);
    // The awaits above and below can interleave with a manual
    // tag filing; re-read the record before writing anything.
    final freshIdx = catalog.indexWhere((m) => m.filename == filename);
    if (freshIdx == -1) return;
    final fresh = catalog[freshIdx];
    if (!fresh.isCustom || fresh.tagsSource == 'manual') return;
    var hasMmproj = false;
    try {
      final stem = filename
          .replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '')
          .toLowerCase();
      await for (final f in Directory(_modelsDir).list()) {
        if (f is File) {
          final b = p.basename(f.path).toLowerCase();
          if (b.contains('mmproj') &&
              (b.startsWith('mmproj') ||
                  stem.startsWith(b.split('-mmproj').first) ||
                  b.startsWith(stem))) {
            hasMmproj = true;
            break;
          }
        }
      }
    } catch (_) {}
    final refined = ModelClassifier.apply(
      fresh,
      header: header,
      hasMmproj: hasMmproj,
    );
    if (refined.name != fresh.name ||
        refined.tags.join() != fresh.tags.join() ||
        refined.label != fresh.label) {
      catalog[freshIdx] = refined;
      _persistCustomModels();
      _notifyUI();
    }
  }

  /// Ticket 25 one-time library pass: classify every custom model
  /// that has no tags yet (records from before this build).
  Future<void> classifyLibraryOnce() async {
    for (final m in catalog.toList()) {
      if (m.isCustom && m.tags.isEmpty && m.tagsSource != 'manual') {
        await refineCustomModel(m.filename);
      }
    }
  }

  /// Ticket 25 (Kai, 1.16.1): put a model into collections by hand
  /// from the long-press menu. Collections ARE the capability tags:
  /// adding a tag files the model into that folder. Works for
  /// catalog models too — theirs persist as per-device overrides
  /// in models_meta. The record is marked manual either way, so
  /// the classifier never overwrites Kai's filing.
  void setModelTags(AiModelInfo model, List<String> tags) {
    final updated = model.copyWith(
      tags: tags,
      tagsSource: 'manual',
      // Custom labels are persistence keys; they never move.
      label: model.isCustom
          ? model.label
          : (tags.contains('uncensored')
                ? 'UNCENSORED'
                : (model.label == 'UNCENSORED' ? 'STANDARD' : model.label)),
    );
    if (model.isCustom) {
      updateCustomModel(updated);
      return;
    }
    final idx = catalog.indexWhere((m) => m.id == model.id);
    if (idx != -1) catalog[idx] = updated;
    final box = Hive.box('models_meta');
    final overrides = Map<String, dynamic>.from(
      box.get('tag_overrides', defaultValue: <String, dynamic>{}) as Map,
    );
    overrides[model.filename] = {
      'tags': tags,
      'tagsSource': 'manual',
      'label': updated.label,
    };
    box.put('tag_overrides', overrides);
    _notifyUI();
  }

  /// Replace a custom model's persisted record (ticket 20: attach or fix
  /// the download source of an imported model without touching its file).
  void updateCustomModel(AiModelInfo updated) {
    final idx = catalog.indexWhere((m) => m.id == updated.id);
    if (idx == -1) return;
    catalog[idx] = updated;
    _persistCustomModels();
  }

  /// Remove a custom model from catalog and persistence.
  void removeCustomModel(String id) {
    catalog.removeWhere((m) => m.id == id);
    _persistCustomModels();
  }

  /// Save all custom models to Hive.
  void _persistCustomModels() {
    final box = Hive.box('models_meta');
    final customList = catalog
        .where((m) => m.isCustom)
        .map((m) => m.toJson())
        .toList();
    box.put('custom_models', customList);
  }

  @override
  void onClose() {
    _httpClient?.close();
    super.onClose();
  }
}
