import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/ai_model_info.dart';
import 'image_gen_service.dart';

/// Ticket 30 - fleet model pins.
///
/// Kai pins a model on his phone; the pin publishes into the shared
/// config (gordykad/minix-config, models.json) and every tester's
/// Models screen shows a Pinned section. Downloading stays each
/// person's own choice (ticket 05 engine); unpinning removes the
/// OFFER, never a downloaded copy.
///
/// V1 write path mirrors ticket 28: the app flags pins locally and
/// they are mirrored into models.json; in-app publish rides ticket
/// 06's write side when it lands. Fleet read path is live now.
class ModelPinsService {
  static const configUrl =
      'https://raw.githubusercontent.com/gordykad/minix-config/main/models.json';
  static const _flagKey = 'pinned_model_filenames';

  bool get connectivityOn => ImageGenService().connectivityOn;

  /// Pinned models from the shared config, as catalog-shaped entries.
  /// Empty when connectivity is off or the fetch fails - silently,
  /// the fleet screen just has no Pinned section (offline law).
  Future<List<AiModelInfo>> fetchPinned() async {
    if (!connectivityOn) return [];
    try {
      final r = await http
          .get(Uri.parse(configUrl))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return [];
      final decoded = jsonDecode(r.body) as Map<String, dynamic>;
      final list = decoded['pinned'] as List? ?? [];
      return list.map((raw) {
        final m = Map<String, dynamic>.from(raw as Map);
        final sizeBytes = (m['sizeBytes'] as num?)?.toInt() ?? 0;
        // Ticket 34 wart fix: catalog models carry 2dp sizes; the
        // raw quotient rendered as "1.929903264 GB" on pinned cards.
        final sizeGb = ((sizeBytes / 1000000000.0) * 100).round() / 100;
        // House estimate (same formula as custom-model intake):
        // size * 1.2, rounded up to an even GB, floor 4.
        var minRam = ((sizeGb * 1.2) / 2).ceil() * 2;
        if (minRam < 4) minRam = 4;
        return AiModelInfo(
          id: 'pin-${m['filename']}',
          name: (m['name'] ?? m['filename']).toString(),
          filename: (m['filename'] ?? '').toString(),
          url: (m['url'] ?? '').toString(),
          sizeGb: sizeGb,
          minRamGb: minRam,
          label: 'STANDARD',
          badge: 'PINNED',
          systemPrompt: '',
        );
      }).where((m) => m.filename.isNotEmpty && m.hasRemoteUrl).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Founder-side pin flags (device-local until ticket 06) ─────

  Set<String> flaggedPins() {
    final box = Hive.box('settings');
    final raw = box.get(_flagKey) as List?;
    return raw?.map((e) => e.toString()).toSet() ?? {};
  }

  Future<void> setFlagged(String filename, bool pinned) async {
    final box = Hive.box('settings');
    final current = flaggedPins();
    if (pinned) {
      current.add(filename);
    } else {
      current.remove(filename);
    }
    await box.put(_flagKey, current.toList());
  }
}
