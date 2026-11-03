// ParticleText — FAITHFUL PORT from the banked source (pack
// particle-text-effect). Steering "arrive" particles (closeEnough 100,
// maxForce = maxSpeed*.05), word sampled from rendered text on a pixel grid,
// one target color per word, word cycle every 240 frames (~4s), surplus
// particles killed to far targets and culled off-canvas, press-and-hold
// destroys particles within 50px (the source's right-click destroy, adapted
// to touch per the founder ruling). Color deviation per founder law: the
// per-word color is drawn from the purple family instead of full-random RGB.
// Trail note: the source accumulates a 0.1-alpha black fade per frame; a
// Flutter painter cannot accumulate, so each particle draws two fading
// ghost rects behind its velocity — the same smear read.
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class ParticleText extends StatefulWidget {
  final List<String> words;
  final double height;
  const ParticleText({
    super.key,
    this.words = const ['MINIX', 'LOCAL', 'OFFLINE'],
    this.height = 150,
  });

  @override
  State<ParticleText> createState() => _ParticleTextState();
}

class _P {
  double x, y, vx = 0, vy = 0, tx, ty;
  double maxSpeed, maxForce, blendRate;
  Color startColor, targetColor;
  double colorW = 0;
  bool killed = false;
  _P(this.x, this.y, this.tx, this.ty, this.maxSpeed, this.startColor,
      this.targetColor, this.blendRate)
      : maxForce = maxSpeed * 0.05;
}

