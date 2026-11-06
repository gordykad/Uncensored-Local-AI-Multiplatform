import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../controllers/chat_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/theme_controller.dart';
import '../services/llm_service.dart';
import '../services/image_gen_service.dart';
import '../services/mesh_service.dart';
import '../services/haptics.dart';
import '../services/phone_node.dart';
import '../theme/type_scale.dart';
import '../services/custom_connections_service.dart';
import '../services/admin_activity_service.dart';
import '../services/log_service.dart';
import '../widgets/chat_sidebar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/faithful/orb.dart';
import '../widgets/faithful/kinetic.dart';
import '../widgets/faithful/morph_orb.dart';
import '../widgets/faithful/textfx.dart';
import '../widgets/faithful/stream.dart';
import '../widgets/faithful/nexus_velocity.dart';
import '../widgets/faithful/widgets.dart';
import '../widgets/faithful/trace_pickers.dart';
import '../widgets/faithful/shared.dart';
import 'model_library_screen.dart';
import 'image_gen_screen.dart';
import '../widgets/dock_nav.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _chatCtrl = Get.find<ChatController>();
  final _modelCtrl = Get.find<ModelController>();
  final _llm = Get.find<LlmService>();
  final _themeCtrl = Get.find<ThemeController>();
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sidebarOpen = true;
  bool _loggedBuild = false; // build 18 diagnostics
  String? _dissolvingText; // ticket 08: Nexus send disintegration
  int _stopCount = 0; // 1.13.0: MorphOrb reads stop taps (no check ball)
  final _composerSlotKey = GlobalKey(); // MorphOrb pill home rect
  bool _autoScrollToBottom = true;
  String? _lastRenderedChatId;

  // Mobile bottom nav index: 0=Chat, 1=Models, 2=Image Gen, 3=Settings
  int _mobileTabIndex = 0;

  // Scaffold key for drawer
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();

  bool _wasGenerating = false;

  @override
  void initState() {
    super.initState();
    _msgController.addListener(() {
      if (mounted) setState(() {});
    });
    _scrollController.addListener(_handleChatScroll);
    // Audit #1: a run ending gets its haptic — soft when it landed,
    // heavy when it errored. Causal only, like the rest of the map.
    _chatCtrl.isGenerating.listen((gen) {
      if (_wasGenerating && !gen) {
        final msgs = _chatCtrl.activeChat?.messages;
        final last = msgs == null || msgs.isEmpty ? null : msgs.last;
        if (last != null && !last.isUser && last.failed) {
          TapFx.error();
        } else {
          TapFx.done();
        }
      }
      _wasGenerating = gen;
    });
    // T-05: re-arm phone-node presence across relaunches.
    if (MeshService().phoneNodeOn && ImageGenService().connectivityOn) {
      setPhoneNode(true).catchError((_) => false);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleChatScroll);
    _scrollController.dispose();
    _msgController.dispose();
    super.dispose();
  }

  void _handleChatScroll() {
    if (!_scrollController.hasClients) return;
    _autoScrollToBottom = _isNearBottom();
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= 120;
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_autoScrollToBottom) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (!force && !_autoScrollToBottom) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Claude C1 (B3): send is only live when something can answer -
  /// a loaded local model or a selected mesh seat - and the composer
  /// holds text. Anything else renders the button dim and inert.
  bool get _canSend {
    final remoteOn =
        _modelCtrl.selectedRemote.value != null &&
        ImageGenService().connectivityOn;
    return (_llm.isLoaded.value || remoteOn) &&
        _msgController.text.trim().isNotEmpty;
  }

  void _send() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    TapFx.send();

    if (_chatCtrl.activeChat == null) {
      _chatCtrl.newChat();
    }

    _msgController.clear();
    setState(() => _dissolvingText = text);
    _autoScrollToBottom = true;
    // Ticket 31: a selected remote source (a mesh seat or one of Kai's
    // custom connections) answers instead of the local model, through
    // the ticket 26 remote-turn seam.
    final remote = _modelCtrl.selectedRemote.value;
    if (remote != null && ImageGenService().connectivityOn) {
      final chat = _chatCtrl.activeChat!;
      final msgs = <Map<String, String>>[
        if (chat.systemPrompt.isNotEmpty)
          {'role': 'system', 'content': chat.systemPrompt},
        ...chat.messages
            .where((m) => !m.isSystem)
            .map((m) => m.toLlamaMessage()),
        {'role': 'user', 'content': text},
      ];
      Stream<String>? stream;
      if (remote['kind'] == 'custom') {
        final matches = CustomConnectionsService()
            .list()
            .where((c) => c.id == remote['id'])
            .toList();
        if (matches.isEmpty) {
          _modelCtrl.clearRemote();
        } else {
          stream = CustomConnectionsService().streamChat(
            conn: matches.first,
            messages: msgs,
          );
        }
      } else {
        final model = remote['model'] as String;
        stream = _watchedSeatStream(
          MeshService().streamChat(model: model, messages: msgs),
          model,
        );
      }
      if (stream != null) {
        _chatCtrl.runRemoteTurn(
          userText: text,
          tokenStream: stream,
          modelFilename: remote['label'] as String?,
        );
        _scrollToBottom(force: true);
        return;
      }
    }
    _chatCtrl.sendMessage(
      text,
      modelFilename: _modelCtrl.selectedModelFilename.value,
    );
    _scrollToBottom(force: true);
  }

  /// Kai (1.14.1): a seat that answers a chat earns verified on
  /// its own — no more long-press Mark verified per seat. The flip
  /// fires only when the stream completes cleanly with real
  /// content; errors and Stop leave the seat unverified. Node
  /// models are not in the seat catalog, so they no-op here. A
  /// "Dead Rn" seat that answers also sheds its tag — it came back.
  Stream<String> _watchedSeatStream(Stream<String> src, String model) async* {
    var answered = false;
    await for (final chunk in src) {
      if (chunk.trim().isNotEmpty) answered = true;
      yield chunk;
    }
    if (!answered) return;
    final mesh = MeshService();
    final seat = mesh.cachedSeats().where((s) => s.model == model).firstOrNull;
    if (seat == null) return;
    if (!seat.isVerified) mesh.setModelVerified(model, true);
    if (seat.dead) mesh.setModelDead(model, false);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 768;
    if (!_loggedBuild) {
      _loggedBuild = true;
      try {
        Get.find<LogService>().info(
          'Home build: w=${MediaQuery.of(context).size.width} h=${MediaQuery.of(context).size.height} desktop=$isDesktop',
          source: 'UI',
        );
      } catch (_) {}
    }

    // Keyboard fix (Kai, 2026-11-03): a tap anywhere outside a text
    // field drops the keyboard. The IndexedStack tabs keep the chat
    // field alive, so without this the keyboard could never be
    // dismissed after switching tabs.
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Stack(
        children: [
          if (isDesktop) _buildDesktopLayout() else _buildMobileLayout(),
          // ── Global model loading overlay ──
          _buildLoadingOverlay(),
          // ── See-Astro-drive toasts (ticket 24) ──
          const _AdminToastOverlay(),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Obx(() {
      if (!_modelCtrl.isImportingModel.value) return const SizedBox.shrink();

      final progress = _modelCtrl.loadingProgress.value;
      final percent = (progress * 100).clamp(0, 100).toInt();
      final msg = _modelCtrl.loadingStatusMsg.value;
      final filename = _modelCtrl.loadingModelFilename.value ?? 'Model';

      // Derive a short display name from the filename
      final displayName = filename.endsWith('.gguf')
          ? filename.substring(0, filename.length - 5)
          : filename;

      return Material(
        color: Colors.transparent,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: context.bgPanel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Circular progress
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            value: progress <= 0
                                ? null
                                : progress.clamp(0.0, 1.0),
                            strokeWidth: 5,
                            backgroundColor: context.border,
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.accent,
                            ),
                          ),
                        ),
                        if (percent > 0)
                          Text(
                            '$percent%',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: context.text,
                            ),
                          ),
                        if (percent <= 0)
                          Icon(
                            Icons.hourglass_empty_rounded,
                            size: 24,
                            color: context.textD,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Model name
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.text,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Status message — #14 scramble-resolves on change
                  ScrambleText(
                    text: msg.isNotEmpty ? msg : 'Importing file...',
                    style: TextStyle(fontSize: 12, color: context.textM),
                  ),
                  const SizedBox(height: 12),

                  // Hint for large models
                  if (progress == 0)
                    Text(
                      'Large models (5GB+) take about 30-50 seconds for the phone to process. Please wait.',
                      style: TextStyle(
                        fontSize: 10,
                        color: context.textD,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 20),

                  // Cancel button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _modelCtrl.cancelImport(),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        side: BorderSide(
                          color: AppColors.red.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // MOBILE LAYOUT — Bottom nav with 3 tabs + drawer for chat history
  // ═══════════════════════════════════════════════════════════════
  Widget _buildMobileLayout() {
    return Scaffold(
      key: _mobileScaffoldKey,
      backgroundColor: context.bg,
      resizeToAvoidBottomInset: true,
      // ── Left drawer for chat history ──
      drawer: Drawer(
        backgroundColor: context.bg,
        child: SafeArea(
          child: Column(
            children: [
              // Drawer header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.border, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      // UI audit 2026-11-06 P2-2: the drawer mark is
                      // identity chrome, not an action; the decorative
                      // gradient retires (house law rules it out).
                      decoration: BoxDecoration(
                        color: context.bgInput,
                        border: Border.all(color: context.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        AppIcons.zap,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Chat History',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.text,
                      ),
                    ),
                    const Spacer(),
                    // New chat button in drawer header
                    IconButton(
                      icon: Icon(
                        Icons.edit_square,
                        size: 20,
                        color: context.textM,
                      ),
                      onPressed: () {
                        _chatCtrl.newChat();
                        Navigator.pop(context); // close drawer
                      },
                      tooltip: 'New Chat',
                    ),
                  ],
                ),
              ),
              // Chat list
              Expanded(
                child: ChatSidebar(
                  onNewChat: () {
                    _chatCtrl.newChat();
                    Navigator.pop(context);
                  },
                  onSelectChat: (id) {
                    _chatCtrl.switchChat(id);
                    Navigator.pop(context);
                  },
                  onDeleteChat: (id) => _chatCtrl.deleteChat(id),
                  showNewChatButton: false,
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false, // let the bottom nav handle the safe area
        child: IndexedStack(
          index: _mobileTabIndex,
          children: [
            // UI audit 2026-11-06 P2-7: hidden tabs stop ticking.
            // IndexedStack keeps every tab mounted; without this,
            // Image Gen's beam and sparkle loops ran forever in the
            // background (battery + Reduce Motion violations).
            TickerMode(
              enabled: _mobileTabIndex == 0,
              child: _buildMobileChatTab(),
            ),
            TickerMode(
              enabled: _mobileTabIndex == 1,
              child: const ModelLibraryScreen(embedded: true),
            ),
            TickerMode(
              enabled: _mobileTabIndex == 2,
              child: const ImageGenScreen(embedded: true),
            ),
            TickerMode(
              enabled: _mobileTabIndex == 3,
              child: const SettingsScreen(embedded: true),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        color: context.bg,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DockNav(
                  selectedIndex: _mobileTabIndex,
                  onSelect: (i) {
                    TapFx.select();
                    // Keyboard fix: switching tabs always drops the keyboard.
                    FocusManager.instance.primaryFocus?.unfocus();
                    try {
                      Get.find<LogService>().info(
                        'Tab selected: $i',
                        source: 'UI',
                      );
                    } catch (_) {}
                    setState(() => _mobileTabIndex = i);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileChatTab() {
    return Column(
      children: [
        // Mobile top bar — minimal with SafeArea for status bar
        SafeArea(bottom: false, child: _buildMobileTopBar()),
        // Model loading progress banner
        Obx(() {
          if (!_modelCtrl.isLoadingModel.value) return const SizedBox.shrink();
          final progress = _modelCtrl.loadingProgress.value;
          final percent = (progress * 100).clamp(0, 100).toInt();
          final msg = _modelCtrl.loadingStatusMsg.value;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.orange.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // #19 AiLoader ring = the load-flow visual
                    const AiLoader(text: '', size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ScrambleText(
                        text: msg.isNotEmpty ? msg : 'Loading model...',
                        style: TextStyle(fontSize: 12, color: context.text),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$percent%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: context.border,
                    valueColor: const AlwaysStoppedAnimation(AppColors.orange),
                  ),
                ),
              ],
            ),
          );
        }),
        // Chat area
        Expanded(child: _buildChatArea()),
      ],
    );
  }

  /// 1.13.0: the generation stop button for both top bars. The
  /// MorphOrb pill becomes the orb during a run (exactly as the
  /// artifact), so stop lives up here instead (Kai's call).
  Widget _stopChip() {
    return Obx(() {
      if (!_chatCtrl.isGenerating.value) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        // UI audit 2026-11-06: 44pt hit area (chip stays 36 tall), a
        // VoiceOver identity, and the deeper red fill (white text on
        // AppColors.red measures only 3.35:1).
        child: Semantics(
          button: true,
          label: 'Stop generation',
          child: InkWell(
            onTap: () {
              TapFx.stop();
              setState(() => _stopCount++);
              _chatCtrl.stopGeneration();
            },
            borderRadius: BorderRadius.circular(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                widthFactor: 1,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.redDeep,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'Stop',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildMobileTopBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: context.bg,
        border: Border(bottom: BorderSide(color: context.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Sidebar / history button — opens drawer from left
          IconButton(
            icon: Icon(Icons.menu_rounded, size: 22, color: context.textM),
            onPressed: () => _mobileScaffoldKey.currentState?.openDrawer(),
            tooltip: 'Chat History',
          ),

          // Model selector dropdown
          Expanded(
            child: Center(
              child: Obx(() {
                final fname = _modelCtrl.selectedModelFilename.value;
                final info = fname != null
                    ? _modelCtrl.getModelInfo(fname)
                    : null;
                final loaded = _llm.isLoaded.value;
                final isLoading = _llm.isLoadingModel.value;
                // Ticket 31: a selected remote source is what answers,
                // so the header names it (1.10.0/1.10.1 showed "No model
                // selected" + red dot while a mesh seat was answering).
                final remote = _modelCtrl.selectedRemote.value;
                final remoteOn =
                    remote != null && ImageGenService().connectivityOn;
                final label = isLoading
                    ? 'Loading...'
                    : remoteOn
                    ? (remote['label'] as String)
                    : loaded
                    ? (info?.name ?? fname ?? 'Model')
                    : 'No model selected';
                final active = loaded || remoteOn;

                return GestureDetector(
                  // UI audit 2026-11-06 residual: the header model
                  // selector's tap area was the text row alone
                  // (~20pt). Opaque hit + vertical padding gives it
                  // a 44pt-tall target without changing the layout.
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showModelPicker(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status dot — audit #8: never color-alone;
                      // it carries a semantics label and the source
                      // caption beside the model name says it in text.
                      Semantics(
                        label: isLoading
                            ? 'Loading model'
                            : remoteOn
                            ? 'Answering from the mesh'
                            : loaded
                            ? 'On-device model ready'
                            : 'No model selected',
                        child: Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // UI audit 2026-11-06 P2-2: remote and
                            // no-model states go neutral (the caption
                            // text already names the state).
                            color: isLoading
                                ? AppColors.orange
                                : remoteOn
                                ? AppColors.darkTextM
                                : loaded
                                ? AppColors.green
                                : AppColors.darkTextD,
                          ),
                        ),
                      ),
                      Flexible(
                        // The velocity-reactive label is OUT of the header
                        // (Kai, 2026-11-04: its scroll animation rendered
                        // the label flying diagonally out of the bar).
                        // Plain static text now; the widget itself stays
                        // in the faithful library for other surfaces.
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isLoading
                                ? context.textD
                                : active
                                ? context.text
                                // UI audit 2026-11-06 P2-5: accent as
                                // 14pt text fails (3.8:1); accentHi
                                // passes (4.9:1).
                                : AppColors.accentHi,
                          ),
                        ),
                      ),
                      if (remoteOn || loaded) ...[
                        const SizedBox(width: 6),
                        Text(
                          remoteOn
                              ? (remote['kind'] == 'custom'
                                    ? '· phone-direct'
                                    : '· Mesh')
                              : '· On device',
                          style: TextStyle(
                            fontSize: TS.of(context, 10),
                            color: context.textD,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: context.textM,
                      ),
                    ],
                    ),
                  ),
                );
              }),
            ),
          ),

          // 1.13.0: generation stop lives HERE (Kai: "a stop button
          // somewhere else") — the composer pill becomes the orb
          // during a run, so stop rides the top bar.
          _stopChip(),

          // New chat button — on the right
          IconButton(
            icon: Icon(Icons.edit_square, size: 20, color: context.textM),
            onPressed: () => _chatCtrl.newChat(),
            tooltip: 'New Chat',
          ),
        ],
      ),
    );
  }

  void _showModelPicker(BuildContext context) {
    // #5 Model Picker (faithful port): source rail + searchable list.
    // Ticket 31 seats ride the same sheet (Kai, 2026-11-04: the header
    // picker showed only local models while the mesh did the work).
    // Remote entries come from the mesh service's last-good cache,
    // which the Models tab keeps warm; opening the picker also kicks
    // a refresh for next time.
    final entries = <PickerEntry>[];
    final actions = <String, VoidCallback>{};
    void addEntry(
      String source,
      String name,
      String meta,
      VoidCallback act, {
      bool favorite = false,
      String? starModel,
      Widget? trailing,
    }) {
      entries.add(
        PickerEntry(
          source,
          name,
          meta,
          favorite: favorite,
          starModel: starModel,
          trailing: trailing,
        ),
      );
      actions['$source|$name'] = act;
    }

    for (final filename in _modelCtrl.downloadedModels) {
      final info = _modelCtrl.getModelInfo(filename);
      final name = info?.name ?? filename;
      final meta = info == null
          ? filename
          : '${info.sizeGb} GB \u00b7 Min ${info.minRamGb} GB RAM \u00b7 '
                '${info.minRamGb > 6
                    ? 'TOO LARGE'
                    : info.sizeGb > 4
                    ? 'STREAMS'
                    : 'FITS'}';
      addEntry('On device', name, meta, () {
        if (_modelCtrl.selectedModelFilename.value != filename) {
          _modelCtrl.loadModel(filename);
        } else {
          // Re-picking the loaded local model returns the mic to it.
          _modelCtrl.clearRemote();
        }
      });
    }

    final mesh = MeshService();
    if (mesh.connectivityOn) {
      mesh.fetchSeats();
      mesh.fetchNodeModels();
      // Sync build (mesh 0.20): favorites pin to the top of the list.
      var sawWakebox = false;
      for (final nm in MeshService.favoritesFirst(
        mesh.cachedNodeModels(),
        (n) => n.favorite,
      )) {
        final isWakebox = nm.node == 'aws' && nm.name == 'wakebox32b';
        if (isWakebox) sawWakebox = true;
        addEntry(
          'Mesh',
          nm.name,
          'On your ${nm.node} node',
          () {
            _modelCtrl.selectRemote({
              'kind': 'mesh',
              'id': 'node:${nm.node}:${nm.name}',
              'label': nm.name,
              'model': nm.name,
            });
          },
          favorite: nm.favorite,
          starModel: nm.name,
          trailing: isWakebox
              ? _BoxPill(
                  label: 'Stop',
                  color: AppColors.red,
                  doneLabel: 'Sleeping',
                  onFire: () => mesh.sleepBox(),
                )
              : null,
        );
      }
      if (!sawWakebox) {
        // The box sleeps: its node is out of the catalog, so the
        // row is synthetic — Warm pre-warms it, picking it lets the
        // gateway auto-wake on the first chat.
        addEntry(
          'Mesh',
          'wakebox32b',
          'AWS node · asleep',
          () {
            _modelCtrl.selectRemote({
              'kind': 'mesh',
              'id': 'node:aws:wakebox32b',
              'label': 'wakebox32b',
              'model': 'wakebox32b',
            });
          },
          trailing: _BoxPill(
            label: 'Warm',
            color: AppColors.accentHi,
            doneLabel: 'Warming…',
            onFire: () => mesh.wakeBox(),
          ),
        );
      }
      for (final s in MeshService.pickerOrder(mesh.cachedSeats())) {
        addEntry(
          'Mesh',
          s.model,
          s.dead
              ? '${s.lane} · NOT WORKING · tap to retry'
              : s.isBlocked
              ? (s.blocked ?? 'Unavailable on this gateway')
              : '${s.lane} \u00b7 ${s.isVerified ? 'VERIFIED' : 'UNTESTED'}',
          () {
            if (s.isBlocked) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(s.blocked ?? 'Unavailable on this gateway'),
                ),
              );
              return;
            }
            if (s.dead) mesh.setModelDead(s.model, false);
            _modelCtrl.selectRemote({
              'kind': 'mesh',
              'id': 'mesh:${s.lane}:${s.model}',
              'label': s.model,
              'model': s.model,
            });
          },
          favorite: s.favorite,
          starModel: s.model,
        );
      }
      for (final c in CustomConnectionsService().list()) {
        addEntry('Custom', c.name, '${c.model} \u00b7 phone-direct', () {
          _modelCtrl.selectRemote({
            'kind': 'custom',
            'id': c.id,
            'label': c.name,
            'model': c.model,
          });
        });
      }
    }

    if (entries.isEmpty) {
      // Nothing anywhere: go to Models, and say why (the old code
      // jumped tabs silently - UI audit 2026-11-06 P2-8).
      setState(() => _mobileTabIndex = 1);
      Get.snackbar(
        'No models yet',
        'Download or import a model to start chatting.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final remote = _modelCtrl.selectedRemote.value;
    final selectedInfo = _modelCtrl.selectedModelFilename.value != null
        ? _modelCtrl.getModelInfo(_modelCtrl.selectedModelFilename.value!)
        : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ModelPickerSheet(
          entries: entries,
          selectedName: remote != null
              ? remote['label'] as String?
              : selectedInfo?.name,
          onPick: (entry) {
            Navigator.pop(context);
            actions['${entry.source}|${entry.name}']?.call();
          },
          onToggleStar: (entry, v) {
            TapFx.select();
            if (entry.starModel != null) {
              MeshService().setModelFavorite(entry.starModel!, v);
            }
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DESKTOP LAYOUT — Sidebar + Top bar
  // ═══════════════════════════════════════════════════════════════
  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: context.bg,
      body: Row(
        children: [
          // Sidebar
          if (_sidebarOpen)
            SizedBox(
              width: 260,
              child: Container(
                decoration: BoxDecoration(
                  color: context.bgSidebar,
                  border: Border(
                    right: BorderSide(color: context.border, width: 0.5),
                  ),
                ),
                child: ChatSidebar(
                  onNewChat: () => _chatCtrl.newChat(),
                  onSelectChat: (id) => _chatCtrl.switchChat(id),
                  onDeleteChat: (id) => _chatCtrl.deleteChat(id),
                ),
              ),
            ),

          // Main content
          Expanded(
            child: Column(
              children: [
                _buildDesktopTopBar(),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: _buildChatArea(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTopBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.bg,
        border: Border(bottom: BorderSide(color: context.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Sidebar toggle
          IconButton(
            icon: Icon(
              _sidebarOpen
                  ? Icons.view_sidebar_rounded
                  : Icons.view_sidebar_outlined,
              size: 20,
              color: context.textM,
            ),
            onPressed: () => setState(() => _sidebarOpen = !_sidebarOpen),
            tooltip: 'Toggle sidebar',
          ),

          const SizedBox(width: 8),

          // Model selector dropdown
          Obx(() {
            final fname = _modelCtrl.selectedModelFilename.value;
            final info = fname != null ? _modelCtrl.getModelInfo(fname) : null;
            final remote = _modelCtrl.selectedRemote.value;
            return InkWell(
              onTap: () => Get.toNamed('/models'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: context.bgHover.withOpacity(0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      remote != null
                          ? (remote['label'] as String)
                          : (info?.name ?? (fname ?? 'Select Model')),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.text,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: context.textM,
                    ),
                  ],
                ),
              ),
            );
          }),

          const Spacer(),

          // 1.13.0: generation stop (see _stopChip).
          _stopChip(),

          // Engine status
          Obx(
            () => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _llm.isLoadingModel.value
                        ? AppColors.orange
                        : _llm.isLoaded.value
                        ? AppColors.green
                        : AppColors.red,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _llm.isLoadingModel.value
                      ? 'Loading... ${(_llm.loadingProgress.value * 100).toInt()}%'
                      : _llm.isLoaded.value
                      ? 'Ready'
                      : 'No Model',
                  style: TextStyle(fontSize: 12, color: context.textD),
                ),
                if (_llm.isLoaded.value && !_llm.isLoadingModel.value) ...[
                  const SizedBox(width: 8),
                  // Unload button on desktop
                  InkWell(
                    onTap: () => _modelCtrl.unloadCurrentModel(),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.eject_rounded,
                            size: 14,
                            color: AppColors.orange,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Unload',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textD,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_llm.isGenerating.value) ...[
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SpringNumber(
                        value: _llm.tokensPerSecond.value,
                        decimals: 1,
                        style: TextStyle(fontSize: 12, color: context.textM),
                      ),
                      Text(
                        ' t/s',
                        style: TextStyle(fontSize: 12, color: context.textM),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Settings
          IconButton(
            icon: Icon(Icons.settings_outlined, size: 20, color: context.textM),
            onPressed: () => Get.toNamed('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SHARED — Chat area used by both layouts
  // ═══════════════════════════════════════════════════════════════
  Widget _buildChatArea() {
    return Stack(
      children: [
        // B3 (Claude C3): the KineticGrid is hoisted out of the
        // welcome body to live behind BOTH the welcome content and
        // the composer - inside the body alone it ended in a hard
        // edge above the composer. Welcome-state only, dissolving
        // through a gradient fade before it reaches the input area.
        Obx(() {
          final chat = _chatCtrl.activeChat;
          final welcome = chat == null || chat.messages.isEmpty;
          if (!welcome) return const SizedBox.shrink();
          return Positioned.fill(
            child: Stack(
              children: [
                const Positioned.fill(child: KineticGrid(subtle: true)),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          context.bg,
                        ],
                        stops: const [0, 0.7, 1],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        Column(
          children: [
            Expanded(
              child: Obx(() {
                final chat = _chatCtrl.activeChat;
                if (chat == null || chat.messages.isEmpty) {
                  return _buildWelcome();
                }

                if (_lastRenderedChatId != chat.id) {
                  _lastRenderedChatId = chat.id;
                  _autoScrollToBottom = true;
                  _scrollToBottom(force: true);
                }

                _scrollToBottom();

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: chat.messages.length,
                  itemBuilder: (context, index) {
                    final msg = chat.messages[index];
                    // Show speed on the last AI message
                    final isLastAi =
                        msg.isAssistant && index == chat.messages.length - 1;
                    return ChatBubble(
                      message: msg,
                      showSpeed: isLastAi,
                      isStreaming: isLastAi && _chatCtrl.isGenerating.value,
                      isRegenerating:
                          isLastAi && _chatCtrl.isRegenerating.value,
                      onRegenerate: isLastAi && !_chatCtrl.isGenerating.value
                          ? () => _chatCtrl.regenerateLast()
                          : null,
                    );
                  },
                );
              }),
            ),

            _buildInputArea(),
          ],
        ),
        // 1.13.0: MorphOrb composer (variant #5, Answer Card Mode,
        // exactly as the artifact) — the pill lives in this overlay
        // at its home slot; on send it collapses into the orb, flies
        // to center stage, thinks, resolves, condenses to the check.
        // Driven by real generation state throughout.
        Obx(() {
          final chat = _chatCtrl.activeChat;
          final gen = _chatCtrl.isGenerating.value;
          var failed = false;
          if (!gen && chat != null && chat.messages.isNotEmpty) {
            final last = chat.messages.last;
            if (last.isAssistant) failed = last.failed;
          }
          return MorphOrbComposer(
            controller: _msgController,
            onSend: _send,
            canSend: _canSend,
            running: gen,
            failed: failed,
            stopCount: _stopCount,
            reducedMotion: MediaQuery.of(context).disableAnimations,
            slotKey: _composerSlotKey,
          );
        }),
      ],
    );
  }

  Widget _buildWelcome() {
    // Re-port (Kai, 2026-11-03): the orb is the centerpiece hero, the
    // app icon does NOT appear here. The KineticGrid background moved
    // up into _buildChatArea (B3/C3) so it runs full-bleed behind the
    // composer too.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(
              () => ThinkingOrb(
                size: 190,
                thinking: _chatCtrl.isGenerating.value,
              ),
            ),
            const SizedBox(height: 26),
            BlurReveal(
              text: 'What are we running today?',
              style: TS.display(context, color: context.text),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Text(
                _llm.isLoaded.value
                    ? 'Type a message below to get started.'
                    : 'Pick a model. On-device models never leave this phone.',
                style: TextStyle(
                  fontSize: TS.of(context, 14),
                  color: context.textM,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 22),
            const RedactionBars(widths: [110, 76, 128, 58], barHeight: 9),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    // 1.13.0: the composer pill itself lives in the MorphOrb overlay
    // (it collapses into the orb on send, exactly as the artifact).
    // What remains here is its invisible home-rect slot: a mirror of
    // the field's text so multiline growth reserves the exact height
    // the real pill takes, plus the ticket-08 dissolve overlay.
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Container(
            key: _composerSlotKey,
            child: Opacity(
              opacity: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 42),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 14, 8, 14),
                      child: Text(
                        _msgController.text.isEmpty ? ' ' : _msgController.text,
                        maxLines: 5,
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ),
        if (_dissolvingText != null)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(86, 22, 16, 16),
              child: DisintegratingText(
                text: _dissolvingText!,
                color: context.text,
                fontSize: 15,
                onDone: () {
                  if (mounted) setState(() => _dissolvingText = null);
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// See-Astro-drive toasts (ticket 24): small dark chips at the top of
/// the chat page narrating each admin action while Astro drives —
/// reads included. They queue politely (the service caps the stack)
/// and fade on their own.
class _AdminToastOverlay extends StatelessWidget {
  const _AdminToastOverlay();

  @override
  Widget build(BuildContext context) {
    AdminActivityService? activity;
    try {
      activity = Get.find<AdminActivityService>();
    } catch (_) {}
    if (activity == null) return const SizedBox.shrink();
    final svc = activity;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Obx(() {
        if (svc.toasts.isEmpty) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final toast in svc.toasts)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.bgPanel,
                  border: Border.all(color: context.border),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.darkTextM,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        toast.label,
                        style: TextStyle(color: context.text, fontSize: 12.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// The wakebox32b row action (sync build): Warm pre-warms the AWS
/// box, Stop sleeps it. One-shot — after firing it shows its done
/// label and goes inert; the catalog state catches up on its own
/// (the node appears/disappears with the box).
class _BoxPill extends StatefulWidget {
  final String label;
  final String doneLabel;
  final Color color;
  final Future<bool> Function() onFire;
  const _BoxPill({
    required this.label,
    required this.doneLabel,
    required this.color,
    required this.onFire,
  });

  @override
  State<_BoxPill> createState() => _BoxPillState();
}

class _BoxPillState extends State<_BoxPill> {
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _fired
            ? null
            : () async {
                TapFx.select();
                setState(() => _fired = true);
                await widget.onFire();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: widget.color),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _fired ? widget.doneLabel : widget.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
