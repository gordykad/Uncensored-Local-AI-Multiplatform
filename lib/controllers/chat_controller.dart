import 'dart:async';
import 'package:get/get.dart';

import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../services/llm_service.dart';
import '../services/chat_storage_service.dart';

class ChatController extends GetxController {
  final LlmService _llm = Get.find<LlmService>();
  final ChatStorageService _storage = Get.find<ChatStorageService>();

  final chats = <ChatModel>[].obs;
  final activeChatId = RxnString();
  final isGenerating = false.obs;
  final isRegenerating = false.obs; // ticket 08: drives the #2 reply style
  final streamedResponse = ''.obs;
  final temperature = 0.7.obs;
  final systemPrompt = ''.obs;

  StreamSubscription<String>? _genSub;

  @override
  void onInit() {
    super.onInit();
    _loadChats();
    temperature.value = _storage.defaultTemperature;
    systemPrompt.value = _storage.globalSystemPrompt;
  }

  void _loadChats() {
    chats.value = _storage.getAllChats();
  }

  ChatModel? get activeChat {
    if (activeChatId.value == null) return null;
    try {
      return chats.firstWhere((c) => c.id == activeChatId.value);
    } catch (_) {
      return null;
    }
  }

  /// Create a new chat and switch to it.
  void newChat() {
    final chat = ChatModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      systemPrompt: systemPrompt.value,
    );
    chats.insert(0, chat);
    _storage.saveChat(chat);
    activeChatId.value = chat.id;
  }

  /// Switch to an existing chat.
  void switchChat(String id) {
    activeChatId.value = id;
    final chat = activeChat;
    if (chat != null) {
      systemPrompt.value = chat.systemPrompt;
    }
  }

  /// Delete a chat.
  void deleteChat(String id) {
    chats.removeWhere((c) => c.id == id);
    _storage.deleteChat(id);
    if (activeChatId.value == id) {
      activeChatId.value = chats.isNotEmpty ? chats.first.id : null;
    }
  }

  /// Send a user message and stream AI response.
  Future<void> sendMessage(String text, {String? modelFilename}) async {
    if (text.trim().isEmpty) return;
    final chat = activeChat;
    if (chat == null) return;

    // Add user message
    final userMsg = MessageModel(role: MessageRole.user, content: text.trim());
    chat.messages.add(userMsg);
    chat.autoTitle();
    chat.updatedAt = DateTime.now();

    // Lock model to this chat on first message
    if (chat.modelId.isEmpty && modelFilename != null) {
      chat.modelId = modelFilename;
    }

    _storage.saveChat(chat);
    chats.refresh();

    // Build message history for LLM
    final history = chat.messages
        .where((m) => !m.isSystem)
        .map((m) => m.toLlamaMessage())
        .toList();

    await _runGeneration(chat, regenerating: false);
  }

  /// Regenerate the last assistant reply (ticket 08 — completes the
  /// Stream Reply anatomy: stop/regenerate; the regenerated run renders
  /// in the #2 progressive style via [isRegenerating]).
  Future<void> regenerateLast() async {
    if (isGenerating.value) return;
    final chat = activeChat;
    if (chat == null || chat.messages.isEmpty) return;
    if (!chat.messages.last.isAssistant) return;
    chat.messages.removeLast();
    chats.refresh();
    await _runGeneration(chat, regenerating: true);
  }

  Future<void> _runGeneration(ChatModel chat,
      {required bool regenerating}) async {
    // Build message history for LLM (system messages excluded)
    final history = chat.messages
        .where((m) => !m.isSystem)
        .map((m) => m.toLlamaMessage())
        .toList();

    // Start generation
    isGenerating.value = true;
    isRegenerating.value = regenerating;
    streamedResponse.value = '';

    final aiMsg = MessageModel(role: MessageRole.assistant, content: '');
    chat.messages.add(aiMsg);
    chats.refresh();

    final stream = _llm.generate(
      messages: history,
      systemPrompt: chat.systemPrompt.isNotEmpty
          ? chat.systemPrompt
          : systemPrompt.value,
      temperature: temperature.value,
    );
    await _consumeStream(chat, aiMsg, stream);
  }

  /// Ticket 26: a remote (API) generation materializes in the chat.
  /// The final user message lands as a user bubble and the reply
  /// streams live into an assistant bubble through the same rendering
  /// and persistence as a local generation. The caller's HTTP response
  /// is unaffected; the engine's busy rules already govern both doors.
  Future<void> runRemoteTurn({
    required String userText,
    required Stream<String> tokenStream,
    String? modelFilename,
  }) async {
    if (isGenerating.value) return;
    if (activeChat == null) newChat();
    final chat = activeChat;
    if (chat == null) return;

    final userMsg = MessageModel(role: MessageRole.user, content: userText);
    chat.messages.add(userMsg);
    chat.autoTitle();
    chat.updatedAt = DateTime.now();
    if (chat.modelId.isEmpty && modelFilename != null) {
      chat.modelId = modelFilename;
    }
    _storage.saveChat(chat);
    chats.refresh();

    isGenerating.value = true;
    isRegenerating.value = false;
    streamedResponse.value = '';

    final aiMsg = MessageModel(role: MessageRole.assistant, content: '');
    chat.messages.add(aiMsg);
    chats.refresh();

    await _consumeStream(chat, aiMsg, tokenStream);
  }

  /// Shared stream consumption for local and remote generations:
  /// appends tokens to [aiMsg], then applies the standard cleanup,
  /// flag reset, and persistence in the finally block.
  Future<void> _consumeStream(
    ChatModel chat,
    MessageModel aiMsg,
    Stream<String> stream,
  ) async {
    try {
      await for (final token in stream) {
        streamedResponse.value += token;
        aiMsg.content = streamedResponse.value;
        // Throttle UI refreshes
        chats.refresh();
      }
    } catch (e) {
      if (aiMsg.content.isEmpty) {
        aiMsg.content = '⚠ Error: ${e.toString()}';
      }
    } finally {
      // Clean up any trailing stop tokens or whitespace
      aiMsg.content = aiMsg.content
          .replaceAll(RegExp(
            r'<\|end\|>|<\|eot_id\|>|<\|endoftext\|>|<\|im_end\|>|<\|im_start\|>'
            r'|<end_of_turn>|<start_of_turn>|<\|assistant\|>|<\|user\|>|<\|system\|>'
            r'|<\|pad\|>|</s>|<s>|\[INST\]|\[/INST\]|\[end\]'
          ), '')
          .trim();
      isGenerating.value = false;
      isRegenerating.value = false;
      streamedResponse.value = '';
      chat.updatedAt = DateTime.now();
      _storage.saveChat(chat);
      chats.refresh();
    }
  }

  /// Stop current generation.
  void stopGeneration() {
    _llm.stopGeneration();
    isGenerating.value = false;
  }

  /// Update the system prompt for the active chat.
  void updateSystemPrompt(String prompt) {
    systemPrompt.value = prompt;
    final chat = activeChat;
    if (chat != null) {
      chat.systemPrompt = prompt;
      _storage.saveChat(chat);
    }
  }

  /// Set and persist the global system prompt.
  void setGlobalSystemPrompt(String prompt) {
    systemPrompt.value = prompt;
    _storage.globalSystemPrompt = prompt;
  }

  /// Clear global system prompt.
  void clearGlobalSystemPrompt() {
    systemPrompt.value = '';
    _storage.globalSystemPrompt = '';
  }

  void updateTemperature(double temp) {
    temperature.value = temp;
    _storage.defaultTemperature = temp;
  }

  @override
  void onClose() {
    _genSub?.cancel();
    super.onClose();
  }
}
