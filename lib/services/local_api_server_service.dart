import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';

import '../controllers/chat_controller.dart';
import '../controllers/model_controller.dart';
import 'admin_activity_service.dart';
import 'chat_storage_service.dart';
import 'llm_service.dart';
import 'log_service.dart';
import 'memory_probe.dart';
import 'telemetry_service.dart';
import 'wakelock_service.dart';

class LocalApiServerService extends GetxService {
  static const defaultHost = '127.0.0.1';
  static const defaultPort = 4891;

  final LlmService _llm = Get.find<LlmService>();
  final ChatStorageService _storage = Get.find<ChatStorageService>();

  HttpServer? _server;

  final isRunning = false.obs;
  final isStarting = false.obs;
  final errorMessage = ''.obs;
  final port = defaultPort.obs;
  final allInterfaces = false.obs;

  String get host => allInterfaces.value ? '0.0.0.0' : defaultHost;
  String get baseUrl {
    if (allInterfaces.value) {
      return 'http://<device-ip>:${port.value}/v1';
    }
    return 'http://$defaultHost:${port.value}/v1';
  }

  bool get isBusy => _llm.isGenerating.value;
  bool get hasLoadedModel => _llm.isLoaded.value;
  String get modelId => _llm.publicModelId;

  Future<LocalApiServerService> init() async {
    port.value = _normalizePort(_storage.localApiServerPort);
    allInterfaces.value = _storage.localApiAllInterfaces;
    if (_storage.localApiServerEnabled) {
      await start();
    }
    return this;
  }

  Future<void> start({int? requestedPort}) async {
    final nextPort = _normalizePort(requestedPort ?? port.value);
    if (isRunning.value && nextPort == port.value) return;
    if (isRunning.value) {
      await stop(persist: false);
    }

    isStarting.value = true;
    errorMessage.value = '';

    try {
      final bindAddress = allInterfaces.value
          ? InternetAddress.anyIPv4
          : InternetAddress.loopbackIPv4;

      _server = await HttpServer.bind(bindAddress, nextPort, shared: false);
      port.value = nextPort;
      _storage.localApiServerPort = nextPort;
      _storage.localApiServerEnabled = true;
      isRunning.value = true;

      try {
        final wakelockService = Get.find<WakelockService>();
        await wakelockService.enableForInference();
      } catch (_) {}

      unawaited(
        _server!
            .listen(
              _handleRequest,
              onError: (Object error) {
                errorMessage.value = error.toString();
              },
            )
            .asFuture<void>(),
      );
    } catch (e) {
      _server = null;
      isRunning.value = false;
      errorMessage.value = e.toString();
      // Do not rethrow here, so that app initialization can continue
      // even if the local API server fails to bind.
    } finally {
      isStarting.value = false;
    }
  }

