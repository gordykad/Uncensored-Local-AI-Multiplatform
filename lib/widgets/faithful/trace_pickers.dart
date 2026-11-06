// AgentTrace (#8), SearchInputGroup (#6), ModelPicker (#5) — ports from
// the banked sources.
//
// #8 truth (pack agent-trace): a run-timeline player. Span rows
// (labelWidth 200 -> scaled to rail width in-app, rowHeight 34); a
// playhead sweeps the total duration at speed x; each span's fill =
// clamp((t - start)/dur); span state machine queued -> running -> done /
// error drives its status text; the running span's duration and token
// meta count up WITH progress; a ruler picks a tick step so at most 8
// intervals show; transport readout "X.XXs / Y.YYs" plus a
// Running/Completed label; at the end it holds (holdMs 900) before an
// optional loop. In MiniX the spans are the engine's real phases
// (load / prefill / decode) from the ticket-01 METER data.
//
// #6 truth (pack search-input-group): anatomy only — a small label above
// a bordered group holding a search icon and the bare input. No motion.
//
// #5 truth (pack model-picker): a popover with a provider RAIL on the
// left and the selected provider's models on the right; a search box
// filters across ALL providers when non-empty; each model can carry a
// thinking level chosen inline; the active provider auto-scrolls to
// center on open. MiniX mapping: providers -> model sources (Catalog /
// Imported), thinking -> the model's RAM fit chip. Popover entrance is a
// plain fade/scale in this library family (no spring constants in the
// source; flagged in the ship report).
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

// ------------------------------------------------------------ AgentTrace
class TraceSpan {
  final String label;
  final double startMs;
  final double durMs;
  final bool error;
  final int? tokens;
  const TraceSpan({
    required this.label,
    required this.startMs,
    required this.durMs,
    this.error = false,
    this.tokens,
  });
}

class AgentTraceView extends StatefulWidget {
  final List<TraceSpan> spans;
  final bool autoPlay;
  final bool loop;
  const AgentTraceView({
    super.key,
    required this.spans,
    this.autoPlay = true,
    this.loop = false,
  });

  @override
  State<AgentTraceView> createState() => _AgentTraceViewState();
}

