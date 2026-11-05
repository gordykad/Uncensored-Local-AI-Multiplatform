// MorphOrb — faithful Flutter port of the banked component
// "ai-thiking-orb-and-input" (anark17r via 21st.dev, MIT). Anatomy pack:
// ~/workspace/references/app-asset-bank/components/ai-thiking-orb-and-input/
// Port source: the live console TSX (ai-thiking-orb-and-input.tsx) —
// timeline tracks, easings, flight path, comet trail, and the canvas
// dot-sphere math carried over as-is. Two named adaptations for MiniX:
//  1. Purple-only recolor (Kai, 2026-11-05): the dot color sweep ends at
//     #9333EA and the condense ball is purple, not the source's emerald.
//  2. Variant #5 (Answer Card Mode) state binding: the run is driven by
//     REAL generation state, never a timer demo — launch on generation
//     start, think while it runs (Thinking before tokens, Composing
//     while they stream), resolve + condense + check on clean finish;
//     a stopped or errored run fades out with no check. The answer
//     itself is the chat bubble — its glitch-in is the card reveal.
//     The composer stays on screen throughout (MiniX's stop button must
//     stay reachable; the source locks its input, MiniX does not), so
//     the ball launches from the pill instead of collapsing it.
// The orb assembles at dead center stage of the chat area (46% height)
// — the seat the main orb held before Kai had it removed (2026-11-05).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_colors.dart';

const double _kCanvas = 220; // source canvas space
const double _kOrbR = 66;
const double _kOrbD = 132;
const double _kBallSmall = 60;
const double _kFlyD = 138;

/* ─────────────────────────── easing ─────────────────────────── */
// The source's cubic-bezier set; Flutter's Cubic is the same solver.
const Curve _eOut = Cubic(0.22, 1, 0.36, 1);
const Curve _eIo = Cubic(0.65, 0, 0.35, 1);
const Curve _eIn = Cubic(0.4, 0, 1, 1);
const Curve _eFly = Cubic(0.5, 0, 0.1, 1);
const Curve _eGrow = Cubic(0.3, 0, 0.2, 1);
const Curve _eVortex = Cubic(0.6, 0, 0.2, 1);
const Curve _eSpring = Cubic(0.34, 1.4, 0.64, 1);

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double _lerp(double a, double b, double t) => a + (b - a) * t;

/* ─────────────────────── timeline tracks ─────────────────────── */
class _Track {
  final String ch;
  final double from, to;
  final int t0, t1;
  final Curve ease;
  const _Track(this.ch, this.from, this.to, this.t0, this.t1,
      [this.ease = _eIo]);
}

const List<_Track> _launch = [
  _Track('w', _kBallSmall, _kFlyD, 620, 1300, _eGrow),
  _Track('w', _kFlyD, _kOrbD, 1300, 1500, _eOut),
  _Track('u', 0, 1, 620, 1500, _eFly),
  _Track('oBall', 0, 1, 300, 560, _eOut),
  _Track('cHalo', 0, 0.6, 620, 1500, _eOut),
  _Track('trail', 0, 1, 700, 800, _eOut),
  _Track('trail', 1, 0, 1300, 1500, _eIn),
];

const List<_Track> _assemble = [
  _Track('oBall', 1, 0, 0, 260, _eOut),
  _Track('orb.k', 0, 1, 0, 800, _eOut),
  _Track('orb.alpha', 0, 1, 0, 800, _eOut),
  _Track('orb.spin', 0, 0.9, 0, 800, _eOut),
  _Track('orb.pop', 1, 1.05, 0, 420, _eOut),
  _Track('orb.pop', 1.05, 1, 420, 800, _eIo),
  _Track('sOp', 0, 1, 300, 620, _eOut),
  _Track('sTy', 6, 0, 300, 620, _eOut),
];

const List<_Track> _resolve = [
  _Track('orb.sweep', 0, 1, 0, 700, _eIo),
  _Track('orb.spin', 0.9, 0.3, 0, 700, _eOut),
  _Track('orb.gain', 1, 0, 0, 700, _eOut),
  _Track('orb.floor', 0, 0.95, 400, 900, _eOut),
  _Track('orb.rad', 0, 0.15, 400, 900, _eOut),
  _Track('orb.pop', 1, 1.04, 600, 800, _eOut),
  _Track('orb.pop', 1.04, 1, 800, 900, _eOut),
];

