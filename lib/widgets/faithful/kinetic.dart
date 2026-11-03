// KineticGrid — FAITHFUL PORT from the banked source (pack kinetic-grid).
// Full-bleed interactive background: fine dot lattice + a warped line grid.
// Mechanics translated 1:1 (spacing 55, warp radius 260, attraction curve,
// edge falloff, ripple suck-to-ring, pointer smoothing .08). Color is the
// only deviation, per founder law: the original's blue active hue becomes
// Astro purple; base lines stay white.
// ignore_for_file: always_use_package_imports
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/app_colors.dart';

const double _spacing = 55; // Hd
const double _warpRadius = 260; // pf
const double _warpDepth = 24; // hy
const double _dotSpacing = 28; // Fn
const double _nodeR0 = 1.8, _nodeR1 = 3.2; // vy, gy
const double _pointerEase = 0.08; // qd

class _Ripple {
  final Offset center;
  final double born; // seconds
  _Ripple(this.center, this.born);
}

class KineticGrid extends StatefulWidget {
  const KineticGrid({super.key, this.subtle = false});

  /// Subtle mode (Kai, 2026-11-03: full-bleed welcome grid was "a little
  /// much"): static lattice only — no pointer warp, no tap ripples,
  /// lines/nodes at roughly half alpha. Mechanics otherwise identical.
  final bool subtle;

  @override
  State<KineticGrid> createState() => _KineticGridState();
}

