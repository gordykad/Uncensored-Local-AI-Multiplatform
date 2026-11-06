// Faithful ports: TextShimmerWave (#20), Switch (#3), AiLoader (#19),
// spring number (#7) — from the banked sources.
//
// #20 truth (pack text-shimmer-wave): per-CHARACTER 3D wave under a 500px
// perspective. Char i delay = i * duration * (1/spread) / length; duration
// default 1s, spread 1; keyframes translateZ [0,10,0], X [0,2,0],
// Y [0,-2,0], scale [1,1.1,1], rotateY [0,10deg,0], color
// [base #71717a, highlight #ffffff, base]; ease easeInOut; repeats with
// repeatDelay = length * .05 / spread. translateZ is rendered via the
// perspective matrix + the source's own scale keyframe.
//
// #3 truth (pack switch): pill track, thumb circle inset 2px translating
// its own width, transition-all; checked = primary. Sizes: md 44x24,
// thumb 20. MiniX: checked = accent purple, track off = panel border tone,
// thumb white.
//
// #19 truth (pack ai-loader): 180px box; word letters centered, each with
// the loaderLetter cycle (3s infinite, delay i*.1s; 0/100% opacity .4,
// 20% opacity 1 + scale 1.15, 40% opacity .7); a full-circle overlay whose
// three INSET shadows (offsets 6/12/36, blurs 12/18/36) form a crescent
// that rotates 90 -> 270 -> 450 over 5s linear, plus two faint outer
// glows. Source blues mapped to the purple family (color law; the orb is
// the only color-locked component).
//
// #7 truth (pack animated-counter): the pack is a stepper whose readout
// number rides a framer-motion spring. Ported as a spring-physics number
// readout (SpringSimulation toward the target value).
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

// ---------------------------------------------------------------- shimmer
class TextShimmerWave extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double duration; // seconds, source default 1
  final double spread; // source default 1
  const TextShimmerWave({
    super.key,
    required this.text,
    required this.style,
    this.duration = 1,
    this.spread = 1,
  });

  @override
  State<TextShimmerWave> createState() => _TextShimmerWaveState();
}

class _TextShimmerWaveState extends State<TextShimmerWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    final cycle = widget.duration + widget.text.length * 0.05 / widget.spread;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (cycle * 1000).round()),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Audit #3 (app-wide Reduce Motion): shimmer becomes plain text.
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(widget.text, style: widget.style);
    }
    final n = widget.text.length;
    final base = const Color(0xFF71717A);
    final hi = const Color(0xFFFFFFFF);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final cycleT = _c.value; // 0..1 over duration + repeatDelay
        final activeFrac =
            widget.duration / (widget.duration + n * 0.05 / widget.spread);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < n; i++)
              _shimmerChar(widget.text[i], i, n, cycleT, activeFrac, base, hi),
          ],
        );
      },
    );
  }

  Widget _shimmerChar(
    String ch,
    int i,
    int n,
    double cycleT,
    double activeFrac,
    Color base,
    Color hi,
  ) {
    final delay = i * widget.duration * (1 / widget.spread) / n;
    final total = widget.duration + n * 0.05 / widget.spread;
    final local = ((cycleT * total - delay) / widget.duration).clamp(0.0, 1.0);
    final e = Curves.easeInOut.transform(local);
    // keyframe envelope: 0 -> 1 -> 0 across the duration
    final env = math.sin(e * math.pi);
    final style = widget.style.copyWith(color: Color.lerp(base, hi, env));
    final m = Matrix4.identity()
      ..setEntry(3, 2, 1 / 500)
      ..rotateY(10 * math.pi / 180 * env);
    return Transform(
      transform: m,
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(2 * env, -2 * env),
        child: Transform.scale(
          scale: 1 + 0.1 * env,
          child: Text(ch, style: style),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- switch
class MinixSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const MinixSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // UI audit 2026-11-06 (P1-7/P1-9, Codex P1-7/P1-11): VoiceOver
    // gets a toggled button identity, the hit area is 44pt tall
    // (visual track unchanged), motion snaps under Reduce Motion,
    // and the track colors read the tokens.
    final rm = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      toggled: value,
      onTap: () => onChanged(!value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: SizedBox(
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: rm ? Duration.zero : const Duration(milliseconds: 150),
              width: 44,
              height: 24,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? AppColors.accent : AppColors.darkBorder,
                borderRadius: BorderRadius.circular(999),
              ),
              child: AnimatedAlign(
                duration:
                    rm ? Duration.zero : const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
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
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- loader
class AiLoader extends StatefulWidget {
  final String text;
  final double size;
  const AiLoader({super.key, this.text = 'Generating', this.size = 180});

  @override
  State<AiLoader> createState() => _AiLoaderState();
}

class _AiLoaderState extends State<AiLoader> with TickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat();
  late final AnimationController _letters = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _ring.dispose();
    _letters.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ring,
            builder: (_, __) {
              final ang = (90 + 360 * _ring.value) * math.pi / 180;
              return Transform.rotate(
                angle: ang,
                child: CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _RingPainter(),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _letters,
            builder: (_, __) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.text.length; i++)
                    _letter(widget.text[i], i),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _letter(String ch, int i) {
    final delay = i * 0.1 / 3.0; // fraction of the 3s cycle
    var t = (_letters.value - delay) % 1.0;
    if (t < 0) t += 1;
    double opacity;
    double scale = 1;
    if (t < 0.2) {
      final k = Curves.easeOut.transform(t / 0.2);
      opacity = 0.4 + 0.6 * k;
      scale = 1 + 0.15 * k;
    } else if (t < 0.4) {
      final k = (t - 0.2) / 0.2;
      opacity = 1 - 0.3 * k;
      scale = 1.15 - 0.15 * k;
    } else {
      final k = (t - 0.4) / 0.6;
      opacity = 0.7 - 0.3 * k;
    }
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Text(
          ch,
          style: const TextStyle(
            color: Color(0xFFF2F2F0),
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    // outer glows (source: 0 0 3px 1.2px / 0 0 6px 1.8px, faint)
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFA855F7).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(c, r - 1, glow);
    // inset crescent: three blurred fills clipped inside, offset down —
    // the lit edge lands at the top inside of the circle (source geometry).
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    void layer(double dy, double blur, Color col) {
      final p = Paint()
        ..color = col
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      canvas.drawCircle(Offset(c.dx, c.dy + dy + r), r, p);
    }

    layer(36, 36, const Color(0xFF4C1D95));
    layer(12, 18, const Color(0xFF9333EA));
    layer(6, 12, const Color(0xFFC084FC));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RingPainter old) => false;
}

// ----------------------------------------------------------- spring number
class SpringNumber extends StatefulWidget {
  final double value;
  final TextStyle style;
  final int decimals;
  const SpringNumber({
    super.key,
    required this.value,
    required this.style,
    this.decimals = 0,
  });

  @override
  State<SpringNumber> createState() => _SpringNumberState();
}

class _SpringNumberState extends State<SpringNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  double _display = 0;

  @override
  void initState() {
    super.initState();
    _display = widget.value;
    _c = AnimationController.unbounded(vsync: this);
    _c.addListener(() {
      if (mounted) setState(() => _display = _c.value);
    });
  }

  @override
  void didUpdateWidget(SpringNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _c.animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 170, damping: 26),
          _display,
          widget.value,
          0,
        ),
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_display.toStringAsFixed(widget.decimals), style: widget.style);
  }
}