const List<_Track> _condense = [
  _Track('orb.pop', 1, 1.06, 0, 120, _eOut),
  _Track('sOp', 1, 0, 0, 160, _eIn),
  _Track('sTy', 0, -6, 0, 160, _eIn),
  _Track('orb.k', 1, 0, 120, 640, _eVortex),
  _Track('orb.vortex', 0, 1.6, 120, 640, _eVortex),
  _Track('oGreen', 0, 1, 260, 700, _eSpring),
  _Track('gs', 0.55, 1, 260, 700, _eSpring),
  _Track('pulse', 0, 1, 320, 760, _eOut),
  _Track('oHalo', 0, 0.35, 380, 700, _eOut),
  _Track('orb.alpha', 1, 0, 500, 800, _eOut),
];

const List<_Track> _exit = [
  _Track('oGreen', 1, 0, 0, 240, _eOut),
  _Track('cHalo', 0.6, 0, 0, 240, _eOut),
  _Track('oHalo', 0.35, 0, 0, 240, _eOut),
];

const List<_Track> _fadeFail = [
  _Track('orb.alpha', 1, 0, 0, 400, _eOut),
  _Track('cHalo', 0.6, 0, 0, 400, _eOut),
  _Track('sOp', 1, 0, 0, 200, _eIn),
];

/* reduced-motion: pure cross-fades (the source's R_* tracks) */
const List<_Track> _rIn = [
  _Track('orb.alpha', 0, 1, 0, 200, _eOut),
  _Track('sOp', 0, 1, 0, 200, _eOut),
  _Track('cHalo', 0, 0.6, 0, 200, _eOut),
];
const List<_Track> _rResolve = [
  _Track('orb.sweep', 0, 1, 0, 250, _eIo),
  _Track('orb.floor', 0, 0.95, 0, 250, _eOut),
];
const List<_Track> _rCondense = [
  _Track('oGreen', 0, 1, 0, 250, _eOut),
  _Track('orb.alpha', 1, 0, 0, 250, _eOut),
  _Track('sOp', 1, 0, 0, 250, _eOut),
];

/* ───────────────────────── dot sphere ───────────────────────── */
class _Mulberry32 {
  int _a;
  _Mulberry32(this._a);
  static int _imul(int a, int b) => (a * b) & 0xFFFFFFFF;
  double next() {
    _a = (_a + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _a;
    t = _imul(t ^ (t >>> 15), 1 | t);
    t = (t + _imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) & 0xFFFFFFFF) / 4294967296.0;
  }
}

class _Dots {
  late final Float32List x, y, z, u, seed;
  late final int n;
  _Dots() {
    const rings = 16;
    final rand = _Mulberry32(7);
    final xs = <double>[], ys = <double>[], zs = <double>[];
    final us = <double>[], ss = <double>[];
    for (var k = 0; k < rings; k++) {
      final yy = 1 - ((k + 0.5) / rings) * 2;
      final r = math.sqrt(1 - yy * yy);
      final m = math.max(4, (30 * r).round());
      for (var j = 0; j < m; j++) {
        final a = (j / m) * (math.pi * 2) + k * 0.35;
        xs.add(math.cos(a) * r);
        ys.add(yy);
        zs.add(math.sin(a) * r);
        us.add((1 - yy) / 2);
        ss.add(rand.next() * 6.283);
      }
    }
    n = xs.length;
    x = Float32List.fromList(xs);
    y = Float32List.fromList(ys);
    z = Float32List.fromList(zs);
    u = Float32List.fromList(us);
    seed = Float32List.fromList(ss);
  }
}

final _Dots _dots = _Dots();

/* ─────────────────────────── widget ─────────────────────────── */
enum _Phase { idle, launch, assemble, think, resolve, condense, hold, exit, fadeFail }

class MorphOrbOverlay extends StatefulWidget {
  /// A generation (local, remote seat, or regenerate) is in flight.
  final bool running;

  /// Tokens are flowing (drives the Composing label + light program 3).
  final bool streaming;

  /// The last run ended on an error bubble (no check ball).
  final bool failed;

  /// Increments every time the user taps stop (no check ball).
  final int stopCount;

  /// MediaQuery.disableAnimations — the source's reduced-motion path.
  final bool reducedMotion;

  const MorphOrbOverlay({
    super.key,
    required this.running,
    required this.streaming,
    required this.failed,
    required this.stopCount,
    required this.reducedMotion,
  });

  @override
  State<MorphOrbOverlay> createState() => _MorphOrbOverlayState();
}

