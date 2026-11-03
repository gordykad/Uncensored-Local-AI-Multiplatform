// GlitchText (#13) + TextGlitch (#25) — FAITHFUL PORTS from the banked
// sources (packs glitch-text / text-glitch-effect).
//
// #13 truth: THREE stacked copies of the text (primary + before + after
// ghost layers). Each layer loops a 6-keyframe transform sequence
// (translate + skew) with its own phase pattern, easing
// cubic-bezier(.25,.46,.45,.94) per segment, while opacity pulses
// [hi, lo, hi, lo, hi]. Intensity presets from the source:
//   light   2.0s  range 2px  skew .5deg  opacity [.80, .90]
//   medium  1.0s  range 3px  skew 1deg   opacity [.70, .85]
//   heavy   0.5s  range 5px  skew 2deg   opacity [.60, .80]
//   extreme 0.3s  range 8px  skew 3deg   opacity [.50, .75]
// Ghost layers carry a soft glow (0 0 7px at 25%). Colors are the only
// deviation (founder law): primary = text, before = accent-hi,
// after = accent-deep.
//
// #25 truth: a display headline with a hidden overlay panel (acid yellow
// #FFFF02 bg, black text) revealed by a clip-path wipe from the center
// line (polygon 50% -> full) over 400ms ease-out on hover; the overlay
// text scrambles toward its hover text at 30ms ticks resolving 1/3 char
// per tick from the left, unresolved chars random A-Z. Entrance: scale
// .95 / opacity .7 -> 1 over .6s back.out(1.7). Touch adaptation: tap
// toggles the hover state. Panel color per founder law: acid yellow ->
// accent purple with black text (same black-on-bright punch).
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// ------------------------------------------------------------- GlitchText
enum GlitchIntensity { light, medium, heavy, extreme }

class _Preset {
  final double seconds, range, skew, opLo, opHi;
  const _Preset(this.seconds, this.range, this.skew, this.opLo, this.opHi);
}

const _presets = {
  GlitchIntensity.light: _Preset(2.0, 2, 0.5, 0.80, 0.90),
  GlitchIntensity.medium: _Preset(1.0, 3, 1.0, 0.70, 0.85),
  GlitchIntensity.heavy: _Preset(0.5, 5, 2.0, 0.60, 0.80),
  GlitchIntensity.extreme: _Preset(0.3, 8, 3.0, 0.50, 0.75),
};

class GlitchText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final GlitchIntensity intensity;
  const GlitchText({
    super.key,
    required this.text,
    required this.style,
    this.intensity = GlitchIntensity.medium,
  });

  @override
  State<GlitchText> createState() => _GlitchTextState();
}

