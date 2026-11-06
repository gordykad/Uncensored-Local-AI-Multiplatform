// MorphOrb — faithful Flutter port of the banked component
// "ai-thiking-orb-and-input" (anark17r via 21st.dev, MIT). Anatomy pack:
// ~/workspace/references/app-asset-bank/components/ai-thiking-orb-and-input/
// Port source: the live console TSX + stylesheet
// (ai-thiking-orb-and-input.tsx / index.css .mo-*) — timeline tracks,
// easings, flight path, comet trail, aurora, ring, surface material,
// and the canvas dot-sphere math carried over as-is.
//
// Kai's rulings baked in (2026-11-05):
//  - Variant #5 (Answer Card Mode) ONLY, hard-locked. No switcher.
//  - Purple-only recolor: the dot sweep ends at #9333EA and the
//    condense ball is purple (the source's emerald stops replaced).
//  - The orb assembles at dead center stage of the chat area (46%
//    height) — the seat the main orb held before Kai had it removed.
//  - EXACTLY as the artifact: the composer pill itself collapses into
//    the ball and flies. Generation stop lives in the top bar, not
//    the composer (Kai: "a stop button somewhere else").
// State binding is real, never a timer demo: launch on generation
// start, think (label cycle) while it runs, resolve + condense +
// check on clean finish; a stopped or errored run takes the source's
// escape path (fast fade, pill returns, no check). The answer itself
// is the chat bubble — its glitch-in is the card reveal.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_colors.dart';
import 'nexus_velocity.dart';

const double _kCanvas = 220; // source canvas space
const double _kOrbR = 66;
const double _kOrbD = 132;
const double _kBallSmall = 60;
const double _kFlyD = 138;

const List<String> _kLabels = [
  'Thinking',
  'Searching',
  'Analyzing',
  'Composing',
];

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

/// The source's launchTracks(geo), built per run from the measured
/// pill geometry (pw = pill width, pillH = pill height).
List<_Track> _launchTracks(double pw, double pillH) => [
      _Track('w', pw, pw - 12, 0, 100, _eOut),
      _Track('oInput', 1, 0, 0, 160, _eIn),
      _Track('inScale', 1, 0.6, 0, 160, _eIn),
      _Track('oGlow', 1, 0, 0, 300, _eOut),
      _Track('oAur', 1, 0, 0, 300, _eOut),
      _Track('w', pw - 12, _kBallSmall, 100, 560, _eIo),
      _Track('h', pillH, pillH + 6, 380, 500, _eOut),
      _Track('h', pillH + 6, _kBallSmall, 500, 620, _eOut),
      _Track('oPill', 1, 0, 300, 560, _eOut),
      _Track('oBall', 0, 1, 300, 560, _eOut),
      _Track('u', 0, 1, 620, 1500, _eFly),
      _Track('w', _kBallSmall, _kFlyD, 620, 1300, _eGrow),
      _Track('h', _kBallSmall, _kFlyD, 620, 1300, _eGrow),
      _Track('w', _kFlyD, _kOrbD, 1300, 1500, _eOut),
      _Track('h', _kFlyD, _kOrbD, 1300, 1500, _eOut),
      _Track('cHalo', 0, 0.6, 620, 1500, _eOut),
      _Track('trail', 0, 1, 700, 800, _eOut),
      _Track('trail', 1, 0, 1300, 1500, _eIn),
    ];

