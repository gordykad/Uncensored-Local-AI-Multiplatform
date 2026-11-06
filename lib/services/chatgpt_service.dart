// Ticket 33: ChatGPT subscription lane (Kai, 2026-11-05).
//
// Rides Kai's ChatGPT Plus subscription - no API key, nothing
// extra billed. "Sign in with ChatGPT" OAuth (the Codex flow):
// PKCE S256 against auth.openai.com with the Codex public client,
// auto-refresh on the refresh token.
//
// 1.20.3 hardening (Codex audit, 2026-11-05 - the lane audited
// itself): tokens live in the platform Keychain via
// flutter_secure_storage, never plaintext Hive (pre-1.20.3 Hive
// tokens migrate on launch); ONE refresh is shared across every
// service instance behind a session-generation guard, so a
// sign-out or a newer login can never be undone by a stale
// in-flight refresh; session writes are validated and awaited;
// transient refresh failures (429/5xx/network) keep the session
// and read as "busy", only terminal OAuth failures end it;
// streamed chats must reach response.completed - a truncated
// stream is an error, never a silently partial answer; SSE is
// parsed as events, not bare lines.
//
// Chat and image generation both go to the subscription backend's
// Responses API: POST chatgpt.com/backend-api/codex/responses with
// the access token as Bearer and the account id from the id token
// in the ChatGPT-Account-Id header. store:false always.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

/// Terminal sign-in failure with a user-safe message (never raw
/// exception text - a token-response parse error can carry
/// credential fragments in its source snippet).
class ChatGptAuthException implements Exception {
  final String message;
  const ChatGptAuthException(this.message);
  @override
  String toString() => message;
}

/// Retry-able failure (rate limit, server error, network): the
/// saved session stays valid.
class ChatGptTransientException implements Exception {
  final String message;
  const ChatGptTransientException(this.message);
  @override
  String toString() => message;
}

class _MalformedSession implements Exception {
  const _MalformedSession();
}

class ChatGptService {
  static const _clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const _authorizeUrl = 'https://auth.openai.com/oauth/authorize';
  static const _tokenUrl = 'https://auth.openai.com/oauth/token';
  static const redirectUri = 'http://localhost:1455/auth/callback';
  static const _backend = 'https://chatgpt.com/backend-api';

  static const _secure = FlutterSecureStorage();
  static const _kAccess = 'cg_access_token';
  static const _kRefresh = 'cg_refresh_token';
  static const _kId = 'cg_id_token';

  /// Bumped on every new login and every sign-out. A refresh that
  /// started under an older generation discards its result.
  static int _generation = 0;

  /// The one in-flight refresh, shared across ALL instances
  /// (chat, image gen, settings and model fetch construct their
  /// services independently - an instance lock would not
  /// synchronize them).
  static Future<void>? _refreshInFlight;

  static bool _migrated = false;

  /// Fallback slugs, current as of 2026-11-05 (the Codex catalog
  /// rotates fast: gpt-5.4 retired for ChatGPT sign-in 2026-08-31,
  /// gpt-5.5 on 2026-10-14 - both answered Kai's first chats with
  /// the backend's "not supported" 400). Roster verified against
  /// Kai's own account via PC Codex probes, 2026-11-05.
  /// fetchModels replaces this with the account's live entitled
  /// list whenever it can; order is best-first.
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

  /// Non-secret presence flag (the tokens themselves are Keychain
  /// material now). Falls back to detecting unmigrated legacy
  /// tokens so the very first 1.20.3 paint is still truthful.
  bool get isSignedIn =>
      _box.get('has_session', defaultValue: false) as bool ||
      ((_box.get('refresh_token') as String?)?.isNotEmpty ?? false);

  ChatGptService() {
    healStoredModel();
  }

  String get email => _box.get('email', defaultValue: '') as String;
  String get accountId => _box.get('account_id', defaultValue: '') as String;

  String get chatModel =>
      _box.get('chat_model', defaultValue: fallbackModels.first) as String;
  set chatModel(String m) => _box.put('chat_model', m);

  // ── Legacy token migration (pre-1.20.3 plaintext Hive) ───────