class _MorphOrbOverlayState extends State<MorphOrbOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);

  _Phase _phase = _Phase.idle;
  double _phaseT = 0; // ms inside the current phase
  double _lastTs = 0;
  double _elapsedMs = 0;
  bool _wasRunning = false;
  int _stopAtStart = 0;
  double _dir = -1;

  // Persistent channel values (the source's `vals`).
  final Map<String, double> _v = {
    'w': _kBallSmall, 'u': 0, 'oBall': 0, 'oGreen': 0, 'oHalo': 0,
    'gs': 0.55, 'pulse': -1, 'sOp': 0, 'sTy': 6, 'cHalo': 0, 'trail': 0,
    'orb.k': 0, 'orb.alpha': 0, 'orb.spin': 0, 'orb.pop': 1,
    'orb.sweep': 0, 'orb.vortex': 0, 'orb.gain': 1, 'orb.floor': 0,
    'orb.rad': 0,
  };

  // Orb sim state (the source's P + lit + flight history).
  double _time = 0, _rot = 0;
  int _prog = 0;
  late final Float32List _lit = Float32List(_dots.n);
  final List<({double t, double x, double y, double d})> _hist = [];

  double _ch(String k) => _v[k] ?? 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MorphOrbOverlay old) {
    super.didUpdateWidget(old);
    if (widget.running && !_wasRunning) _startRun();
    if (!widget.running && _wasRunning && _phase == _Phase.think) {
      _endThink();
    }
    _wasRunning = widget.running;
  }

  void _startRun() {
    _dir = -_dir;
    _stopAtStart = widget.stopCount;
    _lit.fillRange(0, _lit.length, 0);
    _hist.clear();
    _rot = 0;
    _prog = 0;
    _time = widget.reducedMotion ? 1.2 : 0;
    _v.addAll({
      'w': widget.reducedMotion ? _kOrbD : _kBallSmall,
      'u': widget.reducedMotion ? 1 : 0,
      'oBall': 0, 'oGreen': 0, 'oHalo': 0, 'gs': 0.55, 'pulse': -1,
      'sOp': 0, 'sTy': 6, 'cHalo': 0, 'trail': 0,
      'orb.k': widget.reducedMotion ? 1 : 0,
      'orb.alpha': 0, 'orb.spin': 0, 'orb.pop': 1, 'orb.sweep': 0,
      'orb.vortex': 0, 'orb.gain': 1, 'orb.floor': 0, 'orb.rad': 0,
    });
    _phase = widget.reducedMotion ? _Phase.assemble : _Phase.launch;
    _phaseT = 0;
    _lastTs = 0;
    if (!_ticker.isActive) _ticker.start();
    _frame.value++;
  }

  void _endThink() {
    final spoiled = widget.failed || widget.stopCount != _stopAtStart;
    if (spoiled) {
      _phase = _Phase.fadeFail;
    } else {
      _phase = _Phase.resolve;
      if (widget.reducedMotion) _v['gs'] = 1;
    }
    _phaseT = 0;
  }

  void _setPhase(_Phase p) {
    _phase = p;
    _phaseT = 0;
    if (p == _Phase.idle) _ticker.stop();
  }

  List<_Track>? get _phaseTracks {
    switch (_phase) {
      case _Phase.launch:
        return _launch;
      case _Phase.assemble:
        return widget.reducedMotion ? _rIn : _assemble;
      case _Phase.resolve:
        return widget.reducedMotion ? _rResolve : _resolve;
      case _Phase.condense:
        return widget.reducedMotion ? _rCondense : _condense;
      case _Phase.exit:
        return _exit;
      case _Phase.fadeFail:
        return _fadeFail;
      default:
        return null;
    }
  }

  double get _phaseDur {
    switch (_phase) {
      case _Phase.launch:
        return 1500;
      case _Phase.assemble:
        return widget.reducedMotion ? 200 : 800;
      case _Phase.resolve:
        return widget.reducedMotion ? 250 : 900;
      case _Phase.condense:
        return widget.reducedMotion ? 250 : 800;
      case _Phase.hold:
        return widget.reducedMotion ? 350 : 550;
      case _Phase.exit:
        return 240;
      case _Phase.fadeFail:
        return 400;
      default:
        return 0;
    }
  }

  void _advancePhase() {
    switch (_phase) {
      case _Phase.launch:
        _setPhase(_Phase.assemble);
        break;
      case _Phase.assemble:
        _setPhase(_Phase.think);
        break;
      case _Phase.think:
        break; // ends only via didUpdateWidget
      case _Phase.resolve:
        _setPhase(_Phase.condense);
        break;
      case _Phase.condense:
        _setPhase(_Phase.hold);
        break;
      case _Phase.hold:
        _setPhase(_Phase.exit);
        break;
      case _Phase.exit:
      case _Phase.fadeFail:
        _setPhase(_Phase.idle);
        // A new generation may already be running (fast re-send).
        if (widget.running) _startRun();
        break;
      case _Phase.idle:
        break;
    }
  }

  void _evalTracks(List<_Track> tracks, double t) {
    final channels = <String>{};
    for (final k in tracks) {
      channels.add(k.ch);
    }
    for (final ch in channels) {
      var val = _ch(ch);
      for (final k in tracks) {
        if (k.ch != ch || t < k.t0) continue;
        final p = _clamp01((t - k.t0) / (k.t1 - k.t0));
        val = k.from + (k.to - k.from) * k.ease.transform(p);
      }
      _v[ch] = val;
    }
  }

  void _tick(Duration ts) {
    final now = ts.inMicroseconds / 1000.0;
    final dtMs = _lastTs == 0 ? 16.0 : (now - _lastTs).clamp(0.0, 100.0);
    _lastTs = now;
    if (_phase == _Phase.idle) return;
    _elapsedMs += dtMs;

    _phaseT += dtMs;
    final tracks = _phaseTracks;
    if (tracks != null) _evalTracks(tracks, _phaseT);
    if (_phase != _Phase.think && _phaseT >= _phaseDur) {
      _advancePhase();
      if (_phase == _Phase.idle) {
        _frame.value++;
        return;
      }
    }

    // Orb sim clock: frozen under reduced motion (source: dt = 0).
    final dt = widget.reducedMotion ? 0.0 : dtMs / 1000.0;
    _time += dt;
    _rot += _ch('orb.spin') * dt;
    _prog = (_phase == _Phase.think && widget.streaming) ? 3 : 0;

    _frame.value++;
  }

  String get _label {
    switch (_phase) {
      case _Phase.resolve:
      case _Phase.condense:
      case _Phase.hold:
      case _Phase.exit:
        return 'Done';
      default:
        return widget.streaming ? 'Composing' : 'Thinking';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.idle && !widget.running) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _frame,
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              // Stage center: dead center of the chat area at 46%
              // height — the main orb's old seat (Kai, 2026-11-05).
              final target = Offset(size.width / 2, size.height * 0.46);
              // Flight origin: the composer pill's center, just
              // below the chat area's bottom edge.
              final origin = Offset(size.width / 2, size.height + 44);
              final h = origin.dy - target.dy;
              final u = _ch('u');
              double bez(double p0, double c, double p2) =>
                  (1 - u) * (1 - u) * p0 + 2 * (1 - u) * u * c + u * u * p2;
              final cx = target.dx + bez(0, _dir * 0.3 * h, 0);
              final cy = target.dy + bez(h, 0.6 * h, 0);
              final actor = _ch('w');
              // Flight history for the comet trail (source: 500 ms).
              if (_ch('trail') > 0.001 || _phase == _Phase.launch) {
                _hist.add((t: _elapsedMs, x: cx, y: cy, d: actor));
              }
              while (_hist.length > 2 &&
                  _hist.first.t < _elapsedMs - 500) {
                _hist.removeAt(0);
              }
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _OrbPainter(
                        v: Map.of(_v),
                        time: _time,
                        rot: _rot,
                        prog: _prog,
                        lit: _lit,
                        center: Offset(cx, cy),
                        actor: actor,
                        hist: List.of(_hist),
                        nowMs: _elapsedMs,
                      ),
                    ),
                  ),
                  // Status label under the orb.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: target.dy + _kOrbD / 2 + 18,
                    child: Opacity(
                      opacity: _clamp01(_ch('sOp')),
                      child: Transform.translate(
                        offset: Offset(0, _ch('sTy')),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _label,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2.2,
                                color: AppColors.darkTextM,
                              ),
                            ),
                            if (_phase == _Phase.think ||
                                _phase == _Phase.assemble) ...[
                              const SizedBox(width: 7),
                              _dots3(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _dots3() {
    final t = _time * 2.4;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.darkTextM.withValues(
                alpha: 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t - i * 1.05)),
              ),
            ),
          ),
      ],
    );
  }
}