class _AgentTraceViewState extends State<AgentTraceView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  double get _total => math.max(
    1.0,
    widget.spans.fold(0.0, (m, s) => math.max(m, s.startMs + s.durMs)),
  );

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _total.round()),
    );
    if (widget.autoPlay) {
      if (widget.loop) {
        _c.repeat();
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _tickStep() {
    const steps = [100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0, 10000.0];
    for (final s in steps) {
      if (_total / s <= 8) return s;
    }
    return _total / 4;
  }

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(color: AppColors.darkTextM, fontSize: 11);
    const monoStyle = TextStyle(
      color: AppColors.darkTextD,
      fontSize: 10,
      fontFamily: 'monospace',
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value * _total;
        final complete = t >= _total;
        final step = _tickStep();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ruler
            SizedBox(
              height: 14,
              child: CustomPaint(
                painter: _RulerPainter(step: step, total: _total, t: t),
              ),
            ),
            for (final s in widget.spans)
              SizedBox(
                height: 34,
                child: Row(
                  children: [
                    SizedBox(
                      width: 86,
                      child: Text(s.label, style: labelStyle),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (_, box) {
                          final p = s.durMs > 0
                              ? ((t - s.startMs) / s.durMs).clamp(0.0, 1.0)
                              : (t >= s.startMs ? 1.0 : 0.0);
                          final state = t < s.startMs
                              ? 'Queued'
                              : p < 1
                              ? 'Running'
                              : (s.error ? 'Error' : 'Done');
                          final x = s.startMs / _total * box.maxWidth;
                          final w = math.max(
                            2.0,
                            s.durMs / _total * box.maxWidth,
                          );
                          return Stack(
                            children: [
                              Positioned(
                                left: x,
                                top: 8,
                                child: Container(
                                  width: w,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(
                                      alpha: state == 'Queued'
                                          ? 0.12
                                          : 0.25 + 0.55 * p,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: AppColors.darkBorder,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: x + w + 6,
                                top: 10,
                                child: Text(
                                  state == 'Queued'
                                      ? 'Queued'
                                      : '$state · ${(s.durMs * p / 1000).toStringAsFixed(2)}s'
                                            '${s.tokens != null ? ' · ${(s.tokens! * p).round()} tok' : ''}',
                                  style: monoStyle,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(t / 1000).toStringAsFixed(2)}s / ${(_total / 1000).toStringAsFixed(2)}s',
                  style: monoStyle,
                ),
                Text(complete ? 'Completed' : 'Running', style: monoStyle),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _RulerPainter extends CustomPainter {
  final double step, total, t;
  _RulerPainter({required this.step, required this.total, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.darkBorder;
    for (var x = step; x < total; x += step) {
      final px = 86 + (size.width - 86) * (x / total);
      canvas.drawRect(Rect.fromLTWH(px, 4, 1, 6), paint);
    }
    final hx = 86 + (size.width - 86) * (t / total);
    paint.color = AppColors.accentHi;
    canvas.drawRect(Rect.fromLTWH(hx, 0, 1.5, 14), paint);
  }

  @override
  bool shouldRepaint(_RulerPainter old) => true;
}

// ------------------------------------------------------- SearchInputGroup
class SearchInputGroup extends StatelessWidget {
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  const SearchInputGroup({
    super.key,
    required this.label,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.darkTextM,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.darkBgInput,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 12, right: 8),
                child: Icon(Icons.search, size: 17, color: AppColors.darkTextD),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: const TextStyle(
                      color: AppColors.darkTextD,
                      fontSize: 14,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ ModelPicker
class PickerEntry {
  final String source;
  final String name;
  final String meta;
  // Sync build (mesh 0.20): a mesh entry can be starred; [starModel]
  // is the gateway model id the favorite flip writes. [trailing] is
  // an extra row action (the wakebox32b row's Warm / Stop pill).
  final bool favorite;
  final String? starModel;
  final Widget? trailing;
  const PickerEntry(
    this.source,
    this.name,
    this.meta, {
    this.favorite = false,
    this.starModel,
    this.trailing,
  });
}

class ModelPickerSheet extends StatefulWidget {
  final List<PickerEntry> entries;
  final String? selectedName;
  final ValueChanged<PickerEntry> onPick;
  final void Function(PickerEntry entry, bool favorite)? onToggleStar;
  const ModelPickerSheet({
    super.key,
    required this.entries,
    required this.onPick,
    this.selectedName,
    this.onToggleStar,
  });

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet>
    with SingleTickerProviderStateMixin {
  String _query = '';
  final _searchCtrl = TextEditingController();
  late String _source;
  late final Map<String, bool> _fav;
  late final AnimationController _enter;

  List<String> get _sources =>
      widget.entries.map((e) => e.source).toSet().toList();

  @override
  void initState() {
    super.initState();
    _source = _sources.isEmpty ? '' : _sources.first;
    _fav = {
      for (final e in widget.entries)
        if (e.starModel != null) e.starModel!: e.favorite,
    };
    // Audit #7: the sheet lands on a spring, not a cut.
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final visible = widget.entries.where((e) {
      if (searching) {
        return e.name.toLowerCase().contains(_query.toLowerCase());
      }
      return e.source == _source;
    }).toList();
    final rm = MediaQuery.disableAnimationsOf(context);
    return ScaleTransition(
      scale: rm
          ? const AlwaysStoppedAnimation(1.0)
          : Tween(begin: 0.97, end: 1.0).animate(
              CurvedAnimation(parent: _enter, curve: Curves.easeOutBack),
            ),
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: rm
            ? const AlwaysStoppedAnimation(1.0)
            : CurvedAnimation(parent: _enter, curve: Curves.easeOut),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.darkBgPanel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          // UI audit 2026-11-06 P1-10: lift the sheet content
          // above the keyboard when the search field is focused.
          padding: EdgeInsets.fromLTRB(
              16, 14, 16, 24 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // UI audit 2026-11-06 (Codex P2-18): a visible way
              // out of the picker, not just the scrim.
              Row(
                children: [
                  const Text(
                    'Choose model',
                    style: TextStyle(
                      color: AppColors.darkText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.darkTextM, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SearchInputGroup(
                label: 'Model',
                hint: 'Search models',
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!searching)
                    SizedBox(
                      width: 92,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final s in _sources)
                            // UI audit 2026-11-06: rail rows get a
                            // 44pt hit height + selected semantics.
                            Semantics(
                              button: true,
                              selected: s == _source,
                              label: s,
                              child: GestureDetector(
                                onTap: () => setState(() => _source = s),
                                child: Container(
                                  constraints:
                                      const BoxConstraints(minHeight: 44),
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                decoration: BoxDecoration(
                                  color: s == _source
                                      ? AppColors.darkBgHover
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                  child: Text(
                                    s,
                                    style: TextStyle(
                                      color: s == _source
                                          ? AppColors.darkText
                                          : AppColors.darkTextM,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (!searching) const SizedBox(width: 10),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (visible.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 18),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    searching
                                        ? 'No matching models'
                                        : 'Nothing here yet',
                                    style: const TextStyle(
                                      color: AppColors.darkTextM,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (searching)
                                    TextButton(
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _query = '');
                                      },
                                      child: const Text('Clear search'),
                                    ),
                                ],
                              ),
                            ),
                          for (final e in visible)
                            ListTile(
                              dense: true,
                              title: Text(
                                e.name,
                                style: const TextStyle(
                                  color: AppColors.darkText,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                searching ? '${e.source} · ${e.meta}' : e.meta,
                                style: const TextStyle(
                                  color: AppColors.darkTextD,
                                  fontSize: 11,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (e.trailing != null) e.trailing!,
                                  if (e.starModel != null)
                                    IconButton(
                                      icon: Icon(
                                        (_fav[e.starModel] ?? false)
                                            ? Icons.star
                                            : Icons.star_border,
                                        size: 18,
                                        color: (_fav[e.starModel] ?? false)
                                            ? AppColors.accentHi
                                            : AppColors.darkTextM,
                                      ),
                                      tooltip: (_fav[e.starModel] ?? false)
                                          ? 'Remove from favorites'
                                          : 'Add to favorites',
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minWidth: 44,
                                        minHeight: 44,
                                      ),
                                      onPressed: () {
                                        final v = !(_fav[e.starModel] ?? false);
                                        setState(() => _fav[e.starModel!] = v);
                                        widget.onToggleStar?.call(e, v);
                                      },
                                    ),
                                  if (e.name == widget.selectedName)
                                    const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: AppColors.accentHi,
                                    ),
                                ],
                              ),
                              onTap: () => widget.onPick(e),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
