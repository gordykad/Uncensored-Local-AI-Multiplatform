// MorphOrb — FAITHFUL PORT from the banked source (pack
// ai-thiking-orb-and-input, bundle-preview.html createOrb). Renderer math is
// translated 1:1: constants, ring layout, palette, excitation modes, easing.
// Choreography is adapted to the app's two states (idle / generating) using
// the source's own track values (appear spin .9; thinking sweep qh tracks).
// Founder law: the orb takes NO color change — the white->emerald palette is
// the original's and stays.

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const double _stage = 220; // source canvas logical size (ue)
const double _radius = 66; // source sphere radius (Xr)
const double _tilt = 0.35; // source tilt angle
const int _rings = 16; // source Zr
const _easeOut = Cubic(0.22, 1, 0.36, 1); // source D.out

/// mulberry32 with the source's seed (7) — identical particle seeds.
/// JS int32 semantics reproduced with explicit masking.
class _Mulberry32 {
  int _s;
  _Mulberry32(this._s);
  static int _i32(int v) => v.toSigned(32);
  static int _u32(int v) => v & 0xFFFFFFFF;
  static int _shr(int v, int n) => _u32(v) >> n;
  static int _imul(int a, int b) => _i32(_i32(a) * _i32(b));

  double next() {
    _s = _i32(_s + 1831565813);
    var t = _s;
    t = _imul(t ^ _shr(t, 15), 1 | t);
    t = _i32(_i32(t + _imul(t ^ _shr(t, 7), 61 | t)) ^ t);
    return (_u32(t) ^ _shr(t, 14)) / 4294967296.0;
  }
}

class _OrbParticle {
  final double x, y, z, u, seed;
  const _OrbParticle(this.x, this.y, this.z, this.u, this.seed);
}

final List<_OrbParticle> _particles = _buildParticles();

List<_OrbParticle> _buildParticles() {
  final rng = _Mulberry32(7);
  final out = <_OrbParticle>[];
  for (var i = 0; i < _rings; i++) {
    final y = 1 - (i + 0.5) / _rings * 2;
    final r = math.sqrt(1 - y * y);
    final n = math.max(4, (30 * r).round());
    for (var j = 0; j < n; j++) {
      final th = j / n * math.pi * 2 + i * 0.35;
      out.add(
        _OrbParticle(
          math.cos(th) * r,
          y,
          math.sin(th) * r,
          (1 - y) / 2,
          rng.next() * 6.283,
        ),
      );
    }
  }
  return out;
}

/// 25 excitation rows (white -> emerald) x 49 alpha steps, as in the source.
final List<List<Color>> _palette = _buildPalette();

List<List<Color>> _buildPalette() {
  double lerp(double a, double b, double t) => a + (b - a) * t;
  final rows = <List<Color>>[];
  for (var i = 0; i <= 24; i++) {
    final u = i / 24;
    final r = lerp(235, 52, u).round();
    final g = lerp(235, 211, u).round();
    final b = lerp(235, 153, u).round();
    final row = <Color>[];
    for (var j = 0; j <= 48; j++) {
      row.add(Color.fromARGB((j / 48 * 255).round(), r, g, b));
    }
    rows.add(row);
  }
  return rows;
}

class ThinkingOrb extends StatefulWidget {
  final bool thinking;
  final double size;
  const ThinkingOrb({super.key, this.thinking = false, this.size = 120});

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _tick = ValueNotifier<double>(0);
  double _t = 0; // seconds, source I
  double _rot = 0; // source o.rot
  double _lastStamp = 0;
  // Per-particle excitation memory (source N) and mode weights (source K).
  final Float32List _hl = Float32List(_particles.length);
  final List<double> _k = [1, 0, 0, 0];
  double _sweep = 0; // source o.sweep (0 idle; 1 during the gather)
  double _sweepClock = -1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(ThinkingOrb old) {
    super.didUpdateWidget(old);
    if (widget.thinking && !old.thinking) _sweepClock = 0; // gather begins
  }