class _GlitchTextState extends State<GlitchText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    final p = _presets[widget.intensity]!;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (p.seconds * 1000).round()),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // 6-key interpolation with the source's per-segment ease.
  (double, double, double) _pose(List<(double, double, double)> keys) {
    final t = _c.value * (keys.length - 1);
    final idx = t.floor().clamp(0, keys.length - 2);
    final frac = Curves.easeOut.transform(t - idx);
    final a = keys[idx];
    final b = keys[idx + 1];
    return (
      a.$1 + (b.$1 - a.$1) * frac,
      a.$2 + (b.$2 - a.$2) * frac,
      a.$3 + (b.$3 - a.$3) * frac,
    );
  }

  double _opacity(_Preset p) {
    final keys = [p.opHi, p.opLo, p.opHi, p.opLo, p.opHi];
    final t = _c.value * (keys.length - 1);
    final idx = t.floor().clamp(0, keys.length - 2);
    final frac = Curves.easeOut.transform(t - idx);
    return keys[idx] + (keys[idx + 1] - keys[idx]) * frac;
  }

  @override
  Widget build(BuildContext context) {
    final p = _presets[widget.intensity]!;
    final r = p.range;
    final s = p.skew * math.pi / 180;
    final main = <(double, double, double)>[
      (0, 0, 0),
      (r, -r, s),
      (-r, r, -s),
      (-r, -r, s),
      (r, r, -s),
      (0, 0, 0),
    ];
    final before = <(double, double, double)>[
      (0, 0, 0),
      (-r, r, -s),
      (r, -r, s),
      (r, r, -s),
      (-r, -r, s),
      (0, 0, 0),
    ];
    final after = <(double, double, double)>[
      (0, 0, 0),
      (r, -r, -s),
      (-r, r, s),
      (r, r, s),
      (r, -r, -s),
      (0, 0, 0),
    ];
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        Widget layer(Color color, List<(double, double, double)> keys,
            {double glow = 0}) {
          final (dx, dy, sk) = _pose(keys);
          final style = widget.style.copyWith(
            color: color,
            shadows: glow > 0
                ? [
                    Shadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: glow,
                    ),
                  ]
                : null,
          );
          return Transform(
            transform: Matrix4.identity()
              ..translate(dx, dy)
              ..setEntry(1, 0, math.tan(sk)),
            child: Text(widget.text, style: style),
          );
        }

        return Stack(
          children: [
            layer(const Color(0xFF7E22CE), after, glow: 7),
            layer(const Color(0xFFA855F7), before, glow: 7),
            Opacity(
              opacity: _opacity(p),
              child: layer(
                widget.style.color ?? const Color(0xFFF2F2F0),
                main,
                glow: 5,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------- TextGlitch
class TextGlitch extends StatefulWidget {
  final String text;
  final String hoverText;
  final TextStyle style;
  const TextGlitch({
    super.key,
    required this.text,
    required this.hoverText,
    required this.style,
  });

  @override
  State<TextGlitch> createState() => _TextGlitchState();
}

class _TextGlitchState extends State<TextGlitch>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();
  late final AnimationController _wipe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  final _tick = ValueNotifier<int>(0);
  final _rng = math.Random();
  bool _hover = false;
  double _resolved = 0;
  late final Ticker _scrambleTicker;
  double _lastT = 0;

  @override
  void initState() {
    super.initState();
    _scrambleTicker = createTicker(_onScramble);
  }

  void _onScramble(Duration e) {
    final now = e.inMicroseconds / 1e6;
    if (now - _lastT < 0.03) return;
    _lastT = now;
    if (!_hover) {
      _scrambleTicker.stop();
      return;
    }
    _resolved += 1 / 3;
    _tick.value++;
    if (_resolved >= widget.hoverText.length) {
      _resolved = widget.hoverText.length.toDouble();
      _scrambleTicker.stop();
    }
  }

  void _setHover(bool on) {
    setState(() => _hover = on);
    if (on) {
      _wipe.forward();
      _resolved = 0;
      _lastT = 0;
      if (!_scrambleTicker.isActive) _scrambleTicker.start();
    } else {
      _wipe.reverse();
    }
  }

  String get _overlayText {
    if (!_hover) return widget.hoverText;
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final n = widget.hoverText.length;
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      if (i < _resolved) {
        sb.write(widget.hoverText[i]);
      } else if (widget.hoverText[i] == ' ') {
        sb.write(' ');
      } else {
        sb.write(chars[_rng.nextInt(26)]);
      }
    }
    return sb.toString();
  }

  @override
  void dispose() {
    _enter.dispose();
    _wipe.dispose();
    _scrambleTicker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _setHover(!_hover),
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _wipe, _tick]),
        builder: (_, __) {
          final enterT = _enter.value;
          final enterEase =
              Curves.easeOutBack.transform(enterT).clamp(0.0, 1.0);
          final wipeT = Curves.easeOut.transform(_wipe.value);
          return Opacity(
            opacity: 0.7 + 0.3 * enterEase,
            child: Transform.scale(
              scale: 0.95 + 0.05 * enterEase,
              child: Stack(
                children: [
                  Text(widget.text, style: widget.style),
                  Positioned.fill(
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.center,
                        heightFactor: wipeT,
                        child: Container(
                          color: const Color(0xFF9333EA),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _overlayText,
                            style: widget.style
                                .copyWith(color: const Color(0xFF000000)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
