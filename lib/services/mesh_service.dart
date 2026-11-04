// Ticket 31: the Seven Mesh on Kai's PC as a chat source.
//
// The mesh serves an Ollama-compatible API on the PC (system tailnet):
//   GET  /lanes         - lane catalog totals (providers / seats / proven)
//   GET  /lanes/models  - seat-level entries {model, status, lane, group}
//   GET  /api/tags      - models on mesh nodes (PC / VM), node-attributed
//   POST /api/chat      - Ollama chat, NDJSON stream; the mesh routes the
//                         model to a local node or to the seat's lane.
//
// Keys NEVER enter this app (Amendments 2 + 4): the keyed lanes spend
// Kai's Astro OS vault keys broker-side on the PC. The phone holds only
// the mesh address. Kai-only by topology - the tester fleet is not on
// his tailnet, so this source simply never resolves for them.
//
// Gated by the ticket 09 connectivity switch, like every external
// source. The catalog is cached last-good in the 'mesh' Hive box so the
// picker renders instantly; a stale cache is badged as cached.
import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'image_gen_service.dart';

class MeshSeat {
  final String model;
  final String lane;
  final String group;
  final String status; // 'proven' | 'unverified'
  const MeshSeat({
    required this.model,
    required this.lane,
    required this.group,
    required this.status,
  });

  bool get proven => status == 'proven';

  factory MeshSeat.fromMap(Map m) => MeshSeat(
        model: m['model']?.toString() ?? '',
        lane: m['lane']?.toString() ?? '',
        group: m['group']?.toString() ?? '',
        status: m['status']?.toString() ?? 'unverified',
      );

  Map<String, dynamic> toMap() => {
        'model': model,
        'lane': lane,
        'group': group,
        'status': status,
      };
}

class MeshNodeModel {
  final String name;
  final String node; // 'pc' | 'vm' | ...
  const MeshNodeModel({required this.name, required this.node});

  factory MeshNodeModel.fromMap(Map m) => MeshNodeModel(
        name: m['name']?.toString() ?? '',
        node: m['node']?.toString() ?? '',
      );
}

class MeshService {
  static const defaultAddress = 'desktop-64e8166:11435';

  Box get _box => Hive.box('mesh');
  Box get _settings => Hive.box('settings');

  bool get connectivityOn => ImageGenService().connectivityOn;

  String get address =>
      (_settings.get('mesh_address', defaultValue: defaultAddress) as String)
          .trim();

  set address(String v) => _settings.put('mesh_address', v.trim());

  String get _base => 'http://$address';

  DateTime? get catalogFetchedAt {
    final ms = _box.get('catalog_fetched_ms') as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Live catalog fetch. On any failure, falls back to the last-good
  /// cache (the caller can compare [catalogFetchedAt] to badge it).
  /// Empty when connectivity is off or nothing was ever fetched.
  Future<List<MeshSeat>> fetchSeats() async {
    if (!connectivityOn) return cachedSeats();
    try {
      final r = await http
          .get(Uri.parse('$_base/lanes/models'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return cachedSeats();
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (d['models'] as List? ?? [])
          .map((m) => MeshSeat.fromMap(Map<String, dynamic>.from(m as Map)))
          .where((s) => s.model.isNotEmpty)
          .toList();
      await _box.put('catalog_models', list.map((s) => s.toMap()).toList());
      await _box.put(
          'catalog_fetched_ms', DateTime.now().millisecondsSinceEpoch);
      return list;
    } catch (_) {
      return cachedSeats();
    }
  }

  List<MeshSeat> cachedSeats() {
    final raw = _box.get('catalog_models') as List?;
    if (raw == null) return [];
    return raw
        .map((m) => MeshSeat.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  /// Lane totals for the Settings status line. Null when unreachable.
  Future<Map<String, dynamic>?> fetchTotals() async {
    if (!connectivityOn) return null;
    try {
      final r = await http
          .get(Uri.parse('$_base/lanes'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      return Map<String, dynamic>.from(d['totals'] as Map? ?? {});
    } catch (_) {
      return null;
    }
  }

  /// Models living on mesh nodes (Kai's PC Ollama and friends).
  Future<List<MeshNodeModel>> fetchNodeModels() async {
    if (!connectivityOn) return [];
    try {
      final r = await http
          .get(Uri.parse('$_base/api/tags'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return [];
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      return (d['models'] as List? ?? [])
          .map((m) => MeshNodeModel.fromMap(Map<String, dynamic>.from(m as Map)))
          .where((m) => m.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Stream a chat through the mesh. Yields content deltas only.
  /// Throws on HTTP errors so the chat seam can surface them honestly.
  Stream<String> streamChat({
    required String model,
    required List<Map<String, String>> messages,
  }) async* {
    if (!connectivityOn) {
      throw Exception('Connectivity is off (Settings)');
    }
    final client = http.Client();
    final req = http.Request('POST', Uri.parse('$_base/api/chat'));
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode({
      'model': model,
      'messages': messages,
      'stream': true,
    });
    final resp = await client.send(req).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      client.close();
      throw Exception('Mesh answered HTTP ${resp.statusCode}');
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
