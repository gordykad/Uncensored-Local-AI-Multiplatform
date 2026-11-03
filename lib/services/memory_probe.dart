import 'package:flutter/services.dart';

/// Reads OS memory figures through a tiny native channel
/// (iOS: os_proc_available_memory — the same number jetsam decisions are
/// made against; Android: ActivityManager MemoryInfo.availMem).
///
/// Ticket 01 (diagnostics): the readout is best-effort. It returns null
/// when the platform cannot answer, and callers must treat it as a
/// diagnostic signal, never as a hard gate.
///
/// Ticket 22 extends the channel with `sample` (the telemetry series)
/// and `diskFreeBytes` (the ticket 05 pre-download fit check).
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

  /// Free disk space in bytes, or null when unavailable.
  static Future<int?> diskFreeBytes() async {
    try {
      final v = await _channel.invokeMethod<int>('diskFreeBytes');
      if (v == null || v < 0) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  /// One telemetry sample from the native sampler (ticket 22), or null
  /// when the platform cannot answer. Keys: headroomBytes,
  /// footprintBytes, cpuPct (100 = one core), majfltPerSec, thermal
  /// (0 nominal .. 3 critical), batteryLevel (0..1, -1 unknown),
  /// batteryState, mtlAllocBytes (-1 = unavailable), diskFreeBytes.
  static Future<Map<String, dynamic>?> sample() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('sample');
      if (raw == null) return null;
      return raw.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }
}
