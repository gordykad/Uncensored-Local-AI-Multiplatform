import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;

import 'wakelock_service.dart';
import 'memory_probe.dart';
import 'chat_storage_service.dart';
import 'log_service.dart';

/// Wraps llamadart's LlamaEngine for model loading, generation, and lifecycle.
class LlmService extends GetxService {
  LlamaEngine? _engine;
  LlamaBackend? _backend;

  final isLoaded = false.obs;
  final isGenerating = false.obs;
  final loadedModelPath = ''.obs;
  final tokensPerSecond = 0.0.obs;
  final lastGenerationTokens = 0.obs;
  final lastGenerationSpeed = 0.0.obs;

  // ── Fixed meter (ticket 01) ────────────────────────────────
  // The V1 counter started its stopwatch before prompt build + prefill
  // and counted stream chunks, so its figures are NOT comparable to
  // these (a 26B run that displayed "~0.0 tok/s" really decoded at
  // ~0.05 tok/s end-to-end). Here: the watch starts when the engine
  // stream is subscribed; time to the first event is prefill (TTFT);
  // events after it are decode, rated as (events-1) over the
  // first-to-last window.
  final lastPromptTokens = 0.obs;
  final lastTtftMs = 0.obs;
  final lastPrefillTps = 0.0.obs;
  final lastDecodeTps = 0.0.obs;
  final lastMeterSummary = ''.obs;

  // ── Loading progress tracking ──────────────────────────────
  final isLoadingModel = false.obs;
  final loadingProgress = 0.0.obs; // 0.0 to 1.0
  final loadingStatusMsg = ''.obs;
  bool _loadingCancelled = false;

  StreamSubscription? _generateSub;

  String get loadedModelFilename {
    final path = loadedModelPath.value;
    if (path.isEmpty) return '';
    return p.basename(path);
  }