const List<_Track> _assemble = [
  _Track('oRing', 1, 0, 0, 300, _eOut),
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

/* reduced-motion: pure cross-fades (the source's R_* tracks) */
const List<_Track> _rOut = [
  _Track('oInput', 1, 0, 0, 140, _eOut),
  _Track('oPill', 1, 0, 0, 200, _eOut),
  _Track('oGlow', 1, 0, 0, 200, _eOut),
  _Track('oAur', 1, 0, 0, 200, _eOut),
  _Track('oRing', 1, 0, 0, 200, _eOut),
];
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
enum _Phase {
  idle,
  launch,
  assemble,
  think,
  resolve,
  condense,
  hold,
  outFade,
  escOut,
  pillIn,
  rOut,
}

class MorphOrbComposer extends StatefulWidget {
  /// The chat input's controller — the pill hosts the real field.
  final TextEditingController controller;

  /// Send dispatch (home_screen's _send).
  final VoidCallback onSend;

  /// Send gate (a model is loaded / a seat is picked, text present).
  final bool canSend;

  /// A generation (local, remote seat, or regenerate) is in flight.
  final bool running;

  /// The last run ended on an error bubble (escape path, no check).
  final bool failed;

  /// Increments every time the user taps stop (escape path).
  final int stopCount;

  /// MediaQuery.disableAnimations — the source's reduced-motion path.
  final bool reducedMotion;

  /// Key on the invisible slot in the input area that reserves the
  /// pill's home rectangle (measured every frame while idle).
  final GlobalKey slotKey;

  const MorphOrbComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.canSend,
    required this.running,
    required this.failed,
    required this.stopCount,
    required this.reducedMotion,
    required this.slotKey,
  });

  @override
  State<MorphOrbComposer> createState() => _MorphOrbComposerState();
}

