// Text FX — FAITHFUL PORTS from the banked sources.
// #14 Motion Scramble Text (pack motion-scramble-text): 600ms rAF resolve;
//   prefix = floor(progress * len) real chars, EVERYTHING after re-randomized
//   each frame from the full glyph set.
// #22 Signal Reveal Text (pack signal-reveal-text): per-WORD loop — opacity
//   [0,1,1,0], y [.2em,0,0,-.08em], times [0,.16,.8,1], duration speed*3.1
//   (speed 1050 default), word stagger min(80, 480/(words-1)) ms,
//   ease cubic-bezier(.22,1,.36,1), repeats.
// #21 Blur Reveal (pack blur-reveal): per-CHARACTER entrance — opacity 0,
//   blur 12px, y 10 -> resolved; char duration .3/speedSegment (.6s at the
//   default .5), stagger .03/speedReveal (.02s at the default 1.5), one-way.
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// ── #14 Scramble ────────────────────────────────────────────────────────────

const String _scrambleGlyphs =
    '!@#\$%^&*()_+-=[]{}|;:,.<>?/~`░▒▓█▀▄■□▪▫●○◆◇◈◊※†‡';

class ScrambleText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const ScrambleText({super.key, required this.text, this.style});

  @override
  State<ScrambleText> createState() => _ScrambleTextState();
}

class _ScrambleTextState extends State<ScrambleText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
  }

  @override
  void didUpdateWidget(ScrambleText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _frame(double p) {
    final target = widget.text;
    final resolved = (p * target.length).floor();
    final b = StringBuffer();
    for (var i = 0; i < target.length; i++) {
      if (i < resolved || target[i] == ' ') {
        b.write(target[i]);
      } else {
        b.write(_scrambleGlyphs[_rng.nextInt(_scrambleGlyphs.length)]);
      }
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Text(
        _ctrl.isAnimating ? _frame(_ctrl.value) : widget.text,
        style: widget.style,
      ),
    );
  }
}

// ── #22 Signal Reveal (looping word cycle) ──────────────────────────────────

class SignalReveal extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int speed; // source default 1050, clamped 650..1800
  const SignalReveal({super.key, required this.text, this.style, this.speed = 1050});

  @override
  State<SignalReveal> createState() => _SignalRevealState();
}

class _SignalRevealState extends State<SignalReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<String> _words;
  late final double _staggerMs;

  @override
  void initState() {
    super.initState();
    _words = widget.text.trim().split(RegExp(r'\s+'));
    _staggerMs =
        _words.length > 1 ? math.min(80.0, 480 / (_words.length - 1)) : 0;
    final speed = widget.speed.clamp(650, 1800);
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (speed * 3.1).round()),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _word(String w, int i, double fontSize) {
    final total = _ctrl.duration!.inMilliseconds.toDouble();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final local =
            ((_ctrl.value * total - i * _staggerMs) / total).clamp(0.0, 1.0);
        // keyframes: opacity [0,1,1,0] at times [0,.16,.8,1]; ease per segment
        double op;
        if (local < 0.16) {
          op = const Cubic(0.22, 1, 0.36, 1).transform(local / 0.16);
        } else if (local < 0.8) {
          op = 1;
        } else {
          op = 1 - const Cubic(0.22, 1, 0.36, 1).transform((local - 0.8) / 0.2);
        }
        double yEm;
        if (local < 0.16) {
          yEm = 0.2 * (1 - const Cubic(0.22, 1, 0.36, 1).transform(local / 0.16));
        } else if (local < 0.8) {
          yEm = 0;
        } else {
          yEm = -0.08 * const Cubic(0.22, 1, 0.36, 1).transform((local - 0.8) / 0.2);
        }
        return Transform.translate(
          offset: Offset(0, yEm * fontSize),
          child: Opacity(opacity: op, child: Text(w, style: widget.style)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final fs = (widget.style?.fontSize ?? 16);
    return Wrap(
      spacing: fs * 0.28,
      children: [for (var i = 0; i < _words.length; i++) _word(_words[i], i, fs)],
    );
  }
}

// ── #21 Blur Reveal (per-character entrance) ────────────────────────────────

class BlurReveal extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double speedReveal; // source default 1.5
  final double speedSegment; // source default .5
  const BlurReveal({
    super.key,
    required this.text,
    this.style,
    this.speedReveal = 1.5,
    this.speedSegment = 0.5,
  });

  @override
  State<BlurReveal> createState() => _BlurRevealState();
}

class _BlurRevealState extends State<BlurReveal>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _tick = ValueNotifier<double>(0);
  double _t = 0;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      final now = e.inMicroseconds / 1e6;
      final dt = now - _last;
      _last = now;
      if (dt > 0) {
        _t += dt;
        _tick.value = _t;
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // UI audit 2026-11-06 (Codex P1-11): under Reduce Motion the
    // reveal renders its end state as plain text, no ticker work.
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(widget.text, style: widget.style);
    }
    final stagger = 0.03 / widget.speedReveal; // seconds per char
    final dur = 0.3 / widget.speedSegment;
    final chars = widget.text.split('');
    return AnimatedBuilder(
      animation: _tick,
      builder: (_, __) {
        final spans = <InlineSpan>[];
        for (var i = 0; i < chars.length; i++) {
          final p = ((_t - i * stagger) / dur).clamp(0.0, 1.0);
          spans.add(WidgetSpan(
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - p)),
              child: Opacity(
                opacity: p,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                      sigmaX: 12 * (1 - p), sigmaY: 12 * (1 - p)),
                  child: Text(chars[i] == ' ' ? ' ' : chars[i],
                      style: widget.style),
                ),
              ),
            ),
          ));
        }
        return RichText(text: TextSpan(children: spans));
      },
    );
  }
}