/* ─────────────────────────── painter ─────────────────────────── */
class _OrbPainter extends CustomPainter {
  final Map<String, double> v;
  final double time, rot, actor, nowMs;
  final int prog;
  final Float32List lit;
  final Offset center;
  final List<({double t, double x, double y, double d})> hist;

  _OrbPainter({
    required this.v,
    required this.time,
    required this.rot,
    required this.prog,
    required this.lit,
    required this.center,
    required this.actor,
    required this.hist,
    required this.nowMs,
  });

  double _c(String k) => v[k] ?? 0;

  ({double x, double y, double d}) _sampleAt(double t) {
    if (hist.isEmpty) return (x: center.dx, y: center.dy, d: actor);
    if (t <= hist.first.t) {
      final s = hist.first;
      return (x: s.x, y: s.y, d: s.d);
    }
    for (var i = hist.length - 1; i > 0; i--) {
      final a = hist[i - 1], b = hist[i];
      if (t >= a.t) {
        if (t >= b.t) return (x: b.x, y: b.y, d: b.d);
        final k = (t - a.t) / (b.t - a.t == 0 ? 1 : b.t - a.t);
        return (
          x: _lerp(a.x, b.x, k),
          y: _lerp(a.y, b.y, k),
          d: _lerp(a.d, b.d, k),
        );
      }
    }
    final s = hist.last;
    return (x: s.x, y: s.y, d: s.d);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Comet trail: 6 ghost balls sampling the flight history at
    // 45 ms steps (the source's renderTrail).
    final trailVis = _c('trail');
    if (trailVis > 0.001 && hist.length > 2) {
      final gp = Paint();
      for (var i = 0; i < 6; i++) {
        final s = _sampleAt(nowMs - (i + 1) * 45);
        final d = s.d * (1 - 0.08 * (i + 1));
        final op = 0.28 * math.pow(1 - i / 6, 1.5).toDouble() * trailVis;
        if (op <= 0.004 || d <= 1) continue;
        gp.color = AppColors.accent.withValues(alpha: op);
        canvas.drawCircle(Offset(s.x, s.y), d / 2, gp);
      }
    }

    final scale = actor / _kCanvas;
    const c0 = _kCanvas / 2;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-c0, -c0);