class _MorphOrbComposerState extends State<MorphOrbComposer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final FocusNode _focusNode = FocusNode();

  _Phase _phase = _Phase.idle;
  double _phaseT = 0;
  double _lastTs = 0;
  double _elapsedMs = 0;
  bool _wasRunning = false;
  int _stopAtStart = 0;
  double _dir = -1;
  bool _focused = false;
  bool _hasText = false;

  Rect? _homeRect;
  double _pw = 0;
  double _pillH = 56;

  // Persistent channel values (the source's `vals` / INIT).
  final Map<String, double> _v = {
    'w': 0, 'h': 56, 'r': 999, 'oGlow': 1, 'oHalo': 0, 'oPill': 1,
    'oBall': 0, 'oGreen': 0, 'oRing': 1, 'oInput': 1, 'inScale': 1,
    'oAur': 1, 'gs': 0.55, 'u': 0, 'yOff': 0, 'trail': 0, 'pulse': -1,
    'sOp': 0, 'sTy': 6, 'cHalo': 0,
    'orb.k': 0, 'orb.alpha': 0, 'orb.spin': 0, 'orb.pop': 1,
    'orb.sweep': 0, 'orb.vortex': 0, 'orb.gain': 1, 'orb.floor': 0,
    'orb.rad': 0,
  };
  List<_Track>? _dynTracks; // outFade / escOut / pillIn (built live)
  int _pillInDur = 420;

  // Orb sim state (the source's P + lit + flight history).
  double _time = 0, _rot = 0;
  int _prog = 0;
  int _labelIdx = 0;
  double _labelT = 0;
  late final Float32List _lit = Float32List(_dots.n);
  final List<({double t, double x, double y, double d})> _hist = [];

  double _ch(String k) => _v[k] ?? 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
    widget.controller.addListener(_onText);
    _hasText = widget.controller.text.isNotEmpty;
  }

  void _onText() {
    final has = widget.controller.text.isNotEmpty;
    if (has != _hasText && mounted) setState(() => _hasText = has);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focusNode.dispose();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MorphOrbComposer old) {
    super.didUpdateWidget(old);
    if (widget.running && !_wasRunning) _startRun();
    if (!widget.running && _wasRunning && _phase == _Phase.think) {
      _endThink();
    }
    _wasRunning = widget.running;
  }

  /* ── run lifecycle ── */
  void _startRun() {
    _dir = -_dir;
    _stopAtStart = widget.stopCount;
    _lit.fillRange(0, _lit.length, 0);
    _hist.clear();
    _rot = 0;
    _prog = 0;
    _labelIdx = 0;
    _labelT = 0;
    _time = widget.reducedMotion ? 1.2 : 0;
    if (_homeRect != null) {
      _pw = _homeRect!.width;
      _pillH = _homeRect!.height;
    }
    if (_pw <= 0) {
      _pw = MediaQuery.of(context).size.width - 32;
      _pillH = 56;
    }
    _v.addAll({
      'w': _pw, 'h': _pillH, 'r': 999, 'oGlow': 1, 'oHalo': 0,
      'oPill': 1, 'oBall': 0, 'oGreen': 0, 'oRing': 1, 'oInput': 1,
      'inScale': 1, 'oAur': 1, 'gs': 0.55, 'u': 0, 'yOff': 0,
      'trail': 0, 'pulse': -1, 'sOp': 0, 'sTy': 6, 'cHalo': 0,
      'orb.k': 0, 'orb.alpha': 0, 'orb.spin': 0, 'orb.pop': 1,
      'orb.sweep': 0, 'orb.vortex': 0, 'orb.gain': 1, 'orb.floor': 0,
      'orb.rad': 0,
    });
    _dynTracks = null;
    _phase = widget.reducedMotion ? _Phase.rOut : _Phase.launch;
    _phaseT = 0;
    _lastTs = 0;
    if (!_ticker.isActive) _ticker.start();
    _frame.value++;
  }

  void _endThink() {
    final spoiled = widget.failed || widget.stopCount != _stopAtStart;
    if (spoiled) {
      _dynTracks = _fadeTracks(200);
      _phase = _Phase.escOut;
    } else {
      _phase = _Phase.resolve;
      if (widget.reducedMotion) _v['gs'] = 1;
    }
    _phaseT = 0;
  }

  List<_Track> _fadeTracks(int dur) {
    const fade = [
      'oGlow', 'oAur', 'oPill', 'oBall', 'oGreen', 'oRing', 'oInput',
      'oHalo', 'sOp', 'orb.alpha', 'trail',
    ];
    final out = <_Track>[
      _Track('cHalo', _ch('cHalo'), 0, 0, dur, _eOut),
    ];
    for (final ch in fade) {
      final val = _ch(ch);
      if (val > 0.001) out.add(_Track(ch, val, 0, 0, dur, _eOut));
    }
    return out;
  }

  List<_Track> _pillInTracks(int dur, double yOffFrom) {
    return [
      _Track('oPill', 0, 1, 0, dur, _eOut),
      _Track('oInput', 0, 1, 0, dur, _eOut),
      _Track('oGlow', 0, 1, 0, dur, _eOut),
      _Track('oAur', 0, 1, 0, dur, _eOut),
      _Track('oRing', 0, 1, 0, dur, _eOut),
      if (yOffFrom > 0) _Track('yOff', yOffFrom, 0, 0, dur, _eOut),
    ];
  }

  void _snapHome() {
    _v.addAll({
      'w': _pw, 'h': _pillH, 'r': 999, 'oBall': 0, 'oGreen': 0,
      'oHalo': 0, 'trail': 0, 'pulse': -1, 'gs': 0.55, 'sOp': 0,
      'sTy': 6, 'cHalo': 0, 'u': 0, 'inScale': 1,
      'orb.k': 0, 'orb.alpha': 0, 'orb.spin': 0, 'orb.pop': 1,
      'orb.sweep': 0, 'orb.vortex': 0, 'orb.gain': 1, 'orb.floor': 0,
      'orb.rad': 0,
    });
    _lit.fillRange(0, _lit.length, 0);
    _rot = 0;
    _hist.clear();
  }

  void _setPhase(_Phase p) {
    _phase = p;
    _phaseT = 0;
    if (p == _Phase.idle) _ticker.stop();
  }

  List<_Track>? get _phaseTracks {
    switch (_phase) {
      case _Phase.launch:
        return _launchTracks(_pw, _pillH);
      case _Phase.assemble:
        return widget.reducedMotion ? _rIn : _assemble;
      case _Phase.resolve:
        return widget.reducedMotion ? _rResolve : _resolve;
      case _Phase.condense:
        return widget.reducedMotion ? _rCondense : _condense;
      case _Phase.rOut:
        return _rOut;
      case _Phase.outFade:
      case _Phase.escOut:
      case _Phase.pillIn:
        return _dynTracks;
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
      case _Phase.outFade:
        return widget.reducedMotion ? 120 : 240;
      case _Phase.escOut:
        return 200;
      case _Phase.pillIn:
        return _pillInDur.toDouble();
      case _Phase.rOut:
        return 200;
      default:
        return 0;
    }
  }

  void _advancePhase() {
    switch (_phase) {
      case _Phase.launch:
        _v['r'] = _kOrbD / 2;
        _setPhase(_Phase.assemble);
        break;
      case _Phase.rOut:
        // Reduced launch: snap the actor to the stage orb, fade in.
        _v.addAll({
          'u': 1, 'w': _kOrbD, 'h': _kOrbD, 'r': _kOrbD / 2,
          'sTy': 0, 'orb.k': 1, 'orb.spin': 0,
        });
        _setPhase(_Phase.assemble);
        break;
      case _Phase.assemble:
        _setPhase(_Phase.think);
        // A generation faster than the launch+assemble (instant
        // error, cached reply) must not strand the orb in think.
        if (!widget.running) _endThink();
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
        _dynTracks = _fadeTracks(widget.reducedMotion ? 120 : 240);
        _setPhase(_Phase.outFade);
        break;
      case _Phase.outFade:
        _snapHome();
        _pillInDur = 420;
        _dynTracks = _pillInTracks(420, 8);
        _v['yOff'] = 8;
        _setPhase(_Phase.pillIn);
        break;
      case _Phase.escOut:
        _snapHome();
        _pillInDur = 200;
        _dynTracks = _pillInTracks(200, 0);
        _setPhase(_Phase.pillIn);
        break;
      case _Phase.pillIn:
        _setPhase(_Phase.idle);
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
    if (_phase == _Phase.think) {
      // The source's labelLoop: advance every 1150 ms, prog follows.
      _labelT += dtMs;
      if (_labelT >= 1150) {
        _labelT = 0;
        _labelIdx = (_labelIdx + 1) % _kLabels.length;
        _prog = _labelIdx % 4;
      }
    } else if (_phaseT >= _phaseDur) {
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

    _frame.value++;
  }

  /* ── home-rect measurement ── */
  void _measure() {
    final slotCtx = widget.slotKey.currentContext;
    final myBox = context.findRenderObject() as RenderBox?;
    if (slotCtx == null || myBox == null || !myBox.hasSize) return;
    final slotBox = slotCtx.findRenderObject() as RenderBox?;
    if (slotBox == null || !slotBox.hasSize) return;
    final tl = myBox.globalToLocal(slotBox.localToGlobal(Offset.zero));
    final rect = tl & slotBox.size;
    final old = _homeRect;
    if (old == null ||
        (rect.top - old.top).abs() > 0.5 ||
        (rect.left - old.left).abs() > 0.5 ||
        (rect.width - old.width).abs() > 0.5 ||
        (rect.height - old.height).abs() > 0.5) {
      _homeRect = rect;
      if (_phase == _Phase.idle) {
        _pw = rect.width;
        _pillH = rect.height;
        _v['w'] = rect.width;
        _v['h'] = rect.height;
        _frame.value++;
      }
    }
  }

  ({double x, double y, double d}) _sampleAt(double t) {
    if (_hist.isEmpty) return (x: 0, y: 0, d: _kBallSmall);
    if (t <= _hist.first.t) {
      final s = _hist.first;
      return (x: s.x, y: s.y, d: s.d);
    }
    for (var i = _hist.length - 1; i > 0; i--) {
      final a = _hist[i - 1], b = _hist[i];
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
    final s = _hist.last;
    return (x: s.x, y: s.y, d: s.d);
  }

  String get _label {
    switch (_phase) {
      case _Phase.resolve:
      case _Phase.condense:
      case _Phase.hold:
      case _Phase.outFade:
        return 'Done';
      default:
        return _kLabels[_labelIdx];
    }
  }

  bool get _labelDone =>
      _phase == _Phase.resolve ||
      _phase == _Phase.condense ||
      _phase == _Phase.hold ||
      _phase == _Phase.outFade;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
    return SizedBox.expand(
      child: AnimatedBuilder(
      animation: _frame,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final home = _homeRect ??
                Rect.fromLTRB(
                    16, size.height - 72, size.width - 16, size.height - 16);
            if (_phase == _Phase.idle) {
              _pw = home.width;
              _pillH = home.height;
              _v['w'] = home.width;
              _v['h'] = home.height;
            }
            final homeCx = home.center.dx;
            final homeCy = home.center.dy;
            // Stage: dead center of the chat area at 46% height.
            final stageCx = size.width / 2;
            final stageCy = size.height * 0.46;
            final h = homeCy - stageCy;
            final u = _ch('u');
            double bez(double p0, double c, double p2) =>
                (1 - u) * (1 - u) * p0 + 2 * (1 - u) * u * c + u * u * p2;
            final cx = _phase == _Phase.idle
                ? homeCx
                : stageCx + bez(0, _dir * 0.3 * h, 0);
            final cy = _phase == _Phase.idle
                ? homeCy
                : stageCy + bez(h, 0.6 * h, 0) + _ch('yOff');
            final w = _ch('w');
            final hh = _ch('h');

            // Flight history for the comet trail (source: 500 ms).
            if (_ch('trail') > 0.001 || _phase == _Phase.launch) {
              _hist.add((t: _elapsedMs, x: cx, y: cy, d: w));
            }
            while (_hist.length > 2 && _hist.first.t < _elapsedMs - 500) {
              _hist.removeAt(0);
            }
            final ghosts = <({double dx, double dy, double d, double op})>[];
            final trailVis = widget.reducedMotion ? 0.0 : _ch('trail');
            if (trailVis > 0.001 && _hist.length > 2) {
              for (var i = 0; i < 6; i++) {
                final s = _sampleAt(_elapsedMs - (i + 1) * 45);
                final op =
                    0.28 * math.pow(1 - i / 6, 1.5).toDouble() * trailVis;
                ghosts.add((
                  dx: s.x - cx,
                  dy: s.y - cy,
                  d: s.d * (1 - 0.08 * (i + 1)),
                  op: op,
                ));
              }
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Root halo at stage center (.mo-halo, --oCenter).
                Positioned(
                  left: stageCx - 320,
                  top: stageCy - 320,
                  width: 640,
                  height: 640,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            Colors.white
                                .withValues(alpha: 0.07 * _ch('cHalo')),
                            Colors.white
                                .withValues(alpha: 0.022 * _ch('cHalo')),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const [0, 0.52, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                // The actor: pill at home, orb at stage.
                Positioned(
                  left: cx - w / 2,
                  top: cy - hh / 2,
                  width: w,
                  height: hh,
                  child: _actor(context, w, hh, ghosts),
                ),
                // Status label (.mo-status: stage center + 100).
                Positioned(
                  left: 0,
                  right: 0,
                  top: stageCy + 100 - 11,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: _clamp01(_ch('sOp')),
                      child: Transform.translate(
                        offset: Offset(0, _ch('sTy')),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _labelText(),
                            if (!_labelDone &&
                                (_phase == _Phase.think ||
                                    _phase == _Phase.assemble)) ...[
                              const SizedBox(width: 6),
                              _dots3(),
                            ],
                          ],
                        ),
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

  Widget _labelText() {
    const style = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: AppColors.darkText,
    );
    if (_labelDone) {
      return Text(
        _label,
        style: style.copyWith(
          color: AppColors.accent.withValues(alpha: 0.9),
        ),
      );
    }
    if (widget.reducedMotion) return Text(_label, style: style);
    // Shimmer sweep (mo-lab-t): gradient text sliding 2.4 s linear.
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        final shift = (_time % 2.4) / 2.4;
        return LinearGradient(
          colors: const [Color(0xFF6B6B6B), Color(0xFFE8E8E8), Color(0xFF6B6B6B)],
          stops: const [0, 0.5, 1],
          tileMode: TileMode.repeated,
          transform: _SlideTransform(-shift * bounds.width * 1.25),
        ).createShader(bounds);
      },
      child: Text(_label, style: style.copyWith(color: Colors.white)),
    );
  }

  Widget _dots3() {
    final t = _time * (2 * math.pi) / 1.2;
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
                alpha: widget.reducedMotion
                    ? 0.6
                    : 0.25 +
                        0.75 *
                            (0.5 +
                                0.5 * math.sin(t - i * (2 * math.pi / 7.5))),
              ),
            ),
          ),
      ],
    );
  }

  /* ── the actor: surface + aurora + ring + input + canvas ── */
  Widget _actor(
    BuildContext context,
    double w,
    double hh,
    List<({double dx, double dy, double d, double op})> ghosts,
  ) {
    final r = _ch('r');
    final radius = BorderRadius.circular(r > 500 ? 999 : r);
    final ringK = (_focused || _phase != _Phase.idle) ? 0.9 : 0.45;
    final auK = _hasText ? 0.58 : 0.5;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Underglow (.mo-underglow): blurred color bar under the pill.
        if (_ch('oGlow') > 0.003)
          Positioned(
            left: 12,
            right: 12,
            top: hh - 6,
            height: 30,
            child: IgnorePointer(
              child: Opacity(
                opacity: _clamp01(_ch('oGlow')) * 0.18,
                child: CustomPaint(painter: _UnderglowPainter()),
              ),
            ),
          ),
        // Surface (.mo-surface): the material pill.
        Positioned.fill(
          child: Opacity(
            opacity: _clamp01(_ch('oPill')),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.bgInput.withValues(alpha: 0.72),
                          border: Border.all(color: context.border),
                          borderRadius: radius,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x4D000000),
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Aurora (.mo-aurora): drifting color blobs.
                  if (_ch('oAur') > 0.003)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: _clamp01(auK * _ch('oAur')),
                          child: CustomPaint(
                            painter: _AuroraPainter(time: _time),
                          ),
                        ),
                      ),
                    ),
                  // Input (.mo-input).
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _phase != _Phase.idle,
                      child: Opacity(
                        opacity: _clamp01(_ch('oInput')),
                        child: Transform.scale(
                          scale: _ch('inScale'),
                          child: _inputRow(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Ring (.mo-ring): conic iridescent border, spins 8 s.
        if (_ch('oRing') > 0.003)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: _clamp01(ringK * _ch('oRing')),
                child: CustomPaint(
                  painter: _RingPainter(
                    radius: r > 500 ? 999 : r,
                    angle: widget.reducedMotion ? 0 : _time * math.pi / 4,
                  ),
                ),
              ),
            ),
          ),
        // Canvas: ball, dots, condense ball, ghosts, pulse.
        Positioned(
          left: (w - _kCanvas) / 2,
          top: (hh - _kCanvas) / 2,
          width: _kCanvas,
          height: _kCanvas,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _OrbPainter(
                v: Map.of(_v),
                time: _time,
                rot: _rot,
                prog: _prog,
                lit: _lit,
                ghosts: ghosts,
                reduced: widget.reducedMotion,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inputRow(BuildContext context) {
    final inScaleBlur = _ch('inScale') < 0.999 && _phase != _Phase.idle;
    Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: 14),
        Icon(
          Icons.auto_awesome,
          size: 18,
          color: context.textD,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (!_hasText)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 8, 0),
                  child: IgnorePointer(
                    child: RotatingPlaceholder(
                      placeholders: const [
                        'Ask anything...',
                        'Write a haiku about the ocean at midnight',
                        'Explain it like I am five',
                        'Draft it for me...',
                        'What should I run next?',
                      ],
                      style: TextStyle(color: context.textD, fontSize: 15),
                    ),
                  ),
                ),
              TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: TextStyle(
                  fontSize: 15,
                  color: context.text,
                  height: 1.4,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.fromLTRB(2, 14, 8, 14),
                ),
                onSubmitted: (_) {
                  if (_phase == _Phase.idle) widget.onSend();
                },
              ),
            ],
          ),
        ),
        // Send (.mo-send): 36px circle, 44pt hit area (audit #4).
        // UI audit 2026-11-06 residual: VoiceOver identity for the
        // composer send. Semantics wrapper only - the orb's design,
        // choreography and behavior are untouched.
        Semantics(
          button: true,
          label: 'Send',
          enabled: _phase == _Phase.idle && widget.canSend,
          child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: GestureDetector(
              onTap: (_phase == _Phase.idle && widget.canSend)
                  ? widget.onSend
                  : null,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.canSend
                      ? Colors.white
                      : const Color(0xFF1F1F21),
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 18,
                  color: widget.canSend
                      ? const Color(0xFF111111)
                      : AppColors.darkTextM,
                ),
              ),
            ),
          ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
    if (inScaleBlur) {
      row = ImageFiltered(
        imageFilter:
            ui.ImageFilter.blur(sigmaX: 15 * (1 - _ch('inScale')), sigmaY: 15 * (1 - _ch('inScale'))),
        child: row,
      );
    }
    return row;
  }
}