  /// Move any plaintext Hive tokens into the Keychain and delete
  /// the plaintext copies. Called from main() at launch and
  /// (idempotently) before every token use.
  static Future<void> migrateLegacy() async {
    if (_migrated) return;
    _migrated = true;
    try {
      final box = Hive.box('chatgpt');
      final access = box.get('access_token') as String?;
      final refresh = box.get('refresh_token') as String?;
      final id = box.get('id_token') as String?;
      if (access == null && refresh == null && id == null) return;
      if (access != null && access.isNotEmpty) {
        await _secure.write(key: _kAccess, value: access);
      }
      if (refresh != null && refresh.isNotEmpty) {
        await _secure.write(key: _kRefresh, value: refresh);
      }
      if (id != null && id.isNotEmpty) {
        await _secure.write(key: _kId, value: id);
      }
      await box.delete('access_token');
      await box.delete('refresh_token');
      await box.delete('id_token');
      if (refresh != null && refresh.isNotEmpty) {
        await box.put('has_session', true);
      }
    } catch (_) {
      // A failed migration retries on the next launch or token
      // use; the plaintext copy is only deleted after the secure
      // writes above succeeded.
      _migrated = false;
    }
  }

  // ── PKCE + authorize URL ─────────────────────────────────────

  static String _b64url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// (verifier, authorize URL, state) for one sign-in attempt.
  ({String verifier, Uri url, String state}) beginSignIn() {
    final rng = Random.secure();
    final verifier = _b64url(List.generate(48, (_) => rng.nextInt(256)));
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

  Map<String, dynamic> _decodeTokenResponse(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    throw const _MalformedSession();
  }

  /// Validate the whole token response BEFORE mutating anything,
  /// then persist the session in awaited writes. A login replaces
  /// account metadata (absent claims clear, never linger); a
  /// refresh preserves it.
  Future<void> _saveSession(Map<String, dynamic> d,
      {required bool isLogin}) async {
    final access = d['access_token'];
    if (access is! String || access.isEmpty) {
      throw const _MalformedSession();
    }
    final expiresIn = d['expires_in'];
    final secs = expiresIn is num ? expiresIn.toInt() : 3600;
    final refresh = d['refresh_token'];
    final idToken = d['id_token'];

    await _secure.write(key: _kAccess, value: access);
    if (refresh is String && refresh.isNotEmpty) {
      await _secure.write(key: _kRefresh, value: refresh);
    } else if (isLogin) {
      await _secure.delete(key: _kRefresh);
    }
    if (idToken is String && idToken.isNotEmpty) {
      await _secure.write(key: _kId, value: idToken);
      final claims = _jwtClaims(idToken);
      final auth = (claims['https://api.openai.com/auth'] as Map?) ?? const {};
      final acct = auth['chatgpt_account_id']?.toString() ??
          claims['chatgpt_account_id']?.toString() ??
          '';
      final em = claims['email']?.toString() ?? '';
      if (acct.isNotEmpty) {
        await _box.put('account_id', acct);
      } else if (isLogin) {
        await _box.delete('account_id');
      }
      if (em.isNotEmpty) {
        await _box.put('email', em);
      } else if (isLogin) {
        await _box.delete('email');
      }
    } else if (isLogin) {
      await _secure.delete(key: _kId);
      await _box.delete('account_id');
      await _box.delete('email');
    }
    await _box.put('expires_at',
        DateTime.now().millisecondsSinceEpoch + secs * 1000);
    await _box.put('has_session', true);
  }

  /// Exchange the authorize code for tokens (a NEW login - bumps
  /// the session generation so any older refresh is discarded).
  Future<void> exchangeCode(String code, String verifier) async {
    await migrateLegacy();
    _generation++;
    http.Response resp;
    try {
      resp = await http
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
    } catch (_) {
      throw const ChatGptTransientException(
          'ChatGPT could not be reached - check the connection and try again');
    }
    if (resp.statusCode != 200) {
      throw ChatGptAuthException('Sign-in failed (HTTP ${resp.statusCode})');
    }
    try {
      await _saveSession(_decodeTokenResponse(resp.body), isLogin: true);
    } on _MalformedSession {
      throw const ChatGptAuthException(
          'Sign-in failed: incomplete response from OpenAI');
    }
  }

  Future<String> ensureAccessToken() async {
    await migrateLegacy();
    var access = await _secure.read(key: _kAccess) ?? '';
    final expiresAt = _box.get('expires_at', defaultValue: 0) as int;
    final freshUntil =
        DateTime.now().millisecondsSinceEpoch + 5 * 60 * 1000;
    if (access.isNotEmpty && expiresAt > freshUntil) return access;

    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      await inFlight;
    } else {
      final gen = _generation;
      late final Future<void> f;
      f = _doRefresh(gen).whenComplete(() {
        if (identical(_refreshInFlight, f)) _refreshInFlight = null;
      });
      _refreshInFlight = f;
      await f;
    }
    access = await _secure.read(key: _kAccess) ?? '';
    if (access.isEmpty) {
      throw const ChatGptAuthException(
          'ChatGPT sign-in expired - sign in again in Settings');
    }
    return access;
  }

