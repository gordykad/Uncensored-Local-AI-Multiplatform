// SonarGrid — FAITHFUL PORT from the banked source (pack sonar-grid).
// Defaults are the source's props: spacing 26, dotRadius 1.4, baseOpacity
// .28, pingEvery 2.4s, speed 260 px/s, ringWidth 90, amplitude 2.2,
// maxRings 6, seed ping on mount, auto pings inside pingArea
// [.15,.2,.85,.8], tap fires a ping. Single uniform color (the source reads
// CSS color); MiniX uses primary text at the source's alpha mechanics.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class SonarGrid extends StatefulWidget {
  final double height;
  const SonarGrid({super.key, this.height = 190});

  @override
  State<SonarGrid> createState() => _SonarGridState();
}

class _Ring {
  final Offset c;
  final double born;
  _Ring(this.c, this.born);
}

class _SonarGridState extends State<SonarGrid> with SingleTickerProviderStateMixin {
  static const _spacing = 26.0;
  static const _dotR = 1.4;
  static const _baseOp = 0.28;
  static const _pingEvery = 2.4;
  static const _speed = 260.0;
  static const _ringWidth = 90.0;
  static const _amp = 2.2;
  static const _maxRings = 6;

  late final Ticker _ticker;
  final _tick = ValueNotifier<double>(0);
  final List<_Ring> _rings = [];
  final _rng = math.Random();
  double _t = 0;
  double _last = 0;
  double _nextPing = _pingEvery;
  bool _seeded = false;

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
    _tick.value = _t;
  }

  void _addRing(Offset c, double born) {
    _rings.add(_Ring(c, born));
    while (_rings.length > _maxRings) {
      _rings.removeAt(0);
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
    return GestureDetector(
      onTapDown: (d) => _addRing(d.localPosition, _t),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SonarPainter(
            repaint: _tick,
            t: () => _t,
            rings: _rings,
            onSeed: (size) {
              if (!_seeded) {
                _seeded = true;
                _addRing(
                  Offset(size.width * (0.15 + (0.85 - 0.15) * 0.68),
                      size.height * (0.2 + (0.8 - 0.2) * 0.34)),
                  _t - 0.5,
                );
              }
              if (_t >= _nextPing) {
                _nextPing = _t + _pingEvery;
                _addRing(
                  Offset(
                    size.width * (0.15 + _rng.nextDouble() * 0.7),
                    size.height * (0.2 + _rng.nextDouble() * 0.6),
                  ),
                  _t,
                );
              }
            },
          ),
        ),
      ),
    );
  }
}

class _SonarPainter extends CustomPainter {
  final double Function() t;
  final List<_Ring> rings;
  final void Function(Size) onSeed;
  _SonarPainter({
    required Listenable repaint,
    required this.t,
    required this.rings,
    required this.onSeed,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    onSeed(size);
    final now = t();
    final maxAge = (math.sqrt(size.width * size.width + size.height * size.height) +
            _SonarGridState._ringWidth) /
        _SonarGridState._speed;
    rings.removeWhere((r) => now - r.born >= maxAge);
    final active = rings
        .map((r) {
          final age = now - r.born;
          return (
            c: r.c,
            radius: age * _SonarGridState._speed,
            reach: age * _SonarGridState._speed + _SonarGridState._ringWidth,
            fade: 1 - age / maxAge,
          );
        })
        .toList();

    const color = Color(0xFFF2F2F0);
    final cols = (size.width / _SonarGridState._spacing).ceil() + 1;
    final rows = (size.height / _SonarGridState._spacing).ceil() + 1;
    final ox = (size.width - (cols - 1) * _SonarGridState._spacing) / 2;
    final oy = (size.height - (rows - 1) * _SonarGridState._spacing) / 2;

    final basePaint = Paint()..color = color.withValues(alpha: _SonarGridState._baseOp);
    final hotPaint = Paint()..color = color;
    for (var i = 0; i < cols; i++) {
      for (var j = 0; j < rows; j++) {
        final x = ox + i * _SonarGridState._spacing;
        final y = oy + j * _SonarGridState._spacing;
        double ui = 0;
        for (final r in active) {
          if ((x - r.c.dx).abs() > r.reach || (y - r.c.dy).abs() > r.reach) {
            continue;
          }
          final d = math.sqrt(
              (x - r.c.dx) * (x - r.c.dx) + (y - r.c.dy) * (y - r.c.dy));
          final jl = (d - r.radius).abs();
          if (jl >= _SonarGridState._ringWidth) continue;
          final hn = 1 - jl / _SonarGridState._ringWidth;
          final de = hn * hn * (3 - 2 * hn) * r.fade;
          if (de > ui) ui = de;
        }
        if (ui < 0.01) {
          canvas.drawCircle(Offset(x, y), _SonarGridState._dotR, basePaint);
        } else {
          hotPaint.color = color.withValues(
              alpha: _SonarGridState._baseOp +
                  (1 - _SonarGridState._baseOp) * ui);
          canvas.drawCircle(
            Offset(x, y),
            _SonarGridState._dotR * (1 + _SonarGridState._amp * ui),
            hotPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SonarPainter old) => true;
}