/* ───────────────────── gradient slide ───────────────────── */
class _SlideTransform extends GradientTransform {
  final double dx;
  const _SlideTransform(this.dx);
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(dx, 0, 0);
  }
}

/* ───────────────────── underglow painter ───────────────────── */
class _UnderglowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final blobs = [
      (0.18, const Color(0xFF8B5CF6)),
      (0.50, const Color(0xFFEC4899)),
      (0.82, const Color(0xFF60A5FA)),
    ];
    for (final (fx, color) in blobs) {
      final center = Offset(size.width * fx, cy);
      final paint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.3));
      canvas.drawCircle(center, size.width * 0.3, paint);
    }
  }

  @override
  bool shouldRepaint(_UnderglowPainter old) => false;
}

/* ────────────────────── aurora painter ────────────────────── */
class _AuroraPainter extends CustomPainter {
  final double time;
  _AuroraPainter({required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    // Four blobs along the pill's bottom, drifting ±14% (mo-drift).
    final blobs = [
      (0.02, const Color(0xFFA855F7), 0.0),
      (0.26, const Color(0xFFEC4899), -4.0),
      (0.50, const Color(0xFF8B5CF6), -8.0),
      (0.68, const Color(0xFFFBBF24), -11.0),
    ];
    for (final (fx, color, delay) in blobs) {
      final drift = math.sin((time + delay) * (2 * math.pi / 28)) * 0.14;
      final center = Offset(
        size.width * (fx + 0.17) + size.width * drift,
        size.height + 2,
      );
      final r = size.width * 0.17;
      final paint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.time != time;
}

/* ─────────────────────── ring painter ─────────────────────── */
class _RingPainter extends CustomPainter {
  final double radius;
  final double angle;
  _RingPainter({required this.radius, required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius > 500 ? 999 : radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = SweepGradient(
        colors: const [
          Color(0xFF8B5CF6),
          Color(0xFFEC4899),
          Color(0xFFFBBF24),
          Color(0xFFA855F7),
          Color(0xFF60A5FA),
          Color(0xFF8B5CF6),
        ],
        transform: GradientRotation(angle),
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.angle != angle || old.radius != radius;
}

/* ─────────────────────── orb painter ─────────────────────── */
class _OrbPainter extends CustomPainter {
  final Map<String, double> v;
  final double time, rot;
  final int prog;
  final Float32List lit;
  final List<({double dx, double dy, double d, double op})> ghosts;
  final bool reduced;

  _OrbPainter({
    required this.v,
    required this.time,
    required this.rot,
    required this.prog,
    required this.lit,
    required this.ghosts,
    required this.reduced,
  });

  double _c(String k) => v[k] ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
    const c0 = _kCanvas / 2;
    final center = const Offset(c0, c0);

    // Comet trail ghosts (offsets from the actor's current center).
    if (!reduced) {
      final gp = Paint();
      for (final g in ghosts) {
        if (g.op <= 0.004 || g.d <= 1) continue;
        gp.color = AppColors.accent.withValues(alpha: g.op);
        canvas.drawCircle(center + Offset(g.dx, g.dy), g.d / 2, gp);
      }
    }

    final alpha = _c('orb.alpha');

    // Halo behind the sphere (canvas-space part).
    final haloA = _c('cHalo');
    if (haloA > 0.003) {
      final haloPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.28 * haloA),
            AppColors.accent.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: center, radius: _kOrbR * 2.1),
        );
      canvas.drawCircle(center, _kOrbR * 2.1, haloPaint);
    }

    // Condense halo (.mo-halo-green): blurred purple disc.
    final oHalo = _c('oHalo');
    if (oHalo > 0.003) {
      final p = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20)
        ..color = AppColors.accent.withValues(alpha: 0.55 * oHalo);
      canvas.drawCircle(center, 60, p);
    }

    // Pulse ring (condense) — a scaling border ring, source .mo-pulse.
    final pulse = _c('pulse');
    if (!reduced && pulse >= 0) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.accent.withValues(alpha: 0.5 * (1 - pulse));
      canvas.drawCircle(center, _kOrbR * (1 + pulse), p);
    }

    // Pre-assembly ball (.mo-ball): dark sphere with a top-left sheen.
    final oBall = _c('oBall');
    if (oBall > 0.003 && _c('orb.k') < 0.5) {
      const r = _kCanvas / 2 * 0.92;
      final ballPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.36, -0.48),
          radius: 0.9,
          colors: [
            Color(0xFF2A2A2E).withValues(alpha: oBall),
            const Color(0xFF0E0E0F).withValues(alpha: oBall),
            const Color(0xFF08080A).withValues(alpha: oBall),
          ],
          stops: const [0, 0.7, 1],
        ).createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawCircle(center, r, ballPaint);
      final sheen = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.16 * oBall),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(
          center: center + const Offset(-r * 0.36, -r * 0.48),
          radius: r * 0.84,
        ));
      canvas.drawCircle(center, r, sheen);
    }

    // Dot sphere — the source's draw(), ported line for line. The
    // light-program weights snap to the active program instead of
    // the source's 0.35 s chase (visually equivalent at 60 fps);
    // lit[] decay uses a fixed 60 fps step.
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
      final a1 = time * 0.8, b1 = math.sin(time * 0.5) * 0.9;
      final f1x = math.cos(b1) * math.cos(a1),
          f1y = math.sin(b1),
          f1z = math.cos(b1) * math.sin(a1);
      final a2 = time * 0.55 + 2.1, b2 = math.cos(time * 0.42) * 0.9;
      final f2x = math.cos(b2) * math.cos(a2),
          f2y = math.sin(b2),
          f2z = math.cos(b2) * math.sin(a2);
      final lat = math.sin(time * 2.2);
      final swirlK = vortex * 1.5;
      final pw = [0.0, 0.0, 0.0, 0.0];
      pw[prog] = 1.0;

      final sx = Float32List(n), sy = Float32List(n);
      final sr = Float32List(n), sd = Float32List(n);
      final scol = List<Color?>.filled(n, null);
      final paint = Paint();
      for (var i = 0; i < n; i++) {
        final dx = _dots.x[i], dy = _dots.y[i], dz = _dots.z[i];
        final uu = _dots.u[i];
        var pulseL = 0.0;
        if (pw[0] > 0.001) {
          var dd = (i - h0).abs();
          if (dd > n - dd) dd = n - dd;
          final vv = math.max(0.0, 1 - dd / 16);
          pulseL = math.max(pulseL, vv * vv * pw[0]);
        }
        if (pw[1] > 0.001) {
          final v1 =
              math.max(0.0, (dx * f1x + dy * f1y + dz * f1z - 0.72) / 0.28);
          final v2 =
              math.max(0.0, (dx * f2x + dy * f2y + dz * f2z - 0.72) / 0.28);
          final vv = math.max(v1, v2);
          pulseL = math.max(pulseL, vv * vv * pw[1]);
        }
        if (pw[2] > 0.001) {
          final e = dy - lat;
          final vv = math.max(0.0, 1 - (e * e) / 0.02);
          pulseL = math.max(pulseL, vv * vv * pw[2]);
        }
        if (pw[3] > 0.001) {
          var dd = (i - h3).abs();
          if (dd > n - dd) dd = n - dd;
          final vv = math.max(0.0, 1 - dd / 22);
          pulseL = math.max(pulseL, vv * vv * pw[3]);
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

    // Condense ball (.mo-green, purple per Kai): radial gradient +
    // top-left hi sheen + white check.
    final oGreen = _c('oGreen');
    if (oGreen > 0.003) {
      final r = _kOrbR * _c('gs');
      final ballPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accent.withValues(alpha: oGreen),
            AppColors.accentDim.withValues(alpha: oGreen),
          ],
          stops: const [0.46, 1],
        ).createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawCircle(center, r, ballPaint);
      final sheen = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFE9D5FF).withValues(alpha: oGreen),
            const Color(0xFFE9D5FF).withValues(alpha: 0),
          ],
          stops: const [0, 1],
        ).createShader(Rect.fromCircle(
          center: center + Offset(-r * 0.32, -r * 0.37),
          radius: r * 0.68,
        ));
      canvas.drawCircle(center, r, sheen);
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
  }

  @override
  bool shouldRepaint(_OrbPainter old) => true;
}