    final alpha = _c('orb.alpha');

    // Halo behind the sphere.
    final haloA = math.max(_c('cHalo'), _c('oHalo'));
    if (haloA > 0.003) {
      final haloPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.5 * haloA),
            AppColors.accent.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: const Offset(c0, c0), radius: _kOrbR * 2.1),
        );
      canvas.drawCircle(const Offset(c0, c0), _kOrbR * 2.1, haloPaint);
    }

    // Pulse ring (condense).
    final pulse = _c('pulse');
    if (pulse >= 0) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.accent.withValues(alpha: 0.5 * (1 - pulse));
      canvas.drawCircle(const Offset(c0, c0), _kOrbR * (1 + pulse), p);
    }

    // Pre-assembly glowing ball (the pill condensed — here it is the
    // actor-sized ball that launches from the composer).
    final oBall = _c('oBall');
    if (oBall > 0.003 && _c('orb.k') < 0.5) {
      const r = _kCanvas / 2 * 0.92;
      final ballPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFA855F7).withValues(alpha: oBall),
            AppColors.accent.withValues(alpha: 0.85 * oBall),
            AppColors.accentDim.withValues(alpha: 0.9 * oBall),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(
            Rect.fromCircle(center: const Offset(c0, c0), radius: r));
      canvas.drawCircle(const Offset(c0, c0), r, ballPaint);
    }

    // Dot sphere — the source's draw(), ported line for line. The
    // light-program weights snap to the active program instead of
    // the source's 0.35 s chase (programs 1/2 are unused in MiniX's
    // binding); the lit[] decay uses a fixed 60 fps step.
    if (alpha > 0.002) {
      final k = _c('orb.k');
      final sweep = _c('orb.sweep');
      final pop = _c('orb.pop');
      final vortex = _c('orb.vortex');
      final gain = _c('orb.gain');
      final floor = _c('orb.floor');
      final rad = _c('orb.rad');
      const s = 0.6;
      final yaw = rot + vortex;
      final cyw = math.cos(yaw), syw = math.sin(yaw);
      const cp = 0.93937; // cos(0.35)
      const sp = 0.34290; // sin(0.35)
      const decay = 0.96838; // exp(-0.016 / 0.5)
      final n = _dots.n;
      final h0 = (time * 300) % n, h3 = (time * 480) % n;
      final lat = math.sin(time * 2.2);
      final swirlK = vortex * 1.5;
      final pw0 = prog == 0 ? 1.0 : 0.0;
      final pw2 = 0.0; // latitude band program — unused in this binding
      final pw3 = prog == 3 ? 1.0 : 0.0;

      final sx = Float32List(n), sy = Float32List(n);
      final sr = Float32List(n), sd = Float32List(n);
      final scol = List<Color?>(n, null);
      final paint = Paint();
      for (var i = 0; i < n; i++) {
        final dx = _dots.x[i], dy = _dots.y[i], dz = _dots.z[i];
        final uu = _dots.u[i];
        var pulseL = 0.0;
        if (pw0 > 0.001) {
          var dd = (i - h0).abs();
          if (dd > n - dd) dd = n - dd;
          final vv = math.max(0.0, 1 - dd / 16);
          pulseL = math.max(pulseL, vv * vv * pw0);
        }
        if (pw2 > 0.001) {
          final e = dy - lat;
          final vv = math.max(0.0, 1 - (e * e) / 0.02);
          pulseL = math.max(pulseL, vv * vv * pw2);
        }
        if (pw3 > 0.001) {
          var dd = (i - h3).abs();
          if (dd > n - dd) dd = n - dd;
          final vv = math.max(0.0, 1 - dd / 22);
          pulseL = math.max(pulseL, vv * vv * pw3);
        }
        final l = math.max(lit[i] * decay, pulseL * gain);
        lit[i] = l;
        final ki = _clamp01(k * (1 + s) - s * uu);
        if (ki <= 0.001) continue;
        final eo = _eOut.transform(ki);
        final kk = eo * pop;
        final x1 = dx * cyw + dz * syw;
        final z1 = -dx * syw + dz * cyw;
        final y2 = dy * cp - z1 * sp;
        final z2 = dy * sp + z1 * cp;
        final f = 2.8 / (2.8 - z2);
        final depth = (z2 + 1) / 2;
        var ox = x1 * _kOrbR * kk * f;
        var oy = -y2 * _kOrbR * kk * f;
        if (swirlK > 0.001) {
          final sw = (1 - ki) * swirlK;
          final cc = math.cos(sw), ss = math.sin(sw);
          final tx = ox * cc - oy * ss;
          oy = ox * ss + oy * cc;
          ox = tx;
        }
        final g = _clamp01((sweep * 1.4 - uu) / 0.4);
        var a = 0.1 +
            0.035 * math.sin(_dots.seed[i] + time * 1.6) * (1 - g) +
            0.32 * depth * depth +
            0.75 * l * (1 - g) +
            g * (0.55 + 0.4 * depth) +
            2 * g * (1 - g);
        a = math.max(a, floor * (0.7 + 0.3 * depth));
        if (a > 1) a = 1;
        a *= eo * alpha;
        if (a <= 0.004) continue;
        sx[i] = c0 + ox;
        sy[i] = c0 + oy;
        sd[i] = depth;
        sr[i] = (1.15 * (0.45 + 0.75 * depth) * f + 0.9 * l + g * 0.25) *
            (1 + rad) *
            (0.4 + 0.6 * eo);
        final rr = _lerp(235, 147, g).round();
        final gg = _lerp(235, 51, g).round();
        final bb = _lerp(235, 234, g).round();
        scol[i] = Color.fromARGB((a * 255).round(), rr, gg, bb);
      }
      for (var pass = 0; pass < 2; pass++) {
        for (var i = 0; i < n; i++) {
          final col = scol[i];
          if (col == null) continue;
          if ((sd[i] >= 0.5) != (pass == 1)) continue;
          paint.color = col;
          canvas.drawCircle(Offset(sx[i], sy[i]), sr[i], paint);
        }
      }
    }

    // Condense ball (purple — the source's green ball, recolored).
    final oGreen = _c('oGreen');
    if (oGreen > 0.003) {
      final r = _kOrbR * _c('gs');
      final ballPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFA855F7).withValues(alpha: oGreen),
            AppColors.accent.withValues(alpha: oGreen),
            AppColors.accentDim.withValues(alpha: oGreen),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(
            Rect.fromCircle(center: const Offset(c0, c0), radius: r));
      canvas.drawCircle(const Offset(c0, c0), r, ballPaint);
      final check = Path()
        ..moveTo(c0 - 0.38 * r, c0 + 0.02 * r)
        ..lineTo(c0 - 0.13 * r, c0 + 0.27 * r)
        ..lineTo(c0 + 0.42 * r, c0 - 0.28 * r);
      final cp2 = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.11 * r
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: oGreen);
      canvas.drawPath(check, cp2);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter old) => true;
}
