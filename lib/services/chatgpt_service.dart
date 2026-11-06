// Ticket 33: ChatGPT subscription lane (Kai, 2026-11-05).
//
// Rides Kai's ChatGPT Premium subscription - no API key, nothing
// extra billed. "Sign in with ChatGPT" OAuth (the Codex flow):
// PKCE S256 against auth.openai.com with the Codex public client,
// tokens device-local in the 'chatgpt' Hive box (same discipline as
// Kai's pasted keys), auto-refresh on the refresh token.
//
// Chat and image generation both go to the subscription backend's
// Responses API: POST chatgpt.com/backend-api/codex/responses with
// the access token as Bearer and the account id from the id token
// in the ChatGPT-Account-Id header. store:false always.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

class ChatGptService {
  static const _clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const _authorizeUrl = 'https://auth.openai.com/oauth/authorize';
  static const _tokenUrl = 'https://auth.openai.com/oauth/token';
  static const redirectUri = 'http://localhost:1455/auth/callback';
  static const _backend = 'https://chatgpt.com/backend-api';

  /// Fallback slugs, current as of 2026-11-05 (the Codex catalog
  /// rotates fast: gpt-5.4 retired for ChatGPT sign-in 2026-08-31,
  /// gpt-5.5 on 2026-10-14 - both answered Kai's first chats with
  /// the backend's "not supported" 400). fetchModels replaces this
  /// with the account's live entitled list whenever it can; the
  /// order here is best-first, gpt-6.1-sol is OpenAI's named
  /// successor to 5.5 for Plus/Pro accounts.
  static const fallbackModels = [
    'gpt-6.1-sol',
    'gpt-6-astra',
    'gpt-6.1-terra',
    'gpt-6-luna',
    'gpt-5.6-sol',
    'gpt-5.6-terra',
    'gpt-5.6-luna',
  ];

  /// Slugs the backend has retired for ChatGPT sign-in - a stored
  /// pick of one of these can never answer again.
  static const _retiredModels = {'gpt-5.5', 'gpt-5.4', 'gpt-5.4-mini'};