  Future<void> _doRefresh(int gen) async {
    final refresh = await _secure.read(key: _kRefresh) ?? '';
    if (refresh.isEmpty) {
      throw const ChatGptAuthException(
          'ChatGPT sign-in expired - sign in again in Settings');
    }
    http.Response resp;
    try {
      resp = await http
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
    } catch (_) {
      throw const ChatGptTransientException(
          'ChatGPT could not be reached - try again in a moment');
    }
    if (gen != _generation) return; // superseded while in flight
    if (resp.statusCode == 400 || resp.statusCode == 401) {
      // Terminal: the refresh token itself is dead. End the
      // session cleanly so the UI shows signed-out, not a loop.
      await _clearSession();
      throw const ChatGptAuthException(
          'ChatGPT sign-in expired - sign in again in Settings');
    }
    if (resp.statusCode != 200) {
      throw const ChatGptTransientException(
          'ChatGPT is busy right now - try again in a moment');
    }
    try {
      await _saveSession(_decodeTokenResponse(resp.body), isLogin: false);
    } on _MalformedSession {
      throw const ChatGptTransientException(
          'ChatGPT sent an incomplete response - try again in a moment');
    }
  }

  Future<void> _clearSession() async {
    await _secure.delete(key: _kAccess);
    await _secure.delete(key: _kRefresh);
    await _secure.delete(key: _kId);
    await _box.put('has_session', false);
    await _box.delete('expires_at');
    await _box.delete('account_id');
    await _box.delete('email');
  }

