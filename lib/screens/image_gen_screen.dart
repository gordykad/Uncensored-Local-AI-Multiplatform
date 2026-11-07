// Ticket 28: the Image Gen tab. One page, two lanes:
//   Lane B 'owner'  - hosted Gradio Spaces (free), entries shareable by pin.
//   Lane A 'runpod' - Kai's own RunPod endpoint. KAI-ONLY (Amendment 9):
//                     entries + key never leave this device.
// Gated by the connectivity switch (offline-law bend, Amendment 1): switch
// OFF = the tab is dead. Design: Combo C chat presentation, Model Picker,
// Sparkles field (dimmed to 0.7 by founder order), hero ThinkingOrb in a
// Border Beam card (Magic UI mechanics), Nexus bar (rotating placeholders +
// disintegrating send).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/image_entry.dart';
import 'gen_gallery_screen.dart';
import '../services/chatgpt_service.dart';
import '../services/image_gen_service.dart';
import '../services/log_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/type_scale.dart';
import '../widgets/faithful/orb.dart';
import '../widgets/tab_header.dart';

class _Item {
  final String prompt;
  String status; // pending | done | error
  String phase;
  List<int>? bytes;
  int? seed;
  String? error;
  // Ticket 32: video items carry a persisted file path (the mp4 in
  // the gallery store) instead of in-memory bytes.
  bool isVideo = false;
  String? videoPath;
  // Ticket 39: the gallery record for this result, once persisted —
  // the tap target that opens the shared viewer (Share / Photos).
  GenRecord? rec;
  _Item(this.prompt)
      : status = 'pending',
        phase = 'Starting';
}

/// UI audit 2026-11-06: the result tile used to render the raw
/// exception (minus its prefix). Map to a plain cause + next step;
/// the raw error stays in the debug log.
String _friendlyGenError(Object e) {
  final raw = e.toString();
  debugPrint('ImageGen error: $raw');
  if (raw.contains('SocketException') ||
      raw.contains('Network') ||
      raw.contains('timed out') ||
      raw.contains('Timeout')) {
    return 'Network error. Check the connection and try again.';
  }
  if (raw.contains('401') || raw.contains('403')) {
    return 'The lane rejected the request. Check the entry or sign-in, then try again.';
  }
  if (raw.contains('429')) {
    return 'The lane is rate limited. Wait a moment and try again.';
  }
  return 'Generation failed. Try again, or pick another entry.';
}

class ImageGenScreen extends StatefulWidget {
  final bool embedded;
  const ImageGenScreen({super.key, this.embedded = false});

  @override
  State<ImageGenScreen> createState() => _ImageGenScreenState();
}