  Future<void> stop({bool persist = true}) async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
    isRunning.value = false;
    if (persist) {
      _storage.localApiServerEnabled = false;
    }
    try {
      final wakelockService = Get.find<WakelockService>();
      await wakelockService.disable();
    } catch (_) {}
  }

  Future<void> setPort(int nextPort) async {
    final normalized = _normalizePort(nextPort);
    port.value = normalized;
    _storage.localApiServerPort = normalized;
    if (isRunning.value) {
      await start(requestedPort: normalized);
    }
  }

  Future<void> setAllInterfaces(bool value) async {
    allInterfaces.value = value;
    _storage.localApiAllInterfaces = value;
    if (isRunning.value) {
      // Restart with new binding
      await start();
    }
  }

  /// Get the device's local network IP address.
  Future<String?> getDeviceIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  int _normalizePort(int value) {
    if (value < 1024 || value > 65535) return defaultPort;
    return value;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _applyCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/healthz') {
        await _writeJson(request.response, _healthJson());
        return;
      }

      if (request.method == 'GET' && path == '/v1/models') {
        await _writeJson(request.response, _modelsJson());
        return;
      }

      if (request.method == 'POST' && path == '/v1/chat/completions') {
        await _handleChatCompletions(request);
        return;
      }

      // Phone-as-node (T-05): the Ollama-shaped surface the Seven
      // Mesh probes and routes to when this phone joins as a node.
      if (request.method == 'GET' && path == '/api/tags') {
        await _writeJson(request.response, _ollamaTagsJson());
        return;
      }

      if (request.method == 'POST' && path == '/api/chat') {
        await _handleOllamaChat(request);
        return;
      }

      if (path.startsWith('/admin/')) {
        await _handleAdmin(request, path);
        return;
      }

      await _writeError(
        request.response,
        HttpStatus.notFound,
        'No route for `${request.method} $path`.',
        type: 'invalid_request_error',
        code: 'not_found',
      );
    } on _OpenAiRequestException catch (e) {
      await _writeError(
        request.response,
        HttpStatus.badRequest,
        e.message,
        type: 'invalid_request_error',
        param: e.param,
      );
    } catch (e) {
      await _writeError(
        request.response,
        HttpStatus.internalServerError,
        'Unexpected server error: $e',
        type: 'server_error',
      );
    }
  }

  Map<String, dynamic> _healthJson() {
    return {
      'status': 'ok',
      'ready': hasLoadedModel,
      'model': hasLoadedModel ? modelId : null,
      'busy': isBusy,
      'host': host,
      'port': port.value,
      'base_url': baseUrl,
    };
  }

  Map<String, dynamic> _modelsJson() {
    final data = hasLoadedModel
        ? [
            {
              'id': modelId,
              'object': 'model',
              'created': 0,
              'owned_by': 'uncensored-local-ai',
            },
          ]
        : <Map<String, dynamic>>[];

    return {'object': 'list', 'data': data};
  }

  // ── Ollama bridge (phone-as-node, T-05) ───────────────────────

  Map<String, dynamic> _ollamaTagsJson() {
    final ctrl = Get.find<ModelController>();
    final models = <Map<String, dynamic>>[];
    for (final filename in ctrl.downloadedModels) {
      final info = ctrl.getModelInfo(filename);
      final name = info?.name ?? filename;
      int size = 0;
      try {
        size = File(ctrl.modelPathFor(filename)).lengthSync();
      } catch (_) {}
      models.add({
        'name': name,
        'model': name,
        'size': size,
        'modified_at': DateTime.now().toUtc().toIso8601String(),
        'details': <String, dynamic>{},
      });
    }
    return {'models': models};
  }

  Future<void> _handleOllamaChat(HttpRequest request) async {
    final body = await _readJsonObject(request);
    final modelName = body['model']?.toString() ?? '';
    final rawMessages = (body['messages'] as List?) ?? const [];
    final stream = body['stream'] != false;

    final ctrl = Get.find<ModelController>();
    String? filename;
    for (final f in ctrl.downloadedModels) {
      if (f == modelName || ctrl.getModelInfo(f)?.name == modelName) {
        filename = f;
        break;
      }
    }
    if (filename == null) {
      await _writeJson(request.response, {
        'error': 'model "$modelName" not found on this phone',
      }, statusCode: HttpStatus.notFound);
      return;
    }
    if (isBusy) {
      await _writeJson(request.response, {
        'error': 'this phone is already generating',
      }, statusCode: HttpStatus.tooManyRequests);
      return;
    }
    if (ctrl.selectedModelFilename.value != filename || !hasLoadedModel) {
      await ctrl.loadModel(filename);
    }
    if (!hasLoadedModel) {
      await _writeJson(request.response, {
        'error': 'the model failed to load on this phone',
      }, statusCode: HttpStatus.internalServerError);
      return;
    }

    final messages = <LlamaChatMessage>[];
    String lastUser = '';
    for (final raw in rawMessages) {
      final m = Map<String, dynamic>.from(raw as Map);
      final roleStr = m['role']?.toString() ?? 'user';
      final content = m['content']?.toString() ?? '';
      final role = switch (roleStr) {
        'system' => LlamaChatRole.system,
        'assistant' => LlamaChatRole.assistant,
        _ => LlamaChatRole.user,
      };
      if (role == LlamaChatRole.user) lastUser = content;
      messages.add(LlamaChatMessage.fromText(role: role, text: content));
    }

    _noteAdmin(request, 'Mesh ran a generation on this phone');
    final tokens = _llm.generateChatCompletion(messages: messages);

    // Ticket 26 rule: remote runs materialize in the chat UI.
    final sink = StreamController<String>();
    unawaited(
      Get.find<ChatController>()
          .runRemoteTurn(
            userText: lastUser,
            tokenStream: sink.stream,
            modelFilename: filename,
          )
          .catchError((_) {}),
    );

    final resp = request.response;
    if (!stream) {
      final buf = StringBuffer();
      await for (final t in tokens) {
        buf.write(t);
        sink.add(t);
      }
      await sink.close();
      await _writeJson(resp, {
        'model': modelName,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'message': {'role': 'assistant', 'content': buf.toString()},
        'done': true,
        'done_reason': 'stop',
      });
      return;
    }

    resp.statusCode = HttpStatus.ok;
    resp.headers.contentType = ContentType.json;
    await for (final t in tokens) {
      sink.add(t);
      resp.write(
        '${jsonEncode({
          'model': modelName,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'message': {'role': 'assistant', 'content': t},
          'done': false,
        })}\n',
      );
      await resp.flush();
    }
    await sink.close();
    resp.write(
      '${jsonEncode({
        'model': modelName,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'message': {'role': 'assistant', 'content': ''},
        'done': true,
        'done_reason': 'stop',
      })}\n',
    );
    await resp.close();
  }

  Future<void> _handleChatCompletions(HttpRequest request) async {
    if (!hasLoadedModel) {
      await _writeError(
        request.response,
        HttpStatus.serviceUnavailable,
        'No model loaded. Load a model in Uncensored Local AI first.',
        type: 'invalid_request_error',
        code: 'model_not_loaded',
      );
      return;
    }

    if (isBusy) {
      await _writeError(
        request.response,
        HttpStatus.tooManyRequests,
        'Another generation is already in progress. Retry shortly.',
        type: 'server_error',
        code: 'busy',
      );
      return;
    }

    _noteAdmin(request, 'Astro ran a generation');
    final body = await _readJsonObject(request);
    final chatRequest = _parseChatCompletionRequest(body);
    // Ticket 26: remote (non-loopback) generations also materialize
    // in the chat UI. Loopback (the phone's own test buttons) stays
    // private to the API, same as ticket 24's narration rule.
    final materialize =
        !(request.connectionInfo?.remoteAddress.isLoopback ?? false);

    if (chatRequest.stream) {
      await _streamChatCompletion(
        request.response,
        chatRequest,
        materialize: materialize,
      );
      return;
    }

    await _writeJson(
      request.response,
      await _createChatCompletion(chatRequest, materialize: materialize),
    );
  }

  /// Ticket 26 bridge: feed a copy of the token stream into the chat
  /// so the run appears there live and persists in history.
  void _materializeInChat(
    _ChatCompletionRequest request,
    Stream<String> tokens,
  ) {
    try {
      final userText = request.messages
          .lastWhere(
            (m) => m.role == LlamaChatRole.user,
            orElse: () => request.messages.last,
          )
          .content;
      unawaited(
        Get.find<ChatController>()
            .runRemoteTurn(
              userText: userText,
              tokenStream: tokens,
              modelFilename:
                  Get.find<ModelController>().selectedModelFilename.value,
            )
            .catchError((_) {}),
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _createChatCompletion(
    _ChatCompletionRequest request, {
    required bool materialize,
  }) async {
    final created = _unixSeconds();
    final id = _completionId();
    final buffer = StringBuffer();

    StreamController<String>? chatSink;
    if (materialize) {
      chatSink = StreamController<String>();
      _materializeInChat(request, chatSink.stream);
    }

    try {
      await for (final token in _llm.generateChatCompletion(
        messages: request.messages,
        params: request.params,
      )) {
        buffer.write(token);
        chatSink?.add(token);
      }
    } finally {
      await chatSink?.close();
    }

    final content = buffer.toString().trim();
    final usage = await _usageJson(request.messages, content);
    // Honest finish_reason (UPDATE 3): 'length' when the completion
    // ran to the requested token cap, 'stop' otherwise - the old code
    // hardcoded 'stop' even for capped runs.
    final finishReason = usage['completion_tokens']! >= request.params.maxTokens
        ? 'length'
        : 'stop';

    return {
      'id': id,
      'object': 'chat.completion',
      'created': created,
      'model': modelId,
      'choices': [
        {
          'index': 0,
          'message': {'role': 'assistant', 'content': content},
          'finish_reason': finishReason,
        },
      ],
      'usage': usage,
    };
  }

  Future<void> _streamChatCompletion(
    HttpResponse response,
    _ChatCompletionRequest request, {
    required bool materialize,
  }) async {
    final created = _unixSeconds();
    final id = _completionId();

    StreamController<String>? chatSink;
    if (materialize) {
      chatSink = StreamController<String>();
      _materializeInChat(request, chatSink.stream);
    }

    response.statusCode = HttpStatus.ok;
    response.headers
      ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.connectionHeader, 'keep-alive');

    void writeEvent(Map<String, dynamic> payload) {
      response.write('data: ${jsonEncode(payload)}\n\n');
    }

    writeEvent(
      _streamChunk(id: id, created: created, delta: {'role': 'assistant'}),
    );

    final streamed = StringBuffer();
    try {
      await for (final token in _llm.generateChatCompletion(
        messages: request.messages,
        params: request.params,
      )) {
        if (token.isEmpty) continue;
        streamed.write(token);
        chatSink?.add(token);
        writeEvent(
          _streamChunk(id: id, created: created, delta: {'content': token}),
        );
      }

      final usage = await _usageJson(request.messages, streamed.toString());
      writeEvent(
        _streamChunk(
          id: id,
          created: created,
          delta: <String, dynamic>{},
          finishReason: usage['completion_tokens']! >= request.params.maxTokens
              ? 'length'
              : 'stop',
        ),
      );
      response.write('data: [DONE]\n\n');
    } catch (e) {
      writeEvent({
        'error': {
          'message': 'Model generation failed: $e',
          'type': 'server_error',
          'param': null,
          'code': 'generation_failed',
        },
      });
      response.write('data: [DONE]\n\n');
    } finally {
      await chatSink?.close();
      await response.close();
    }
  }

  Map<String, dynamic> _streamChunk({
    required String id,
    required int created,
    required Map<String, dynamic> delta,
    String? finishReason,
  }) {
    return {
      'id': id,
      'object': 'chat.completion.chunk',
      'created': created,
      'model': modelId,
      'choices': [
        {'index': 0, 'delta': delta, 'finish_reason': finishReason},
      ],
    };
  }

  _ChatCompletionRequest _parseChatCompletionRequest(
    Map<String, dynamic> body,
  ) {
    if (body['tools'] is List && (body['tools'] as List).isNotEmpty) {
      throw _OpenAiRequestException(
        'Tool calling is not supported by this local API server yet.',
        param: 'tools',
      );
    }

    final rawMessages = body['messages'];
    if (rawMessages is! List || rawMessages.isEmpty) {
      throw _OpenAiRequestException(
        '`messages` must be a non-empty array.',
        param: 'messages',
      );
    }

    final messages = rawMessages
        .map((raw) => _parseMessage(raw))
        .toList(growable: false);

    final maxTokens =
        _readInt(body['max_completion_tokens'], 'max_completion_tokens') ??
        _readInt(body['max_tokens'], 'max_tokens');

    var params = const GenerationParams(penalty: 1.0, topP: 0.95, minP: 0.05);

    if (maxTokens != null) {
      params = params.copyWith(maxTokens: maxTokens);
    }

    final temperature = _readDouble(body['temperature'], 'temperature');
    if (temperature != null) {
      params = params.copyWith(temp: temperature);
    }

    final topP = _readDouble(body['top_p'], 'top_p');
    if (topP != null) {
      params = params.copyWith(topP: topP);
    }

    final seed = _readInt(body['seed'], 'seed');
    if (seed != null) {
      params = params.copyWith(seed: seed);
    }

    final stops = _parseStop(body['stop']);
    if (stops.isNotEmpty) {
      params = params.copyWith(stopSequences: stops);
    }

    return _ChatCompletionRequest(
      messages: messages,
      params: params,
      stream: _readBool(body['stream'], 'stream') ?? false,
    );
  }

  LlamaChatMessage _parseMessage(Object? raw) {
    if (raw is! Map) {
      throw _OpenAiRequestException('Each message must be an object.');
    }

    final roleRaw = raw['role'];
    final contentRaw = raw['content'];
    if (roleRaw is! String || roleRaw.trim().isEmpty) {
      throw _OpenAiRequestException(
        'Message role must be a non-empty string.',
        param: 'messages.role',
      );
    }

    final role = switch (roleRaw) {
      'developer' || 'system' => LlamaChatRole.system,
      'user' => LlamaChatRole.user,
      'assistant' => LlamaChatRole.assistant,
      'tool' => LlamaChatRole.tool,
      _ => throw _OpenAiRequestException(
        'Unsupported message role `$roleRaw`.',
        param: 'messages.role',
      ),
    };

    final content = _parseMessageContent(contentRaw);
    return LlamaChatMessage.fromText(role: role, text: content);
  }

  String _parseMessageContent(Object? raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is List) {
      final buffer = StringBuffer();
      for (final part in raw) {
        if (part is! Map) {
          throw _OpenAiRequestException(
            'Message content parts must be objects.',
          );
        }
        final type = part['type'];
        if (type == 'text' && part['text'] is String) {
          buffer.write(part['text'] as String);
        } else {
          throw _OpenAiRequestException(
            'Only text message content is supported by this local API server.',
            param: 'messages.content',
          );
        }
      }
      return buffer.toString();
    }
    throw _OpenAiRequestException(
      'Message content must be a string or text content parts.',
      param: 'messages.content',
    );
  }

  List<String> _parseStop(Object? raw) {
    if (raw == null) return const [];
    if (raw is String) return [raw];
    if (raw is List && raw.every((item) => item is String)) {
      return raw.cast<String>();
    }
    throw _OpenAiRequestException(
      '`stop` must be a string or an array of strings.',
      param: 'stop',
    );
  }

  int? _readInt(Object? raw, String param) {
    if (raw == null) return null;
    if (raw is int) return raw;
    throw _OpenAiRequestException('`$param` must be an integer.', param: param);
  }

  double? _readDouble(Object? raw, String param) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    throw _OpenAiRequestException('`$param` must be a number.', param: param);
  }

  bool? _readBool(Object? raw, String param) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    throw _OpenAiRequestException('`$param` must be a boolean.', param: param);
  }

  Future<Map<String, dynamic>> _readJsonObject(HttpRequest request) async {
    try {
      final raw = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw _OpenAiRequestException('Request body must be valid JSON.');
    }
    throw _OpenAiRequestException('Request body must be a JSON object.');
  }

  Future<Map<String, int>> _usageJson(
    List<LlamaChatMessage> messages,
    String completion,
  ) async {
    // UPDATE 3 (B3): prompt tokens are counted on the RENDERED chat
    // template, never on 'role: content' lines - the old count was
    // not the prefill the engine actually ran.
    final promptTokens = await _llm.countPromptTokens(messages);
    final completionTokens = await _llm.countTokens(completion);
    return {
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': promptTokens + completionTokens,
    };
  }

  Future<void> _writeJson(
    HttpResponse response,
    Map<String, dynamic> body, {
    int statusCode = HttpStatus.ok,
  }) async {
    response.headers.contentType ??= ContentType.json;
    response.statusCode = statusCode;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _writeError(
    HttpResponse response,
    int statusCode,
    String message, {
    String type = 'invalid_request_error',
    String? code,
    String? param,
  }) {
    return _writeJson(response, {
      'error': {'message': message, 'type': type, 'param': param, 'code': code},
    }, statusCode: statusCode);
  }

  // ── Astro Remote Control (ticket 21) ───────────────────────
  // Token-gated admin surface on the same server. The app only ever
  // LISTENS (offline law); every /admin route requires the per-install
  // token, on loopback too. The token is generated on first use and
  // shown in the API screen; regenerating invalidates the old one.

  static const appVersion = '1.16.1';

  String get adminToken {
    var token = _storage.adminToken;
    if (token.isEmpty) {
      token = _generateAdminToken();
      _storage.adminToken = token;
    }
    return token;
  }

  String regenerateAdminToken() {
    final token = _generateAdminToken();
    _storage.adminToken = token;
    // Ticket 24: a new token ends the narrated session too.
    try {
      Get.find<AdminActivityService>().endSession();
    } catch (_) {}
    return token;
  }

  String _generateAdminToken() {
    final rng = Random.secure();
    return List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
  }

  bool _adminAuthorized(HttpRequest request) {
    final expected = adminToken;
    final header = request.headers.value('x-admin-token');
    if (header != null && header == expected) return true;
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    if (auth != null && auth == 'Bearer $expected') return true;
    return false;
  }

  // ── See-Astro-drive narration (ticket 24) ──────────────────
  // Every admin action is narrated on screen — reads included, no
  // silent reads. Only remote (non-loopback) callers count: the
  // phone's own test buttons use loopback and never narrate.
  void _noteAdmin(HttpRequest request, String label) {
    try {
      if (request.connectionInfo?.remoteAddress.isLoopback ?? false) return;
      Get.find<AdminActivityService>().note(label);
    } catch (_) {}
  }

  void _touchAdmin(HttpRequest request) {
    try {
      if (request.connectionInfo?.remoteAddress.isLoopback ?? false) return;
      Get.find<AdminActivityService>().touchSession();
    } catch (_) {}
  }

  Future<void> _handleAdmin(HttpRequest request, String path) async {
    if (!_adminAuthorized(request)) {
      await _writeError(
        request.response,
        HttpStatus.unauthorized,
        'Missing or invalid admin token.',
        type: 'authentication_error',
        code: 'invalid_admin_token',
      );
      return;
    }
    final method = request.method;
    if (method == 'GET' && path == '/admin/status') {
      _noteAdmin(request, 'Astro checked status');
      await _writeJson(request.response, await _adminStatus());
      return;
    }
    if (method == 'GET' && path == '/admin/logs') {
      _noteAdmin(request, 'Astro pulled logs');
      await _writeJson(request.response, await _adminLogs(request));
      return;
    }
    if (method == 'GET' && path == '/admin/models') {
      _noteAdmin(request, 'Astro listed models');
      await _writeJson(request.response, await _adminModels());
      return;
    }
    if (method == 'GET' && path == '/admin/telemetry') {
      _noteAdmin(request, 'Astro pulled telemetry');
      await _writeJson(request.response, _adminTelemetry(request));
      return;
    }
    if (method == 'POST' && path == '/admin/load') {
      _touchAdmin(request);
      await _adminLoad(request);
      return;
    }
    if (method == 'POST' && path == '/admin/unload') {
      _noteAdmin(request, 'Astro unloaded the model');
      await Get.find<ModelController>().unloadModel();
      await _writeJson(request.response, await _adminStatus());
      return;
    }
    if (method == 'GET' && path == '/admin/settings') {
      _noteAdmin(request, 'Astro read settings');
      await _writeJson(request.response, _adminSettings());
      return;
    }
    if (method == 'PUT' && path == '/admin/settings') {
      await _adminUpdateSettings(request);
      return;
    }
    await _writeError(
      request.response,
      HttpStatus.notFound,
      'No admin route for `$method $path`.',
      type: 'invalid_request_error',
      code: 'not_found',
    );
  }

  Future<Map<String, dynamic>> _adminStatus() async {
    final headroom = await MemoryProbe.availableBytes();
    String? loadedFile;
    final path = _llm.loadedModelPath.value;
    if (path.isNotEmpty) {
      loadedFile = path.split('/').last;
    }
    String lastError = '';
    try {
      lastError = Get.find<LogService>().lastError.value;
    } catch (_) {}
    return {
      'app': 'Astro MiniX',
      'version': appVersion,
      'server': 'running',
      'loaded': _llm.isLoaded.value,
      'model': loadedFile,
      'generating': _llm.isGenerating.value,
      'loading': _llm.isLoadingModel.value,
      'headroomBytes': headroom,
      'lastMeter': _llm.lastMeterSummary.value,
      'lastError': lastError,
      'settings': _adminSettings(),
    };
  }

  Map<String, dynamic> _adminSettings() {
    return {
      'backend': _storage.backendType,
      'threads': _storage.threadCount,
      'contextSize': _storage.contextSize,
      'gpuLayers': _storage.gpuLayers,
    };
  }

  Future<Map<String, dynamic>> _adminLogs(HttpRequest request) async {
    var tail = 200;
    final raw = request.uri.queryParameters['tail'];
    if (raw != null) {
      tail = (int.tryParse(raw) ?? 200).clamp(1, 1000);
    }
    List<String> lines = [];
    try {
      final logService = Get.find<LogService>();
      final filePath = logService.logFilePath;
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          lines = await file.readAsLines();
        }
      }
      if (lines.isEmpty) {
        lines = logService.logs.map((e) => e.formatted).toList();
      }
    } catch (_) {}
    final start = lines.length > tail ? lines.length - tail : 0;
    return {'count': lines.length, 'tail': tail, 'lines': lines.sublist(start)};
  }

  Future<Map<String, dynamic>> _adminModels() async {
    final ctrl = Get.find<ModelController>();
    final loadedPath = _llm.loadedModelPath.value;
    final models = <Map<String, dynamic>>[];
    for (final filename in ctrl.downloadedModels) {
      int? size;
      try {
        final f = File(ctrl.modelPathFor(filename));
        if (await f.exists()) size = await f.length();
      } catch (_) {}
      models.add({
        'filename': filename,
        'sizeBytes': size,
        'loaded': loadedPath.endsWith(filename),
      });
    }
    return {'models': models};
  }

  Future<void> _adminLoad(HttpRequest request) async {
    final body = await _readJsonObject(request);
    final filename = body['filename'];
    if (filename is! String || filename.isEmpty) {
      await _writeError(
        request.response,
        HttpStatus.badRequest,
        '`filename` (a downloaded model file name) is required.',
        param: 'filename',
      );
      return;
    }
    final ctrl = Get.find<ModelController>();
    if (!ctrl.downloadedModels.contains(filename)) {
      await _writeError(
        request.response,
        HttpStatus.notFound,
        'No downloaded model named `$filename`.',
        code: 'model_not_found',
      );
      return;
    }
    final error = await ctrl.loadModelRemote(filename);
    final short = filename.endsWith('.gguf')
        ? filename.substring(0, filename.length - 5)
        : filename;
    if (error != null) {
      _noteAdmin(request, 'Astro tried to load $short - it failed');
      await _writeError(
        request.response,
        HttpStatus.internalServerError,
        'Load failed: $error',
        type: 'server_error',
        code: 'load_failed',
      );
      return;
    }
    _noteAdmin(request, 'Astro loaded $short');
    await _writeJson(request.response, await _adminStatus());
  }

  Future<void> _adminUpdateSettings(HttpRequest request) async {
    final body = await _readJsonObject(request);
    const backends = ['auto', 'metal', 'cpu', 'vulkan', 'opencl'];
    final applied = <String, dynamic>{};
    if (body.containsKey('backend')) {
      final v = body['backend'];
      if (v is! String || !backends.contains(v)) {
        await _writeError(
          request.response,
          HttpStatus.badRequest,
          '`backend` must be one of $backends.',
          param: 'backend',
        );
        return;
      }
      _storage.backendType = v;
      applied['backend'] = v;
    }
    if (body.containsKey('threads')) {
      final v = body['threads'];
      if (v is! int || v < 0 || v > 16) {
        await _writeError(
          request.response,
          HttpStatus.badRequest,
          '`threads` must be an int 0..16 (0 = auto).',
          param: 'threads',
        );
        return;
      }
      _storage.threadCount = v;
      applied['threads'] = v;
    }
    if (body.containsKey('contextSize')) {
      final v = body['contextSize'];
      const sizes = [0, 512, 1024, 2048, 4096, 8192, 16384];
      if (v is! int || !sizes.contains(v)) {
        await _writeError(
          request.response,
          HttpStatus.badRequest,
          '`contextSize` must be one of $sizes (0 = default).',
          param: 'contextSize',
        );
        return;
      }
      _storage.contextSize = v;
      applied['contextSize'] = v;
    }
    if (body.containsKey('gpuLayers')) {
      final v = body['gpuLayers'];
      if (v is! int || v < 0 || v > 999) {
        await _writeError(
          request.response,
          HttpStatus.badRequest,
          '`gpuLayers` must be an int 0..999.',
          param: 'gpuLayers',
        );
        return;
      }
      _storage.gpuLayers = v;
      applied['gpuLayers'] = v;
    }
    if (applied.isNotEmpty) {
      _noteAdmin(
        request,
        'Astro changed settings: '
        '${applied.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
      );
    }
    await _writeJson(request.response, {
      'applied': applied,
      'note': 'Knobs apply on the next model load.',
      'settings': _adminSettings(),
    });
  }

  /// Ticket 22: the telemetry series (same admin auth as every
  /// /admin route). Served from the sampler's ring buffer.
  Map<String, dynamic> _adminTelemetry(HttpRequest request) {
    var tail = 300;
    final raw = request.uri.queryParameters['tail'];
    if (raw != null) {
      tail = (int.tryParse(raw) ?? 300).clamp(1, 900);
    }
    try {
      final svc = Get.find<TelemetryService>();
      return {
        'count': svc.samples.length,
        'tail': tail,
        'samples': svc.tailJson(tail),
      };
    } catch (_) {
      return {'count': 0, 'tail': tail, 'samples': <Map<String, dynamic>>[]};
    }
  }

  void _applyCorsHeaders(HttpResponse response) {
    response.headers
      ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
      ..set(
        HttpHeaders.accessControlAllowMethodsHeader,
        'GET, POST, PUT, OPTIONS',
      )
      ..set(
        HttpHeaders.accessControlAllowHeadersHeader,
        'authorization, content-type, x-admin-token',
      );
  }

  int _unixSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  String _completionId() => 'chatcmpl-${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<void> onClose() async {
    await stop();
    super.onClose();
  }
}

class _ChatCompletionRequest {
  final List<LlamaChatMessage> messages;
  final GenerationParams params;
  final bool stream;

  const _ChatCompletionRequest({
    required this.messages,
    required this.params,
    required this.stream,
  });
}

class _OpenAiRequestException implements Exception {
  final String message;
  final String? param;

  const _OpenAiRequestException(this.message, {this.param});
}
