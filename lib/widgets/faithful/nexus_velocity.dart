// AskNexusInput (#24) + VelocityText (#23) — FAITHFUL PORTS from the
// banked sources (packs ask-nexus-input / velocity-text).
//
// #24 truth: placeholder rotates every 2800ms while the field is empty
// and idle. On submit the bar pulses scale [1, .985, 1] over .45s easeOut
// and the submitted text DISINTEGRATES on a canvas overlay: the text is
// rasterized at 14px, pixels with alpha > 110 become particles (sizes:
// 65% 1px, 27% 1.4px, 8% 1.8px). Disintegration sweeps RIGHT to LEFT:
// char delay = (len-1-charIndex) * 50ms + rand * 22ms. Each particle:
// velocity angle (rand-.5)*pi*.6, speed .18 + rand*.55 px/frame,
// vx = cos*speed + .12 (rightward bias), vy = sin*speed*.55; life
// 480 + rand*320ms; alpha = cos(progress * pi/2); an x sway of
// sin((originX + frames) * .22) * .4 * progress; in the last 80ms before
// its delay a particle jitters in place. When all particles die the
// field resets to idle. MiniX color: the source's rgb(17,24,39) ink ->
// primary text color on the dark bar.
//
// #23 truth: scrollYProgress velocity -> useSpring(damping 50,
// stiffness 400) -> skewX mapped [-1, 1] -> [45deg, -45deg]; a parallel
// x-drift from progress [0,1] -> [0,-3000] rides spring(mass 3,
// stiffness 400, damping 50). Poster type only (bank NOTES friction:
// never gate readability). In the app the driver is a ScrollController's
// progress velocity; constants unchanged.
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

// ---------------------------------------------------------------- nexus
class DisintegratingText extends StatefulWidget {
  final String text;
  final double fontSize;
  final Color color;
  final VoidCallback onDone;
  const DisintegratingText({
    super.key,
    required this.text,
    required this.color,
    required this.onDone,
    this.fontSize = 14,
  });

  @override
  State<DisintegratingText> createState() => _DisintegratingTextState();
}

class _Particle {
  final double ox, oy, vx, vy, delay, life, size;
  _Particle(this.ox, this.oy, this.vx, this.vy, this.delay, this.life,
      this.size);
}

class _DisintegratingTextState extends State<DisintegratingText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _tick = ValueNotifier<double>(0);
  List<_Particle> _ps = [];
  double _t = 0;
  bool _ready = false;
  bool _doneFired = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _rasterize();
  }

  Future<void> _rasterize() async {
    final style = TextStyle(fontSize: widget.fontSize, color: widget.color);
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = (painter.width + 90).ceil();
    final h = painter.height.ceil();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    painter.paint(canvas, Offset(0, 0));
    final img = await rec.endRecording().toImage(w, h);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null || !mounted) return;
    final data = bytes.buffer.asUint8List();
    // char x-ranges for the right-to-left delay wave
    final ranges = <(double, double)>[];
    double cx = 0;
    for (final ch in widget.text.characters) {
      final cp = TextPainter(
        text: TextSpan(text: ch, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      ranges.add((cx, cx + cp.width));
      cx += cp.width;
    }
    int charIdx(double x) {
      for (var i = 0; i < ranges.length; i++) {
        if (x >= ranges[i].$1 && x < ranges[i].$2) return i;
      }
      return ranges.length - 1;
    }

    final rng = math.Random();
    final len = widget.text.length;
    final ps = <_Particle>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final a = data[(y * w + x) * 4 + 3];
        if (a > 110) {
          final ci = charIdx(x.toDouble());
          final delay = (len - 1 - ci) * 50.0 + rng.nextDouble() * 22;
          final ang = (rng.nextDouble() - 0.5) * math.pi * 0.6;
          final spd = 0.18 + rng.nextDouble() * 0.55;
          final vx = math.cos(ang) * spd + 0.12;
          final vy = math.sin(ang) * spd * 0.55;
          final u = rng.nextDouble();
          final size = u < 0.65 ? 1.0 : (u < 0.92 ? 1.4 : 1.8);
          ps.add(_Particle(x.toDouble(), y.toDouble(), vx, vy, delay,
              480 + rng.nextDouble() * 320, size));
        }
      }
    }
    setState(() {
      _ps = ps;
      _ready = true;
    });
    _ticker.start();
  }

  void _onTick(Duration e) {
    _t = e.inMicroseconds / 1000.0;
    _tick.value = _t;
    var alive = false;
    for (final p in _ps) {
      if (_t < p.delay + p.life) {
        alive = true;
        break;
      }
    }
    if (!alive && !_doneFired) {
      _doneFired = true;
      _ticker.stop();
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return CustomPaint(
      painter: _DisintegratePainter(
        repaint: _tick,
        ps: _ps,
        t: () => _t,
        color: widget.color,
      ),
      size: Size.infinite,
    );
  }
}