class _ImageGenScreenState extends State<ImageGenScreen>
    with SingleTickerProviderStateMixin {
  final _svc = ImageGenService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Item> _items = [];
  List<ImageEntry> _entries = [];
  ImageEntry? _current;
  bool _busy = false;
  String _phase = '';
  int _batch = 1;
  late final AnimationController _beam;

  static const _placeholders = [
    'A lighthouse at dusk, cinematic',
    'A portrait in neon rain, 35mm',
    'A cabin in snow under the aurora',
    'A red fox in fresh snow, wildlife photo',
    'A vinyl record store at night, moody light',
  ];
  int _phIndex = 0;
  Timer? _phTimer;

  bool _loggedBuild = false; // build 18 diagnostics

  // UI audit 2026-11-06 (Codex P1-3): the ChatGPT synthetic entry
  // must track sign-in state; this tab lives in an IndexedStack and
  // never re-inits, so build() re-checks and resyncs after the frame.
  bool _chatGptPresent = false;
  static const _chatGptEntry = ImageEntry(
    id: 'chatgpt-images',
    name: 'ChatGPT',
    link: '',
    lane: 'chatgpt',
    createdMs: 0,
  );

  /// Local entries plus the ChatGPT row when signed in. Every
  /// mutation path rebuilds through here so the synthetic row is
  /// never dropped by a pin/delete refresh.
  List<ImageEntry> _allEntries() {
    final base = _svc.localEntries();
    return _chatGptPresent ? [_chatGptEntry, ...base] : base;
  }

  void _syncChatGptEntry() {
    final signedIn = ChatGptService().isSignedIn;
    if (signedIn == _chatGptPresent || !mounted) return;
    _chatGptPresent = signedIn;
    setState(() {
      _entries = _entries.where((e) => e.id != 'chatgpt-images').toList();
      if (signedIn) _entries = [_chatGptEntry, ..._entries];
      if (_current?.id == 'chatgpt-images' && !signedIn) {
        _current = _entries.isNotEmpty ? _entries.first : null;
      }
    });
  }

  void _diag(String msg) {
    try {
      Get.find<LogService>().info(msg, source: 'ImageGen');
    } catch (_) {}
  }

  @override
  void initState() {
    _diag('initState start');
    super.initState();
    _beam = AnimationController(
        vsync: this, duration: const Duration(seconds: 6));
    _entries = _svc.localEntries();
    // Ticket 33: the ChatGPT subscription lane rides as a synthetic
    // entry whenever Kai is signed in - no catalog row, device-local.
    _chatGptPresent = ChatGptService().isSignedIn;
    if (_chatGptPresent) {
      _entries = [_chatGptEntry, ..._entries];
    }
    _current = _entries.isNotEmpty ? _entries.first : null;
    _diag('initState entries=${_entries.length} online=${_svc.connectivityOn}');
    _input.addListener(() => setState(() {}));
    _phTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (!mounted || _busy || _input.text.isNotEmpty) return;
      setState(() => _phIndex = (_phIndex + 1) % _placeholders.length);
    });
    if (_svc.connectivityOn) _loadPinned();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // UI audit 2026-11-06 P2-7: the hero beam loop honors Reduce
    // Motion (it is driven from this State, so the gate lives here,
    // not in a TickerMode below).
    if (RM.off(context)) {
      _beam.stop();
    } else if (!_beam.isAnimating) {
      _beam.repeat();
    }
  }

  Future<void> _loadPinned() async {
    final pinned = await _svc.fetchPinned();
    if (!mounted || pinned.isEmpty) return;
    setState(() {
      final links = _entries.map((e) => e.link).toSet();
      _entries = [
        ..._entries,
        ...pinned.where((e) => !links.contains(e.link)),
      ];
    });
  }

  @override
  void dispose() {
    _beam.dispose();
    _phTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _online => _svc.connectivityOn;

  void _toast(String msg) => Get.snackbar(
        'Image Gen',
        msg,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.darkBgPanel,
        colorText: AppColors.darkText,
        duration: const Duration(seconds: 3),
      );

  Future<void> _generate(String prompt) async {
    final entry = _current;
    if (entry == null || _busy || prompt.trim().isEmpty) return;
    if (!_online) {
      _toast('Connectivity is off - this tab is disabled');
      return;
    }
    if (entry.isVideo) {
      await _generateVideo(entry, prompt.trim());
      return;
    }
    // Batch stepper (1.11.2): fire _batch stills back to back, each
    // its own item with its own random seed server-side. One failure
    // marks its item and the batch carries on.
    final total = _batch;
    setState(() {
      _busy = true;
      _phase = 'Starting';
    });
    for (var i = 0; i < total; i++) {
      final item = _Item(prompt.trim());
      if (!mounted) return;
      setState(() {
        _items.add(item);
        if (total > 1) _phase = 'Generating ${i + 1} of $total';
      });
      _scrollDown();
      try {
        final result = entry.isChatGpt
            ? await _svc.generateChatGpt(entry,
                prompt: item.prompt,
                onPhase: (p) => _setPhase(item, p))
            : entry.isRunpod
                ? await _svc.generateRunpod(entry,
                    prompt: item.prompt,
                    onPhase: (p) => _setPhase(item, p))
                : await _svc.generateOwner(entry,
                    prompt: item.prompt,
                    onPhase: (p) => _setPhase(item, p));
        item.bytes = result.bytes;
        item.seed = result.seed;
        item.status = 'done';
        // Persist to the Previous Gens gallery (Kai, 2026-11-04).
        // recordGeneration never throws; ticket 39 keeps the record
        // so the result can open in the gallery viewer.
        item.rec = await _svc.recordGeneration(
          bytes: result.bytes,
          prompt: item.prompt,
          seed: result.seed,
          model: entry.name,
        );
      } catch (e) {
        item.status = 'error';
        item.error = _friendlyGenError(e);
      }
      if (mounted) setState(() {});
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _phase = '';
      });
      _scrollDown();
    }
  }

  /// Ticket 32: run a video job (text-to-video, or image-to-video
  /// when [imageBytes] carries a still to animate).
  Future<void> _generateVideo(ImageEntry entry, String prompt,
      {List<int>? imageBytes}) async {
    if (_busy || prompt.trim().isEmpty) return;
    if (!_online) {
      _toast('Connectivity is off - this tab is disabled');
      return;
    }
    final item = _Item(prompt.trim())..isVideo = true;
    setState(() {
      _busy = true;
      _phase = 'Starting';
      _items.add(item);
    });
    _scrollDown();
    try {
      final result = await _svc.generateRunpodVideo(entry,
          prompt: item.prompt,
          imageBytes: imageBytes,
          onPhase: (p) => _setPhase(item, p));
      // Persist first: the player reads the gallery file.
      final rec = await _svc.recordGeneration(
        bytes: result.bytes,
        prompt: item.prompt,
        seed: result.seed,
        model: entry.name,
        kind: 'video',
      );
      if (rec == null) throw Exception('Could not save the clip');
      item.rec = rec;
      item.videoPath = rec.file;
      item.seed = result.seed;
      item.status = 'done';
    } catch (e) {
      item.status = 'error';
      item.error = _friendlyGenError(e);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _phase = '';
      });
      _scrollDown();
    }
  }

  /// Animate a picture brought in from outside the thread: Photos
  /// (file_picker, already a dependency) or a Previous Gens still.
  /// The composer text, when present, becomes the motion prompt.
  Future<void> _animatePicture() async {
    if (_busy) return;
    final vids = _entries.where((e) => e.isVideo).toList();
    if (vids.isEmpty) {
      // UI audit 2026-11-06 P2-6: a dead-end toast becomes the
      // action itself; the sheet opens on the spot.
      _toast('No video entry yet. Add one to continue.');
      _openAdd();
      return;
    }
    final src = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.darkBgPanel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: AppColors.accentHi),
            title: const Text('From Photos',
                style: TextStyle(color: AppColors.darkText, fontSize: 14)),
            onTap: () => Navigator.of(sheetCtx).pop('photos'),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_rounded,
                color: AppColors.accentHi),
            title: const Text('From Previous Gens',
                style: TextStyle(color: AppColors.darkText, fontSize: 14)),
            onTap: () => Navigator.of(sheetCtx).pop('gens'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (src == null || !mounted) return;
    List<int>? bytes;
    if (src == 'photos') {
      final r = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (r == null || r.files.isEmpty) return;
      bytes = r.files.first.bytes;
      if (bytes == null && r.files.first.path != null) {
        bytes = await File(r.files.first.path!).readAsBytes();
      }
    } else {
      final rec = await _pickGenStill();
      if (rec == null) return;
      bytes = await File(rec.file).readAsBytes();
    }
    if (bytes == null || !mounted) return;
    final entry = (_current?.isVideo ?? false) ? _current! : vids.first;
    final typed = _input.text.trim();
    _generateVideo(
        entry,
        typed.isEmpty
            ? 'slow cinematic push-in, gentle natural motion'
            : typed,
        imageBytes: bytes);
  }

  Future<GenRecord?> _pickGenStill() {
    final recs = _svc.history().where((r) => !r.isVideo).toList();
    if (recs.isEmpty) {
      _toast('No saved stills yet');
      return Future.value(null);
    }
    return showModalBottomSheet<GenRecord>(
      context: context,
      backgroundColor: AppColors.darkBgPanel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) => SafeArea(
        child: SizedBox(
          height: 430,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Pick a still to animate',
                    style: TextStyle(
                        color: AppColors.darkText,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8),
                itemCount: recs.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => Navigator.of(sheetCtx).pop(recs[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(recs[i].file),
                        fit: BoxFit.cover, cacheWidth: 300),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Animate a finished still with the selected (or first) video
  /// entry - the image-to-video half of ticket 32.
  void _animate(_Item src) {
    if (src.bytes == null || _busy) return;
    final vids = _entries.where((e) => e.isVideo).toList();
    if (vids.isEmpty) {
      // UI audit 2026-11-06 P2-6: a dead-end toast becomes the
      // action itself; the sheet opens on the spot.
      _toast('No video entry yet. Add one to continue.');
      _openAdd();
      return;
    }
    final entry = (_current?.isVideo ?? false) ? _current! : vids.first;
    _generateVideo(entry, src.prompt, imageBytes: src.bytes);
  }

  void _setPhase(_Item item, String p) {
    if (!mounted) return;
    setState(() {
      item.phase = p;
      _phase = p;
    });
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  void _send() {
    // The Nexus disintegration on the prompt text is REMOVED for good
    // (Kai, 2026-11-04): it sampled the typed prompt into particles and
    // froze mid-dissolve on long prompts, trapping the submit behind
    // the animation. Sending is direct now: capture, clear, generate.
    if (_busy) return;
    // UI audit 2026-11-06 (Codex P1-4/P3-33): validate BEFORE
    // clearing. The old flow cleared the field and then _generate
    // returned silently with no entry picked, eating the prompt;
    // an empty field also used to submit the rotating example.
    if (_current == null) {
      _toast('Pick a model first. Your prompt is still in the field.');
      return;
    }
    final text = _input.text.trim();
    if (text.isEmpty) {
      _toast('Type a prompt first.');
      return;
    }
    _input.clear();
    _generate(text);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedBuild) {
      _loggedBuild = true;
      _diag('first build');
    }
    if (ChatGptService().isSignedIn != _chatGptPresent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncChatGptEntry();
      });
    }
    final online = _online;
    // Keyboard open: the hero card collapses out of the way. With it
    // up, the thread crushed to a slit and images rendered as thin
    // strips (Kai's screen recording, 2026-11-04).
    final kbOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final body = Column(
      children: [
        _header(online),
        if (!online) _veil() else ...[
          if (!kbOpen) _heroCard(),
          Expanded(child: _threadWithSparkles()),
          _pickerRow(),
          _nexusBar(),
        ],
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(backgroundColor: AppColors.darkBg, body: SafeArea(child: body));
  }

  Widget _header(bool online) {
    // UI audit 2026-11-06 (Claude P2-10): the shared 52pt bordered
    // TabHeader, same as Models and Settings; the connectivity pill
    // rides as the trailing action.
    return TabHeader(
      title: 'Image Gen',
      trailing: [
        Semantics(
          button: true,
          toggled: online,
          label: 'Connectivity',
          child: GestureDetector(
            onTap: () {
              setState(() => _svc.connectivityOn = !online);
              if (!online) _loadPinned();
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.darkBgPanel,
              border: Border.all(color: AppColors.darkBorder),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? AppColors.green : AppColors.red,
                ),
              ),
                const SizedBox(width: 7),
                Text(online ? 'Connectivity on' : 'Connectivity off',
                    style: const TextStyle(
                        color: AppColors.darkTextM, fontSize: 12)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _veil() {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppColors.darkTextD, size: 40),
            const SizedBox(height: 14),
            const Text('Image generation is off',
                style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Turn on Connectivity to use the hosted lanes. Your local models are unaffected.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.darkTextM, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 18),
            // UI audit 2026-11-06 (Claude P2-8, Codex P1-14): the
            // veil gets its own actions. Previous Gens is local
            // content; connectivity must never gate it.
            FilledButton(
              onPressed: () {
                setState(() => _svc.connectivityOn = true);
                _loadPinned();
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                minimumSize: const Size(180, 44),
              ),
              child: const Text('Turn on Connectivity'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const GenGalleryScreen()),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.darkText,
                side: const BorderSide(color: AppColors.darkBorder),
                minimumSize: const Size(180, 44),
              ),
              child: const Text('Previous Gens'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _heroCard() {
    final caption = _busy
        ? _phase
        : _current == null
            ? 'Pick a model below'
            : '${_current!.name} - ready';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Center(
        child: TickerMode(
          // The orb's own tickers live in this subtree: frozen under
          // Reduce Motion (the beam is gated in didChangeDependencies).
          enabled: !RM.off(context),
          child: AnimatedBuilder(
          animation: _beam,
          builder: (_, __) => CustomPaint(
            painter: _BeamPainter(_beam.value),
            child: Container(
              width: 280,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.darkBgPanel,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ThinkingOrb(size: 132, thinking: _busy),
                const SizedBox(height: 8),
                Text(caption,
                    style: const TextStyle(
                        color: AppColors.darkTextM, fontSize: 12.5)),
              ]),
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _threadWithSparkles() {
    // Hard clip: the thread stays in its lane. Kai's 2026-11-04
    // recording showed items bleeding under the hero card and over
    // the picker row while scrolling/resizing.
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // UI audit 2026-11-06: the sparkle field is a repeating
        // ambient loop; frozen under Reduce Motion.
        Positioned.fill(
          child: TickerMode(
            enabled: !RM.off(context),
            child: const _SparklesField(),
          ),
        ),
        if (_items.isEmpty)
          const Center(
            child: Text('Describe an image to begin',
                style: TextStyle(color: AppColors.darkTextD, fontSize: 13.5)),
          )
        else
          ListView.builder(
            controller: _scroll,
            clipBehavior: Clip.hardEdge,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            itemCount: _items.length,
            itemBuilder: (_, i) => _itemCard(_items[i]),
          ),
      ],
    );
  }

  Widget _itemCard(_Item item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 290),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            // UI audit 2026-11-06 P2-2: the user's own prompt is
            // content, not the screen's action; panel fill like the
            // Chat tab's treatment of user text.
            decoration: BoxDecoration(
              color: AppColors.darkBgInput,
              border: Border.all(color: AppColors.darkBorder),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(5),
              ),
            ),
            child: Text(item.prompt,
                style: const TextStyle(
                    color: AppColors.darkText, fontSize: 13.5)),
          ),
        ),
        const SizedBox(height: 8),
        if (item.status == 'pending')
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkBgPanel,
              border: Border.all(color: AppColors.darkBorderFaint),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accentHi),
              ),
              const SizedBox(width: 12),
              Text(item.phase,
                  style: const TextStyle(
                      color: AppColors.darkTextM, fontSize: 13)),
            ]),
          )
        else if (item.status == 'error')
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.darkBgPanel,
              border: Border.all(color: AppColors.darkBorderFaint),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(item.error ?? 'Generation failed',
                style: const TextStyle(
                    color: AppColors.red, fontSize: 13, height: 1.45)),
          )
        else if (item.isVideo && item.videoPath != null)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: item.rec == null
                  ? null
                  : () => Get.to(() => GenViewer(rec: item.rec!, svc: _svc)),
              child: _VideoTile(path: item.videoPath!),
            ),
            const SizedBox(height: 6),
            Text(
              '832 x 480 - video${item.seed != null ? ' - seed ${item.seed}' : ''}',
              style: const TextStyle(
                  color: AppColors.darkTextD, fontSize: 11.5),
            ),
          ])
        else
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: item.rec == null
                  ? null
                  : () => Get.to(() => GenViewer(rec: item.rec!, svc: _svc)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                // Pinned 1:1 box: the image can never collapse into a
                // strip whatever the viewport is doing (2026-11-04).
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Image.memory(Uint8List.fromList(item.bytes!),
                      fit: BoxFit.cover, width: double.infinity),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // UI audit 2026-11-06 (Codex P2-20): metadata and
            // actions no longer fight for one row; actions wrap.
            Text(
              '1024 x 1024${item.seed != null ? ' · seed ${item.seed}' : ''}',
              style: const TextStyle(
                  color: AppColors.darkTextD, fontSize: 11.5),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: item.rec == null
                      ? null
                      : () => Get.to(() => GenViewer(rec: item.rec!, svc: _svc)),
                  child: const Text('View',
                      style: TextStyle(
                          color: AppColors.darkTextM, fontSize: 12.5)),
                ),
                if (_entries.any((e) => e.isVideo))
                  TextButton(
                    onPressed: _busy ? null : () => _animate(item),
                    child: const Text('Animate',
                        style: TextStyle(
                            color: AppColors.darkTextM, fontSize: 12.5)),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => _generate('${item.prompt} '),
                  child: const Text('Re-roll',
                      style: TextStyle(
                          color: AppColors.darkTextM, fontSize: 12.5)),
                ),
              ],
            ),
          ]),
      ]),
    );
  }

  // Ticket 39: the old _save wrote a second, unindexed copy of the
  // result into the images folder — an orphan the gallery cap never
  // evicted. It is gone; the viewer (tap the result) carries Share
  // and Save to Photos now.

  Widget _pickerRow() {
    final e = _current;
    // UI audit 2026-11-06 (Codex P1-1): the old single row (pill +
    // stepper + three icon buttons sharing one line) overflowed a
    // phone width with ordinary entry names. The pill now flexes on
    // row one with the stepper; the icon actions get their own row.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Choose model, current: ${e?.name ?? 'none'}',
                child: GestureDetector(
                  onTap: _openPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.darkBgPanel,
                      border: Border.all(color: AppColors.darkBorder),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.auto_awesome_rounded,
                          size: 15, color: AppColors.accentHi),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(e?.name ?? 'No model',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.darkText, fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          // Lane badge is metadata, not an action.
                          color: AppColors.darkBgHover,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          e == null
                              ? 'none'
                              : (e.isChatGpt
                                  ? 'Subscription'
                                  : e.isRunpod
                                      ? 'RunPod'
                                      : 'Hosted'),
                          style: const TextStyle(
                              color: AppColors.darkTextM, fontSize: 10.5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more_rounded,
                          size: 16, color: AppColors.darkTextM),
                    ]),
                  ),
                ),
              ),
            ),
            if (e != null && !e.isVideo) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                decoration: BoxDecoration(
                  color: AppColors.darkBgPanel,
                  border: Border.all(color: AppColors.darkBorder),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    onPressed: _batch > 1
                        ? () => setState(() => _batch--)
                        : null,
                    icon: const Icon(Icons.remove_rounded, size: 15),
                    color: AppColors.darkTextM,
                    disabledColor: AppColors.darkTextD,
                    padding: EdgeInsets.zero,
                    // UI audit 2026-11-06 P1-7: 44pt stepper targets.
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    tooltip: 'Fewer',
                  ),
                  Text('x$_batch',
                      style: const TextStyle(
                          color: AppColors.darkText, fontSize: 12.5)),
                  IconButton(
                    onPressed: _batch < 20
                        ? () => setState(() => _batch++)
                        : null,
                    icon: const Icon(Icons.add_rounded, size: 15),
                    color: AppColors.darkTextM,
                    disabledColor: AppColors.darkTextD,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    tooltip: 'More',
                  ),
                ]),
              ),
            ],
          ]),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Animate a picture: bring a still in from Photos or
              // Previous Gens (Kai, 2026-11-04).
              IconButton(
                onPressed: _animatePicture,
                icon: const Icon(Icons.add_photo_alternate_outlined,
                    size: 19, color: AppColors.darkTextM),
                tooltip: 'Animate a picture',
              ),
              // Previous Gens lives HERE, inside the studio (Kai,
              // 2026-11-04: not a dock tab of its own).
              IconButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const GenGalleryScreen())),
                icon: const Icon(Icons.photo_library_rounded,
                    size: 19, color: AppColors.darkTextM),
                tooltip: 'Previous Gens',
              ),
              IconButton(
                onPressed: _openRunpodSettings,
                icon: const Icon(Icons.tune_rounded,
                    size: 19, color: AppColors.darkTextM),
                tooltip: 'Lane settings',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nexusBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Stack(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 5, 5, 5),
          decoration: BoxDecoration(
            color: AppColors.darkBgInput,
            border: Border.all(color: AppColors.darkBorder),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(children: [
            Expanded(
              child: Stack(alignment: Alignment.centerLeft, children: [
                TextField(
                  controller: _input,
                  style:
                      TextStyle(color: AppColors.darkText, fontSize: 14),
                  cursorColor: AppColors.accent,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: (_) => _send(),
                ),
                if (_input.text.isEmpty)
                  IgnorePointer(
                    child: AnimatedSwitcher(
                      // UI audit 2026-11-06: no slide under Reduce
                      // Motion; the example swaps instantly.
                      duration: RM.off(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 350),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.35),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        _placeholders[_phIndex],
                        key: ValueKey(_phIndex),
                        style: const TextStyle(
                            color: AppColors.darkTextD, fontSize: 14),
                      ),
                    ),
                  ),
              ]),
            ),
            // UI audit 2026-11-06: 44pt hit area (circle stays 36),
            // a VoiceOver name, and a dimmed state when no model is
            // picked (the tap explains instead of eating the prompt).
            Semantics(
              button: true,
              label: 'Generate',
              enabled: !_busy,
              child: GestureDetector(
                onTap: _busy ? null : _send,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _busy || _current == null
                            ? AppColors.darkBgHover
                            : AppColors.accent,
                      ),
                      child: Icon(
                        _busy
                            ? Icons.hourglass_top_rounded
                            : Icons.arrow_upward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  void _openPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkBgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Models',
                      style: TextStyle(
                          color: AppColors.darkText,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                // UI audit 2026-11-06 (Codex P2-18): every sheet gets
                // a visible way out, not just the scrim.
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded,
                      size: 19, color: AppColors.darkTextM),
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                ),
              ],
            ),
          ),
          // UI audit 2026-11-06 (Codex P2-19): the entry list
          // scrolls; it can no longer push the sheet off-screen.
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final e in _entries)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      e.id == _current?.id
                          ? AppIcons.checkCircle
                          : Icons.circle_outlined,
                      color: e.id == _current?.id
                          ? AppColors.accentHi
                          : AppColors.darkTextD,
                      size: 19,
                    ),
                    title: Text(e.name,
                        style: const TextStyle(
                            color: AppColors.darkText, fontSize: 13.5)),
                    subtitle: Text(
                      e.isVideo
                          ? 'RunPod video · your endpoint only'
                          : e.isRunpod
                              ? 'RunPod · your endpoint only'
                              : (e.remote
                                  ? 'Hosted · pinned by you'
                                  : 'Hosted'),
                      style: const TextStyle(
                          color: AppColors.darkTextD, fontSize: 11.5),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (e.pinned && !e.remote)
                          const Icon(AppIcons.pin,
                              size: 15, color: AppColors.accentHi),
                        // UI audit 2026-11-06 (Codex P2-17): entry
                        // actions get a visible button; long-press
                        // is no longer the only door.
                        if (e.id != 'chatgpt-images')
                          IconButton(
                            tooltip: 'Entry options',
                            icon: const Icon(Icons.more_horiz_rounded,
                                size: 19, color: AppColors.darkTextM),
                            onPressed: () {
                              Navigator.of(sheetCtx).pop();
                              _entryActions(e);
                            },
                          ),
                      ],
                    ),
                    onTap: () {
                      setState(() => _current = e);
                      Navigator.of(sheetCtx).pop();
                    },
                    onLongPress: () {
                      Navigator.of(sheetCtx).pop();
                      _entryActions(e);
                    },
                  ),
              ],
            ),
          ),
          const Divider(color: AppColors.darkBorderFaint, height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.add_rounded,
                color: AppColors.accentHi, size: 19),
            title: const Text('Add entry',
                style: TextStyle(color: AppColors.darkText, fontSize: 13.5)),
            subtitle: const Text('Paste a link · validated before it is added',
                style: TextStyle(color: AppColors.darkTextD, fontSize: 11.5)),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _openAdd();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _entryActions(ImageEntry e) {
    if (e.remote) {
      _toast('Pinned entries are managed from your own tab');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkBgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(e.name,
                  style: const TextStyle(
                      color: AppColors.darkText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          if (!e.isRunpod)
            ListTile(
              dense: true,
              leading: const Icon(AppIcons.pin,
                  color: AppColors.accentHi, size: 19),
              title: Text(e.pinned ? 'Unpin' : 'Pin to all profiles',
                  style: const TextStyle(
                      color: AppColors.darkText, fontSize: 13.5)),
              subtitle: const Text(
                  'Pinned entries publish to the fleet through the shared config',
                  style:
                      TextStyle(color: AppColors.darkTextD, fontSize: 11.5)),
              onTap: () {
                _svc.setPinned(e.id, !e.pinned);
                setState(() => _entries = _allEntries());
                Navigator.of(sheetCtx).pop();
                _toast(e.pinned ? 'Unpinned' : 'Pinned. It will publish to all profiles');
              },
            ),
          ListTile(
            dense: true,
            leading:
                const Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 19),
            title: const Text('Delete entry',
                style: TextStyle(color: AppColors.red, fontSize: 13.5)),
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              // UI audit 2026-11-06 P1-5: irreversible deletes
              // confirm first, same pattern as chats and models.
              final sure = await showDialog<bool>(
                context: context,
                builder: (dCtx) => AlertDialog(
                  backgroundColor: AppColors.darkBgPanel,
                  title: const Text('Delete entry?',
                      style: TextStyle(color: AppColors.darkText)),
                  content: Text(
                    '"${e.name}" will be removed from this phone.',
                    style: const TextStyle(
                        color: AppColors.darkTextM, fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dCtx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.redDeep),
                      onPressed: () => Navigator.of(dCtx).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (sure != true || !mounted) return;
              _svc.removeEntry(e.id);
              setState(() {
                _entries = _allEntries();
                if (_current?.id == e.id) {
                  _current = _entries.isNotEmpty ? _entries.first : null;
                }
              });
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _openAdd() {
    final name = TextEditingController();
    final link = TextEditingController();
    var lane = 'owner';
    var kind = 'image';
    var checking = false;
    String? error;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkBgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 16, 18, MediaQuery.of(sheetCtx).viewInsets.bottom + 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Add entry',
                  style: TextStyle(
                      color: AppColors.darkText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'owner', label: Text('Owner hosted')),
                ButtonSegment(value: 'runpod', label: Text('RunPod')),
              ],
              selected: {lane},
              onSelectionChanged: (s) => setSheet(() => lane = s.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5)),
              ),
            ),
            if (lane == 'runpod') ...[
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'image', label: Text('Image')),
                  ButtonSegment(value: 'video', label: Text('Video')),
                ],
                selected: {kind},
                onSelectionChanged: (s) => setSheet(() => kind = s.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle:
                      WidgetStatePropertyAll(TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: name,
              style: const TextStyle(color: AppColors.darkText, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: AppColors.darkTextM, fontSize: 13),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.darkBorder)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accent)),
              ),
            ),
            TextField(
              controller: link,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              keyboardType: TextInputType.url,
              style: const TextStyle(color: AppColors.darkText, fontSize: 14),
              decoration: InputDecoration(
                labelText: lane != 'runpod'
                    ? 'Space · paste the full link or user/space'
                    : kind == 'video'
                        ? 'LoRA repo · HF link (the Wan base is built in)'
                        : 'HF repo · paste the full link or user/model',
                labelStyle:
                    const TextStyle(color: AppColors.darkTextM, fontSize: 13),
                enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.darkBorder)),
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accent)),
              ),
            ),
            if (lane == 'runpod')
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'RunPod entries live only on this device and spend only from your endpoint.',
                  style: TextStyle(color: AppColors.darkTextD, fontSize: 12),
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent),
                onPressed: checking
                    ? null
                    : () async {
                        if (name.text.trim().isEmpty ||
                            link.text.trim().isEmpty) {
                          setSheet(() => error = 'Name and link are both required');
                          return;
                        }
                        setSheet(() {
                          checking = true;
                          error = null;
                        });
                        final (err, endpoint, fnIndex) = await _svc.validate(
                            lane, link.text.trim(),
                            kind: lane == 'runpod' ? kind : 'image');
                        // UI audit 2026-11-06 (Codex P1-13): if the
                        // sheet was dismissed while validating, stop.
                        // No setSheet, no commit, no pop on a dead
                        // context.
                        if (!sheetCtx.mounted) return;
                        if (err != null) {
                          setSheet(() {
                            checking = false;
                            error = err;
                          });
                          return;
                        }
                        final e = ImageEntry(
                          id: 'e${DateTime.now().millisecondsSinceEpoch}',
                          name: name.text.trim(),
                          link: ImageGenService.normalizeLink(
                              lane, link.text),
                          lane: lane,
                          endpoint: endpoint.isEmpty ? '/generate' : endpoint,
                          fnIndex: fnIndex,
                          createdMs: DateTime.now().millisecondsSinceEpoch,
                          kind: lane == 'runpod' ? kind : 'image',
                        );
                        _svc.addEntry(e);
                        if (!mounted) return;
                        setState(() {
                          _entries = _allEntries();
                          _current = e;
                        });
                        Navigator.of(sheetCtx).pop();
                        _toast('Added and selected');
                      },
                child: Text(checking ? 'Validating...' : 'Validate & add',
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetCtx).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.darkTextM, fontSize: 13)),
            ),
          ]),
        ),
      ),
    );
  }

  void _openRunpodSettings() {
    final endpoint = TextEditingController(text: _svc.runpodEndpoint);
    final key = TextEditingController(text: _svc.runpodKey);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkBgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 16, 18, MediaQuery.of(sheetCtx).viewInsets.bottom + 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('RunPod lane · your endpoint only',
                style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Stored only on this device. Never synced, never shared. Generations on this lane spend from your RunPod balance.',
            style: TextStyle(color: AppColors.darkTextM, fontSize: 12.5, height: 1.45),
          ),
          TextField(
            controller: endpoint,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            style: const TextStyle(color: AppColors.darkText, fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'Endpoint ID',
              labelStyle: TextStyle(color: AppColors.darkTextM, fontSize: 13),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.darkBorder)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accent)),
            ),
          ),
          TextField(
            controller: key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            style: const TextStyle(color: AppColors.darkText, fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'API key',
              labelStyle: TextStyle(color: AppColors.darkTextM, fontSize: 13),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.darkBorder)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accent)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: () {
                _svc.setRunpod(endpoint.text, key.text);
                Navigator.of(sheetCtx).pop();
                _toast(_svc.runpodReady
                    ? 'RunPod lane armed on this device'
                    : 'RunPod lane cleared');
              },
              child: const Text('Save',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(sheetCtx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.darkTextM, fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}

// Magic UI Border Beam mechanics: a 50px comet (gradient #ffaa40 -> #9c40ff
// -> transparent) travels the rounded-rect perimeter on a 6s linear loop.
/// Ticket 32: an inline clip player for a finished video item.
/// Owns its controller; loops; tap toggles play/pause.
class _VideoTile extends StatefulWidget {
  final String path;
  const _VideoTile({required this.path});

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  VideoPlayerController? _ctl;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.file(File(widget.path));
    _ctl = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c.setLooping(true);
      setState(() => _ready = true);
    }).catchError((_) {
      // UI audit 2026-11-06 (Codex P1-15): a failed init used to
      // spin forever; it now says so.
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 832 / 480,
        child: Container(
          color: AppColors.darkBgPanel,
          child: _failed
              ? const Center(
                  child: Text(
                    'This video could not be played.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.darkTextM),
                  ),
                )
              : (!_ready || c == null)
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accentHi),
                  ),
                )
              : GestureDetector(
                  onTap: () =>
                      setState(() => c.value.isPlaying ? c.pause() : c.play()),
                  child: Stack(alignment: Alignment.center, children: [
                    VideoPlayer(c),
                    if (!c.value.isPlaying)
                      Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0x99000000),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 30),
                      ),
                  ]),
                ),
        ),
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  final double t;
  const _BeamPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(16));
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.darkBorder;
    canvas.drawRRect(rrect, base);

    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    final total = metric.length;
    const comet = 50.0;
    final head = t * total;
    final tail = head - comet;
    final seg = metric.extractPath(tail < 0 ? 0 : tail, head);
    if (tail < 0) {
      final wrap = metric.extractPath(total + tail, total);
      canvas.drawPath(wrap, _segPaint(metric, total + tail, total));
    }
    canvas.drawPath(seg, _segPaint(metric, tail < 0 ? 0 : tail, head));
  }

  Paint _segPaint(ui.PathMetric m, double from, double to) {
    final a = m.getTangentForOffset(from)?.position ?? Offset.zero;
    final b = m.getTangentForOffset(to)?.position ?? Offset.zero;
    return Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = ui.Gradient.linear(
        a,
        b,
        const [Color(0x00000000), Color(0xFF9C40FF), Color(0xFFFFAA40)],
        const [0.0, 0.55, 1.0],
      );
  }

  @override
  bool shouldRepaint(_BeamPainter old) => old.t != t;
}