  String get publicModelId {
    final filename = loadedModelFilename;
    if (filename.isEmpty) return 'local';
    final stem = filename.toLowerCase().endsWith('.gguf')
        ? filename.substring(0, filename.length - 5)
        : p.basenameWithoutExtension(filename);
    return stem
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Initialize the service.
  Future<LlmService> init() async {
    // Backend is created fresh per loadModel() call — no init needed here
    return this;
  }

  /// Cancel an in-progress model load.
  void cancelLoading() {
    _loadingCancelled = true;
  }

  /// Load a GGUF model from [path] with progress tracking.
  Future<void> loadModel(String path) async {
    LogService? log;
    try { log = Get.find<LogService>(); } catch (_) {}

    // Verify file exists first
    final file = File(path);
    if (!await file.exists()) {
      log?.error('Model file not found: $path', source: 'LLM');
      throw Exception('Model file not found: $path');
    }

    final filename = p.basename(path);
    log?.info('Loading model: $filename', source: 'LLM');
    final headBefore = await MemoryProbe.availableBytes();
    if (headBefore != null) {
      log?.info(
        'Memory headroom before load: ${(headBefore / 1073741824).toStringAsFixed(2)} GB',
        source: 'LLM',
      );
    }

    _loadingCancelled = false;
    isLoadingModel.value = true;
    loadingProgress.value = 0.0;
    loadingStatusMsg.value = 'Preparing...';

    // Enable wake lock during model loading (heavy memory operation)
    WakelockService? wakelockService;
    try {
      wakelockService = Get.find<WakelockService>();
    } catch (_) {}

    // Unload previous if any — MUST fully tear down engine + backend
    if (_engine != null || isLoaded.value) {
      loadingStatusMsg.value = 'Unloading previous model...';
      loadingProgress.value = 0.05;
      await _fullTeardown();
      // Give native side time to release resources
      await Future.delayed(const Duration(milliseconds: 500));
      if (_loadingCancelled) {
        _resetLoadingState();
        return;
      }
    }

    // Fresh backend + engine for every load — prevents stale native state
    // Wrapped in try-catch to handle SELinux crashes on Android where
    // ggml_backend_load_all() attempts to scan '/' which is denied.
    try {
      _backend = LlamaBackend();
      _engine = LlamaEngine(_backend!);
    } catch (e) {
      _backend = null;
      _engine = null;
      _resetLoadingState();
      log?.error('Engine init failed: $e', source: 'LLM');
      throw Exception(
        'Failed to initialize AI engine. '
        'This may be a device compatibility issue. '
        'Error: $e',
      );
    }

    try {
      loadingStatusMsg.value = 'Loading into memory...';
      loadingProgress.value = 0.1;

      // Get file size for display
      final fileSize = await file.length();
      final sizeGb = (fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1);
      loadingStatusMsg.value = 'Loading $sizeGb GB into memory...';

      // Start a timer to animate progress while loading
      Timer? progressTimer;
      progressTimer = Timer.periodic(const Duration(milliseconds: 300), (
        timer,
      ) {
        if (_loadingCancelled) {
          timer.cancel();
          return;
        }
        // Gradually increase progress (asymptotic approach to 0.95)
        final current = loadingProgress.value;
        if (current < 0.95) {
          loadingProgress.value = current + (0.95 - current) * 0.04;
        }
      });

      if (_loadingCancelled) {
        progressTimer.cancel();
        await _fullTeardown();
        _resetLoadingState();
        return;
      }

      // Context size (ticket 03 knob): a stored value wins; 0 keeps the
      // platform default - smaller on Android to prevent OOM kills from
      // the Low Memory Killer (LMK), 2048 elsewhere.
      final storage = Get.find<ChatStorageService>();
      final contextSize = storage.contextSize > 0
          ? storage.contextSize
          : (Platform.isAndroid ? 1024 : 2048);

      // Map the string backend to GpuBackend enum. 'metal' and 'auto'
      // are mapped since ticket 03a - llamadart has shipped both all
      // along, but the old switch silently forced every unlisted value
      // to CPU, and the storage default was 'cpu' besides.
      GpuBackend parsedBackend;
      switch (storage.backendType) {
        case 'vulkan':
          parsedBackend = GpuBackend.vulkan;
          break;
        case 'opencl':
          parsedBackend = GpuBackend.opencl;
          break;
        case 'metal':
          parsedBackend = GpuBackend.metal;
          break;
        case 'auto':
          parsedBackend = GpuBackend.auto;
          break;
        default:
          parsedBackend = GpuBackend.cpu;
      }

      // Read gpu layers
      final userGpuLayers = storage.gpuLayers;

      // Ticket 03a: with a GPU backend selected, a stored layer count of
      // 0 means "not configured" - resolve it as "offload whatever
      // fits": resident models (weights fit inside the current headroom
      // with margin left for KV cache + compute buffers) get every
      // layer on the GPU; oversized models (the streamed-MoE class)
      // stay on CPU until ticket 11's hybrid profile rules on them.
      var effectiveGpuLayers = userGpuLayers;
      if ((parsedBackend == GpuBackend.metal ||
              parsedBackend == GpuBackend.auto) &&
          userGpuLayers == 0) {
        final avail = await MemoryProbe.availableBytes();
        if (avail != null && fileSize <= avail * 0.75) {
          effectiveGpuLayers = 999;
        }
      }

      // Threads (ticket 03 knob): a stored value wins; 0 keeps the
      // legacy auto rule (4 when the device has >4 processors, else 0).
      final threads = storage.threadCount > 0
          ? storage.threadCount
          : (Platform.numberOfProcessors > 4 ? 4 : 0);
      // B2 (ticket 10): flash attention ON for CPU loads — the named
      // prefill lever vs the 1.50 tok/s / TTFT 8.0s / 22.3 tok/s prefill
      // baseline measured in B1. GPU backends keep auto.
      // B3: the stored flash knob now resolves the mode — 'on' keeps
      // the B2 rule above exactly (the A/B baseline), 'auto' and 'off'
      // apply across backends.
      final flash = switch (storage.flashAttentionMode) {
        'off' => FlashAttention.disabled,
        'auto' => FlashAttention.auto,
        _ => parsedBackend == GpuBackend.cpu
            ? FlashAttention.enabled
            : FlashAttention.auto,
      };
      final params = ModelParams(
        contextSize: contextSize,
        gpuLayers: effectiveGpuLayers,
        preferredBackend: parsedBackend,
        numberOfThreads: threads,
        numberOfThreadsBatch: threads,
        flashAttention: flash,
      );

      log?.info('Backend=$parsedBackend, GPU layers=$effectiveGpuLayers (stored $userGpuLayers), ctx=$contextSize, threads=$threads', source: 'LLM');

      // B2: loadModel() is deprecated in llamadart 0.17.x — setModel is
      // the migration target (same fresh-engine-per-load pattern).
      await _engine!.setModel(
        LlamaModel(ModelSource.path(path)),
        params: params,
      );
      progressTimer.cancel();

      if (_loadingCancelled) {
        // User cancelled while loading — full cleanup
        await _fullTeardown();
        _resetLoadingState();
        return;
      }

      loadingProgress.value = 1.0;
      loadingStatusMsg.value = 'Ready!';
      isLoaded.value = true;
      loadedModelPath.value = path;
      log?.info('Model loaded successfully: $filename', source: 'LLM');
      final headAfter = await MemoryProbe.availableBytes();
      if (headAfter != null) {
        log?.info(
          'Memory headroom after load: ${(headAfter / 1073741824).toStringAsFixed(2)} GB',
          source: 'LLM',
        );
      }

      // Enable wake lock for inference on mobile (keeps app from being killed)
      final modelName = p.basenameWithoutExtension(path);
      await wakelockService?.enableForInference(modelName: modelName);

      // Brief delay to show 100%
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      isLoaded.value = false;
      loadedModelPath.value = '';
      await _fullTeardown();
      log?.error('Model load failed: $e', source: 'LLM');

      // Provide a clearer error message for common Android failures
      if (Platform.isAndroid) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('memory') || errStr.contains('alloc')) {
          throw Exception(
            'Not enough RAM to load this model. '
            'Try a smaller model (e.g. Gemma 2 2B at 1.6 GB).',
          );
        }
      }
      rethrow;
    } finally {
      _resetLoadingState();
    }
  }

  void _resetLoadingState() {
    isLoadingModel.value = false;
    loadingProgress.value = 0.0;
    loadingStatusMsg.value = '';
    _loadingCancelled = false;
  }

  /// Tokens/patterns the model may emit that should be stripped from output.
  /// Covers ChatML, Llama, Gemma, Phi, Mistral, and other common formats.
  static final _stopPatterns = RegExp(
    r'<\|end\|>'
    r'|<\|eot_id\|>'
    r'|<\|endoftext\|>'
    r'|<\|im_end\|>'
    r'|<\|im_start\|>'
    r'|<end_of_turn>'
    r'|<start_of_turn>'
    r'|<\|channel\|>'
    r'|<channel\|>'
    r'|<\|assistant\|>'
    r'|<\|user\|>'
    r'|<\|system\|>'
    r'|<\|pad\|>'
    r'|</s>'
    r'|<s>'
    r'|\[INST\]'
    r'|\[/INST\]'
    r'|\[end\]',
  );

  /// Pattern that signals the model is hallucinating a new user turn — stop immediately.
  static final _userTurnPattern = RegExp(
    r'<\|user\|>|<\|im_start\|>\s*user|<start_of_turn>\s*user|\[INST\]',
  );

  /// Generate a chat completion using llamadart's chat-template API.
  ///
  /// Ticket 04 (B3): this is now THE chat path — the hand-rolled Phi-3
  /// prompt builder is retired. The engine renders each model's own
  /// GGUF chat template, so end-of-turn formats are the model's own
  /// (the old path's prime suspect for the <|channel> leak and the
  /// tail-repetition loops). Prompt tokens are counted on the RENDERED
  /// template — the string the engine actually prefills — never on
  /// summed message contents (Claude UPDATE 3: content sums understate
  /// prefill and poison the METER).
  ///
  /// With [backstop] on (the chat path), emitted text is held behind a
  /// 30-char window and scanned for leaked template markers; a hit is
  /// logged as BACKSTOP HIT and ends the stream on the pre-match text.
  /// It is a logged safety net only — the template path is the fix.
  /// The API path leaves it off (the engine already separates the
  /// Gemma reasoning channel from content there).
  Stream<String> generateChatCompletion({
    required List<LlamaChatMessage> messages,
    GenerationParams params = const GenerationParams(),
    bool backstop = false,
  }) async* {
    if (_engine == null || !isLoaded.value) {
      throw StateError('No model loaded. Call loadModel() first.');
    }
    if (isGenerating.value) {
      throw StateError('Another generation is already in progress.');
    }

    isGenerating.value = true;
    tokensPerSecond.value = 0.0;

    // Render once: the same string feeds the token count and the
    // TEMPLATE inspectability log (ticket 04 acceptance #1).
    String? rendered;
    try {
      rendered = (await _engine!.chatTemplate(messages)).prompt;
    } catch (_) {
      rendered = null;
    }
    var promptTokens = 0;
    if (rendered != null) {
      promptTokens = await countTokens(rendered);
    } else {
      for (final m in messages) {
        promptTokens += await countTokens(m.content);
      }
    }
    if (backstop) {
      try {
        final log = Get.find<LogService>();
        log.info(
          'TEMPLATE model=$loadedModelFilename '
          'chars=${rendered?.length ?? -1} tokens=$promptTokens',
          source: 'CHAT',
        );
        if (rendered != null) log.info(rendered, source: 'TEMPLATE');
      } catch (_) {}
    }

    final genWatch = Stopwatch()..start();
    int eventCount = 0;
    int? firstEventMs;
    var buffer = '';
    var hitBackstop = false;

    try {
      await for (final chunk in _engine!.create(
        messages,
        params: params,
        toolChoice: ToolChoice.none,
      )) {
        final choice = chunk.choices.isNotEmpty ? chunk.choices.first : null;
        final content = choice?.delta.content;
        if (content == null || content.isEmpty) continue;

        final nowMs = genWatch.elapsedMilliseconds;
        firstEventMs ??= nowMs;
        eventCount++;
        final decodeMs = nowMs - (firstEventMs ?? nowMs);
        if (eventCount > 1 && decodeMs > 0) {
          tokensPerSecond.value = (eventCount - 1) / (decodeMs / 1000);
        }

        if (!backstop) {
          yield content;
          continue;
        }

        buffer += content;
        final userHit = _userTurnPattern.hasMatch(buffer);
        if (userHit || _stopPatterns.hasMatch(buffer)) {
          hitBackstop = true;
          try {
            Get.find<LogService>().info(
              'BACKSTOP HIT pattern=${userHit ? 'user-turn' : 'stop-marker'} '
              'model=$loadedModelFilename',
              source: 'CHAT',
            );
          } catch (_) {}
          final cleaned = buffer
              .replaceAll(_stopPatterns, '')
              .replaceAll(_userTurnPattern, '')
              .trim();
          if (cleaned.isNotEmpty) yield cleaned;
          break;
        }
        // Hold back the last 30 chars so a marker split across chunks
        // is still caught whole.
        if (buffer.length > 40) {
          final safe = buffer.substring(0, buffer.length - 30);
          buffer = buffer.substring(buffer.length - 30);
          yield safe;
        }
      }

      if (backstop && !hitBackstop && buffer.isNotEmpty) {
        final cleaned = buffer
            .replaceAll(_stopPatterns, '')
            .replaceAll(_userTurnPattern, '')
            .trim();
        if (cleaned.isNotEmpty) yield cleaned;
      }
    } finally {
      genWatch.stop();
      _finishMeter(genWatch, promptTokens, eventCount, firstEventMs);
      isGenerating.value = false;
    }
  }

  /// Token count of the RENDERED chat template for [messages] — the
  /// honest prefill figure for usage accounting (ticket 04 / Claude
  /// UPDATE 3). Falls back to summed content counts when the template
  /// cannot be rendered.
  Future<int> countPromptTokens(List<LlamaChatMessage> messages) async {
    if (_engine == null || !isLoaded.value) return 0;
    try {
      final rendered = (await _engine!.chatTemplate(messages)).prompt;
      return await countTokens(rendered);
    } catch (_) {
      var sum = 0;
      for (final m in messages) {
        sum += await countTokens(m.content);
      }
      return sum;
    }
  }

  /// Close out one generation's fixed-meter measurements (ticket 01):
  /// decode tok/s from the first-to-last event window, prefill tok/s from
  /// prompt tokens over TTFT, both written to the diagnostics log so any
  /// speed claim on any device can be checked against a METER line.
  void _finishMeter(
    Stopwatch watch,
    int promptTokens,
    int events,
    int? firstEventMs,
  ) {
    final totalMs = watch.elapsedMilliseconds;
    final ttftMs = firstEventMs ?? totalMs;
    final decodeMs = totalMs - ttftMs;
    final decodeTps = (events > 1 && decodeMs > 0)
        ? (events - 1) / (decodeMs / 1000)
        : 0.0;
    final prefillTps = (promptTokens > 0 && ttftMs > 0)
        ? promptTokens / (ttftMs / 1000)
        : 0.0;
    lastPromptTokens.value = promptTokens;
    lastTtftMs.value = ttftMs;
    lastPrefillTps.value = prefillTps;
    lastDecodeTps.value = decodeTps;
    lastGenerationTokens.value = events;
    lastGenerationSpeed.value = decodeTps;
    tokensPerSecond.value = decodeTps;
    lastMeterSummary.value =
        'prompt $promptTokens tok - TTFT ${ttftMs}ms - '
        'prefill ${prefillTps.toStringAsFixed(1)} tok/s - '
        'decode $events tok @ ${decodeTps.toStringAsFixed(2)} tok/s - '
        'total ${totalMs}ms';
    try {
      Get.find<LogService>().info(
        'METER model=$loadedModelFilename promptTok=$promptTokens '
        'ttftMs=$ttftMs prefillTps=${prefillTps.toStringAsFixed(2)} '
        'decodeTok=$events decodeTps=${decodeTps.toStringAsFixed(3)} '
        'totalMs=$totalMs',
        source: 'METER',
      );
    } catch (_) {}
  }

  Future<int> countTokens(String text) async {
    if (_engine == null || !isLoaded.value) return 0;
    try {
      return await _engine!.getTokenCount(text);
    } catch (_) {
      return 0;
    }
  }

  /// Stop ongoing generation.
  Future<void> stopGeneration() async {
    _generateSub?.cancel();
    _generateSub = null;
    _engine?.cancelGeneration();
    isGenerating.value = false;
  }

  /// Full native teardown — dispose engine AND backend to prevent stale state.
  Future<void> _fullTeardown() async {
    if (_engine != null) {
      try {
        await _engine!.dispose();
      } catch (_) {
        // Engine may already be in broken state — ignore
      }
      _engine = null;
    }
    // Also destroy the backend — it can't be reused after engine disposal
    _backend = null;
    isLoaded.value = false;
    loadedModelPath.value = '';
    tokensPerSecond.value = 0.0;
  }

  /// Unload the current model and free memory.
  Future<void> unloadModel() async {
    await _fullTeardown();

    // Disable wake lock when model is unloaded
    try {
      final wakelockService = Get.find<WakelockService>();
      await wakelockService.disable();
    } catch (_) {}
  }

  @override
  void onClose() {
    unloadModel();
    super.onClose();
  }
}