  Future<void> signOut() async {
    _generation++;
    _refreshInFlight = null;
    await _clearSession();
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

  /// The account's live entitled model list (the only
  /// authoritative roster - the Codex catalog rotates too fast
  /// for anything baked in). Auth failures SURFACE (the 1.20.0
  /// build hid a dead session behind the fallback list for a
  /// whole evening); catalog/network failures fall back.
  Future<List<String>> fetchModels() async {
    final headers = await _headers();
    try {
      final resp = await http
          .get(
            Uri.parse('$_backend/codex/models?client_version=1.0.0'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw const ChatGptAuthException(
            'ChatGPT sign-in expired - sign in again in Settings');
      }
      if (resp.statusCode != 200) return fallbackModels;
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      final models = (d['models'] as List?) ?? const [];
      final slugs = models
          .map((m) => (m as Map)['slug']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return slugs.isEmpty ? fallbackModels : slugs;
    } on ChatGptAuthException {
      rethrow;
    } catch (_) {
      return fallbackModels;
    }
  }

  // ── Chat (Responses API, streamed) ───────────────────────────

  /// Stream a chat turn, yielding output text deltas only. The
  /// stream must reach response.completed: a premature EOF is an
  /// error, never a silently partial answer presented as done.
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
    try {
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
        final body = await resp.stream
            .bytesToString()
            .timeout(const Duration(seconds: 15));
        throw Exception(_reason(body, resp.statusCode));
      }
      var completed = false;
      String? incompleteReason;

      await for (final d in _events(resp)) {
        switch (d['type']) {
          case 'response.output_text.delta':
            final delta = d['delta']?.toString() ?? '';
            if (delta.isNotEmpty) yield delta;
          case 'response.failed':
          case 'error':
            throw Exception(_reason(jsonEncode(d), resp.statusCode));
          case 'response.incomplete':
            final r = d['response'] as Map?;
            final det = r?['incomplete_details'] as Map?;
            incompleteReason = det?['reason']?.toString() ?? 'incomplete';
          case 'response.completed':
            completed = true;
        }
      }
      if (!completed) {
        if (incompleteReason != null) {
          throw Exception(
              'ChatGPT cut the response short ($incompleteReason)');
        }
        throw const ChatGptTransientException(
            'ChatGPT stream ended before the response completed');
      }
    } finally {
      client.close();
    }
  }

  /// Decode a streamed Responses reply into event maps. SSE is
  /// parsed as EVENTS: data: lines accumulate until a blank line
  /// dispatches the event (multi-line payloads are legal and
  /// line-wise parsing silently dropped them). [idle] aborts a
  /// stalled stream as a transient failure.
  Stream<Map<String, dynamic>> _events(
    http.StreamedResponse resp, {
    Duration idle = const Duration(seconds: 90),
  }) async* {
    final dataLines = <String>[];

    Stream<String> payloads() async* {
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(idle,
              onTimeout: (sink) => sink.addError(
                  const ChatGptTransientException(
                      'ChatGPT stopped responding')))) {
        if (line.isEmpty) {
          if (dataLines.isNotEmpty) {
            yield dataLines.join('\n');
            dataLines.clear();
          }
          continue;
        }
        if (line.startsWith('data:')) {
          var payload = line.substring(5);
          if (payload.startsWith(' ')) payload = payload.substring(1);
          dataLines.add(payload);
        }
      }
      if (dataLines.isNotEmpty) yield dataLines.join('\n');
    }

    await for (final payload in payloads()) {
      if (payload.isEmpty || payload == '[DONE]') continue;
      try {
        final d = jsonDecode(payload);
        if (d is Map<String, dynamic>) yield d;
      } catch (_) {
        continue;
      }
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
  ///
  /// 1.20.4: the backend demands stream:true for image calls too
  /// (Kai's 1.20.2/1.20.3 tests: 400 "Stream must be set to
  /// true" - this also settles the question the Codex audit left
  /// open). The finished image is collected from the stream: the
  /// output_item.done event and the completed response's output
  /// both carry it; partial_image events are progress only.
  Future<List<int>> generateImage({
    required String prompt,
    String size = '1024x1024',
    void Function(String phase)? onPhase,
  }) async {
    onPhase?.call('Asking ChatGPT');
    final headers = await _headers();
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('$_backend/codex/responses'));
      req.headers.addAll(headers);
      req.body = jsonEncode({
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
        'stream': true,
        'store': false,
      });
      final resp = await client.send(req).timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) {
        final body = await resp.stream
            .bytesToString()
            .timeout(const Duration(seconds: 15));
        throw Exception(_reason(body, resp.statusCode));
      }
      String? imageB64;
      String? incompleteReason;
      var painting = false;
      await for (final d
          in _events(resp, idle: const Duration(seconds: 150))) {
        switch (d['type']) {
          case 'response.image_generation_call.partial_image':
            if (!painting) {
              painting = true;
              onPhase?.call('Painting');
            }
          case 'response.output_item.done':
            final item = d['item'] as Map?;
            if (item?['type'] == 'image_generation_call') {
              final r = item?['result']?.toString() ?? '';
              if (r.isNotEmpty) imageB64 = r;
            }
          case 'response.completed':
            final r = d['response'] as Map?;
            final output = (r?['output'] as List?) ?? const [];
            for (final item in output) {
              final m = item as Map;
              if (m['type'] == 'image_generation_call') {
                final res = m['result']?.toString() ?? '';
                if (res.isNotEmpty) imageB64 = res;
              }
            }
          case 'response.incomplete':
            final r = d['response'] as Map?;
            final det = r?['incomplete_details'] as Map?;
            incompleteReason = det?['reason']?.toString() ?? 'incomplete';
          case 'response.failed':
          case 'error':
            throw Exception(_reason(jsonEncode(d), resp.statusCode));
        }
      }
      if (imageB64 != null) return base64Decode(imageB64);
      if (incompleteReason != null) {
        throw Exception('ChatGPT cut the image short ($incompleteReason)');
      }
      throw Exception('ChatGPT returned no image for that prompt');
    } finally {
      client.close();
    }
  }
}
