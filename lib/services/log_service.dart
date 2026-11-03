import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LogEntry {
  final DateTime timestamp;
  final String level; // INFO, WARN, ERROR
  final String message;
  final String? source;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source,
  });

  String get formatted {
    final t = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final src = source != null ? ' ($source)' : '';
    return '[$t] [$level]$src $message';
  }
}

class LogService extends GetxService {
  static const int maxLogs = 1000;
  final logs = <LogEntry>[].obs;

  /// Most recent ERROR entry, surfaced by the diagnostics header (ticket 01).
  final lastError = ''.obs;
  final lastErrorAt = Rx<DateTime?>(null);

  // ── File persistence (ticket 01) ────────────────────────────
  // Entries are appended to <documents>/engine.log so a diagnostics trail
  // survives the in-memory ring buffer and can be pulled after a crash or
  // a jetsam kill. Writes are best-effort and serialized through a future
  // chain; a storage failure never breaks logging itself.
  File? _logFile;
  Future<void> _writeChain = Future.value();

  LogService init() {
    info('App started', source: 'System');
    return this;
  }

  Future<void> _ensureFile() async {
    if (_logFile != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File(p.join(dir.path, 'engine.log'));
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
    } catch (_) {
      _logFile = null;
    }
  }

  void _appendToFile(LogEntry entry) {
    _writeChain = _writeChain.then((_) async {
      await _ensureFile();
      final f = _logFile;
      if (f == null) return;
      try {
        await f.writeAsString(
          '${entry.timestamp.toIso8601String()} ${entry.formatted}\n',
          mode: FileMode.append,
        );
      } catch (_) {
        // Best-effort only — never let diagnostics break the app.
      }
    });
  }

  /// Absolute path of the on-disk log, once it exists (for support/export).
  String? get logFilePath => _logFile?.path;

  void info(String message, {String? source}) => _add('INFO', message, source);

  void warn(String message, {String? source}) => _add('WARN', message, source);

  void error(String message, {String? source}) =>
      _add('ERROR', message, source);

  void _add(String level, String message, String? source) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      source: source,
    );
    logs.add(entry);
    if (level == 'ERROR') {
      lastError.value = message;
      lastErrorAt.value = entry.timestamp;
    }
    _appendToFile(entry);
    // Keep within limit
    while (logs.length > maxLogs) {
      logs.removeAt(0);
    }
  }

  /// Export all logs as a single string for sharing.
  String exportAll() {
    final buf = StringBuffer();
    buf.writeln('=== Portable AI Logs ===');
    buf.writeln('Exported: ${DateTime.now().toIso8601String()}');
    buf.writeln('Total entries: ${logs.length}');
    if (lastError.value.isNotEmpty) {
      buf.writeln('Last error: ${lastError.value}');
    }
    buf.writeln('');
    for (final entry in logs) {
      buf.writeln(entry.formatted);
    }
    return buf.toString();
  }

  void clear() => logs.clear();
}
