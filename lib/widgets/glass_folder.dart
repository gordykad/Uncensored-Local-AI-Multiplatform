import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Ticket 25 — the glass folder, EXACTLY how Astro OS has it
/// (Kai's ruling, 2026-11-05): Astro OS never ported the 21st
/// component to source — it embeds the banked pack bundle
/// (glass-folder-cards) in a frame and drives it over the
/// astroPack postMessage bridge. MiniX does the same: the
/// identical pack bytes ship as an asset and render in a WebView;
/// props go in as {astroPack, type: 'props'}, events come back as
/// {astroPack, type: 'event', name, args}. The only MiniX-side
/// code is this bridge — the folder itself is untouched bytes.
class GlassFolderPack extends StatefulWidget {
  final String label;
  final String meta;
  final int seed;
  final List<({String name, String meta})> files;
  final void Function(int index)? onFileSelect;

  const GlassFolderPack({
    super.key,
    required this.label,
    required this.meta,
    required this.files,
    this.seed = 3,
    this.onFileSelect,
  });

  @override
  State<GlassFolderPack> createState() => _GlassFolderPackState();
}

class _GlassFolderPackState extends State<GlassFolderPack> {
  WebViewController? _ctrl;
  bool _ready = false;

  static const _bridgeScript = '''
<script>
(function(){
  var orig = window.postMessage.bind(window);
  window.postMessage = function(m, o){
    try { AstroPack.postMessage(typeof m === 'string' ? m : JSON.stringify(m)); } catch(e) {}
    return orig(m, o);
  };
})();
</script>
''';

  Map<String, dynamic> get _props => {
    'label': widget.label,
    'meta': widget.meta,
    'tone': 'dark',
    'art': 'none',
    'action': 'none',
    'seed': widget.seed,
    // Astro OS's exact frame contract: width prop 340 inside a
    // 352x404 frame (page.ts iframe.pack-folder). Without the
    // width the component lays out at desktop scale and the
    // fan-out clips (Kai's 1.16.0 screenshot).
    'width': 340,
    'files': [
      for (final f in widget.files) {'name': f.name, 'meta': f.meta},
    ],
  };

  Future<void> _sendProps() async {
    final ctrl = _ctrl;
    if (ctrl == null || !_ready) return;
    final msg = jsonEncode({
      'astroPack': true,
      'type': 'props',
      'props': _props,
    });
    await ctrl.runJavaScript(
      "window.dispatchEvent(new MessageEvent('message', {data: $msg}))",
    );
  }

  @override
  void initState() {
    super.initState();
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF050506))
      ..addJavaScriptChannel(
        'AstroPack',
        onMessageReceived: (msg) {
          try {
            final d = jsonDecode(msg.message) as Map<String, dynamic>;
            if (d['astroPack'] != true) return;
            if (d['type'] == 'ready') {
              _ready = true;
              _sendProps();
            } else if (d['type'] == 'event' && d['name'] == 'onFileSelect') {
              final args = d['args'] as List?;
              if (args != null && args.length > 1 && args[1] is num) {
                widget.onFileSelect?.call((args[1] as num).toInt());
              }
            }
          } catch (_) {}
        },
      );
    _ctrl = ctrl;
    rootBundle.loadString('assets/glass_folder_pack.html').then((html) {
      if (!mounted) return;
      final i = html.indexOf('<head>');
      final injected = i == -1
          ? '$_bridgeScript$html'
          : html.replaceRange(i + 6, i + 6, _bridgeScript);
      ctrl.loadHtmlString(injected);
    });
  }

  @override
  void didUpdateWidget(GlassFolderPack old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label || old.files.length != widget.files.length) {
      _sendProps();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null) return const SizedBox(width: 352, height: 404);
    // Astro OS's folder frame box: 352x404, flex none.
    return SizedBox(
      width: 352,
      height: 404,
      child: WebViewWidget(controller: ctrl),
    );
  }
}