class _ParticleTextState extends State<ParticleText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _tick = ValueNotifier<double>(0);
  final _rng = math.Random();
  final List<_P> _ps = [];
  int _wordIdx = 0;
  int _frame = 0;
  Size _size = Size.zero;
  Offset? _pressPos;
  bool _sampling = false;

  static const _purples = [
    Color(0xFFA855F7),
    Color(0xFF9333EA),
    Color(0xFF7E22CE),
    Color(0xFFC084FC),
  ];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _sampleWord(String word, Size size) async {
    if (_sampling) return;
    _sampling = true;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final fs = size.height * 0.52;
    final painter = TextPainter(
      text: TextSpan(
        text: word,
        style: TextStyle(
          fontSize: fs,
          fontWeight: FontWeight.bold,
          color: const Color(0xFFFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Scale the word to fit the width like the source's fixed canvas.
    final scaleW = (size.width * 0.92) / painter.width;
    final effFs = fs * math.min(1.0, scaleW);
    painter.text = TextSpan(
      text: word,
      style: TextStyle(
        fontSize: effFs,
        fontWeight: FontWeight.bold,
        color: const Color(0xFFFFFFFF),
      ),
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset((size.width - painter.width) / 2, (size.height - painter.height) / 2),
    );
    final img = await recorder
        .endRecording()
        .toImage(size.width.ceil(), size.height.ceil());
    final bytes =
        await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    _sampling = false;
    if (bytes == null || !mounted) return;
    final data = bytes.buffer.asUint8List();
    final w = size.width.ceil();
    const gap = 3;
    final targets = <Offset>[];
    final order = <int>[];
    for (var yy = 0; yy < size.height; yy += gap) {
      for (var xx = 0; xx < size.width; xx += gap) {
        order.add(yy * w + xx);
      }
    }
    order.shuffle(_rng);
    for (final idx in order) {
      final a = data[idx * 4 + 3];
      if (a > 0) {
        targets.add(Offset((idx % w).toDouble(), (idx ~/ w).toDouble()));
      }
    }
    final color = _purples[_rng.nextInt(_purples.length)];
    var used = 0;
    for (final t in targets) {
      if (used < _ps.length) {
        final p = _ps[used];
        p.startColor = Color.lerp(p.startColor, p.targetColor, p.colorW)!;
        p.targetColor = color;
        p.colorW = 0;
        p.tx = t.dx;
        p.ty = t.dy;
        p.killed = false;
      } else {
        final ang = _rng.nextDouble() * math.pi * 2;
        final dist = (size.width + size.height) / 2;
        _ps.add(_P(
          size.width / 2 + math.cos(ang) * dist,
          size.height / 2 + math.sin(ang) * dist,
          t.dx,
          t.dy,
          _rng.nextDouble() * 6 + 4,
          const Color(0xFF000000),
          color,
          _rng.nextDouble() * 0.0275 + 0.0025,
        ));
      }
      used++;
    }
    for (var i = used; i < _ps.length; i++) {
      final p = _ps[i];
      final ang = _rng.nextDouble() * math.pi * 2;
      final dist = (size.width + size.height) / 2;
      p.tx = size.width / 2 + math.cos(ang) * dist;
      p.ty = size.height / 2 + math.sin(ang) * dist;
      p.startColor = Color.lerp(p.startColor, p.targetColor, p.colorW)!;
      p.targetColor = const Color(0xFF000000);
      p.colorW = 0;
      p.killed = true;
    }
  }

  void _onTick(Duration e) {
    if (_size == Size.zero) return;
    _frame++;
    if (_frame % 240 == 0) {
      _wordIdx = (_wordIdx + 1) % widget.words.length;
      _sampleWord(widget.words[_wordIdx], _size);
    }
    const step = 1.0; // source physics are per-frame at 60fps
    for (var i = _ps.length - 1; i >= 0; i--) {
      final p = _ps[i];
      final dx = p.tx - p.x, dy = p.ty - p.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      final ramp = dist < 100 ? dist / 100 : 1.0;
      double dvx = 0, dvy = 0;
      if (dist > 0) {
        dvx = dx / dist * p.maxSpeed * ramp;
        dvy = dy / dist * p.maxSpeed * ramp;
      }
      var sx = dvx - p.vx, sy = dvy - p.vy;
      final sm = math.sqrt(sx * sx + sy * sy);
      if (sm > 0) {
        sx = sx / sm * p.maxForce;
        sy = sy / sm * p.maxForce;
      }
      p.vx += sx * step;
      p.vy += sy * step;
      p.x += p.vx * step;
      p.y += p.vy * step;
      if (p.colorW < 1) {
        p.colorW = math.min(p.colorW + p.blendRate, 1);
      }
      final press = _pressPos;
      if (press != null) {
        final pdx = p.x - press.dx, pdy = p.y - press.dy;
        if (pdx * pdx + pdy * pdy < 50 * 50 && !p.killed) {
          final ang = _rng.nextDouble() * math.pi * 2;
          final dist2 = (_size.width + _size.height) / 2;
          p.tx = _size.width / 2 + math.cos(ang) * dist2;
          p.ty = _size.height / 2 + math.sin(ang) * dist2;
          p.startColor = Color.lerp(p.startColor, p.targetColor, p.colorW)!;
          p.targetColor = const Color(0xFF000000);
          p.colorW = 0;
          p.killed = true;
        }
      }
      if (p.killed &&
          (p.x < -20 || p.x > _size.width + 20 || p.y < -20 || p.y > _size.height + 20)) {
        _ps.removeAt(i);
      }
    }
    _tick.value = _frame.toDouble();
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
          _size = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _sampleWord(widget.words[_wordIdx], size);
          });
        }
        return GestureDetector(
          onLongPressStart: (d) => _pressPos = d.localPosition,
          onLongPressMoveUpdate: (d) => _pressPos = d.localPosition,
          onLongPressEnd: (_) => _pressPos = null,
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _ParticlePainter(repaint: _tick, ps: () => _ps),
            ),
          ),
        );
      },
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_P> Function() ps;
  _ParticlePainter({required Listenable repaint, required this.ps})
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in ps()) {
      final col = Color.lerp(p.startColor, p.targetColor, p.colorW)!;
      // smear ghosts (trail adaptation, see header)
      paint.color = col.withValues(alpha: 0.16);
      canvas.drawRect(
          Rect.fromLTWH(p.x - p.vx * 4, p.y - p.vy * 4, 2, 2), paint);
      paint.color = col.withValues(alpha: 0.3);
      canvas.drawRect(
          Rect.fromLTWH(p.x - p.vx * 2, p.y - p.vy * 2, 2, 2), paint);
      paint.color = col;
      canvas.drawRect(Rect.fromLTWH(p.x, p.y, 2, 2), paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}