  void _onTick(Duration elapsed) {
    // Audit #3 (app-wide Reduce Motion): the sphere holds still.
    if (mounted && MediaQuery.disableAnimationsOf(context)) return;
    final now = elapsed.inMicroseconds / 1e6;
    var dt = now - _lastStamp;
    _lastStamp = now;
    if (dt > 0.05) dt = 0.05; // source clamps frame dt to .05
    if (dt <= 0) return;
    _t += dt;
    // Spin: source appear/thinking spin .9.
    _rot += 0.9 * dt;
    // Mode weights chase the active program (source K chase, rate dt/.35).
    final prog = widget.thinking ? (_t ~/ 0.9) % 4 : 0;
    final step = dt / 0.35;
    for (var j = 0; j < 4; j++) {
      final target = j == prog ? 1.0 : 0.0;
      final d = target - _k[j];
      _k[j] += d.abs() <= step ? d : (d > 0 ? step : -step);
    }
    // Sweep (thinking-start gather, qh tracks): 0->1 over .7s, hold, release.
    if (_sweepClock >= 0) {
      _sweepClock += dt;
      final c = _sweepClock;
      _sweep = c < 0.7
          ? const Cubic(0.65, 0, 0.35, 1).transform(c / 0.7)
          : c < 1.6
          ? 1
          : math.max(0, 1 - (c - 1.6) / 0.7);
      if (c > 2.3) _sweepClock = -1;
    }
    // Excitation decay memory (source exp(-dt/.5)).
    final decay = math.exp(-dt / 0.5);
    for (var i = 0; i < _hl.length; i++) {
      _hl[i] *= decay;
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
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _OrbPainter(
        repaint: _tick,
        t: () => _t,
        rot: () => _rot,
        k: () => _k,
        sweep: () => _sweep,
        hl: _hl,
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double Function() t;
  final double Function() rot;
  final List<double> Function() k;
  final double Function() sweep;
  final Float32List hl;
  _OrbPainter({
    required Listenable repaint,
    required this.t,
    required this.rot,
    required this.k,
    required this.sweep,
    required this.hl,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final time = t();
    final count = _particles.length;
    final scale = size.width / _stage;
    final c = size.width / 2;
    final yt = math.cos(_tilt), ut = math.sin(_tilt);
    final sw = sweep();
    final gain = 1 - sw; // source: sweep drives gain -> 0
    final floor = 0.95 * sw; // source floor -> .95
    final rad = 0.15 * sw; // source rad -> .15
    final kk = k();
    // Excitation sources (source draw loop).
    final e0 = (time * 300) % count;
    final e3 = (time * 480) % count;
    final nt = math.sin(time * 0.5) * 0.9;
    final yy = time * 0.8;
    final r1 = math.cos(nt) * math.cos(yy),
        z1 = math.sin(nt),
        j1 = math.cos(nt) * math.sin(yy);
    final ll = math.cos(time * 0.42) * 0.9;
    final xx = time * 0.55 + 2.1;
    final o2 = math.cos(ll) * math.cos(xx),
        t2 = math.sin(ll),
        c2 = math.cos(ll) * math.sin(xx);
    final wBand = math.sin(time * 2.2);
    final rotX = rot();
    final et = math.cos(rotX), il = math.sin(rotX);

    final paint = Paint();
    // Two passes: back (depth<.5) then front — the source's draw order.
    for (var pass = 0; pass < 2; pass++) {
      for (var j = 0; j < count; j++) {
        final p = _particles[j];
        double lt = 0;
        if (kk[0] > 0.001) {
          var d = (j - e0).abs();
          if (d > count - d) d = count - d;
          final el = math.max(0.0, 1 - d / 16);
          lt = math.max(lt, el * el * kk[0]);
        }
        if (kk[1] > 0.001) {
          final v1 = math.max(
            0.0,
            (p.x * r1 + p.y * z1 + p.z * j1 - 0.72) / 0.28,
          );
          final v2 = math.max(
            0.0,
            (p.x * o2 + p.y * t2 + p.z * c2 - 0.72) / 0.28,
          );
          final jl = math.max(v1, v2);
          lt = math.max(lt, jl * jl * kk[1]);
        }
        if (kk[2] > 0.001) {
          final d = p.y - wBand;
          final el = math.max(0.0, 1 - d * d / 0.02);
          lt = math.max(lt, el * el * kk[2]);
        }
        if (kk[3] > 0.001) {
          var d = (j - e3).abs();
          if (d > count - d) d = count - d;
          final el = math.max(0.0, 1 - d / 22);
          lt = math.max(lt, el * el * kk[3]);
        }
        final wt = math.max(hl[j], lt * gain);
        if (wt > hl[j]) hl[j] = wt;
        final form = (1 * (1 + 0.6) - 0.6 * p.u).clamp(0.0, 1.0); // k=1
        if (form <= 0.001) continue;
        final fe = _easeOut.transform(form);
        final mt = p.x * et + p.z * il;
        final nl = -p.x * il + p.z * et;
        final hc = p.y * yt - nl * ut;
        final ke = p.y * ut + nl * yt;
        final je = 2.8 / (2.8 - ke);
        final ma = (ke + 1) / 2;
        if ((ma >= 0.5) != (pass == 1)) continue;
        final px = c + mt * _radius * fe * je * scale;
        final py = c - hc * _radius * fe * je * scale;
        final hlSweep = ((sw * 1.4 - p.u) / 0.4).clamp(0.0, 1.0);
        var ft =
            0.1 +
            0.035 * math.sin(p.seed + time * 1.6) * (1 - hlSweep) +
            0.32 * ma * ma +
            0.75 * wt * (1 - hlSweep) +
            hlSweep * (0.55 + 0.4 * ma) +
            2 * hlSweep * (1 - hlSweep);
        ft = math.max(ft, floor * (0.7 + 0.3 * ma));
        if (ft > 1) ft = 1;
        ft *= fe; // alpha (orb.alpha = 1 in app states)
        final fu = (ft * 48).round();
        if (fu <= 0) continue;
        final yc = (hlSweep * 24).round();
        final q =
            (1.15 * (0.45 + 0.75 * ma) * je + 0.9 * wt + hlSweep * 0.25) *
            (1 + rad) *
            (0.4 + 0.6 * fe);
        paint.color = _palette[yc][fu];
        canvas.drawCircle(Offset(px, py), q * scale, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => true;
}
