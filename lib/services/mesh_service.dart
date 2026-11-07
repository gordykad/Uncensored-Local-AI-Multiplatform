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
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'image_gen_service.dart';

class MeshSeat {
  final String model;
  final String lane;
  final String group;
  final String status; // 'proven' | 'unverified'
  // Mesh 0.17 fields (from GET /lanes/models, computed live by the
  // serving gateway): unverified seats ROUTE - picking one is Kai's
  // smoke test - and only blocked seats are dead.
  final bool available;
  final String? blocked; // reason, only when truly unservable
  final bool unverifiedFlag;
  final bool verifiedOverride; // Kai flipped it via /mesh/model-prefs
  final bool favorite; // mesh 0.20: starred via /mesh/model-prefs
  // Kai's "Dead Rn" tag (1.14.1): an app-side mark for seats that
  // fail in practice. The gateway's prefs accept only
  // name/favorite/verified, so the tag lives in the mesh box here;
  // dead seats sink to the bottom of every list until retried.
  final bool dead;
  const MeshSeat({
    required this.model,
    required this.lane,
    required this.group,
    required this.status,
    this.available = true,
    this.blocked,
    this.unverifiedFlag = false,
    this.verifiedOverride = false,
    this.favorite = false,
    this.dead = false,
  });

  bool get proven => status == 'proven';
  bool get isVerified => proven || verifiedOverride;
  bool get isBlocked => !available;
  bool get unverified => !isVerified && (unverifiedFlag || !proven);

  factory MeshSeat.fromMap(Map m) => MeshSeat(
    model: m['model']?.toString() ?? '',
    lane: m['lane']?.toString() ?? '',
    group: m['group']?.toString() ?? '',
    status: m['status']?.toString() ?? 'unverified',
    available: m['available'] != false,
    blocked: m['blocked']?.toString(),
    unverifiedFlag: m['unverified'] == true,
    verifiedOverride: m['verified_override'] == true,
    favorite: m['favorite'] == true,
  );

  Map<String, dynamic> toMap() => {
    'model': model,
    'lane': lane,
    'group': group,
    'status': status,
    'available': available,
    if (blocked != null) 'blocked': blocked,
    'unverified': unverifiedFlag,
    'verified_override': verifiedOverride,
    'favorite': favorite,
  };

  MeshSeat copyWith({bool? favorite, bool? verifiedOverride, bool? dead}) =>
      MeshSeat(
        model: model,
        lane: lane,
        group: group,
        status: status,
        available: available,
        blocked: blocked,
        unverifiedFlag: unverifiedFlag,
        verifiedOverride: verifiedOverride ?? this.verifiedOverride,
        favorite: favorite ?? this.favorite,
        dead: dead ?? this.dead,
      );
}

class MeshNodeModel {
  final String name;
  final String node; // 'pc' | 'vm' | 'aws' | ...
  final bool favorite; // mesh 0.20: starred via /mesh/model-prefs
  const MeshNodeModel({
    required this.name,
    required this.node,
    this.favorite = false,
  });

  factory MeshNodeModel.fromMap(Map m) => MeshNodeModel(
    name: m['name']?.toString() ?? '',
    node: m['node']?.toString() ?? '',
    favorite: m['favorite'] == true,
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
  // ── "Dead Rn" tags (Kai, 1.14.1) ─────────────────────────────
  // App-side set of seat model ids Kai has marked dead. Applied to
  // every seat list on the way out; the cache stores the raw flags.

  Set<String> get deadModels {
    final raw = _box.get('dead_models') as List?;
    if (raw == null) return {};
    return raw.map((e) => e.toString()).toSet();
  }

  List<MeshSeat> _applyDead(List<MeshSeat> seats) {
    final dead = deadModels;
    if (dead.isEmpty) return seats;
    return [for (final s in seats) s.copyWith(dead: dead.contains(s.model))];
  }

  /// Tag or untag a seat "Dead Rn". Dead seats sink to the bottom
  /// of every list until retried (picking one clears the tag).
  Future<void> setModelDead(String model, bool dead) async {
    final set = deadModels;
    if (dead) {
      set.add(model);
    } else {
      set.remove(model);
    }
    await _box.put('dead_models', set.toList());
  }

  /// Picker order: favorites first, "Dead Rn" last (stable inside
  /// each class).
  static List<MeshSeat> pickerOrder(List<MeshSeat> items) {
    int rank(MeshSeat s) => (s.dead ? 2 : 0) + (s.favorite ? 0 : 1);
    final indexed = items.asMap().entries.toList()
      ..sort((a, b) {
        final r = rank(a.value).compareTo(rank(b.value));
        return r != 0 ? r : a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }

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
        'catalog_fetched_ms',
        DateTime.now().millisecondsSinceEpoch,
      );
      return _applyDead(list);
    } catch (_) {
      return cachedSeats();
    }
  }