class _DisintegratePainter extends CustomPainter {
  final List<_Particle> ps;
  final double Function() t;
  final Color color;
  final _rng = math.Random();
  _DisintegratePainter({
    required Listenable repaint,
    required this.ps,
    required this.t,
    required this.color,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final now = t();
    final paint = Paint();
    for (final p in ps) {
      if (now < p.delay) {
        double jx = 0, jy = 0;
        final until = p.delay - now;
        if (until < 80) {
          final q = 1 - until / 80;
          jx = (_rng.nextDouble() - 0.5) * 0.5 * q;
          jy = (_rng.nextDouble() - 0.5) * 0.5 * q;
        }
        paint.color = color;
        canvas.drawRect(
            Rect.fromLTWH(p.ox + jx, p.oy + jy, p.size, p.size), paint);
        continue;
      }
      final dt = now - p.delay;
      if (dt > p.life) continue;
      final prog = dt / p.life;
      final frames = dt / 16;
      final sway = math.sin((p.ox + frames) * 0.22) * 0.4;
      final x = p.ox + p.vx * frames + sway * prog;
      final y = p.oy + p.vy * frames;
      paint.color =
          color.withValues(alpha: math.cos(prog * math.pi / 2).clamp(0, 1));
      canvas.drawRect(Rect.fromLTWH(x, y, p.size, p.size), paint);
    }
  }

  @override
  bool shouldRepaint(_DisintegratePainter old) => true;
}

/// Rotating placeholder (2800ms) exactly as the source cycles it.
class RotatingPlaceholder extends StatefulWidget {
  final List<String> placeholders;
  final TextStyle style;
  const RotatingPlaceholder({
    super.key,
    required this.placeholders,
    required this.style,
  });

  @override
  State<RotatingPlaceholder> createState() => _RotatingPlaceholderState();
}

class _RotatingPlaceholderState extends State<RotatingPlaceholder> {
  int _i = 0;
  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 2800));
      if (!mounted) return false;
      setState(() => _i = (_i + 1) % widget.placeholders.length);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(widget.placeholders[_i], style: widget.style, maxLines: 1,
        overflow: TextOverflow.ellipsis);
  }
}

// ------------------------------------------------------------- velocity
class VelocityText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final ScrollController scroll;
  const VelocityText({
    super.key,
    required this.text,
    required this.style,
    required this.scroll,
  });

  @override
  State<VelocityText> createState() => _VelocityTextState();
}

class _VelocityTextState extends State<VelocityText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring;
  double _lastPos = 0;
  double _lastT = 0;
  double _skewDeg = 0;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController.unbounded(vsync: this, value: 0);
    _spring.addListener(() {
      if (mounted) setState(() => _skewDeg = _spring.value);
    });
    widget.scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final now = DateTime.now().microsecondsSinceEpoch / 1e6;
    if (_lastT == 0) {
      _lastT = now;
      _lastPos = widget.scroll.position.pixels;
      return;
    }
    final dt = (now - _lastT) / 1000;
    if (dt <= 0) return;
    final extent = (widget.scroll.hasClients &&
            widget.scroll.position.maxScrollExtent > 0)
        ? widget.scroll.position.maxScrollExtent
        : 1.0;
    final progressVel =
        ((widget.scroll.position.pixels - _lastPos) / extent) / dt;
    _lastT = now;
    _lastPos = widget.scroll.position.pixels;
    // source map: velocity [-1, 1] -> skew [45, -45] degrees, clamped
    final target = (-45 * progressVel).clamp(-45.0, 45.0);
    _spring.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 400, damping: 50),
        _spring.value,
        target,
        _spring.velocity,
      ),
    );
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform(
      transform: Matrix4.identity()
        ..setEntry(1, 0, math.tan(_skewDeg * math.pi / 180)),
      child: Text(widget.text, style: widget.style),
    );
  }
}
