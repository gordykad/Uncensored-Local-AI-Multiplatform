// StreamReply (#26) + StreamingMessage regen style (#2) — FAITHFUL PORTS
// from the banked sources (packs stream-reply / streaming-message).
//
// #26 truth: content is tokenized on whitespace; each token enters with
// .42s cubic-bezier(.22,1,.36,1) from opacity 0 + blur(5px). The caret is
// an inline block .5em wide x 1.05em high, radius 2, accent fill with a
// glow shadow, blinking on a .9s ease-in-out cycle; it sits inside the
// last visible token while streaming. A 7px pulse dot shares the blink.
// The demo's self-play pacing (450ms start, 38 tok/s with jitter) is its
// own playback machinery; in the app the engine stream drives arrival and
// each arriving word plays the source entrance.
//
// #2 truth: the streaming tail block enters at 320ms
// cubic-bezier(.23,1,.32,1) from opacity 0 + blur(3px) + translateY(4px);
// its caret blinks 1.05s ease-in-out (opacity 1 to 45%, .2 from 55%).
// Founder ruling: #2's progressive reveal is the REGENERATING style — a
// regenerated reply sweeps in progressively in word chunks (the demo
// chunks \S{1,5} every 32ms; app chunks are 3 words per 32ms tick so a
// full reply lands in seconds, same cadence family).
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The #26 caret: .5em x 1.05em rounded block, accent glow, .9s blink.
class StreamCaret extends StatefulWidget {
  final double fontSize;
  final Color color;
  const StreamCaret({super.key, required this.fontSize, required this.color});

  @override
  State<StreamCaret> createState() => _StreamCaretState();
}

class _StreamCaretState extends State<StreamCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = Curves.easeInOut.transform(_c.value);
        return Opacity(
          opacity: 1 - 0.75 * v,
          child: Container(
            width: widget.fontSize * 0.5,
            height: widget.fontSize * 1.05,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.6),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Ticket 29 (B3): the word entrance is a GLITCH now, replacing the
/// #26 blur-rise and the #2 sweep entrances. Mechanics are the
/// in-tree GlitchText port's (faithful/glitch.dart, bank #13): two
/// Astro-purple ghost layers (0xFF7E22CE / 0xFFA855F7, glow 7) riding
/// the source's 6-key pose tracks against the main layer (glow 5),
/// skew through the same tangent matrix entry, medium preset values
/// (range 3, skew 1 degree). The one bound the ticket sets: it fires
/// ONCE on entry (~250 ms) with the jitter envelope decaying to
/// zero - settled text is a plain static Text, never a looping
/// glitch, so a 450-word reply stays readable and flat-cost.
class _GlitchIn extends StatefulWidget {
  final String word;
  final TextStyle style;
  const _GlitchIn(this.word, {required this.style});

  @override
  State<_GlitchIn> createState() => _GlitchInState();
}

class _GlitchInState extends State<_GlitchIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // The source's 6-key pose interpolation (per-segment easeOut).
  (double, double, double) _pose(
    List<(double, double, double)> keys,
    double v,
  ) {
    final t = v * (keys.length - 1);
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

  @override
  Widget build(BuildContext context) {
    // Audit #3 (app-wide Reduce Motion): the glitch entrance is a
    // plain word when the system asks for stillness.
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(widget.word, style: widget.style);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = _c.value;
        if (v >= 1) return Text(widget.word, style: widget.style);
        const r = 3.0;
        final s = 1.0 * math.pi / 180;
        final env = 1 - v;
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
        Widget layer(
          Color color,
          List<(double, double, double)> keys,
          double glow,
        ) {
          final (dx, dy, sk) = _pose(keys, v);
          return Transform(
            transform: Matrix4.identity()
              ..translate(dx * env, dy * env)
              ..setEntry(1, 0, math.tan(sk * env)),
            child: Text(
              widget.word,
              style: widget.style.copyWith(
                color: color,
                shadows: [
                  Shadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: glow,
                  ),
                ],
              ),
            ),
          );
        }

        return Stack(
          children: [
            layer(const Color(0xFF7E22CE), after, 7),
            layer(const Color(0xFFA855F7), before, 7),
            layer(widget.style.color ?? const Color(0xFFF2F2F0), main, 5),
          ],
        );
      },
    );
  }
}

