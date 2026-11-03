import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MiniX canvas effects — faithful Flutter ports of the banked 21st motion
// components (ticket 08, founder motion law: mechanics exactly, color the
// only change — except the Thinking Orb, which takes NO change at all).
// Particle budgets tuned to the founder's floor: his iPhone 14.
// ─────────────────────────────────────────────────────────────────────────────

/// #1 Thinking Orb — canvas sphere of ~460 WHITE dots, denser at the
/// silhouette, slow rotation on near-black. FAITHFUL PORT, ZERO CHANGES:
/// monochrome, no purple anywhere in this widget.
class ThinkingOrb extends StatefulWidget {
  final bool thinking;
  final double size;
  const ThinkingOrb({super.key, this.thinking = false, this.size = 54});

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_OrbDot> _dots;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
    // Fibonacci sphere — even coverage, denser read at the silhouette.
    _dots = [];
    const n = 460;
    final golden = pi * (3 - sqrt(5));
    for (int i = 0; i < n; i++) {
      final y = 1 - (i / (n - 1)) * 2;
      final r = sqrt(max(0.0, 1 - y * y));
      final theta = golden * i;
      _dots.add(_OrbDot(cos(theta) * r, y, sin(theta) * r));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _OrbPainter(
          dots: _dots,
          angle: _ctrl.value * 2 * pi,
          thinking: widget.thinking,
          t: _ctrl.value,
        ),
      ),
    );
  }
}

class _OrbDot {
  final double x, y, z;
  const _OrbDot(this.x, this.y, this.z);
}