class _KineticGridState extends State<KineticGrid> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _tick = ValueNotifier<double>(0);
  double _t = 0;
  double _last = 0;
  Offset _pointer = const Offset(-9999, -9999);
  Offset _pointerTarget = const Offset(-9999, -9999);
  final List<_Ripple> _ripples = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration e) {
    final now = e.inMicroseconds / 1e6;
    final dt = now - _last;
    _last = now;
    if (dt <= 0) return;
    _t += dt;
    _pointer = Offset(
      _pointer.dx + (_pointerTarget.dx - _pointer.dx) * _pointerEase,
      _pointer.dy + (_pointerTarget.dy - _pointer.dy) * _pointerEase,
    );
    _ripples.removeWhere((r) => 1 - (_t - r.born) * 1.2 <= 0);
    _tick.value = _t;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart:
          widget.subtle ? null : (d) => _pointerTarget = d.localPosition,
      onPanUpdate:
          widget.subtle ? null : (d) => _pointerTarget = d.localPosition,
      onTapDown: widget.subtle
          ? null
          : (d) => _ripples.add(_Ripple(d.localPosition, _t)),
      child: CustomPaint(
        painter: _KineticPainter(
          repaint: _tick,
          t: () => _t,
          pointer: () => widget.subtle ? const Offset(-9999, -9999) : _pointer,
          ripples: () => widget.subtle ? const <_Ripple>[] : _ripples,
          subtle: widget.subtle,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _KineticPainter extends CustomPainter {
  final bool subtle;
  final double Function() t;
  final Offset Function() pointer;
  final List<_Ripple> Function() ripples;
  _KineticPainter({
    required Listenable repaint,
    required this.t,
    required this.pointer,
    required this.ripples,
    required this.subtle,
  }) : super(repaint: repaint);

  static double _smooth(double x) => x * x * (3 - 2 * x);
  static Color _lerpC(Color a, Color b, double s) => Color.lerp(a, b, s)!;

  @override
  void paint(Canvas canvas, Size size) {
    final now = t();
    final ptr = pointer();
    final rips = ripples()
        .map((r) => (
              c: r.center,
              radius: (now - r.born) * 400,
              opacity: math.max(0.0, 1 - (now - r.born) * 1.2),
            ))
        .toList();

    final bg = Paint()..color = AppColors.darkBg; // void #050506
    canvas.drawRect(Offset.zero & size, bg);

    // Fine background dot lattice (source: Fn spacing, r .7, white .05).
    final dot = Paint()..color = const Color(0x0DFFFFFF);
    for (double x = _dotSpacing / 2; x < size.width; x += _dotSpacing) {
      for (double y = _dotSpacing / 2; y < size.height; y += _dotSpacing) {
        canvas.drawCircle(Offset(x, y), 0.7, dot);
      }
    }

    final cols = math.max(2, (size.width / _spacing).ceil()) + 1;
    final rows = math.max(2, (size.height / _spacing).ceil()) + 1;
    final stepX = size.width / (cols - 1);
    final stepY = size.height / (rows - 1);

    final pts = List.generate(
        rows, (_) => List<Offset>.filled(cols, Offset.zero));
    final prox = List.generate(rows, (_) => List<double>.filled(cols, 0));

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final fx = col * stepX, fy = row * stepY;
        final ej = math.min(col / 1.5, math.min((cols - 1 - col) / 1.5, 1.0));
        final ei = math.min(row / 1.5, math.min((rows - 1 - row) / 1.5, 1.0));
        final edge = ej * ej * ei * ei;
        double cx = 0, cy = 0;
        for (final rp in rips) {
          final dx = fx - rp.c.dx, dy = fy - rp.c.dy;
          final dist = math.sqrt(dx * dx + dy * dy);
          final sl = dist - rp.radius;
          if (sl.abs() < 55) {
            final d = (1 - sl.abs() / 55) * rp.opacity * 18 * edge;
            final ang = math.atan2(dy, dx);
            final h = sl < 0 ? -1.0 : 1.0;
            cx += math.cos(ang) * d * h * -1;
            cy += math.sin(ang) * d * h * -1;
          }
        }
        final dx = fx - ptr.dx, dy = fy - ptr.dy;
        final distP = math.sqrt(dx * dx + dy * dy);
        final z = math.max(0.0, 1 - distP / _warpRadius) * edge;
        prox[row][col] = z;
        if (distP < _warpRadius && distP > 0 && edge > 0) {
          final pl = distP / _warpRadius;
          final s = (pl < 0.01
                  ? 0.0
                  : (1 - pl) * (1 - pl) * math.min(1.0, distP / 60)) *
              _warpDepth *
              edge;
          final ang = math.atan2(dy, dx);
          pts[row][col] =
              Offset(fx - math.cos(ang) * s + cx, fy - math.sin(ang) * s + cy);
        } else {
          pts[row][col] = Offset(fx + cx, fy + cy);
        }
      }
    }

    final baseLine = subtle ? const Color(0x0FFFFFFF) : const Color(0x21FFFFFF); // white a .13 (.06 subtle)
    final baseNode = subtle ? const Color(0x14FFFFFF) : const Color(0x33FFFFFF); // white a .2 (.08 subtle)
    const activeLine = Color(0xE69333EA); // purple a .9
    const activeNode = Color(0xFF9333EA);

    final linePaint = Paint()..strokeCap = StrokeCap.butt;
    void seg(Offset a, Offset b, double pa, double pb) {
      final s = _smooth((pa + pb) / 2);
      linePaint
        ..color = _lerpC(baseLine, activeLine, s)
        ..strokeWidth = 0.8 + (1.5 - 0.8) * s;
      canvas.drawLine(a, b, linePaint);
    }

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols - 1; col++) {
        seg(pts[row][col], pts[row][col + 1], prox[row][col], prox[row][col + 1]);
      }
    }
    for (var col = 0; col < cols; col++) {
      for (var row = 0; row < rows - 1; row++) {
        seg(pts[row][col], pts[row + 1][col], prox[row][col], prox[row + 1][col]);
      }
    }

    final nodePaint = Paint();
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final pl = prox[row][col];
        final ul = _smooth(pl);
        final r = _nodeR0 + (_nodeR1 - _nodeR0) * ul;
        final p = pts[row][col];
        if (ul > 0.3) {
          final gr = r + (ul - 0.3) / 0.7 * 6;
          final glow = Paint()
            ..shader = RadialGradient(
              colors: [
                const Color(0xFF9333EA).withValues(alpha: ul * 0.3),
                const Color(0xFF9333EA).withValues(alpha: 0),
              ],
            ).createShader(
                Rect.fromCircle(center: p, radius: gr));
          canvas.drawCircle(p, gr, glow);
        }
        nodePaint.color = _lerpC(baseNode, activeNode, ul);
        canvas.drawCircle(p, r, nodePaint);
      }
    }

    final ripplePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final rp in rips) {
      ripplePaint.color =
          const Color(0xFFA855F7).withValues(alpha: rp.opacity * 0.28);
      canvas.drawCircle(rp.c, math.max(0.0, rp.radius), ripplePaint);
    }
  }

  @override
  bool shouldRepaint(_KineticPainter old) => true;
}