  List<MeshSeat> cachedSeats() {
    final raw = _box.get('catalog_models') as List?;
    if (raw == null) return [];
    return _applyDead(
      raw
          .map((m) => MeshSeat.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList(),
    );
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
  /// Cached last-good like the seat catalog, so the chat header picker
  /// can list them synchronously.
  Future<List<MeshNodeModel>> fetchNodeModels() async {
    if (!connectivityOn) return cachedNodeModels();
    try {
      final r = await http
          .get(Uri.parse('$_base/api/tags'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return cachedNodeModels();
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (d['models'] as List? ?? [])
          .map(
            (m) => MeshNodeModel.fromMap(Map<String, dynamic>.from(m as Map)),
          )
          .where((m) => m.name.isNotEmpty)
          .toList();
      await _box.put(
        'catalog_nodes',
        list
            .map(
              (m) => {'name': m.name, 'node': m.node, 'favorite': m.favorite},
            )
            .toList(),
      );
      return list;
    } catch (_) {
      return cachedNodeModels();
    }
  }

  List<MeshNodeModel> cachedNodeModels() {
    final raw = _box.get('catalog_nodes') as List?;
    if (raw == null) return [];
    return raw
        .map((m) => MeshNodeModel.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  /// Flip a seat's verified state on the serving gateway (mesh 0.17:
  /// POST /mesh/model-prefs {model, verified}). The flip is stored
  /// per-gateway; the cached catalog entry is updated in place so the
  /// pickers tell the truth without waiting for a refetch.
  /// Returns true when the gateway accepted the flip.
  Future<bool> setModelVerified(String model, bool verified) async {
    if (!connectivityOn) return false;
    try {
      final r = await http
          .post(
            Uri.parse('$_base/mesh/model-prefs'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'model': model, 'verified': verified}),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return false;
      final seats = cachedSeats();
      final i = seats.indexWhere((s) => s.model == model);
      if (i >= 0) {
        final s = seats[i];
        seats[i] = MeshSeat(
          model: s.model,
          lane: s.lane,
          group: s.group,
          status: s.status,
          available: s.available,
          blocked: s.blocked,
          unverifiedFlag: verified ? false : s.unverifiedFlag,
          verifiedOverride: verified,
        );
        await _box.put('catalog_models', seats.map((s) => s.toMap()).toList());
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Star/unstar a model on the serving gateway (mesh 0.20:
  /// POST /mesh/model-prefs {model, favorite}). Prefs are
  /// per-gateway; the write goes to the same gateway the catalog
  /// came from. Cached seat + node entries update in place.
  Future<bool> setModelFavorite(String model, bool favorite) async {
    if (!connectivityOn) return false;
    try {
      final r = await http
          .post(
            Uri.parse('$_base/mesh/model-prefs'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'model': model, 'favorite': favorite}),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return false;
      final seats = cachedSeats();
      final i = seats.indexWhere((s) => s.model == model);
      if (i >= 0) {
        seats[i] = seats[i].copyWith(favorite: favorite);
        await _box.put('catalog_models', seats.map((s) => s.toMap()).toList());
      }
      final nodes = cachedNodeModels();
      final j = nodes.indexWhere((n) => n.name == model);
      if (j >= 0) {
        nodes[j] = MeshNodeModel(
          name: nodes[j].name,
          node: nodes[j].node,
          favorite: favorite,
        );
        await _box.put(
          'catalog_nodes',
          nodes
              .map(
                (m) => {'name': m.name, 'node': m.node, 'favorite': m.favorite},
              )
              .toList(),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Favorites first, stable within each class (mesh 0.20 curation:
  /// a starred model pins to the top of every picker).
  static List<T> favoritesFirst<T>(List<T> items, bool Function(T) isFav) {
    final fav = items.where(isFav).toList();
    final rest = items.where((e) => !isFav(e)).toList();
    return [...fav, ...rest];
  }

  // ── Wake box (mesh 0.23/0.24) ─────────────────────────────────
  // The 'aws' node's wakebox32b: Warm wakes + pre-warms it, Stop
  // sleeps the instance (storage intact, never terminates). Both
  // ride the PC gateway, which relays to the VM gateway's creds.

  Future<bool> wakeBox() async {
    if (!connectivityOn) return false;
    try {
      final r = await http
          .post(Uri.parse('$_base/mesh/wake'))
          .timeout(const Duration(seconds: 15));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sleepBox() async {
    if (!connectivityOn) return false;
    try {
      final r = await http
          .post(Uri.parse('$_base/mesh/sleep'))
          .timeout(const Duration(seconds: 15));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Phone-as-node (T-05 app side) ─────────────────────────────
  // While the phone-node switch is on, this phone joins the mesh as
  // node "phone": the gateway probes its /api/tags and routes chats
  // to its /api/chat like any Ollama-shaped node. Heartbeat = a
  // re-join every 60s (gateway TTL 180s); leaving is explicit.

  static const phoneNodeName = 'phone';

  bool get phoneNodeOn =>
      _settings.get('mesh_phone_node', defaultValue: false) as bool;

  Timer? _heartbeat;
  Future<Map<String, dynamic>> Function()? _presencePayload;

  /// The tailnet (100.64.0.0/10) IPv4 of this phone, or null when
  /// Tailscale is not up.
  /// The tailnet address this phone should advertise, when the
  /// gateway has echoed one back from a join (T-05 bulletproofing:
  /// the gateway sees the true source address; the phone's own
  /// interface guess is only the fallback).
  static String? _echoedIp;
  static String? _echoedUrl;

  /// Response keys the gateway's join echo may arrive under, in
  /// preference order. Confirmed against the mesh chat's contract
  /// before this ships; unknown keys are ignored.
  static const _echoKeys = ['observed_ip', 'echo_ip', 'advertised_ip'];

  static bool _isTailnetV4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4 || parts[0] != '100') return false;
    final second = int.tryParse(parts[1]) ?? 0;
    return second >= 64 && second <= 127;
  }

  /// The address to advertise: the gateway's echo when we have one,
  /// otherwise the interface heuristic.
  static Future<String?> advertisedIp() async => _echoedIp ?? tailnetIp();

  /// The full URL to advertise: the gateway's echoed URL wins
  /// (mesh 0.30 contract: observed_url), then the echoed IP, then
  /// the heuristic address.
  static Future<String?> advertisedUrl(int port) async {
    if (_echoedUrl != null) return _echoedUrl;
    final ip = await advertisedIp();
    return ip == null ? null : 'http://$ip:$port';
  }

  static Future<String?> tailnetIp() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? onInterface(bool Function(String name) test) {
        for (final iface in ifaces) {
          if (!test(iface.name)) continue;
          for (final a in iface.addresses) {
            if (_isTailnetV4(a.address)) return a.address;
          }
        }
        return null;
      }

      // T-05 fix: the carrier's cellular interface (pdp_ip*) also
      // holds a CGNAT address in 100.64/10 and enumerates ahead of
      // the Tailscale utun — the old first-match version advertised
      // an unroutable cellular address, so the phone joined and
      // heartbeat fine but never served a single routed request.
      // Prefer the tunnel interface, then any non-cellular one;
      // a cellular address is the last resort, never the default.
      return onInterface((n) => n.startsWith('utun')) ??
          onInterface((n) => !n.startsWith('pdp_ip')) ??
          onInterface((_) => true);
    } catch (_) {}
    return null;
  }

  Future<bool> _join(Map<String, dynamic> payload) async {
    try {
      final r = await http
          .post(
            Uri.parse('$_base/mesh/join'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        // T-05: if the gateway echoed the source address it saw,
        // adopt it — the next heartbeat's payload advertises the
        // echo instead of the interface guess.
        try {
          final body = jsonDecode(r.body);
          if (body is Map) {
            for (final k in _echoKeys) {
              final v = body[k];
              if (v is String && _isTailnetV4(v)) {
                _echoedIp = v;
                break;
              }
            }
            final echoedUrl = body['observed_url'];
            if (echoedUrl is String) {
              final host = Uri.tryParse(echoedUrl)?.host ?? '';
              if (_isTailnetV4(host)) _echoedUrl = echoedUrl;
            }
          }
        } catch (_) {}
      }
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Start (or restart) phone-node presence. [payloadOf] is read at
  /// every heartbeat so the address and model list stay current.
  Future<bool> startPresence(
    Future<Map<String, dynamic>> Function() payloadOf,
  ) async {
    _presencePayload = payloadOf;
    await _settings.put('mesh_phone_node', true);
    final ok = await _join(await payloadOf());
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) async {
      final p = _presencePayload;
      if (p != null) _join(await p());
    });
    return ok;
  }

  Future<void> stopPresence({bool leave = true}) async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _presencePayload = null;
    await _settings.put('mesh_phone_node', false);
    if (leave && connectivityOn) {
      try {
        await http
            .post(
              Uri.parse('$_base/mesh/leave'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'name': phoneNodeName}),
            )
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
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
      // Mesh 0.16+: the error body carries the real cause (seat
      // unavailable + reason, or the upstream lane error). Surface it
      // verbatim instead of a bare status code.
      final body = await resp.stream.bytesToString();
      client.close();
      String reason = '';
      try {
        final d = jsonDecode(body) as Map<String, dynamic>;
        reason = d['error']?.toString() ?? '';
      } catch (_) {}
      if (reason.isEmpty) {
        final t = body.trim();
        reason = t.isEmpty
            ? 'Mesh answered HTTP ${resp.statusCode}'
            : 'Mesh answered HTTP ${resp.statusCode}: '
                  '${t.length > 180 ? t.substring(0, 180) : t}';
      }
      throw Exception(reason);
    }
    try {
      await for (final line
          in resp.stream
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
