import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../services/llm_service.dart';
import '../services/log_service.dart';
import '../services/memory_probe.dart';
import '../services/telemetry_service.dart';
import '../controllers/model_controller.dart';
import '../widgets/faithful/stats.dart';
import '../widgets/faithful/trace_pickers.dart';
import '../widgets/faithful/textfx.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logService = Get.find<LogService>();

    return Scaffold(
      backgroundColor: context.bg,
      body: Column(
        children: [
          // ── Top bar ──────────────────────────────────
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
              left: 4,
              right: 4,
            ),
            decoration: BoxDecoration(
              color: context.bg,
              border: Border(
                bottom: BorderSide(color: context.border, width: 0.5),
              ),
            ),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.text),
                    onPressed: () => Get.back(),
                  ),
                  BlurReveal(
                    text: 'App Logs',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: context.text,
                    ),
                  ),
                  const Spacer(),
                  // Copy all logs
                  IconButton(
                    icon: Icon(Icons.copy_rounded, size: 20, color: context.textM),
                    tooltip: 'Copy all logs',
                    onPressed: () {
                      final text = logService.exportAll();
                      Clipboard.setData(ClipboardData(text: text));
                      Get.snackbar(
                        'Copied',
                        'All logs copied to clipboard. Share on Telegram or GitHub!',
                        snackPosition: SnackPosition.BOTTOM,
                        duration: const Duration(seconds: 2),
                      );
                    },
                  ),
                  // Clear logs
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: 20, color: context.textD),
                    tooltip: 'Clear logs',
                    onPressed: () {
                      logService.clear();
                      Get.snackbar(
                        'Cleared',
                        'All logs cleared.',
                        snackPosition: SnackPosition.BOTTOM,
                        duration: const Duration(seconds: 1),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),

          // ── Diagnostics header (ticket 01) ──────────
          const _DiagnosticsHeader(),

          // ── Engine panel (ticket 08): stats card + agent trace ──
          const _EnginePanel(),

          // ── Telemetry panel (ticket 22) ───────────────
          const _TelemetryPanel(),

          // ── Filter chips ──────────────────────────────
          _FilterBar(),

          // ── Log list ──────────────────────────────────
          Expanded(
            child: Obx(() {
              final filter = _FilterBar._activeFilter.value;
              final allLogs = logService.logs.toList().reversed.toList();
              final filtered = filter == 'ALL'
                  ? allLogs
                  : allLogs.where((e) => e.level == filter).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.article_outlined, size: 48, color: context.textD),
                      const SizedBox(height: 16),
                      Text(
                        'No logs yet.',
                        style: TextStyle(color: context.textD, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final entry = filtered[index];
                  return _LogTile(entry: entry);
                },
              );
            }),
          ),

          // ── Bottom share banner ──────────────────────
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: context.bgPanel,
              border: Border(
                top: BorderSide(color: context.border, width: 0.5),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final text = logService.exportAll();
                  Clipboard.setData(ClipboardData(text: text));
                  Get.snackbar(
                    'Logs Copied!',
                    'Paste in Telegram or GitHub Issues to share with developers.',
                    snackPosition: SnackPosition.BOTTOM,
                    duration: const Duration(seconds: 3),
                  );
                },
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Copy Logs to Share'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter bar ──────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  static final _activeFilter = 'ALL'.obs;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Obx(() => ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _chip(context, 'All', 'ALL'),
              _chip(context, 'Info', 'INFO'),
              _chip(context, 'Warnings', 'WARN'),
              _chip(context, 'Errors', 'ERROR'),
            ],
          )),
    );
  }

  Widget _chip(BuildContext context, String label, String value) {
    final selected = _activeFilter.value == value;
    final color = value == 'ERROR'
        ? AppColors.red
        : value == 'WARN'
            ? AppColors.orange
            : value == 'INFO'
                ? AppColors.green
                : AppColors.accent;

    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : context.textM,
          ),
        ),
        selected: selected,
        onSelected: (_) => _activeFilter.value = value,
        selectedColor: color,
        backgroundColor: context.bgPanel,
        side: BorderSide(color: selected ? color : context.border),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ── Single log entry tile ─────────────────────────────────────
