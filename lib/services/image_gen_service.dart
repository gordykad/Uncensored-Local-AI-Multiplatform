// Ticket 28: image-generation lanes.
//
// Lane B 'owner'  - third-party Gradio Spaces via the queue API. $0/gen.
// Lane A 'runpod' - Kai's own RunPod serverless endpoint. KAI-ONLY
//   (Amendment 9): entries + key live in the on-device 'imagegen' Hive box
//   only - never synced, never seeded for anyone else, never pinned.
//
// Entries are local-first (Hive). Pinned entries (Amendment 10) are read
// from the shared config on GitHub - the read side ships here; pinning
// flags an entry locally and the flag is mirrored into that config.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/image_entry.dart';

class ImageGenResult {
  final List<int> bytes;
  final int? seed;
  const ImageGenResult(this.bytes, this.seed);
}

/// One persisted generation for the Previous Gens gallery (Kai,
/// 2026-11-04). The PNG lives in the app documents /images folder;
/// this record is its index entry in the 'imagegen' Hive box.
class GenRecord {
  final String file;
  final String prompt;
  final int? seed;
  final String model;
  final int ts; // epoch ms
  const GenRecord({
    required this.file,
    required this.prompt,
    this.seed,
    required this.model,
    required this.ts,
  });

  Map<String, dynamic> toMap() => {
        'file': file,
        'prompt': prompt,
        'seed': seed,
        'model': model,
        'ts': ts,
      };

  factory GenRecord.fromMap(Map m) => GenRecord(
        file: m['file'] as String,
        prompt: (m['prompt'] ?? '') as String,
        seed: (m['seed'] as num?)?.toInt(),
        model: (m['model'] ?? '') as String,
        ts: ((m['ts'] ?? 0) as num).toInt(),
      );
}

class ImageGenService {
  static const configUrl =
      'https://raw.githubusercontent.com/gordykad/minix-config/main/imagegen.json';
  static const seedSpaceLink =
      'https://huggingface.co/spaces/a-test-user-in-the-wrold/qwen-image-21-uncensored';
  static const seedRunpodLink = 'abenzerps/Qwen-Image-2.1-Uncensored-GGUF';

  Box get _box => Hive.box('imagegen');
  Box get _settings => Hive.box('settings');

  bool get connectivityOn =>
      _settings.get('connectivity_enabled', defaultValue: true) == true;
  set connectivityOn(bool v) => _settings.put('connectivity_enabled', v);

  String get runpodEndpoint =>
      _box.get('runpod_endpoint', defaultValue: '') as String;
  String get runpodKey => _box.get('runpod_key', defaultValue: '') as String;
  void setRunpod(String endpoint, String key) {
    _box.put('runpod_endpoint', endpoint.trim());
    _box.put('runpod_key', key.trim());
  }

  bool get runpodReady => runpodEndpoint.isNotEmpty && runpodKey.isNotEmpty;

  // ── Generation history (Previous Gens gallery) ─────────────
  /// Bumped on every history change; the gallery tab listens.
  static final historyRevision = ValueNotifier<int>(0);

