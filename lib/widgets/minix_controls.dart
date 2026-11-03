import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../models/ai_model_info.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MiniX controls — faithful Flutter ports of the banked 21st components
// (ticket 08; motion law: mechanics exactly, color the only change).
// ─────────────────────────────────────────────────────────────────────────────

/// #4 Segmented Control — sliding pill indicator across segments.
class MinixSegmented extends StatelessWidget {
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  const MinixSegmented({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderFaint),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth / options.length;
          return SizedBox(
            height: 32,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: selectedIndex * w,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (int i = 0; i < options.length; i++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelect(i),
                          child: Center(
                            child: Text(
                              options[i],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: i == selectedIndex
                                    ? Colors.white
                                    : context.textM,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// #3 Switch — smooth sliding thumb, accent fill when on (the anatomy that
/// becomes ticket 09's connectivity switch unchanged).
class MinixSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const MinixSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 46,
        height: 27,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? AppColors.accent : context.bgHover,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderFaint),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// #11 Approval Card — the consequential-action confirmation (replaces the
/// stock large-model dialog): what, how big, one deliberate confirm.
Future<bool> showApprovalDialog(
  BuildContext context, {
  required String title,
  required String itemName,
  required double sizeGb,
  String confirmLabel = 'Download',
  String? note,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.bgPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: TextStyle(color: ctx.text, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(itemName,
              style: TextStyle(
                  color: ctx.text, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.storage_rounded, size: 15, color: ctx.textD),
              const SizedBox(width: 6),
              Text('${sizeGb.toStringAsFixed(1)} GB',
                  style: TextStyle(
                      fontSize: 13,
                      color: ctx.textM,
                      fontFamily: 'monospace')),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(note, style: TextStyle(fontSize: 12, color: ctx.textD)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: TextStyle(color: ctx.textD)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(confirmLabel, style: const TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// #10 Chat Thread Skeleton — loading placeholders: redaction-family bars
/// with a soft shimmer pulse (DESIGN.md §3.4), never a stock spinner.
class SkeletonThread extends StatefulWidget {
  final int groups;
  const SkeletonThread({super.key, this.groups = 3});

  @override
  State<SkeletonThread> createState() => _SkeletonThreadState();
}

class _SkeletonThreadState extends State<SkeletonThread>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final pulse = reduce ? 0.5 : 0.35 + _ctrl.value * 0.3;
        Widget bar(double w) => Container(
              width: w,
              height: 11,
              decoration: BoxDecoration(
                color: Color.lerp(
                  Colors.black,
                  AppColors.accent,
                  pulse * 0.25,
                ),
                border: Border.all(color: context.borderFaint),
                borderRadius: BorderRadius.circular(2),
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int g = 0; g < widget.groups; g++) ...[
              if (g > 0) const SizedBox(height: 18),
              Opacity(
                opacity: 0.45 + pulse * 0.55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(190 - g * 24),
                    const SizedBox(height: 7),
                    bar(250 - g * 18),
                    const SizedBox(height: 7),
                    bar(130 + g * 12),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// #8 Agent Trace — engine event timeline (load → context → first token →
/// stream → done) in mono, live during a run.
class AgentTrace extends StatelessWidget {
  final List<({String label, bool done, bool active})> events;
  const AgentTrace({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < events.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: events[i].done
                          ? AppColors.green
                          : events[i].active
                              ? AppColors.accentHi
                              : context.bgHover,
                      border: Border.all(color: context.borderFaint),
                    ),
                  ),
                  if (i < events.length - 1)
                    Container(width: 1.5, height: 18, color: context.borderFaint),
                ],
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  events[i].label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: events[i].active
                        ? context.text
                        : events[i].done
                            ? context.textM
                            : context.textD,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// #9 Statistics Card — labeled stat rows with mono values (real values
/// only — the host passes probe data, never the demo's samples).
class StatsCard extends StatelessWidget {
  final String title;
  final List<({String label, String value})> rows;
  const StatsCard({super.key, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border.all(color: context.borderFaint),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: context.textD,
            ),
          ),
          const SizedBox(height: 10),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(r.label,
                        style: TextStyle(fontSize: 12.5, color: context.textM)),
                  ),
                  Text(
                    r.value,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: context.text,
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

/// #6 Search Input Group — grouped search field: icon, field, clear, and a
/// live count chip; filters the host's list as you type.
class SearchInputGroup extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int? resultCount;
  final ValueChanged<String> onChanged;
  const SearchInputGroup({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.resultCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderFaint),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Icon(Icons.search_rounded, size: 17, color: context.textD),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(fontSize: 13.5, color: context.text),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 13, color: context.textD),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          if (resultCount != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$resultCount',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: AppColors.accentHi,
                ),
              ),
            ),
          if (controller.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close_rounded, size: 16, color: context.textD),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
              visualDensity: VisualDensity.compact,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// #5 Model Picker — bottom-sheet selection with fit badges.
Future<AiModelInfo?> showModelPicker(
  BuildContext context, {
  required List<AiModelInfo> models,
  required Set<String> downloaded,
  required String? activeFilename,
  required ({String label, Color color}) Function(AiModelInfo) badgeFor,
}) {
  return showModalBottomSheet<AiModelInfo>(
    context: context,
    backgroundColor: context.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ctx.textD,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text('Pick a model',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ctx.text)),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in models)
                    ListTile(
                      title: Text(m.name,
                          style: TextStyle(fontSize: 14, color: ctx.text)),
                      subtitle: Text(
                        '${m.sizeGb.toStringAsFixed(1)} GB · min ${m.minRamGb} GB RAM',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: ctx.textD),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeFor(m).color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              badgeFor(m).label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: badgeFor(m).color,
                              ),
                            ),
                          ),
                          if (m.filename == activeFilename) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check_circle_rounded,
                                size: 17, color: AppColors.green),
                          ],
                        ],
                      ),
                      onTap: () => Navigator.pop(ctx, m),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// #26 Stream Reply (+ #2 as its regenerating style) — token stream with
/// blur-in words and a glowing caret at the head while streaming. In
/// [regenerating] mode the reveal is the original #2's: progressive text
/// with a plain blinking caret, no blur.
class StreamReplyText extends StatefulWidget {
  final String text;
  final bool streaming;
  final bool regenerating;
  final TextStyle? style;
  const StreamReplyText({
    super.key,
    required this.text,
    this.streaming = false,
    this.regenerating = false,
    this.style,
  });

  @override
  State<StreamReplyText> createState() => _StreamReplyTextState();
}

class _StreamReplyTextState extends State<StreamReplyText> {
  final Map<int, DateTime> _wordBorn = {};
  int _lastWordCount = 0;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _stamp();
    _refresh = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (mounted && widget.streaming) setState(() {});
    });
  }

  @override
  void didUpdateWidget(StreamReplyText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _stamp();
  }

  void _stamp() {
    final words = widget.text.split(' ');
    for (int i = _lastWordCount; i < words.length; i++) {
      _wordBorn[i] = DateTime.now();
    }
    _lastWordCount = words.length;
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ??
        TextStyle(fontSize: 14.5, height: 1.45, color: context.text);
    final words = widget.text.split(' ');
    final now = DateTime.now();
    final spans = <InlineSpan>[];
    for (int i = 0; i < words.length; i++) {
      final born = _wordBorn[i];
      final age = born == null ? 999 : now.difference(born).inMilliseconds;
      final t = widget.regenerating
          ? 1.0
          : (age / 350).clamp(0.0, 1.0); // blur-in window
      spans.add(TextSpan(
        text: i == words.length - 1 ? words[i] : '${words[i]} ',
        style: base.copyWith(
          color: (base.color ?? AppColors.darkText)
              .withValues(alpha: 0.25 + 0.75 * t),
          shadows: (!widget.regenerating && t < 1)
              ? [
                  Shadow(
                    color: (base.color ?? AppColors.darkText)
                        .withValues(alpha: 0.7 * (1 - t)),
                    blurRadius: 7 * (1 - t),
                  ),
                ]
              : null,
        ),
      ));
    }
    if (widget.streaming) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _Caret(regenerating: widget.regenerating),
      ));
    }
    return RichText(text: TextSpan(children: spans));
  }
}

class _Caret extends StatefulWidget {
  final bool regenerating;
  const _Caret({required this.regenerating});

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1060),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final on = _ctrl.value > 0.5;
        if (widget.regenerating) {
          return Opacity(
            opacity: on ? 1 : 0,
            child: Container(width: 7, height: 15, color: context.textM),
          );
        }
        return Container(
          width: 8,
          height: 16,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: AppColors.accentHi,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.55),
                blurRadius: 9,
                spreadRadius: 1.5,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// #24 Ask Nexus — the send moment: the typed text disintegrates into
/// particles. Overlay this on the composer, call [play] via key/state, and
/// it dissolves [text] then calls [onDone].
class NexusDisintegrate extends StatefulWidget {
  final String text;
  final VoidCallback onDone;
  const NexusDisintegrate({super.key, required this.text, required this.onDone});

