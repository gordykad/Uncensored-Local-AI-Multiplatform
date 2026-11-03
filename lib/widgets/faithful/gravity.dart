// GravityStars — FAITHFUL PORT from the banked source (pack gravity-stars).
// A starfield with pointer gravity + tangential swirl, twinkle sprites and
// proximity link lines. All constants are the source's defaults: count 220
// (x0.6 under 640px wide), gravity 4e6 with 676 softening, cap 5000, swirl
// .85, drag .03, speed cap 1200, link distance 130, glow sprite gradient
// stops (0/1, .06/.95, .14/.5, .28/.16, .55/.04, 1/0). Palette is the only
// deviation (founder color law): white base + purple cool/warm, tint .5.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class GravityStars extends StatefulWidget {
  final double height;
  const GravityStars({super.key, this.height = 220});

  @override
  State<GravityStars> createState() => _GravityStarsState();
}

class _Star {
  double x, y, vx, vy, dx, dy, e, ut, phase, rate;
  int pal;
  _Star(this.x, this.y, this.vx, this.vy, this.dx, this.dy, this.e, this.ut,
      this.phase, this.rate, this.pal);
}

class _GravityStarsState extends State<GravityStars>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _tick = ValueNotifier<double>(0);
  final _rng = math.Random(7);
  List<_Star> _stars = [];
  Size _size = Size.zero;
  Offset? _pointer;
  double _t = 0;
  double _last = 0;

  static const _baseCount = 220;
  static const _linkDist = 130.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _seed(Size size) {
    _size = size;
    final count =
        size.width < 640 ? math.max(8, (_baseCount * 0.6).round()) : _baseCount;
    _stars = List.generate(count, (_) {
      final e = 1.15 * (1 + (_rng.nextDouble() - 0.5) * 0.8);
      final ut = 1 + (_rng.nextDouble() - 0.5) * 0.5;
      final ang = _rng.nextDouble() * math.pi * 2;
      final spd = 12 * (0.15 + ut);
      final pal = (((_rng.nextDouble() + _rng.nextDouble()) / 2) * 4).floor();
      return _Star(
        _rng.nextDouble() * size.width,
        _rng.nextDouble() * size.height,
        0,
        0,
        math.cos(ang) * spd,
        math.sin(ang) * spd,
        e,
        ut,
        _rng.nextDouble() * math.pi * 2,
        0.6 + _rng.nextDouble() * 1.2,
        pal.clamp(0, 3),
      );
    });
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    var dt = now - _last;
    _last = now;
    if (dt <= 0) return;
    if (dt > 0.05) dt = 0.05;
    _t += dt;
    if (_stars.isEmpty || _size == Size.zero) return;
    final dragK = math.pow(1 - 0.03, dt * 60).toDouble();
    for (final s in _stars) {
      double ax = 0, ay = 0;
      final p = _pointer;
      if (p != null) {
        final dx = p.dx - s.x, dy = p.dy - s.y;
        final q = 260 * (1 + s.e * 0.8);
        final d2 = dx * dx + dy * dy;
        if (d2 < q * q) {
          final dist = math.sqrt(d2);
          final jt = math.sqrt(d2 + 676);
          final jl = 0.55 + s.e * 1.0;
          var dl = math.min(4e6 * jl / (jt * jt), 5000.0);
          final kt = 1 - dist / q;
          dl *= kt * kt;
          if (jt > 0) {
            final ux = dx / jt, uy = dy / jt;
            ax += ux * dl - uy * dl * 0.85;
            ay += uy * dl + ux * dl * 0.85;
          }
        }
      }
      var nvx = (s.vx + ax * dt) * dragK;
      var nvy = (s.vy + ay * dt) * dragK;
      final sp2 = nvx * nvx + nvy * nvy;
      if (sp2 > 1200 * 1200) {
        final f = 1200 / math.sqrt(sp2);
        nvx *= f;
        nvy *= f;
      }
      s.vx = nvx;
      s.vy = nvy;
      s.x += (nvx + s.dx) * dt;
      s.y += (nvy + s.dy) * dt;
      if (s.x < 0) s.x += _size.width;
      if (s.x > _size.width) s.x -= _size.width;
      if (s.y < 0) s.y += _size.height;
      if (s.y > _size.height) s.y -= _size.height;
    }
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
    return LayoutBuilder(
      builder: (_, box) {
        final size = Size(box.maxWidth, widget.height);
        if (_size != size) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _seed(size);
          });
        }
        return GestureDetector(
          onPanStart: (d) => _pointer = d.localPosition,
          onPanUpdate: (d) => _pointer = d.localPosition,
          onPanEnd: (_) => _pointer = null,
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _GravityPainter(
                repaint: _tick,
                stars: () => _stars,
                t: () => _t,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GravityPainter extends CustomPainter {
  final List<_Star> Function() stars;
  final double Function() t;
  _GravityPainter({
    required Listenable repaint,
    required this.stars,
    required this.t,
  }) : super(repaint: repaint);

  static const _palBase = Color(0xFFE8E8F0);
  static const _palCool = Color(0xFFA855F7);
  static const _palWarm = Color(0xFFF2F2F0);

  Color _starColor(int pal) {
    final u = pal / 3;
    final mixed = Color.lerp(_palCool, _palWarm, u)!;
    return Color.lerp(_palBase, mixed, 0.5)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ss = stars();
    final now = t();
    // Link lines (source: 6 alpha buckets over palette base).
    final linePaint = Paint()..strokeWidth = 0.3;
    for (var i = 0; i < ss.length; i++) {
      for (var j = i + 1; j < ss.length; j++) {
        final a = ss[i], b = ss[j];
        final dx = a.x - b.x, dy = a.y - b.y;
        final d2 = dx * dx + dy * dy;
        if (d2 > _GravityStarsState._linkDist * _GravityStarsState._linkDist ||
            d2 == 0) {
          continue;
        }
        final d = math.sqrt(d2);
        final jl = math.pow(1 - d / _GravityStarsState._linkDist, 1.5);
        final dl = 0.25 + (a.e + b.e) / 2 * 0.75;
        final bucket = math.min(5, (jl * dl * 6).floor());
        linePaint
          ..strokeWidth = 0.3 + bucket * 0.12
          ..color = _palBase.withValues(alpha: 0.3 * (bucket + 1) / 6);
        canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), linePaint);
      }
    }
    // Stars (source glow sprites).
    for (final s in ss) {
      final tw = math.sin(now * s.rate + s.phase);
      final alpha =
          (0.18 + s.e * 0.82) * (1 - 0.55 * 0.5 * (1 - tw));
      final kt = alpha.clamp(0.0, 1.0);
      if (kt <= 0.01) continue;
      final r = 1.5 * (0.42 + s.e * 1.9) * s.ut * 5.5 * (0.6 + s.e * 0.7);
      final col = _starColor(s.pal);
      final rect = Rect.fromCircle(center: Offset(s.x, s.y), radius: r);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            col.withValues(alpha: kt),
            col.withValues(alpha: kt * 0.95),
            col.withValues(alpha: kt * 0.5),
            col.withValues(alpha: kt * 0.16),
            col.withValues(alpha: kt * 0.04),
            col.withValues(alpha: 0),
          ],
          stops: const [0, 0.06, 0.14, 0.28, 0.55, 1],
        ).createShader(rect);
      canvas.drawCircle(Offset(s.x, s.y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_GravityPainter old) => true;
}