class _LogTile extends StatelessWidget {
  final LogEntry entry;
  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final Color levelColor;
    final IconData levelIcon;
    switch (entry.level) {
      case 'ERROR':
        levelColor = AppColors.red;
        levelIcon = Icons.error_outline_rounded;
        break;
      case 'WARN':
        levelColor = AppColors.orange;
        levelIcon = Icons.warning_amber_rounded;
        break;
      default:
        levelColor = AppColors.green;
        levelIcon = Icons.info_outline_rounded;
    }

    final time = DateFormat('HH:mm:ss').format(entry.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: levelColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: levelColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(levelIcon, size: 14, color: levelColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 10,
                        color: context.textD,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (entry.source != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: levelColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          entry.source!,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: levelColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  entry.message,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.text,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Diagnostics header (ticket 01) ────────────────────────────
// Live memory headroom (native os_proc_available_memory on iOS), the
// last error in plain terms, and the last generation's fixed-meter
// summary — the three things every fleet measurement depends on.
class _DiagnosticsHeader extends StatefulWidget {
  const _DiagnosticsHeader();

  @override
  State<_DiagnosticsHeader> createState() => _DiagnosticsHeaderState();
}

class _DiagnosticsHeaderState extends State<_DiagnosticsHeader> {
  String _headroom = '...';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final label = await MemoryProbe.availableLabel();
    if (mounted) setState(() => _headroom = label);
  }

  @override
  Widget build(BuildContext context) {
    final logService = Get.find<LogService>();
    final llm = Get.isRegistered<LlmService>() ? Get.find<LlmService>() : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border(
          bottom: BorderSide(color: context.border, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory_rounded, size: 14, color: context.textM),
              const SizedBox(width: 6),
              Text(
                'Memory available: $_headroom',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.text,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          Obx(() {
            final err = logService.lastError.value;
            if (err.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Last error: $err',
                style: TextStyle(fontSize: 12, color: AppColors.red),
              ),
            );
          }),
          if (llm != null)
            Obx(() {
              final summary = llm.lastMeterSummary.value;
              if (summary.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Last generation: $summary',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textM,
                    fontFamily: 'monospace',
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}


// ── Engine panel (ticket 08) ──────────────────────────────
// Statistics Card (#9) fed by the REAL probes + Agent Trace (#8) of the
// engine's run phases. No demo values anywhere.
class _EnginePanel extends StatelessWidget {
  const _EnginePanel();

  @override
  Widget build(BuildContext context) {
    final llm = Get.isRegistered<LlmService>() ? Get.find<LlmService>() : null;
    if (llm == null) return const SizedBox.shrink();
    final models = Get.isRegistered<ModelController>()
        ? Get.find<ModelController>()
        : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border(
          bottom: BorderSide(color: context.border, width: 0.5),
        ),
      ),
      child: Obx(() {
        final loaded = llm.isLoaded.value;
        final generating = llm.isGenerating.value;
        final loading = llm.isLoadingModel.value;
        final onDisk = models == null
            ? 0
            : models.catalog
                .where((m) => models.downloadedModels.contains(m.filename))
                .length;
        final rows = <({String label, String value})>[
          (
            label: 'Model',
            value: loaded
                ? llm.loadedModelPath.value.split('/').last
                : 'none loaded',
          ),
          (label: 'Models on disk', value: '$onDisk'),
          (
            label: 'Last decode',
            value: llm.lastDecodeTps.value > 0
                ? '${llm.lastDecodeTps.value.toStringAsFixed(2)} tok/s'
                : '\u2014',
          ),
          (
            label: 'Last TTFT',
            value: llm.lastTtftMs.value > 0
                ? '${llm.lastTtftMs.value} ms'
                : '\u2014',
          ),
          (
            label: 'Last reply tokens',
            value: llm.lastGenerationTokens.value > 0
                ? '${llm.lastGenerationTokens.value}'
                : '\u2014',
          ),
        ];
        // #8 Agent Trace fed by the real METER numbers (ticket 01):
        // prefill span = TTFT, decode span = tokens / decode rate.
        final ttft = llm.lastTtftMs.value.toDouble();
        final decodeMs = (llm.lastDecodeTps.value > 0 &&
                llm.lastGenerationTokens.value > 0)
            ? llm.lastGenerationTokens.value / llm.lastDecodeTps.value * 1000
            : 0.0;
        final spans = <TraceSpan>[
          if (ttft > 0)
            TraceSpan(label: 'Prefill', startMs: 0, durMs: ttft),
          if (ttft > 0 && decodeMs > 0)
            TraceSpan(
              label: 'Decode',
              startMs: ttft,
              durMs: decodeMs,
              tokens: llm.lastGenerationTokens.value,
            ),
          if (ttft == 0)
            const TraceSpan(label: 'No run yet', startMs: 0, durMs: 1),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final r in rows)
                  SizedBox(
                    width: 168,
                    child: MinixStatsCard(label: r.label, value: r.value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AgentTraceView(spans: spans, autoPlay: ttft > 0),
          ],
        );
      }),
    );
  }
}

/// Telemetry panel (ticket 22): current values from the sampler plus
/// sparklines over the ring buffer. GPU utilisation is not exposed to
/// third-party apps on iOS, so it is never graphed here.
class _TelemetryPanel extends StatelessWidget {
  const _TelemetryPanel();

  static const _thermalNames = ['Nominal', 'Fair', 'Serious', 'Critical'];

  @override
  Widget build(BuildContext context) {
    TelemetryService? svc;
    try {
      svc = Get.find<TelemetryService>();
    } catch (_) {}
    if (svc == null) return const SizedBox.shrink();
    final service = svc;
    return Obx(() {
      final latest = service.latest.value;
      if (latest == null) return const SizedBox.shrink();
      final samples = service.samples.toList();
      String gb(int bytes) =>
          bytes < 0 ? 'n/a' : '${(bytes / 1073741824).toStringAsFixed(2)} GB';
      String mb(int bytes) =>
          bytes < 0 ? 'n/a' : '${(bytes / 1048576).toStringAsFixed(0)} MB';
      final thermal = latest.thermal.clamp(0, 3);
      final thermalColor = thermal >= 2
          ? AppColors.red
          : thermal == 1
              ? AppColors.orange
              : AppColors.green;
      Widget stat(String label, String value) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: context.textD,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: context.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      }

      Widget spark(String label, List<double> values, Color color) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  label,
                  style: TextStyle(color: context.textD, fontSize: 10),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: CustomPaint(
                    painter: _SparklinePainter(values, color),
                    size: const Size(double.infinity, 26),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.bgPanel,
          border: Border.all(color: context.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'TELEMETRY',
                  style: TextStyle(
                    color: context.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 8),
                if (latest.generating)
                  Text(
                    'GENERATING',
                    style: TextStyle(
                      color: AppColors.accentHi,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: thermalColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _thermalNames[thermal],
                    style: TextStyle(
                      color: thermalColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                stat('HEADROOM', gb(latest.headroomBytes)),
                stat('FOOTPRINT', mb(latest.footprintBytes)),
                stat('CPU', '${latest.cpuPct.toStringAsFixed(0)}%'),
                stat('FAULTS/S', latest.majfltPerSec.toStringAsFixed(1)),
                stat('METAL', mb(latest.mtlAllocBytes)),
                stat(
                  'BATTERY',
                  latest.batteryLevel < 0
                      ? 'n/a'
                      : '${(latest.batteryLevel * 100).round()}%',
                ),
              ],
            ),
            spark(
              'Headroom',
              samples.map((s) => s.headroomBytes / 1048576).toList(),
              AppColors.accentHi,
            ),
            spark(
              'CPU %',
              samples.map((s) => s.cpuPct).toList(),
              AppColors.green,
            ),
            spark(
              'Faults/s',
              samples.map((s) => s.majfltPerSec).toList(),
              AppColors.orange,
            ),
          ],
        ),
      );
    });
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  const _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var min = values.first;
    var max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    if (max - min < 0.0001) {
      max = min + 1;
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y =
          size.height - ((values[i] - min) / (max - min)) * (size.height - 4) - 2;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}