  @override
  State<NexusDisintegrate> createState() => _NexusDisintegrateState();
}

class _NexusDisintegrateState extends State<NexusDisintegrate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  List<_Dust> _dust = [];
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _ignite());
  }

  Future<void> _ignite() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final tp = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
    )..layout(maxWidth: size.width - 24);
    tp.paint(canvas, const Offset(12, 10));
    final img = await recorder
        .endRecording()
        .toImage(size.width.ceil(), size.height.ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null || !mounted) return;
    final pts = <_Dust>[];
    for (int y = 0; y < size.height; y += 3) {
      for (int x = 0; x < size.width; x += 3) {
        if (bytes.getUint8((y * size.width.ceil() + x) * 4 + 3) > 110) {
          pts.add(_Dust(
            Offset(x.toDouble(), y.toDouble()),
            Offset((_rng.nextDouble() - 0.5) * 26,
                -18 - _rng.nextDouble() * 46),
          ));
        }
      }
    }
    if (mounted) {
      setState(() => _dust = pts);
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        painter: _DustPainter(_dust, _ctrl.value),
        size: Size.infinite,
      ),
    );
  }
}

class _Dust {
  final Offset origin;
  final Offset drift;
  const _Dust(this.origin, this.drift);
}

class _DustPainter extends CustomPainter {
  final List<_Dust> dust;
  final double t;
  _DustPainter(this.dust, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (dust.isEmpty) return;
    final paint = Paint()..style = PaintingStyle.fill;
    for (final d in dust) {
      final p = d.origin + d.drift * t + Offset(0, -26 * t * t);
      paint.color = const Color(0xFFD8B4FE).withValues(alpha: (1 - t) * 0.9);
      canvas.drawCircle(p, 1.5 * (1 - t) + 0.4, paint);
    }
  }

  @override
  bool shouldRepaint(_DustPainter old) => true;
}
