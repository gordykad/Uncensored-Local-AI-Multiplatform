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
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

const _easeOut = Cubic(0.22, 1, 0.36, 1);
const _easeOut2 = Cubic(0.23, 1, 0.32, 1);

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

/// One #26 token with its source entrance.
class _TokenIn extends StatefulWidget {
  final String word;
  final TextStyle style;
  final bool blur5;
  const _TokenIn(this.word, {required this.style, this.blur5 = true});

  @override
  State<_TokenIn> createState() => _TokenInState();
}

class _TokenInState extends State<_TokenIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

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
        final t = _easeOut.transform(_c.value);
        final w = Text(widget.word, style: widget.style);
        if (t >= 1) return w;
        return Opacity(
          opacity: t,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: (widget.blur5 ? 5 : 3) * (1 - t),
              sigmaY: (widget.blur5 ? 5 : 3) * (1 - t),
            ),
            child: w,
          ),
        );
      },
    );
  }
}

/// Live reply text: words play the #26 entrance as they arrive; the #26
/// caret rides the tail while [streaming].
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

  @override
  Widget build(BuildContext context) {
    final words = text.split(RegExp(r'(?<=\s)'));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final w in words)
          if (w.isNotEmpty) _TokenIn(w, style: style),
        if (streaming)
          StreamCaret(fontSize: style.fontSize ?? 15, color: caretColor),
      ],
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

  @override
  void initState() {
    super.initState();
    _words = widget.text.split(RegExp(r'(?<=\s)'));
    _timer = Timer.periodic(const Duration(milliseconds: 32), (tm) {
      if (!mounted) {
        tm.cancel();
        return;
      }
      setState(() => _shown = (_shown + 3).clamp(0, _words.length));
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
          setState(() => _shown = (_shown + 3).clamp(0, _words.length));
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
    return Wrap(
      children: [
        for (var i = 0; i < _shown && i < _words.length; i++)
          if (_words[i].isNotEmpty) _RegenWord(_words[i], widget.style),
      ],
    );
  }
}

class _RegenWord extends StatefulWidget {
  final String word;
  final TextStyle style;
  const _RegenWord(this.word, this.style);

  @override
  State<_RegenWord> createState() => _RegenWordState();
}

class _RegenWordState extends State<_RegenWord>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

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
        final t = _easeOut2.transform(_c.value);
        final w = Text(widget.word, style: widget.style);
        if (t >= 1) return w;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 4 * (1 - t)),
            child: ImageFiltered(
              imageFilter:
                  ui.ImageFilter.blur(sigmaX: 3 * (1 - t), sigmaY: 3 * (1 - t)),
              child: w,
            ),
          ),
        );
      },
    );
  }
}
