import 'package:flutter/services.dart';

/// Reads the OS available-memory figure through a tiny native channel
/// (iOS: os_proc_available_memory — the same number jetsam decisions are
/// made against; Android: ActivityManager MemoryInfo.availMem).
///
/// Ticket 01 (diagnostics): the readout is best-effort. It returns null
/// when the platform cannot answer, and callers must treat it as a
/// diagnostic signal, never as a hard gate.
class MemoryProbe {
  static const MethodChannel _channel = MethodChannel('minix/diagnostics');

  /// Available memory in bytes, or null when unavailable.
  static Future<int?> availableBytes() async {
    try {
      return await _channel.invokeMethod<int>('availableMemoryBytes');
    } catch (_) {
      return null;
    }
  }

  /// Human-readable available memory, e.g. "2.41 GB" (or "unknown").
  static Future<String> availableLabel() async {
    final bytes = await availableBytes();
    if (bytes == null) return 'unknown';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }
}
