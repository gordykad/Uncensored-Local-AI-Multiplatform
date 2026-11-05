import 'dart:async';
import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';

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

  /// Delete EVERY chat - storage first, then memory. (The Settings
  /// Danger Zone button used to clear the in-memory list only, so
  /// every chat resurrected from Hive on the next launch. Kai caught
  /// it 2026-11-04: "clear chat doesn't clear chat.")
  Future<void> deleteAllChats() async {
    await _storage.deleteAllChats();
    chats.clear();
    activeChatId.value = null;
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
    // Ticket 04 (B3): history rides the engine's own chat template -
    // a LlamaChatMessage list into generateChatCompletion. The retired
    // hand-rolled Phi-3 prompt was the prime suspect for both the
    // <|channel> leak and Shaun's tail-repetition loops. Sampler per
    // the execution map: temperature from the chat knob, penalty
    // pinned NEUTRAL at 1.0 (the penalty A/B is measured AFTER the
    // template fix, never tuned to hide a template bug), topP 0.95,
    // minP 0.05 - the same set the local API ships.
    final effectiveSystem = chat.systemPrompt.isNotEmpty
        ? chat.systemPrompt
        : systemPrompt.value;
    final messages = <LlamaChatMessage>[
      if (effectiveSystem.isNotEmpty)
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: effectiveSystem,
        ),
      for (final m in chat.messages.where((m) => !m.isSystem))
        LlamaChatMessage.fromText(
          role: switch (m.role) {
            MessageRole.user => LlamaChatRole.user,
            MessageRole.assistant => LlamaChatRole.assistant,
            MessageRole.system => LlamaChatRole.system,
          },
          text: m.content,
        ),
    ];

    // Start generation
    isGenerating.value = true;
    isRegenerating.value = regenerating;
    streamedResponse.value = '';

    final aiMsg = MessageModel(role: MessageRole.assistant, content: '');
    chat.messages.add(aiMsg);
    chats.refresh();

    final stream = _llm.generateChatCompletion(
      messages: messages,
      params: GenerationParams(
        temp: temperature.value,
        penalty: 1.0,
        topP: 0.95,
        minP: 0.05,
      ),
      backstop: true,
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
            r'|<\|pad\|>|</s>|<s>|\[INST\]|\[/INST\]|\[end\]|<\|channel\|>|<channel\|>'
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
