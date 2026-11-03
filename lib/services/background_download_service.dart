import 'package:flutter/services.dart';

/// Dart face of the native background download engine (ticket 05).
///
/// On iOS the transfer runs in a background URLSession owned by
/// AppDelegate: the system daemon performs it while MiniX is suspended
/// or not running at all, moves the finished file into the models
/// directory, and posts the completion notification natively. This
/// wrapper only starts/cancels tasks and polls their status — it never
/// touches the bytes itself.
class BackgroundDownloadService {
  static const MethodChannel _channel = MethodChannel('minix/downloads');

  /// Founder import scope (2026-11-03): stranger download sources
  /// resolve ONLY to Hugging Face + GitHub. Redirect targets (HF's LFS
  /// and Xet CDNs) are followed by the session itself; the check
  /// applies to the link the founder actually supplied.
  static bool isImportScopeUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host == 'huggingface.co' ||
        host.endsWith('.huggingface.co') ||
        host == 'github.com' ||
        host.endsWith('.github.com') ||
        host == 'raw.githubusercontent.com' ||
        host.endsWith('.githubusercontent.com');
  }

  static Future<void> start({
    required String url,
    required String filename,
    required String destDir,
    required String displayName,
  }) async {
    await _channel.invokeMethod<bool>('start', {
      'url': url,
      'filename': filename,
      'destDir': destDir,
      'name': displayName,
    });
  }

  static Future<void> cancel(String filename) async {
    try {
      await _channel.invokeMethod<bool>('cancel', {'filename': filename});
    } catch (_) {}
  }

  /// Status for one file: {status: downloading|completed|failed|none,
  /// received, total, error?} — or null when the channel is unavailable.
  static Future<Map<String, dynamic>?> status(String filename) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'status',
        {'filename': filename},
      );
      if (raw == null) return null;
      return raw.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  /// Every tracked download's status, keyed by filename.
  static Future<Map<String, Map<String, dynamic>>> allStatuses() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'allStatuses',
      );
      if (raw == null) return {};
      return raw.map((k, v) => MapEntry(
            k.toString(),
            (v as Map).map((k2, v2) => MapEntry(k2.toString(), v2)),
          ));
    } catch (_) {
      return {};
    }
  }

  /// Tell the native side Dart has adopted a finished/failed entry so
  /// it can drop its bookkeeping.
  static Future<void> ack(String filename) async {
    try {
      await _channel.invokeMethod<bool>('ack', {'filename': filename});
    } catch (_) {}
  }
}