class _OrbPainter extends CustomPainter {
  final List<_OrbDot> dots;
  final double angle;
  final bool thinking;
  final double t;
  _OrbPainter({
    required this.dots,
    required this.angle,
    required this.thinking,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.width / 2 - 2;
    final speed = thinking ? 2.6 : 1.0;
    final a = angle * speed;
    final cosA = cos(a), sinA = sin(a);
    final paint = Paint()..style = PaintingStyle.fill;
    for (final d in dots) {
      // rotate around Y, slight X tilt for the drift
      final x1 = d.x * cosA - d.z * sinA;
      final z1 = d.x * sinA + d.z * cosA;
      final y1 = d.y * 0.92 - z1 * 0.12;
      final churn = thinking
          ? sin(t * 40 + d.y * 9 + d.x * 7) * 0.012
          : sin(t * 12 + d.y * 5) * 0.004;
      final px = c.dx + x1 * radius * (1 + churn);
      final py = c.dy + y1 * radius * (1 + churn);
      final depth = (z1 + 1) / 2; // 0 back, 1 front
      final r = 0.7 + depth * 1.15;
      paint.color =
          Colors.white.withValues(alpha: 0.25 + depth * 0.75);
      canvas.drawCircle(Offset(px, py), r, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => true;
}

/// #19 AI Loader — the original's glowing sphere, breathing with a
/// slow-turning sheen and a label inside. No controls.
class AiLoaderSphere extends StatefulWidget {
  final String label;
  final double size;
  const AiLoaderSphere({super.key, this.label = 'Loading', this.size = 120});

  @override
  State<AiLoaderSphere> createState() => _AiLoaderSphereState();
}

class _AiLoaderSphereState extends State<AiLoaderSphere>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final breathe = 1 + sin(_ctrl.value * 2 * pi * 2) * 0.035;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: breathe,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(
                        cos(_ctrl.value * 2 * pi) * 0.35,
                        sin(_ctrl.value * 2 * pi) * 0.35 - 0.2,
                      ),
                      radius: 0.9,
                      colors: const [
                        Color(0xFF3B1470),
                        AppColors.accentDim,
                        Color(0xFF170A2E),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.35),
                        blurRadius: 34,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// #23 Velocity Text — scroll-velocity-reactive type: page scroll skews and
/// stretches it in proportion to speed; spring physics settle it at rest.
class VelocityText extends StatefulWidget {
  final String text;
  final ScrollController scrollController;
  final TextStyle? style;
  const VelocityText({
    super.key,
    required this.text,
    required this.scrollController,
    this.style,
  });

  @override
  State<VelocityText> createState() => _VelocityTextState();
}

class _VelocityTextState extends State<VelocityText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _lastOffset = 0;
  double _skew = 0; // current skew amount
  double _vel = 0; // spring velocity

  @override
  void initState() {
    super.initState();
    _lastOffset =
        widget.scrollController.hasClients ? widget.scrollController.offset : 0;
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration _) {
    if (!mounted) return;
    if (widget.scrollController.hasClients) {
      final off = widget.scrollController.offset;
      final delta = off - _lastOffset;
      _lastOffset = off;
      // impulse from scroll delta, spring back to 0 (stiffness/damping tuned
      // to the original's settle feel)
      _vel += delta * 0.0022;
    }
    const stiffness = 0.085;
    const damping = 0.82;
    _vel += (-_skew * stiffness);
    _vel *= damping;
    final next = _skew + _vel;
    if ((next - _skew).abs() > 0.00005 || next.abs() > 0.0005) {
      setState(() => _skew = next);
    } else if (_skew != 0) {
      setState(() => _skew = 0);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _skew.clamp(-0.32, 0.32);
    final m = Matrix4.identity();
    m.setEntry(1, 0, s); // skewX
    m.scale(1.0, 1.0 + s.abs() * 0.35);
    return Transform(
      transform: m,
      alignment: Alignment.centerLeft,
      child: Text(
        widget.text,
        style: widget.style ??
            TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.textM,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// #18 Sonar Grid — expanding sonar rings over a calm dot matrix: dots
/// swell and brighten in the ring band; ambient ping every 2.4s; a tap
/// fires a ping from that point. Still under reduced motion.
class SonarGrid extends StatefulWidget {
  final double height;
  const SonarGrid({super.key, this.height = 190});

  @override
  State<SonarGrid> createState() => _SonarGridState();
}

class _SonarGridState extends State<SonarGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<_Ping> _pings = [];
  Timer? _ambient;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_size != Size.zero) {
        _addPing(Offset(_size.width / 2, _size.height / 2));
      }
    });
    _ambient = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (_size != Size.zero && mounted) {
        _addPing(Offset(_size.width / 2, _size.height / 2));
      }
    });
  }

  void _addPing(Offset origin) {
    _pings.add(_Ping(origin, DateTime.now()));
    _pings.removeWhere(
        (p) => DateTime.now().difference(p.start).inMilliseconds > 2600);
  }

  @override
  void dispose() {
    _ambient?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, widget.height);
        return GestureDetector(
          onTapDown: reduce ? null : (d) => _addPing(d.localPosition),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => CustomPaint(
              size: _size,
              painter: _SonarPainter(
                pings: _pings,
                now: DateTime.now(),
                still: reduce,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Ping {
  final Offset origin;
  final DateTime start;
  _Ping(this.origin, this.start);
}

class _SonarPainter extends CustomPainter {
  final List<_Ping> pings;
  final DateTime now;
  final bool still;
  _SonarPainter({required this.pings, required this.now, required this.still});

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 22.0;
    final paint = Paint()..style = PaintingStyle.fill;
    final maxR = max(size.width, size.height) * 1.1;
    for (double x = gap / 2; x < size.width; x += gap) {
      for (double y = gap / 2; y < size.height; y += gap) {
        double swell = 0;
        if (!still) {
          for (final p in pings) {
            final age =
                now.difference(p.start).inMilliseconds / 2600.0;
            if (age > 1) continue;
            final ringR = age * maxR;
            final dist = (Offset(x, y) - p.origin).distance;
            final band = (1 - (dist - ringR).abs() / 26).clamp(0.0, 1.0);
            swell = max(swell, band * (1 - age));
          }
        }
        final r = 1.4 + swell * 2.6;
        paint.color = Color.lerp(
          const Color(0xFF3A3A42),
          AppColors.accentHi,
          swell,
        )!;
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
    // ring strokes
    if (!still) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (final p in pings) {
        final age = now.difference(p.start).inMilliseconds / 2600.0;
        if (age > 1) continue;
        ringPaint.color =
            AppColors.accent.withValues(alpha: 0.35 * (1 - age));
        canvas.drawCircle(p.origin, age * maxR, ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_SonarPainter old) => true;
}

/// #16 Gravity Stars — the whole field leans and swirls softly across a
/// wide well (no marker); constellation links at the original's generous
/// proportion. Touch moves the well.
class GravityStars extends StatefulWidget {
  final double height;
  final int starCount;
  const GravityStars({super.key, this.height = 220, this.starCount = 90});

  @override
  State<GravityStars> createState() => _GravityStarsState();
}

class _GravityStarsState extends State<GravityStars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final _rng = Random(7);
  late final List<_Star> _stars;
  Offset? _well;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    _stars = List.generate(
      widget.starCount,
      (_) => _Star(_rng.nextDouble(), _rng.nextDouble(),
          0.6 + _rng.nextDouble() * 1.5, _rng.nextDouble() * 2 * pi),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, widget.height);
        return GestureDetector(
          onPanUpdate: (d) => _well = d.localPosition,
          onPanEnd: (_) => _well = null,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => CustomPaint(
              size: _size,
              painter: _StarsPainter(
                stars: _stars,
                t: _ctrl.value,
                well: _well ??
                    Offset(_size.width * (0.5 + 0.22 * sin(_ctrl.value * 2 * pi)),
                        _size.height * (0.5 + 0.18 * cos(_ctrl.value * 2 * pi))),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Star {
  final double nx, ny, r, phase;
  const _Star(this.nx, this.ny, this.r, this.phase);
}

class _StarsPainter extends CustomPainter {
  final List<_Star> stars;
  final double t;
  final Offset well;
  _StarsPainter({required this.stars, required this.t, required this.well});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[];
    final paint = Paint()..style = PaintingStyle.fill;
    for (final s in stars) {
      final home = Offset(s.nx * size.width, s.ny * size.height);
      final toWell = well - home;
      final dist = toWell.distance + 40;
      // soft wide well: gentle lean + tangential swirl, no hard magnet
      final lean = toWell / dist * (2600 / dist);
      final tangent = Offset(-toWell.dy, toWell.dx) / dist * (1500 / dist);
      final drift = Offset(sin(t * 2 * pi + s.phase), cos(t * 2 * pi + s.phase)) * 3;
      final p = home + lean + tangent + drift;
      pts.add(p);
      paint.color = Colors.white.withValues(alpha: 0.35 + (s.r / 2.1) * 0.5);
      canvas.drawCircle(p, s.r, paint);
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    const linkDist = 92.0;
    for (int i = 0; i < pts.length; i++) {
      for (int j = i + 1; j < pts.length; j++) {
        final d = (pts[i] - pts[j]).distance;
        if (d < linkDist) {
          line.color = AppColors.accentHi
              .withValues(alpha: (1 - d / linkDist) * 0.20);
          canvas.drawLine(pts[i], pts[j], line);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => true;
}

/// #17 Kinetic Grid — a line-and-node mesh, still until touched: it warps
/// and bulges toward the pointer with a glow near it; a tap sends a ripple
/// outward.
class KineticGrid extends StatefulWidget {
  final double height;
  const KineticGrid({super.key, this.height = 200});

  @override
  State<KineticGrid> createState() => _KineticGridState();
}

class _KineticGridState extends State<KineticGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Offset? _pointer;
  final List<_Ping> _ripples = [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        return GestureDetector(
          onPanUpdate: (d) => setState(() => _pointer = d.localPosition),
          onPanEnd: (_) => setState(() => _pointer = null),
          onTapDown: (d) {
            _ripples.add(_Ping(d.localPosition, DateTime.now()));
            _ripples.removeWhere((p) =>
                DateTime.now().difference(p.start).inMilliseconds > 1400);
          },
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => CustomPaint(
              size: size,
              painter: _KineticPainter(
                pointer: _pointer,
                ripples: _ripples,
                now: DateTime.now(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _KineticPainter extends CustomPainter {
  final Offset? pointer;
  final List<_Ping> ripples;
  final DateTime now;
  _KineticPainter({required this.pointer, required this.ripples, required this.now});

  Offset _warp(Offset home, Size size) {
    var p = home;
    if (pointer != null) {
      final to = pointer! - home;
      final d = to.distance;
      const influence = 130.0;
      if (d < influence) {
        final f = pow(1 - d / influence, 2).toDouble();
        p += to * f * 0.38; // bulge toward the pointer
      }
    }
    for (final r in ripples) {
      final age = now.difference(r.start).inMilliseconds / 1400.0;
      if (age > 1) continue;
      final ringR = age * 260;
      final dist = (home - r.origin).distance;
      final band = (1 - (dist - ringR).abs() / 20).clamp(0.0, 1.0);
      if (band > 0) {
        final dir = dist == 0 ? const Offset(0, -1) : (home - r.origin) / dist;
        p += dir * band * 7 * (1 - age);
      }
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const gapX = 30.0;
    const gapY = 30.0;
    final cols = (size.width / gapX).floor();
    final rows = (size.height / gapY).floor();
    final grid = <List<Offset>>[];
    for (int j = 0; j <= rows; j++) {
      final row = <Offset>[];
      for (int i = 0; i <= cols; i++) {
        row.add(_warp(Offset(i * gapX + gapX / 2, j * gapY + gapY / 2), size));
      }
      grid.add(row);
    }
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = const Color(0xFF2A2A31);
    final path = Path();
    for (final row in grid) {
      for (int i = 0; i < row.length - 1; i++) {
        path.moveTo(row[i].dx, row[i].dy);
        path.lineTo(row[i + 1].dx, row[i + 1].dy);
      }
    }
    for (int i = 0; i <= cols; i++) {
      for (int j = 0; j < rows; j++) {
        path.moveTo(grid[j][i].dx, grid[j][i].dy);
        path.lineTo(grid[j + 1][i].dx, grid[j + 1][i].dy);
      }
    }
    canvas.drawPath(path, linePaint);
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final row in grid) {
      for (final p in row) {
        double glow = 0;
        if (pointer != null) {
          final d = (p - pointer!).distance;
          glow = (1 - d / 130).clamp(0.0, 1.0);
        }
        dotPaint.color = Color.lerp(
          const Color(0xFF4A4A53),
          AppColors.accentHi,
          glow,
        )!;
        canvas.drawCircle(p, 1.6 + glow * 1.8, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_KineticPainter old) => true;
}

/// #15 Particle Text Effect — thousands of spring-steered particles sampled
/// from letterforms hold the word's shape; words cycle with fluid smear /
/// re-form transitions; press-and-hold destroys the particles and the cloud
/// heals on release. Color is the ONLY change: purple family per word.
class ParticleText extends StatefulWidget {
  final List<String> words;
  final double height;
  final double fontSize;
  const ParticleText({
    super.key,
    this.words = const ['MINIX', 'LOCAL', 'OFFLINE'],
    this.height = 150,
    this.fontSize = 64,
  });

  @override
  State<ParticleText> createState() => _ParticleTextState();
}

class _Particle {
  Offset pos;
  Offset vel;
  Offset home;
  Color color;
  _Particle(this.pos, this.home, this.color) : vel = Offset.zero;
}

class _ParticleTextState extends State<ParticleText>
    with SingleTickerProviderStateMixin {
  static const _colors = [
    Color(0xFFA855F7),
    Color(0xFF9333EA),
    Color(0xFF7E22CE),
  ];
  static const _count = 1400; // tuned to the founder's iPhone 14 floor
  late final Ticker _ticker;
  final List<_Particle> _particles = [];
  final _rng = Random(3);
  int _wordIdx = 0;
  Timer? _cycle;
  Size _size = Size.zero;
  bool _destroyed = false;
  Offset? _touch;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _cycle = Timer.periodic(const Duration(milliseconds: 3400), (_) {
      if (!_destroyed && _size != Size.zero) {
        _wordIdx = (_wordIdx + 1) % widget.words.length;
        _sample();
      }
    });
  }

  Future<void> _sample() async {
    final size = _size;
    if (size == Size.zero) return;
    final targets = await _textTargets(widget.words[_wordIdx], size);
    if (!mounted || targets.isEmpty) return;
    final color = _colors[_wordIdx % _colors.length];
    if (_particles.isEmpty) {
      for (int i = 0; i < _count; i++) {
        final home = targets[_rng.nextInt(targets.length)];
        final start = Offset(
          _rng.nextDouble() * size.width,
          _rng.nextDouble() * size.height,
        );
        _particles.add(_Particle(start, home, color));
      }
    } else {
      for (int i = 0; i < _particles.length; i++) {
        _particles[i].home = targets[_rng.nextInt(targets.length)];
        _particles[i].color = color;
      }
    }
    if (mounted) setState(() {});
  }

  Future<List<Offset>> _textTargets(String word, Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final tp = TextPainter(
      text: TextSpan(
        text: word,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.width.ceil(), size.height.ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return [];
    final targets = <Offset>[];
    const step = 3;
    for (int y = 0; y < size.height; y += step) {
      for (int x = 0; x < size.width; x += step) {
        final alpha = bytes.getUint8((y * size.width.ceil() + x) * 4 + 3);
        if (alpha > 120) targets.add(Offset(x.toDouble(), y.toDouble()));
      }
    }
    return targets;
  }

  void _tick(Duration elapsed) {
    if (_particles.isEmpty || _size == Size.zero) return;
    final dt = _last == Duration.zero
        ? 0.016
        : ((elapsed - _last).inMicroseconds / 1000000).clamp(0.008, 0.033);
    _last = elapsed;
    for (final p in _particles) {
      var force = (p.home - p.pos) * 26 * dt; // spring home (fluid smear)
      if (_destroyed) {
        final away = p.pos - (_touch ?? _size.center(Offset.zero));
        final d = away.distance + 24;
        force += away / d * 900 * dt;
      } else if (_touch != null) {
        final away = p.pos - _touch!;
        final d = away.distance;
        if (d < 70) force += (away / (d + 8)) * 620 * dt;
      }
      p.vel = (p.vel + force) * 0.86;
      p.pos += p.vel;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cycle?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final newSize = Size(constraints.maxWidth, widget.height);
        if (newSize != _size) {
          _size = newSize;
          if (_particles.isEmpty) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _sample());
          }
        }
        return GestureDetector(
          onPanDown: (d) {
            _touch = d.localPosition;
            _destroyed = true;
          },
          onPanUpdate: (d) => _touch = d.localPosition,
          onPanEnd: (_) {
            _touch = null;
            _destroyed = false; // the cloud heals
          },
          onLongPressStart: (d) {
            _touch = d.localPosition;
            _destroyed = true;
          },
          onLongPressEnd: (_) {
            _touch = null;
            _destroyed = false;
          },
          child: CustomPaint(
            size: _size,
            painter: _ParticlePainter(_particles),
          ),
        );
      },
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  _ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      paint.color = p.color.withValues(alpha: 0.85);
      canvas.drawCircle(p.pos, 1.35, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}