  /// One-time heal: a stored model pick from the retired set (the
  /// 1.20.0 fallback seeded gpt-5.5) resets to the current default,
  /// and the seeded picker connection follows. Runs on service use.
  void healStoredModel() {
    final m = _box.get('chat_model') as String?;
    if (m == null || !_retiredModels.contains(m)) return;
    _box.put('chat_model', fallbackModels.first);
    try {
      final box = Hive.box('connections');
      final raw = box.get('items') as List?;
      if (raw == null) return;
      var changed = false;
      final items = raw.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        if (map['id'] == 'chatgpt-sub' &&
            _retiredModels.contains(map['model']?.toString())) {
          map['model'] = fallbackModels.first;
          changed = true;
        }
        return map;
      }).toList();
      if (changed) box.put('items', items);
    } catch (_) {}
  }

  Box get _box => Hive.box('chatgpt');

  bool get isSignedIn => (_box.get('refresh_token') as String?)?.isNotEmpty ?? false;

  ChatGptService() {
    healStoredModel();
  }

  String get email => _box.get('email', defaultValue: '') as String;
  String get accountId => _box.get('account_id', defaultValue: '') as String;

  String get chatModel =>
      _box.get('chat_model', defaultValue: fallbackModels.first) as String;
  set chatModel(String m) => _box.put('chat_model', m);

  // ── PKCE + authorize URL ─────────────────────────────────────

  static String _b64url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// (verifier, authorize URL, state) for one sign-in attempt.
  ({String verifier, Uri url, String state}) beginSignIn() {
    final rng = Random.secure();
    final verifier =
        _b64url(List.generate(48, (_) => rng.nextInt(256)));
    final challenge = _b64url(sha256.convert(utf8.encode(verifier)).bytes);
    final state = _b64url(List.generate(24, (_) => rng.nextInt(256)));
    final params = <String, String>{
      'response_type': 'code',
      'client_id': _clientId,
      'redirect_uri': redirectUri,
      'scope': 'openid profile email offline_access',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'id_token_add_organizations': 'true',
      'codex_cli_simplified_flow': 'true',
      'originator': 'minix',
    };
    final url = Uri.parse(_authorizeUrl).replace(queryParameters: params);
    return (verifier: verifier, url: url, state: state);
  }

  // ── Token lifecycle ──────────────────────────────────────────

  Map<String, dynamic> _jwtClaims(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return {};
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      return jsonDecode(utf8.decode(base64.decode(payload)))
          as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  void _saveTokens(Map<String, dynamic> d) {
    final access = d['access_token']?.toString() ?? '';
    final refresh = d['refresh_token']?.toString() ?? '';
    final idToken = d['id_token']?.toString() ?? '';
    if (access.isNotEmpty) _box.put('access_token', access);
    if (refresh.isNotEmpty) _box.put('refresh_token', refresh);
    if (idToken.isNotEmpty) {
      _box.put('id_token', idToken);
      final claims = _jwtClaims(idToken);
      final auth =
          (claims['https://api.openai.com/auth'] as Map?) ?? const {};
      final acct = auth['chatgpt_account_id']?.toString() ??
          claims['chatgpt_account_id']?.toString() ??
          '';
      if (acct.isNotEmpty) _box.put('account_id', acct);
      final em = claims['email']?.toString() ?? '';
      if (em.isNotEmpty) _box.put('email', em);
    }
    final expiresIn = (d['expires_in'] as num?)?.toInt() ?? 3600;
    _box.put('expires_at',
        DateTime.now().millisecondsSinceEpoch + expiresIn * 1000);
  }

  /// Exchange the authorize code for tokens. Throws with the
  /// server's reason on failure.
  Future<void> exchangeCode(String code, String verifier) async {
    final resp = await http
        .post(
          Uri.parse(_tokenUrl),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': redirectUri,
            'client_id': _clientId,
            'code_verifier': verifier,
          },
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('Sign-in failed (HTTP ${resp.statusCode})');
    }
    _saveTokens(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<String> ensureAccessToken() async {
    final access = _box.get('access_token', defaultValue: '') as String;
    final expiresAt = _box.get('expires_at', defaultValue: 0) as int;
    final fresh = DateTime.now().millisecondsSinceEpoch + 5 * 60 * 1000;
    if (access.isNotEmpty && expiresAt > fresh) return access;
    final refresh = _box.get('refresh_token', defaultValue: '') as String;
    if (refresh.isEmpty) {
      throw Exception('ChatGPT sign-in expired - sign in again in Settings');
    }
    final resp = await http
        .post(
          Uri.parse(_tokenUrl),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'refresh_token',
            'refresh_token': refresh,
            'client_id': _clientId,
            'scope': 'openid profile email offline_access',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('ChatGPT sign-in expired - sign in again in Settings');
    }
    _saveTokens(jsonDecode(resp.body) as Map<String, dynamic>);
    return _box.get('access_token', defaultValue: '') as String;
  }

  Future<void> signOut() async {
    await _box.clear();
  }

  Future<Map<String, String>> _headers() async {
    final token = await ensureAccessToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'OpenAI-Beta': 'responses=experimental',
      'originator': 'minix',
    };
    if (accountId.isNotEmpty) {
      headers['ChatGPT-Account-Id'] = accountId;
    }
    return headers;
  }

  // ── Models ───────────────────────────────────────────────────

  Future<List<String>> fetchModels() async {
    try {
      final headers = await _headers();
      final resp = await http
          .get(
            Uri.parse('$_backend/codex/models?client_version=1.0.0'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return fallbackModels;
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      final models = (d['models'] as List?) ?? const [];
      final slugs = models
          .map((m) => (m as Map)['slug']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return slugs.isEmpty ? fallbackModels : slugs;
    } catch (_) {
      return fallbackModels;
    }
  }

  // ── Chat (Responses API, streamed) ───────────────────────────

  /// Stream a chat turn, yielding output text deltas only. Throws
  /// with the backend's reason on errors so the chat seam surfaces
  /// them verbatim.
  Stream<String> streamChat({
    required String model,
    required List<Map<String, String>> messages,
  }) async* {
    final headers = await _headers();
    String? instructions;
    final input = <Map<String, dynamic>>[];
    for (final m in messages) {
      final role = m['role'] ?? 'user';
      final content = m['content'] ?? '';
      if (role == 'system') {
        instructions =
            instructions == null ? content : '$instructions\n$content';
        continue;
      }
      input.add({
        'role': role == 'assistant' ? 'assistant' : 'user',
        'content': [
          {
            'type': role == 'assistant' ? 'output_text' : 'input_text',
            'text': content,
          }
        ],
      });
    }
    final client = http.Client();
    final req = http.Request('POST', Uri.parse('$_backend/codex/responses'));
    req.headers.addAll(headers);
    req.body = jsonEncode({
      'model': model,
      'instructions': ?instructions,
      'input': input,
      'stream': true,
      'store': false,
    });
    final resp = await client.send(req).timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      final body = await resp.stream.bytesToString();
      client.close();
      throw Exception(_reason(body, resp.statusCode));
    }
    try {
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final t = line.trim();
        if (!t.startsWith('data:')) continue;
        final payload = t.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        Map<String, dynamic> d;
        try {
          d = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        switch (d['type']) {
          case 'response.output_text.delta':
            final delta = d['delta']?.toString() ?? '';
            if (delta.isNotEmpty) yield delta;
          case 'response.failed':
          case 'error':
            throw Exception(_reason(jsonEncode(d), resp.statusCode));
          case 'response.completed':
            return;
        }
      }
    } finally {
      client.close();
    }
  }

  String _reason(String body, int status) {
    try {
      final d = jsonDecode(body) as Map<String, dynamic>;
      final e = d['error'];
      if (e is Map && e['message'] != null) {
        return 'ChatGPT: ${e['message']}';
      }
      final r = d['response'] as Map?;
      final re = r?['error'];
      if (re is Map && re['message'] != null) {
        return 'ChatGPT: ${re['message']}';
      }
    } catch (_) {}
    final t = body.trim();
    final short = t.length > 180 ? t.substring(0, 180) : t;
    return 'ChatGPT answered HTTP $status${short.isEmpty ? '' : ': $short'}';
  }

  // ── Image generation (Responses image_generation tool) ──────

  /// One image from the subscription backend. Returns PNG bytes.
  /// Throws with the backend's reason when it refuses (the image
  /// tab shows it on the item, same as every other lane).
  Future<List<int>> generateImage({
    required String prompt,
    String size = '1024x1024',
    void Function(String phase)? onPhase,
  }) async {
    onPhase?.call('Asking ChatGPT');
    final headers = await _headers();
    final resp = await http
        .post(
          Uri.parse('$_backend/codex/responses'),
          headers: headers,
          body: jsonEncode({
            'model': chatModel,
            // The codex backend rejects a bare-string input with
            // 400 "Input must be a list" (Kai's first image test,
            // 2026-11-05) - same item-list shape as the chat path.
            'input': [
              {
                'role': 'user',
                'content': [
                  {'type': 'input_text', 'text': prompt}
                ],
              }
            ],
            'tools': [
              {'type': 'image_generation', 'size': size}
            ],
            'store': false,
          }),
        )
        .timeout(const Duration(seconds: 240));
    if (resp.statusCode != 200) {
      throw Exception(_reason(resp.body, resp.statusCode));
    }
    final d = jsonDecode(resp.body) as Map<String, dynamic>;
    final output = (d['output'] as List?) ?? const [];
    for (final item in output) {
      final m = item as Map;
      if (m['type'] == 'image_generation_call') {
        final result = m['result']?.toString() ?? '';
        if (result.isNotEmpty) return base64Decode(result);
      }
    }
    throw Exception('ChatGPT returned no image for that prompt');
  }
}