  List<GenRecord> history() {
    final raw = _box.get('history');
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => GenRecord.fromMap(m))
        .toList();
  }

  /// Persist a finished generation (PNG to app files + index
  /// record). Never throws: a history write must not fail the
  /// generation itself.
  Future<GenRecord?> recordGeneration({
    required List<int> bytes,
    required String prompt,
    int? seed,
    required String model,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/images');
      if (!await folder.exists()) await folder.create(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final f = File('${folder.path}/gen_$ts.png');
      await f.writeAsBytes(bytes);
      final rec = GenRecord(
          file: f.path, prompt: prompt, seed: seed, model: model, ts: ts);
      final list = history()..insert(0, rec);
      // Cap the gallery at 200; evict the oldest files with them.
      while (list.length > 200) {
        final old = list.removeLast();
        try {
          await File(old.file).delete();
        } catch (_) {}
      }
      await _box.put('history', list.map((r) => r.toMap()).toList());
      historyRevision.value++;
      return rec;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteGeneration(GenRecord rec) async {
    try {
      await File(rec.file).delete();
    } catch (_) {}
    final list = history()..removeWhere((r) => r.file == rec.file);
    await _box.put('history', list.map((r) => r.toMap()).toList());
    historyRevision.value++;
  }

  List<ImageEntry> localEntries() {
    final raw = _box.get('entries');
    if (raw == null) {
      // First run: seed both lanes. The runpod seed is just a repo pointer -
      // it cannot spend anything until Kai adds HIS endpoint + key.
      final seeds = [
        ImageEntry(
          id: 'seed-qwen-space',
          name: 'Qwen Image 2.1 Uncensored',
          link: seedSpaceLink,
          lane: 'owner',
          createdMs: DateTime.now().millisecondsSinceEpoch,
        ),
        ImageEntry(
          id: 'seed-qwen-runpod',
          name: 'Qwen Image 2.1 GGUF (RunPod)',
          link: seedRunpodLink,
          lane: 'runpod',
          createdMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ];
      _box.put('entries', seeds.map((e) => e.toMap()).toList());
      return seeds;
    }
    return (raw as List)
        .map((m) => ImageEntry.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  void _save(List<ImageEntry> entries) =>
      _box.put('entries', entries.map((e) => e.toMap()).toList());

  void addEntry(ImageEntry e) {
    final all = localEntries()..add(e);
    _save(all);
  }

  void removeEntry(String id) {
    final all = localEntries()..removeWhere((e) => e.id == id);
    _save(all);
  }

  void setPinned(String id, bool pinned) {
    final all = localEntries()
        .map((e) => e.id == id ? e.copyWith(pinned: pinned) : e)
        .toList();
    _save(all);
  }

  /// Pinned entries published by Kai, read from the shared config.
  /// Silent on any failure (offline, no config yet, bad JSON).
  Future<List<ImageEntry>> fetchPinned() async {
    try {
      final r = await http
          .get(Uri.parse(configUrl))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return [];
      final d = jsonDecode(r.body);
      final list = (d is Map ? d['entries'] : d) as List? ?? [];
      return list
          .map((m) => ImageEntry.fromMap(
                Map<String, dynamic>.from(m as Map),
                remote: true,
              ))
          // The config can only ever carry the free lane (Amendment 9).
          .where((e) => !e.isRunpod)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Link paste normalization (Kai's order 2026-11-04): whatever shape the
  /// paste arrives in - a full huggingface.co URL, a bare user/model path,
  /// a URL with a /tree/... tail - it becomes the canonical form the
  /// validator, the store and the worker all expect.
  static String normalizeRepoLink(String raw) {
    var l = raw.trim();
    l = l.replaceFirst(RegExp(r'^https?://'), '');
    l = l.replaceFirst(RegExp(r'^(www\.)?huggingface\.co/'), '');
    l = l.replaceFirst(RegExp(r'^api/models/'), '');
    for (final cut in ['/tree/', '/blob/', '/resolve/']) {
      final i = l.indexOf(cut);
      if (i > 0) l = l.substring(0, i);
    }
    if (l.contains('?')) l = l.split('?').first;
    if (l.contains('#')) l = l.split('#').first;
    while (l.endsWith('/')) {
      l = l.substring(0, l.length - 1);
    }
    return l;
  }

  static String normalizeSpaceLink(String raw) {
    var l = raw.trim();
    if (!l.contains('huggingface.co') && !l.contains('.hf.space')) {
      // Bare user/space paste becomes the canonical Space page URL.
      final parts = l
          .replaceFirst(RegExp(r'^https?://'), '')
          .split('/')
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length == 2) {
        return 'https://huggingface.co/spaces/${parts[0]}/${parts[1]}';
      }
      return l;
    }
    if (!l.startsWith('http')) l = 'https://$l';
    if (l.contains('?')) l = l.split('?').first;
    if (l.contains('#')) l = l.split('#').first;
    while (l.endsWith('/')) {
      l = l.substring(0, l.length - 1);
    }
    final sp = l.indexOf('/spaces/');
    if (sp >= 0) {
      final rest = l.substring(sp + '/spaces/'.length).split('/');
      if (rest.length > 2) {
        l = l.substring(0, sp + '/spaces/'.length) + '${rest[0]}/${rest[1]}';
      }
    }
    return l;
  }

  static String normalizeLink(String lane, String raw) =>
      lane == 'runpod' ? normalizeRepoLink(raw) : normalizeSpaceLink(raw);

  /// Add-time validation. Returns an error string, or the resolved gradio
  /// endpoint path for owner entries.
  Future<(String?, String, int)> validate(String lane, String link) async {
    link = normalizeLink(lane, link);
    if (lane == 'runpod') {
      try {
        final r = await http
            .get(Uri.parse('https://huggingface.co/api/models/${link.trim()}'))
            .timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) {
          return ('Hugging Face repo not found (HTTP ${r.statusCode})', '', 0);
        }
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final sibs = (d['siblings'] as List? ?? [])
            .map((s) => (s as Map)['rfilename']?.toString() ?? '')
            .toList();
        // Lane A backends: a GGUF diffusion model (Qwen graph) or a
        // standalone SDXL checkpoint - a .safetensors that is not one of
        // the diffusers-layout parts. The worker routes by the same rule.
        const skipPrefixes = [
          'text_encoders/',
          'text_encoder/',
          'text_encoder_2/',
          'vae/',
          'unet/',
          'loras/',
        ];
        final hasGguf = sibs.any((f) => f.endsWith('.gguf'));
        final hasCheckpoint = sibs.any((f) =>
            f.endsWith('.safetensors') &&
            !skipPrefixes.any((p) => f.startsWith(p)));
        if (!hasGguf && !hasCheckpoint) {
          return ('That repo has no .gguf model and no standalone '
              '.safetensors checkpoint in it', '', 0);
        }
        return (null, '', 0);
      } catch (e) {
        return ('Could not reach Hugging Face: $e', '', 0);
      }
    }
    // owner lane: probe the Space's gradio API
    final probe = ImageEntry(
        id: 'probe', name: 'probe', link: link, lane: 'owner', createdMs: 0);
    try {
      final r = await http
          .get(Uri.parse('${probe.gradioBase}/gradio_api/info'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        return ('Space API answered HTTP ${r.statusCode} - is it running?', '', 0);
      }
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final named = (d['named_endpoints'] as Map?) ?? {};
      if (named.isEmpty) return ('That Space exposes no API endpoints', '', 0);
      final names = named.keys.map((k) => k.toString()).toList();
      final ep = names.contains('/generate') ? '/generate' : names.first;
      return (null, ep, names.indexOf(ep));
    } catch (e) {
      return ('Could not reach that Space: $e', '', 0);
    }
  }

  /// Lane B generation: the classic Gradio queue protocol - join
  /// with fn_index + session_hash, then read the queue/data stream.
  /// Verified live against a Gradio 6 Space on 2026-11-03 (the /call
  /// route and a session-less join both fail on current Gradio).
  Future<ImageGenResult> generateOwner(
    ImageEntry e, {
    required String prompt,
    String size = '1024x1024 (1:1)',
    int steps = 28,
    void Function(String phase)? onPhase,
  }) async {
    final base = e.gradioBase;
    final rng = Random.secure();
    final sessionHash = List.generate(
        16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    onPhase?.call('Joining the queue');
    final join = await http
        .post(
          Uri.parse('$base/gradio_api/queue/join'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'data': [prompt, size, steps, 0, true, 1.0],
            'fn_index': e.fnIndex,
            'session_hash': sessionHash,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (join.statusCode != 200) {
      throw Exception(
          'Space refused the job (HTTP ${join.statusCode}): ${_short(join.body)}');
    }

    onPhase?.call('In queue');
    final client = http.Client();
    try {
      final req = http.Request(
        'GET',
        Uri.parse('$base/gradio_api/queue/data?session_hash=$sessionHash'),
      );
      final resp =
          await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw Exception('Queue stream failed (HTTP ${resp.statusCode})');
      }
      final lines = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(minutes: 10));
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        Map<String, dynamic> msg;
        try {
          msg = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        switch (msg['msg']) {
          case 'estimation':
            final rank = msg['rank'];
            onPhase?.call(rank is num && rank > 0
                ? 'In queue (position ${rank.toInt() + 1})'
                : 'In queue');
          case 'process_starts':
            onPhase?.call('Generating');
          case 'process_completed':
            if (msg['success'] != true) {
              final err = (msg['output'] as Map?)?['error'];
              throw Exception(err != null
                  ? 'That Space reported an error: $err'
                  : 'That Space failed to generate. Its backend may be down.');
            }
            final out = (msg['output'] as Map)['data'] as List;
            if (out.isEmpty) {
              throw Exception('Generation finished with no image');
            }
            final file = Map<String, dynamic>.from(out[0] as Map);
            final seed =
                out.length > 1 && out[1] is num ? (out[1] as num).toInt() : null;
            onPhase?.call('Fetching image');
            final bytes = await _fetchGradioFile(base, file);
            return ImageGenResult(bytes, seed);
          case 'unexpected_error':
            throw Exception(
                'That Space reported an error: ${msg['message'] ?? 'unknown'}');
        }
      }
    } finally {
      client.close();
    }
    throw Exception('The queue stream ended before the image arrived');
  }

  static String _short(String s) =>
      s.length <= 140 ? s : '${s.substring(0, 140)}...';

  Future<List<int>> _fetchGradioFile(
      String base, Map<String, dynamic> file) async {
    final url = file['url']?.toString();
    final path = file['path']?.toString();
    Uri uri;
    if (url != null && url.startsWith('http')) {
      uri = Uri.parse(url);
    } else if (path != null && path.isNotEmpty) {
      uri = Uri.parse('$base/gradio_api/file=$path');
    } else {
      throw Exception('Image result had no file reference');
    }
    final r = await http.get(uri).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      throw Exception('Image download failed (HTTP ${r.statusCode})');
    }
    return r.bodyBytes;
  }

  /// Lane A generation: Kai's RunPod serverless endpoint.
  /// Worker contract (ticket 28): input {prompt, width, height, steps, seed,
  /// model} -> output {images: [base64]} or {image_url}.
  Future<ImageGenResult> generateRunpod(
    ImageEntry e, {
    required String prompt,
    int width = 1024,
    int height = 1024,
    int steps = 28,
    void Function(String phase)? onPhase,
  }) async {
    if (!runpodReady) {
      throw Exception(
          'Add your RunPod endpoint ID and API key in Image Gen settings first');
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $runpodKey',
    };
    onPhase?.call('Waking your endpoint');
    final run = await http
        .post(
          Uri.parse('https://api.runpod.ai/v2/$runpodEndpoint/run'),
          headers: headers,
          body: jsonEncode({
            'input': {
              'prompt': prompt,
              'width': width,
              'height': height,
              'steps': steps,
              'seed': 0,
              'model': normalizeRepoLink(e.link),
            },
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (run.statusCode != 200) {
      throw Exception('RunPod answered HTTP ${run.statusCode}');
    }
    final jobId = (jsonDecode(run.body) as Map<String, dynamic>)['id'];
    if (jobId == null) throw Exception('RunPod returned no job id');

    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 3));
      final st = await http
          .get(
            Uri.parse('https://api.runpod.ai/v2/$runpodEndpoint/status/$jobId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));
      if (st.statusCode != 200) continue;
      final d = jsonDecode(st.body) as Map<String, dynamic>;
      switch (d['status']) {
        case 'IN_QUEUE':
          onPhase?.call('In queue');
        case 'IN_PROGRESS':
          onPhase?.call('Generating on your GPU');
        case 'COMPLETED':
          final out = d['output'] as Map<String, dynamic>?;
          if (out == null) throw Exception('RunPod finished with no output');
          final imgs = out['images'] as List?;
          if (imgs != null && imgs.isNotEmpty) {
            return ImageGenResult(base64Decode(imgs[0].toString()), null);
          }
          final u = out['image_url']?.toString();
          if (u != null && u.isNotEmpty) {
            final r =
                await http.get(Uri.parse(u)).timeout(const Duration(seconds: 60));
            if (r.statusCode == 200) return ImageGenResult(r.bodyBytes, null);
          }
          throw Exception('RunPod output had no image');
        case 'FAILED':
          throw Exception('RunPod job failed: ${d['error'] ?? 'unknown error'}');
        case 'CANCELLED':
          throw Exception('RunPod job was cancelled');
      }
    }
    throw Exception('RunPod job timed out after 10 minutes');
  }
}