// Aceternity Sparkles field, founder-dimmed: particle alpha caps at 0.7.
class _SparklesField extends StatefulWidget {
  const _SparklesField();

  @override
  State<_SparklesField> createState() => _SparklesFieldState();
}

class _SparklesFieldState extends State<_SparklesField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<(double, double, double, double, double)> _dots;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 9))
      ..repeat();
    final rnd = math.Random(7);
    _dots = List.generate(110, (_) => (
          rnd.nextDouble(),
          rnd.nextDouble(),
          0.4 + rnd.nextDouble() * 0.8, // size factor
          rnd.nextDouble() * math.pi * 2, // phase
          0.5 + rnd.nextDouble() * 1.6, // twinkle speed
        ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _SparklesPainter(_dots, _ctrl.value * 9),
        size: Size.infinite,
      ),
    );
  }
}

class _SparklesPainter extends CustomPainter {
  final List<(double, double, double, double, double)> dots;
  final double time;
  const _SparklesPainter(this.dots, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    for (final (x, y, s, phase, speed) in dots) {
      final tw = (math.sin(time * speed + phase) + 1) / 2;
      final a = 0.7 * (0.15 + 0.85 * tw * tw);
      paint.color = Colors.white.withOpacity(a);
      canvas.drawCircle(
          Offset(x * size.width, y * size.height), s * 1.1, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklesPainter old) => old.time != time;
}