/// Live reply text: words play the #26 entrance as they arrive; the #26
/// caret rides the tail while [streaming].
///
/// HOTFIX 1.9.2 (ticket 29 pull-forward): the original build tokenized
/// EVERY word into its own animated widget inside a Wrap. A long reply
/// meant thousands of stateful children relaid out on every stream
/// chunk — the UI thread died mid-generation (Kai, 2026-11-04). Now the
/// settled prefix renders as ONE plain span in a single paragraph and
/// only the trailing [_tailWords] words keep their entrances, so
/// render cost stays flat no matter how long the reply gets. B3
/// (ticket 29) swapped the entrance itself for the glitch-in above.
class StreamReplyText extends StatelessWidget {
  final String text;
  final bool streaming;
  final TextStyle style;
  final Color caretColor;
  const StreamReplyText({
    super.key,
    required this.text,
    required this.streaming,
    required this.style,
    required this.caretColor,
  });

  static const int _tailWords = 24;

  @override
  Widget build(BuildContext context) {
    if (!streaming) return Text(text, style: style);
    final words = text.split(RegExp(r'(?<=\s)'));
    if (words.length <= _tailWords) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final w in words)
            if (w.isNotEmpty) _GlitchIn(w, style: style),
          StreamCaret(fontSize: style.fontSize ?? 15, color: caretColor),
        ],
      );
    }
    final cut = words.length - _tailWords;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: words.sublist(0, cut).join()),
          for (var i = cut; i < words.length; i++)
            if (words[i].isNotEmpty)
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: _GlitchIn(words[i], style: style),
              ),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: StreamCaret(
              fontSize: style.fontSize ?? 15,
              color: caretColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// #2 regenerating reveal: an existing reply sweeps in progressively.
class RegenRevealText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final VoidCallback? onDone;
  const RegenRevealText({
    super.key,
    required this.text,
    required this.style,
    this.onDone,
  });

  @override
  State<RegenRevealText> createState() => _RegenRevealTextState();
}

class _RegenRevealTextState extends State<RegenRevealText> {
  int _shown = 0;
  Timer? _timer;
  late List<String> _words;

  /// Words revealed per 32ms tick. The #2 cadence is 3 — kept for any
  /// reply up to ~900 words; longer replies scale the chunk so the
  /// sweep always lands in about ten seconds instead of half a minute
  /// of full-screen repaints (hotfix 1.9.2).
  int get _step => _words.length <= 900 ? 3 : (_words.length / 300).ceil();

  /// Words at the sweep head that keep their animated token form; the
  /// revealed prefix before them renders as one plain span (hotfix
  /// 1.9.2 — same flat-cost rule as StreamReplyText).
  static const int _headWords = 6;

  @override
  void initState() {
    super.initState();
    _words = widget.text.split(RegExp(r'(?<=\s)'));
    _timer = Timer.periodic(const Duration(milliseconds: 32), (tm) {
      if (!mounted) {
        tm.cancel();
        return;
      }
      setState(() => _shown = (_shown + _step).clamp(0, _words.length));
      if (_shown >= _words.length) {
        tm.cancel();
        _timer = null;
        widget.onDone?.call();
      }
    });
  }

  @override
  void didUpdateWidget(RegenRevealText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _words = widget.text.split(RegExp(r'(?<=\s)'));
      if (_shown > _words.length) _shown = _words.length;
      if (_timer == null && _shown < _words.length) {
        _timer = Timer.periodic(const Duration(milliseconds: 32), (tm) {
          if (!mounted) {
            tm.cancel();
            return;
          }
          setState(() => _shown = (_shown + _step).clamp(0, _words.length));
          if (_shown >= _words.length) {
            tm.cancel();
            _timer = null;
            widget.onDone?.call();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown.clamp(0, _words.length);
    if (shown <= _headWords) {
      return Wrap(
        children: [
          for (var i = 0; i < shown; i++)
            if (_words[i].isNotEmpty) _GlitchIn(_words[i], style: widget.style),
        ],
      );
    }
    final cut = shown - _headWords;
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          TextSpan(text: _words.sublist(0, cut).join()),
          for (var i = cut; i < shown; i++)
            if (_words[i].isNotEmpty)
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: _GlitchIn(_words[i], style: widget.style),
              ),
        ],
      ),
    );
  }
}
