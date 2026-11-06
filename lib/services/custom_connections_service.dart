// Ticket 31, Amendment 3 + correction: Kai's own custom connections.
//
// Kai adds a URL/API connection himself and it becomes a seat in his
// picker. Connections are PHONE-DIRECT (his correction, 2026-11-04):
// MiniX calls the pasted URL itself, from the phone, on whatever
// network he is on - no PC, no tailnet, works anywhere.
//
// Storage is DEVICE-LOCAL ONLY (the 'connections' Hive box), same
// discipline as the RunPod key: a key Kai pastes lives on his device,
// never synced, never pinned, never in the shared config; deleting the
// connection deletes the key with it.
//
// Two API shapes:
//   openai - POST {base}/v1/chat/completions, SSE data: lines
//   ollama - POST {base}/api/chat, NDJSON lines
// Gated by the ticket 09 connectivity switch like every external source.
import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'chatgpt_service.dart';
import 'image_gen_service.dart';

class CustomConnection {
  final String id;
  final String name;
  final String baseUrl; // root only, no endpoint path (normalized on save)
  final String model;
  final String apiKey;
  final String type; // 'openai' | 'ollama'
  const CustomConnection({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    required this.type,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
        'apiKey': apiKey,
        'type': type,
      };

  factory CustomConnection.fromMap(Map m) => CustomConnection(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? 'Connection',
        baseUrl: m['baseUrl']?.toString() ?? '',
        model: m['model']?.toString() ?? '',
        apiKey: m['apiKey']?.toString() ?? '',
        type: m['type']?.toString() ?? 'openai',
      );

  /// Paste-tolerant base URL (same lesson as the link-paste fix):
  /// accepts a bare host, a full root URL, or a URL that already ends
  /// in the endpoint path, and stores the root.
  static String normalizeBase(String raw, String type) {
    var l = raw.trim();
    if (!l.startsWith('http://') && !l.startsWith('https://')) {
      l = 'https://$l';
    }
    for (final suffix in ['/v1/chat/completions', '/api/chat', '/v1']) {
      if (l.endsWith(suffix)) l = l.substring(0, l.length - suffix.length);
    }
    while (l.endsWith('/')) {
      l = l.substring(0, l.length - 1);
    }
    return l;
  }
}

class CustomConnectionsService {
  Box get _box => Hive.box('connections');

  bool get connectivityOn => ImageGenService().connectivityOn;

  List<CustomConnection> list() {
    final raw = _box.get('items') as List?;
    if (raw == null) return [];
    return raw
        .map((m) =>
            CustomConnection.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  void _save(List<CustomConnection> items) =>
      _box.put('items', items.map((c) => c.toMap()).toList());

  void add(CustomConnection c) => _save(list()..add(c));

  void update(CustomConnection c) =>
      _save(list().map((x) => x.id == c.id ? c : x).toList());

  void remove(String id) => _save(list()..removeWhere((x) => x.id == id));

  /// Stream a chat from this connection, phone-direct. Yields content
  /// deltas only. Throws on HTTP errors so the chat seam surfaces them.
  Stream<String> streamChat({
    required CustomConnection conn,
    required List<Map<String, String>> messages,
  }) async* {
    if (!connectivityOn) {
      throw Exception('Connectivity is off (Settings)');
    }
    if (conn.type == 'ollama') {
      yield* _streamOllama(conn, messages);
    } else if (conn.type == 'chatgpt') {
      // Ticket 33: the ChatGPT subscription seat - tokens ride the
      // OAuth store, the connection row only carries name + model.
      yield* ChatGptService().streamChat(model: conn.model, messages: messages);
    } else {
      yield* _streamOpenAi(conn, messages);
    }
  }

  /// Read an error response's body so the chat bubble carries the
  /// server's actual reason instead of a bare status code. OpenAI-
  /// shaped bodies nest the message under error.message.
  Future<String> _httpError(
      CustomConnection conn, http.StreamedResponse resp) async {
    final body = await resp.stream.bytesToString();
    String reason = '';
    try {
      final d = jsonDecode(body) as Map<String, dynamic>;
      final e = d['error'];
      if (e is Map) reason = e['message']?.toString() ?? '';
      if (reason.isEmpty && e != null) reason = e.toString();
    } catch (_) {}
    if (reason.isEmpty) {
      final t = body.trim();
      reason = t.isEmpty
          ? ''
          : (t.length > 180 ? t.substring(0, 180) : t);
    }
    return reason.isEmpty
        ? '${conn.name} answered HTTP ${resp.statusCode}'
        : '${conn.name}: $reason';
  }

  Stream<String> _streamOpenAi(
    CustomConnection conn,
    List<Map<String, String>> messages,
  ) async* {
    final client = http.Client();
    final req = http.Request(
        'POST', Uri.parse('${conn.baseUrl}/v1/chat/completions'));
    req.headers['Content-Type'] = 'application/json';
    if (conn.apiKey.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer ${conn.apiKey}';
    }
    req.body = jsonEncode({
      'model': conn.model,
      'messages': messages,
      'stream': true,
    });
    final resp = await client.send(req).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      final err = await _httpError(conn, resp);
      client.close();
      throw Exception(err);
    }
    try {
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final t = line.trim();
        if (!t.startsWith('data:')) continue;
        final payload = t.substring(5).trim();
        if (payload == '[DONE]') break;
        Map<String, dynamic> d;
        try {
          d = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        if (d['error'] != null) {
          throw Exception(d['error'].toString());
        }
        final choices = d['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = (choices.first as Map)['delta'] as Map?;
        final content = delta?['content']?.toString() ?? '';
        if (content.isNotEmpty) yield content;
      }
    } finally {
      client.close();
    }
  }

  Stream<String> _streamOllama(
    CustomConnection conn,
    List<Map<String, String>> messages,
  ) async* {
    final client = http.Client();
    final req = http.Request('POST', Uri.parse('${conn.baseUrl}/api/chat'));
    req.headers['Content-Type'] = 'application/json';
    if (conn.apiKey.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer ${conn.apiKey}';
    }
    req.body = jsonEncode({
      'model': conn.model,
      'messages': messages,
      'stream': true,
    });
    final resp = await client.send(req).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      final err = await _httpError(conn, resp);
      client.close();
      throw Exception(err);
    }
    try {
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final t = line.trim();
        if (t.isEmpty) continue;
        Map<String, dynamic> d;
        try {
          d = jsonDecode(t) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        if (d['error'] != null) {
          throw Exception(d['error'].toString());
        }
        final msg = d['message'] as Map?;
        final content = msg?['content']?.toString() ?? '';
        if (content.isNotEmpty) yield content;
        if (d['done'] == true) break;
      }
    } finally {
      client.close();
    }
  }
}
