// Previous Gens - the in-app gallery of every image MiniX has
// generated (Kai, 2026-11-04). Generations persist at completion
// (ImageGenService.recordGeneration): PNG in app files + a
// GenRecord index in the 'imagegen' Hive box. Local files only -
// the gallery works with Connectivity off. Ticket 32: clips live
// here too (kind 'video', mp4 files, playable in the viewer).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../services/image_gen_service.dart';
import '../services/media_save_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../widgets/tab_header.dart';

class GenGalleryScreen extends StatefulWidget {
  final bool embedded;
  const GenGalleryScreen({super.key, this.embedded = false});

  @override
  State<GenGalleryScreen> createState() => _GenGalleryScreenState();
}

class _GenGalleryScreenState extends State<GenGalleryScreen> {
  final _svc = ImageGenService();
  List<GenRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
    ImageGenService.historyRevision.addListener(_load);
  }

  @override
  void dispose() {
    ImageGenService.historyRevision.removeListener(_load);
    super.dispose();
  }

  void _load() {
    if (!mounted) return;
    setState(() => _records = _svc.history());
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        // Shared TabHeader (audit P2-10). Back stays maybePop: as
        // a pushed page it must never trap the user (Kai, 2026-11-04).
        TabHeader(
          title: 'Previous Gens',
          showBackButton: true,
          onBack: () => Navigator.of(context).maybePop(),
          trailing: [
            Text(
              _records.isEmpty ? '' : '${_records.length} saved',
              style: const TextStyle(
                  color: AppColors.darkTextD, fontSize: 12.5),
            ),
            const SizedBox(width: 14),
          ],
        ),
        Expanded(child: _records.isEmpty ? _empty() : _grid()),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
        backgroundColor: AppColors.darkBg, body: SafeArea(child: body));
  }

  Widget _empty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.photo_library_outlined,
              color: AppColors.darkTextD, size: 40),
          SizedBox(height: 14),
          Text('No generations yet',
              style: TextStyle(
                  color: AppColors.darkText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text(
            'Every image you generate is saved here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.darkTextM, fontSize: 13.5, height: 1.5),
          ),
        ]),
      ),
    );
  }

  Widget _grid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _records.length,
      itemBuilder: (_, i) {
        final rec = _records[i];
        // UI audit 2026-11-06 (Codex P1-7): tiles announce what
        // they are - media type plus the prompt that made them.
        return Semantics(
          button: true,
          label:
              '${rec.isVideo ? 'Video' : 'Image'}: ${rec.prompt}',
          child: GestureDetector(
          onTap: () => Get.to(() => _GenViewer(rec: rec, svc: _svc)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: rec.isVideo
                ? Container(
                    color: AppColors.darkBgPanel,
                    child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_circle_outline_rounded,
                              color: AppColors.accentHi, size: 30),
                          SizedBox(height: 4),
                          Text('VIDEO',
                              style: TextStyle(
                                  color: AppColors.darkTextD,
                                  fontSize: 9,
                                  letterSpacing: 1.2)),
                        ]),
                  )
                : Image.file(
                    File(rec.file),
                    fit: BoxFit.cover,
                    cacheWidth: 360,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.darkBgPanel,
                      child: const Icon(Icons.broken_image_outlined,
                          color: AppColors.darkTextD, size: 22),
                    ),
                  ),
          ),
          ),
        );
      },
    );
  }
}

/// Full-view clip player (ticket 32): autoplays, loops, tap toggles.
class _ClipView extends StatefulWidget {
  final String path;
  const _ClipView({required this.path});

  @override
  State<_ClipView> createState() => _ClipViewState();
}

class _ClipViewState extends State<_ClipView> {
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
      // UI audit 2026-11-06: no autoplay under Reduce Motion, and a
      // failed init surfaces instead of spinning forever (P1-15).
      if (!MediaQuery.disableAnimationsOf(context)) c.play();
      setState(() => _ready = true);
    }).catchError((_) {
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
    if (_failed) {
      return AspectRatio(
        aspectRatio: 832 / 480,
        child: Center(
          child: Text(
            'This video could not be played.',
            style: TextStyle(fontSize: 12, color: context.textM),
          ),
        ),
      );
    }
    if (!_ready || c == null) {
      return const AspectRatio(
        aspectRatio: 832 / 480,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.accentHi),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
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
    );
  }
}

class _GenViewer extends StatelessWidget {
  final GenRecord rec;
  final ImageGenService svc;
  const _GenViewer({required this.rec, required this.svc});

  String _when(int ts) => DateFormat('M/d/yyyy  HH:mm')
      .format(DateTime.fromMillisecondsSinceEpoch(ts));

  Future<void> _share() async {
    await SharePlus.instance
        .share(ShareParams(files: [XFile(rec.file)]));
  }

  Future<void> _save() async {
    final err =
        await MediaSaveService.saveToPhotos(rec.file, isVideo: rec.isVideo);
    Get.snackbar('Previous Gens', err ?? 'Saved to Photos.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.darkBgPanel,
        colorText: AppColors.darkText,
        duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabHeader(
              title: 'Generation',
              showBackButton: true,
              onBack: () => Get.back(),
              trailing: [
              TextButton(
                onPressed: () async {
                  // UI audit 2026-11-06 P1-5: permanent deletion
                  // confirms first (Codex P2-31).
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      backgroundColor: AppColors.darkBgPanel,
                      title: const Text('Delete this generation?',
                          style: TextStyle(color: AppColors.darkText)),
                      content: const Text(
                        'The file and its history entry will be removed. This cannot be undone.',
                        style: TextStyle(
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
                  if (sure != true) return;
                  await svc.deleteGeneration(rec);
                  Get.back();
                  Get.snackbar('Previous Gens', 'Deleted.',
                      snackPosition: SnackPosition.BOTTOM,
                      backgroundColor: AppColors.darkBgPanel,
                      colorText: AppColors.darkText,
                      duration: const Duration(seconds: 2));
                },
                child: const Text('Delete',
                    style: TextStyle(
                        color: AppColors.red, fontSize: 13.5)),
              ),
                const SizedBox(width: 6),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: rec.isVideo
                            ? _ClipView(path: rec.file)
                            // UI audit 2026-11-06 P2-12: pinch to zoom.
                            : InteractiveViewer(
                                minScale: 1,
                                maxScale: 4,
                                child: Image.file(File(rec.file),
                                    fit: BoxFit.cover,
                                    width: double.infinity),
                              ),
                      ),
                      const SizedBox(height: 14),
                      Text(rec.prompt,
                          style: const TextStyle(
                              color: AppColors.darkText,
                              fontSize: 14,
                              height: 1.5)),
                      const SizedBox(height: 10),
                      Text(
                        '${rec.model}  -  ${_when(rec.ts)}'
                        '${rec.seed != null ? '  -  seed ${rec.seed}' : ''}',
                        style: const TextStyle(
                            color: AppColors.darkTextD, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _share,
                              icon: const Icon(AppIcons.share, size: 16),
                              label: const Text('Share'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.darkText,
                                side: const BorderSide(
                                    color: AppColors.darkBorder),
                                textStyle: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _save,
                              icon: const Icon(AppIcons.download, size: 16),
                              label: const Text('Save to Photos'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.darkText,
                                side: const BorderSide(
                                    color: AppColors.darkBorder),
                                textStyle: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
