// Ticket 33: "Sign in with ChatGPT" - the OAuth authorize page in
// an in-app WebView. The loopback redirect is caught by navigation
// interception (no local server is ever run): when the page tries
// to load http://localhost:1455/auth/callback we lift the code out
// of the URL, cancel the load, and hand the code back to the caller.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/chatgpt_service.dart';
import '../theme/app_colors.dart';

class ChatGptSignInScreen extends StatefulWidget {
  const ChatGptSignInScreen({super.key});

  @override
  State<ChatGptSignInScreen> createState() => _ChatGptSignInScreenState();
}

class _ChatGptSignInScreenState extends State<ChatGptSignInScreen> {
  late final WebViewController _ctrl;
  late final ({String verifier, Uri url, String state}) _attempt;
  bool _loading = true;
  String? _error;

  /// One-shot: the authorization code is single-use - a repeated
  /// or replayed callback navigation must never exchange twice.
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _attempt = ChatGptService().beginSignIn();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.darkBg)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (req) {
            // Exact callback match only (1.20.3 audit hardening):
            // main-frame, scheme/host/port/path all equal to the
            // registered loopback redirect - a prefix match also
            // accepted /auth/callback-extra and subframe loads.
            if (req.isMainFrame) {
              final uri = Uri.tryParse(req.url);
              if (uri != null &&
                  uri.scheme == 'http' &&
                  uri.host == 'localhost' &&
                  uri.port == 1455 &&
                  uri.path == '/auth/callback') {
                _handleCallback(uri);
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (e) {
            if (mounted && (e.isForMainFrame ?? true)) {
              setState(() {
                _loading = false;
                _error = 'The sign-in page failed to load. Check the '
                    'connection and try again.';
              });
            }
          },
        ),
      )
      ..loadRequest(_attempt.url);
  }

  Future<void> _handleCallback(Uri uri) async {
    if (_handled) return;
    _handled = true;
    final code = uri.queryParameters['code'] ?? '';
    final state = uri.queryParameters['state'] ?? '';
    final err = uri.queryParameters['error'] ?? '';
    // State is validated BEFORE the error branch too: an error
    // callback with a foreign state is not ours to display (the
    // raw OAuth error text is never rendered either).
    if (state != _attempt.state) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sign-in returned an unexpected response. Try again.';
        });
      }
      return;
    }
    if (err.isNotEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sign-in was cancelled or failed. Try again.';
        });
      }
      return;
    }
    if (code.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sign-in returned an unexpected response. Try again.';
        });
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await ChatGptService().exchangeCode(code, _attempt.verifier);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          // Sanitized only: arbitrary exception text (e.g. a JSON
          // parse failure over a token response) can embed
          // credential fragments - never render it.
          _error = e is ChatGptAuthException
              ? e.message
              : e is ChatGptTransientException
                  ? e.message
                  : 'Sign-in failed. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkBgPanel,
        foregroundColor: AppColors.darkText,
        title: const Text('Sign in with ChatGPT',
            style: TextStyle(fontSize: 16)),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _ctrl),
          if (_loading)
            const LinearProgressIndicator(
              color: AppColors.accent,
              backgroundColor: Colors.transparent,
            ),
          if (_error != null)
            Container(
              color: AppColors.darkBg,
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.darkText, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
