import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MiniX text effects — faithful Flutter ports of the banked 21st components
// (ticket 08, founder motion law: original mechanics exactly, color the only
// change; see .scratch/minix-v2/design/COMPONENT-MAP.md).
// ─────────────────────────────────────────────────────────────────────────────

/// Redaction-bar motif (DESIGN.md §3): pure-black bars, 2px radius, groups
/// of 2–4, never over functional content.
class RedactionBars extends StatelessWidget {
  final List<double> widths;
  final double barHeight;
  const RedactionBars({
    super.key,
    this.widths = const [120, 84, 142, 64],
    this.barHeight = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < widths.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Container(
            width: widths[i],
            height: barHeight,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: AppColors.darkBorder, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}

/// #14 Motion Scramble Text — noise glyphs resolve left-to-right in mono,
/// auto-cycling is the host's choice (here: re-scrambles whenever [text]
/// changes, which is how status lines use it).
class ScrambleText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration duration;
  const ScrambleText({
    super.key,
    required this.text,
    this.style,
    this.duration = const Duration(milliseconds: 700),
  });

  @override
  State<ScrambleText> createState() => _ScrambleTextState();
}

class _ScrambleTextState extends State<ScrambleText> {
  static const _glyphs = 'ABCDEFHIJKLMNOPQRSTUVWXYZ0123456789#%&@$';
  final _rng = Random();
  Timer? _timer;
  String _shown = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(ScrambleText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _run();
  }

  void _run() {
    _timer?.cancel();
    final target = widget.text;
    final steps = max(1, widget.duration.inMilliseconds ~/ 30);
    int frame = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      frame++;
      final locked = (frame / steps * target.length).floor();
      final buf = StringBuffer();
      for (int i = 0; i < target.length; i++) {
        if (i < locked || target[i] == ' ') {
          buf.write(target[i]);
        } else {
          buf.write(_glyphs[_rng.nextInt(_glyphs.length)]);
        }
      }
      if (mounted) setState(() => _shown = buf.toString());
      if (frame >= steps) {
        t.cancel();
        if (mounted) setState(() => _shown = target);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _shown,
      style: (widget.style ??
              TextStyle(fontSize: 12, color: context.textD))
          .copyWith(fontFamily: 'monospace'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// #20 Text Shimmer Wave — a per-character brightness wave travels through
/// the letters in a loop. No controls, per the original.
class ShimmerText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const ShimmerText({super.key, required this.text, this.style});

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? TextStyle(fontSize: 12, color: context.textM);
    final baseColor = base.color ?? AppColors.darkTextM;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final head = _ctrl.value * (widget.text.length + 6) - 3;
        return RichText(
          text: TextSpan(
            children: [
              for (int i = 0; i < widget.text.length; i++)
                TextSpan(
                  text: widget.text[i],
                  style: base.copyWith(
                    color: Color.lerp(
                      baseColor,
                      AppColors.accentHi,
                      (1 - (i - head).abs() / 3).clamp(0.0, 1.0) * 0.9,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// #22 Signal Reveal Text — SOFT blur/fade focus-pull: ghost text resolving
/// to solid, once per appearance (~800ms). NOT static/noise (frame-checked
/// against the banked original during the artifact audit).
class SignalReveal extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  const SignalReveal({super.key, required this.text, this.style, this.textAlign});

  @override
  State<SignalReveal> createState() => _SignalRevealState();
}

class _SignalRevealState extends State<SignalReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final style = widget.style ?? TextStyle(fontSize: 17, color: context.text);
    if (reduce) return Text(widget.text, style: style, textAlign: widget.textAlign);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_ctrl.value);
        return Opacity(
          opacity: 0.25 + 0.75 * t,
          child: Transform.translate(
            offset: Offset(0, 4 * (1 - t)),
            child: Text(
              widget.text,
              style: style.copyWith(
                shadows: t < 1
                    ? [
                        Shadow(
                          color: AppColors.accent.withValues(alpha: 0.35 * (1 - t)),
                          blurRadius: 12 * (1 - t),
                        ),
                      ]
                    : null,
              ),
              textAlign: widget.textAlign,
            ),
          ),
        );
      },
    );
  }
}

/// #21 Blur Reveal — characters resolve out of blur one by one (staggered
/// blur+fade) as a one-way entrance.
class BlurReveal extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const BlurReveal({super.key, required this.text, this.style});

  @override
  State<BlurReveal> createState() => _BlurRevealState();
}

class _BlurRevealState extends State<BlurReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + widget.text.length * 45),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? TextStyle(fontSize: 17, color: context.text);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return RichText(
          text: TextSpan(
            children: [
              for (int i = 0; i < widget.text.length; i++)
                TextSpan(
                  text: widget.text[i],
                  style: base.copyWith(
                    color: (base.color ?? AppColors.darkText).withValues(
                      alpha: ((_ctrl.value * (widget.text.length + 4) - i) / 4)
                          .clamp(0.08, 1.0),
                    ),
                    shadows: [
                      Shadow(
                        color: (base.color ?? AppColors.darkText).withValues(
                          alpha: (1 -
                                  ((_ctrl.value *
                                              (widget.text.length + 4) -
                                          i) /
                                      4)
                                      .clamp(0.0, 1.0)) *
                              0.8,
                        ),
                        blurRadius: 8 *
                            (1 -
                                ((_ctrl.value * (widget.text.length + 4) - i) /
                                        4)
                                    .clamp(0.0, 1.0)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// #13 Glitch Text — periodic red/cyan RGB-split slices that snap back.
/// (Colors here are the component's own identity — slices are RGB by
/// definition in the original; kept faithful.)
class GlitchText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const GlitchText({super.key, required this.text, this.style});

  @override
  State<GlitchText> createState() => _GlitchTextState();
}

class _GlitchTextState extends State<GlitchText> {
  final _rng = Random();
  Timer? _timer;
  double _dx = 0;
  bool _glitching = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer = Timer(Duration(milliseconds: 2200 + _rng.nextInt(2600)), () {
      if (!mounted) return;
      setState(() {
        _glitching = true;
        _dx = (_rng.nextDouble() - 0.5) * 6;
      });
      Timer(const Duration(milliseconds: 140), () {
        if (mounted) setState(() => _glitching = false);
        _schedule();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ??
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: context.text,
        );
    if (!_glitching) return Text(widget.text, style: style);
    return Stack(
      children: [
        Transform.translate(
          offset: Offset(_dx, 0),
          child: Text(widget.text,
              style: style.copyWith(
                  color: const Color(0xFFFF004C).withValues(alpha: 0.75))),
        ),
        Transform.translate(
          offset: Offset(-_dx, 0),
          child: Text(widget.text,
              style: style.copyWith(
                  color: const Color(0xFF00FFF9).withValues(alpha: 0.75))),
        ),
        Text(widget.text, style: style),
      ],
    );
  }
}

/// #25 Text Glitch Effect — tap scrambles with physics-eased glyph cycling
/// into the PAIRED string and back. Grayscale; purple only mid-flight.
class PairedGlitchText extends StatefulWidget {
  final String a;
  final String b;
  final TextStyle? style;
  const PairedGlitchText({super.key, required this.a, required this.b, this.style});

  @override
  State<PairedGlitchText> createState() => _PairedGlitchTextState();
}

class _PairedGlitchTextState extends State<PairedGlitchText> {
  static const _glyphs = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#%&@$';
  final _rng = Random();
  Timer? _timer;
  bool _onB = false;
  String _shown = '';
  bool _flying = false;

  @override
  void initState() {
    super.initState();
    _shown = widget.a;
  }

  void _flip() {
    if (_flying) return;
    final target = _onB ? widget.a : widget.b;
    _onB = !_onB;
    _flying = true;
    final len = max(widget.a.length, widget.b.length);
    final start = DateTime.now();
    const total = Duration(milliseconds: 650);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 28), (t) {
      final raw = DateTime.now().difference(start).inMilliseconds /
          total.inMilliseconds;
      if (raw >= 1) {
        t.cancel();
        if (mounted) {
          setState(() {
            _shown = target;
            _flying = false;
          });
        }
        return;
      }
      // cubic ease-out, per-character lock with a stagger (physics feel)
      final eased = 1 - pow(1 - raw, 3).toDouble();
      final buf = StringBuffer();
      for (int i = 0; i < len; i++) {
        final lockAt = (i + 1) / (len + 1);
        if (eased >= lockAt) {
          if (i < target.length) buf.write(target[i]);
        } else if (target.startsWith(' ', i) || (i < target.length && target[i] == ' ')) {
          buf.write(' ');
        } else {
          buf.write(_glyphs[_rng.nextInt(_glyphs.length)]);
        }
      }
      if (mounted) setState(() => _shown = buf.toString());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ??
        TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.text);
    return GestureDetector(
      onTap: _flip,
      child: Text(
        _shown,
        style: base.copyWith(
          fontFamily: 'monospace',
          color: _flying ? AppColors.accentHi : base.color,
        ),
      ),
    );
  }
}

/// #7 Animated Counter — numeric readouts tween to their new value.
class AnimatedCounter extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle? style;
  final Duration duration;
  const AnimatedCounter({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 600),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, v, _) => Text(
        format(v),
        style: (style ?? TextStyle(fontSize: 12, color: context.textM))
            .copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}
