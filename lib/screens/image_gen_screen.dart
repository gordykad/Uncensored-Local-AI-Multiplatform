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
import 'package:path_provider/path_provider.dart';

import '../models/image_entry.dart';
import '../services/image_gen_service.dart';
import '../services/log_service.dart';
import '../theme/app_colors.dart';
import '../widgets/faithful/nexus_velocity.dart';
import '../widgets/faithful/orb.dart';

class _Item {
  final String prompt;
  String status; // pending | done | error
  String phase;
  List<int>? bytes;
  int? seed;
  String? error;
  _Item(this.prompt)
      : status = 'pending',
        phase = 'Starting';
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
  String? _dissolving;
  late final AnimationController _beam;

  static const _placeholders = [
    'A lighthouse at dusk, cinematic',
    'Write a haiku about the ocean at midnight',
    'A portrait in neon rain, 35mm',
    'A cabin in snow under the aurora',
    'Explain quantum entanglement like I\'m five',
  ];
  int _phIndex = 0;
  Timer? _phTimer;

  bool _loggedBuild = false; // build 18 diagnostics

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
        vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
    _entries = _svc.localEntries();
    _current = _entries.isNotEmpty ? _entries.first : null;
    _diag('initState entries=${_entries.length} online=${_svc.connectivityOn}');
    _input.addListener(() => setState(() {}));
    _phTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (!mounted || _busy || _input.text.isNotEmpty) return;
      setState(() => _phIndex = (_phIndex + 1) % _placeholders.length);
    });
    if (_svc.connectivityOn) _loadPinned();
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
    final item = _Item(prompt.trim());
    setState(() {
      _busy = true;
      _phase = 'Starting';
      _items.add(item);
    });
    _scrollDown();
    try {
      final result = entry.isRunpod
          ? await _svc.generateRunpod(entry,
              prompt: item.prompt,
              onPhase: (p) => _setPhase(item, p))
          : await _svc.generateOwner(entry,
              prompt: item.prompt,
              onPhase: (p) => _setPhase(item, p));
      item.bytes = result.bytes;
      item.seed = result.seed;
      item.status = 'done';
    } catch (e) {
      item.status = 'error';
      item.error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _phase = '';
      });
      _scrollDown();
    }
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
    if (_busy || _dissolving != null) return;
    final text = _input.text.trim().isEmpty
        ? _placeholders[_phIndex]
        : _input.text.trim();
    setState(() => _dissolving = text);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedBuild) {
      _loggedBuild = true;
      _diag('first build');
    }
    final online = _online;
    final body = Column(
      children: [
        _header(online),
        if (!online) _veil() else ...[
          _heroCard(),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 6),
      child: Row(
        children: [
          const Text('Image Gen',
              style: TextStyle(
                  color: AppColors.darkText,
                  fontSize: 19,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() => _svc.connectivityOn = !online);
              if (!online) _loadPinned();
            },
            child: Container(
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
                Text(online ? 'Connected' : 'Offline',
                    style: const TextStyle(
                        color: AppColors.darkTextM, fontSize: 12)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _veil() {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.cloud_off_rounded,
                color: AppColors.darkTextD, size: 40),
            SizedBox(height: 14),
            Text('Image generation is off',
                style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text(
              'Turn on Connectivity to use the hosted lanes. Your local models are unaffected.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.darkTextM, fontSize: 13.5, height: 1.5),
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
    );
  }

  Widget _threadWithSparkles() {
    return Stack(
      children: [
        const Positioned.fill(child: _SparklesField()),
        if (_items.isEmpty)
          const Center(
            child: Text('Describe an image to begin',
                style: TextStyle(color: AppColors.darkTextD, fontSize: 13.5)),
          )
        else
          ListView.builder(
            controller: _scroll,
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
            decoration: const BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(5),
              ),
            ),
            child: Text(item.prompt,
                style: const TextStyle(color: Colors.white, fontSize: 13.5)),
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
        else
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(Uint8List.fromList(item.bytes!), fit: BoxFit.cover),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text(
                '1024 x 1024${item.seed != null ? ' - seed ${item.seed}' : ''}',
                style: const TextStyle(
                    color: AppColors.darkTextD, fontSize: 11.5),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _save(item),
                child: const Text('Save',
                    style: TextStyle(color: AppColors.accentHi, fontSize: 12.5)),
              ),
              TextButton(
                onPressed: _busy ? null : () => _generate('${item.prompt} '),
                child: const Text('Re-roll',
                    style: TextStyle(color: AppColors.accentHi, fontSize: 12.5)),
              ),
            ]),
          ]),
      ]),
    );
  }

  Future<void> _save(_Item item) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/images');
      if (!await folder.exists()) await folder.create(recursive: true);
      final f = File(
          '${folder.path}/gen_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(item.bytes!);
      _toast('Saved to app files');
    } catch (e) {
      _toast('Save failed: $e');
    }
  }

  Widget _pickerRow() {
    final e = _current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: Row(children: [
        GestureDetector(
          onTap: _openPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.darkBgPanel,
              border: Border.all(color: AppColors.darkBorder),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 15, color: AppColors.accentHi),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(e?.name ?? 'No model',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.darkText, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  e == null ? 'none' : (e.isRunpod ? 'RunPod' : 'Hosted'),
                  style: const TextStyle(
                      color: AppColors.accentHi, fontSize: 10.5),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more_rounded,
                  size: 16, color: AppColors.darkTextM),
            ]),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: _openRunpodSettings,
          icon: const Icon(Icons.tune_rounded,
              size: 19, color: AppColors.darkTextM),
          tooltip: 'Lane settings',
        ),
      ]),
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
                  style: TextStyle(
                      color: _dissolving == null
                          ? AppColors.darkText
                          : Colors.transparent,
                      fontSize: 14),
                  cursorColor: _dissolving == null
                      ? AppColors.accent
                      : Colors.transparent,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: (_) => _send(),
                ),
                if (_input.text.isEmpty && _dissolving == null)
                  IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
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
            GestureDetector(
              onTap: _busy ? null : _send,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _busy
                      ? AppColors.darkBgHover
                      : AppColors.accent,
                ),
                child: Icon(
                  _busy ? Icons.hourglass_top_rounded : Icons.arrow_upward_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ]),
        ),
        if (_dissolving != null)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(19, 15, 60, 4),
              child: DisintegratingText(
                text: _dissolving!,
                color: AppColors.darkText,
                fontSize: 14,
                onDone: () {
                  final text = _dissolving!;
                  if (mounted) setState(() => _dissolving = null);
                  _input.clear();
                  _generate(text);
                },
              ),
            ),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Models',
                  style: TextStyle(
                      color: AppColors.darkText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          for (final e in _entries)
            ListTile(
              dense: true,
              leading: Icon(
                e.id == _current?.id
                    ? Icons.check_circle_rounded
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
                e.isRunpod
                    ? 'RunPod - your endpoint only'
                    : (e.remote ? 'Hosted - pinned by you' : 'Hosted'),
                style: const TextStyle(
                    color: AppColors.darkTextD, fontSize: 11.5),
              ),
              trailing: (e.pinned && !e.remote)
                  ? const Icon(Icons.push_pin_rounded,
                      size: 15, color: AppColors.accentHi)
                  : null,
              onTap: () {
                setState(() => _current = e);
                Navigator.of(sheetCtx).pop();
              },
              onLongPress: () {
                Navigator.of(sheetCtx).pop();
                _entryActions(e);
              },
            ),
          const Divider(color: AppColors.darkBorderFaint, height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.add_rounded,
                color: AppColors.accentHi, size: 19),
            title: const Text('Add entry',
                style: TextStyle(color: AppColors.darkText, fontSize: 13.5)),
            subtitle: const Text('Paste a link - validated before it is added',
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
              leading: const Icon(Icons.push_pin_rounded,
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
                setState(() => _entries = _svc.localEntries());
                Navigator.of(sheetCtx).pop();
                _toast(e.pinned ? 'Unpinned' : 'Pinned - it will publish to all profiles');
              },
            ),
          ListTile(
            dense: true,
            leading:
                const Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 19),
            title: const Text('Delete entry',
                style: TextStyle(color: AppColors.red, fontSize: 13.5)),
            onTap: () {
              _svc.removeEntry(e.id);
              setState(() {
                _entries = _svc.localEntries();
                if (_current?.id == e.id) {
                  _current = _entries.isNotEmpty ? _entries.first : null;
                }
              });
              Navigator.of(sheetCtx).pop();
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
              style: const TextStyle(color: AppColors.darkText, fontSize: 14),
              decoration: InputDecoration(
                labelText: lane == 'runpod'
                    ? 'Hugging Face repo (user/model-GGUF)'
                    : 'Space link (huggingface.co/spaces/...)',
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
                        final (err, endpoint, fnIndex) =
                            await _svc.validate(lane, link.text.trim());
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
                          link: link.text.trim(),
                          lane: lane,
                          endpoint: endpoint.isEmpty ? '/generate' : endpoint,
                          fnIndex: fnIndex,
                          createdMs: DateTime.now().millisecondsSinceEpoch,
                        );
                        _svc.addEntry(e);
                        if (!mounted) return;
                        setState(() {
                          _entries = _svc.localEntries();
                          _current = e;
                        });
                        Navigator.of(sheetCtx).pop();
                        _toast('Added and selected');
                      },
                child: Text(checking ? 'Validating...' : 'Validate & add',
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
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
            child: Text('RunPod lane - your endpoint only',
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
        ]),
      ),
    );
  }
}

// Magic UI Border Beam mechanics: a 50px comet (gradient #ffaa40 -> #9c40ff
// -> transparent) travels the rounded-rect perimeter on a 6s linear loop.
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
