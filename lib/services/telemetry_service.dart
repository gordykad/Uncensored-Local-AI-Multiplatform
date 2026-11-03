import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'chat_storage_service.dart';
import 'llm_service.dart';
import 'memory_probe.dart';

/// One telemetry sample (ticket 22). The honest iOS proxy set: GPU
/// utilisation % is not exposed to third-party apps, so it is never
/// sampled or graphed; mtlAllocBytes is -1 when Metal reports nothing.
class TelemetrySample {
  final DateTime at;
  final int headroomBytes;
  final int footprintBytes;
  final double cpuPct; // 100 = one core fully busy
  final double majfltPerSec; // major page faults — flash reads
  final int thermal; // 0 nominal, 1 fair, 2 serious, 3 critical
  final double batteryLevel; // 0..1, -1 unknown
  final int batteryState; // 0 unknown, 1 unplugged, 2 charging, 3 full
  final int mtlAllocBytes;
  final int diskFreeBytes;
  final bool generating;
  final String backend;
  final String? model;

  const TelemetrySample({
    required this.at,
    required this.headroomBytes,
    required this.footprintBytes,
    required this.cpuPct,
    required this.majfltPerSec,
    required this.thermal,
    required this.batteryLevel,
    required this.batteryState,
    required this.mtlAllocBytes,
    required this.diskFreeBytes,
    required this.generating,
    required this.backend,
    required this.model,
  });

  Map<String, dynamic> toJson() => {
        't': at.toIso8601String(),
        'headroomMB': _mb(headroomBytes),
        'footprintMB': _mb(footprintBytes),
        'cpuPct': double.parse(cpuPct.toStringAsFixed(1)),
        'majfltPerSec': double.parse(majfltPerSec.toStringAsFixed(2)),
        'thermal': thermal,
        'batteryPct': batteryLevel < 0
            ? null
            : (batteryLevel * 100).round(),
        'batteryState': batteryState,
        'mtlAllocMB': mtlAllocBytes < 0 ? null : _mb(mtlAllocBytes),
        'diskFreeMB': _mb(diskFreeBytes),
        'generating': generating,
        'backend': backend,
        'model': model,
      };

  static double _mb(int bytes) =>
      bytes < 0 ? -1 : double.parse((bytes / 1048576).toStringAsFixed(1));
}

/// Telemetry sampler (ticket 22): 1 Hz while a generation runs,
/// 0.1 Hz idle, into a ~15-minute ring buffer, a telemetry.log file
/// beside engine.log, the /admin/telemetry route, and the Logs
/// screen graphs. Best-effort throughout — a sampler failure never
/// breaks the app.
class TelemetryService extends GetxService {
  static const int _capacity = 900;

  final samples = <TelemetrySample>[].obs;
  final latest = Rx<TelemetrySample?>(null);

  Timer? _timer;
  int _tick = 0;
  File? _logFile;
  Future<void> _writeChain = Future.value();

  TelemetryService init() {
    unawaited(_sampleOnce());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick++;
      final generating = _generatingNow();
      if (generating || _tick % 10 == 0) {
        unawaited(_sampleOnce());
      }
    });
    return this;
  }

  bool _generatingNow() {
    try {
      return Get.find<LlmService>().isGenerating.value;
    } catch (_) {
      return false;
    }
  }

  Future<void> _sampleOnce() async {
    try {
      final raw = await MemoryProbe.sample();
      if (raw == null) return;

      String backend = 'unknown';
      bool generating = false;
      String? model;
      try {
        backend = Get.find<ChatStorageService>().backendType;
      } catch (_) {}
      try {
        final llm = Get.find<LlmService>();
        generating = llm.isGenerating.value;
        final path = llm.loadedModelPath.value;
        if (path.isNotEmpty) model = path.split('/').last;
      } catch (_) {}

      final sample = TelemetrySample(
        at: DateTime.now(),
        headroomBytes: (raw['headroomBytes'] as num?)?.toInt() ?? -1,
        footprintBytes: (raw['footprintBytes'] as num?)?.toInt() ?? -1,
        cpuPct: (raw['cpuPct'] as num?)?.toDouble() ?? 0,
        majfltPerSec: (raw['majfltPerSec'] as num?)?.toDouble() ?? 0,
        thermal: (raw['thermal'] as num?)?.toInt() ?? 0,
        batteryLevel: (raw['batteryLevel'] as num?)?.toDouble() ?? -1,
        batteryState: (raw['batteryState'] as num?)?.toInt() ?? 0,
        mtlAllocBytes: (raw['mtlAllocBytes'] as num?)?.toInt() ?? -1,
        diskFreeBytes: (raw['diskFreeBytes'] as num?)?.toInt() ?? -1,
        generating: generating,
        backend: backend,
        model: model,
      );

      samples.add(sample);
      while (samples.length > _capacity) {
        samples.removeAt(0);
      }
      latest.value = sample;
      _appendToFile(sample);
    } catch (_) {
      // Best-effort only.
    }
  }

  /// The newest [n] samples as JSON maps, oldest first (API route).
  List<Map<String, dynamic>> tailJson(int n) {
    final list = samples.toList();
    final start = list.length > n ? list.length - n : 0;
    return list.sublist(start).map((s) => s.toJson()).toList();
  }

  Future<void> _ensureFile() async {
    if (_logFile != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File(p.join(dir.path, 'telemetry.log'));
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
    } catch (_) {
      _logFile = null;
    }
  }

  void _appendToFile(TelemetrySample sample) {
    _writeChain = _writeChain.then((_) async {
      await _ensureFile();
      final f = _logFile;
      if (f == null) return;
      try {
        await f.writeAsString(
          '${jsonEncode(sample.toJson())}\n',
          mode: FileMode.append,
        );
      } catch (_) {}
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
