// Previous Gens - the in-app gallery of every image MiniX has
// generated (Kai, 2026-11-04). Generations persist at completion
// (ImageGenService.recordGeneration): PNG in app files + a
// GenRecord index in the 'imagegen' Hive box. Local files only -
// the gallery works with Connectivity off.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/image_gen_service.dart';
import '../theme/app_colors.dart';

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
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Row(
            children: [
              const Text('Previous Gens',
                  style: TextStyle(
                      color: AppColors.darkText,
                      fontSize: 19,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                _records.isEmpty ? '' : '${_records.length} saved',
                style: const TextStyle(
                    color: AppColors.darkTextD, fontSize: 12.5),
              ),
            ],
          ),
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
        return GestureDetector(
          onTap: () => Get.to(() => _GenViewer(rec: rec, svc: _svc)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
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
        );
      },
    );
  }
}

class _GenViewer extends StatelessWidget {
  final GenRecord rec;
  final ImageGenService svc;
  const _GenViewer({required this.rec, required this.svc});

  String _when(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.month}/${d.day}/${d.year}  ${d.hour}:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 14, 4),
              child: Row(children: [
                IconButton(
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: AppColors.darkText, size: 19),
                ),
                const Text('Generation',
                    style: TextStyle(
                        color: AppColors.darkText,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
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
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(File(rec.file),
                            fit: BoxFit.cover, width: double.infinity),
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
                    ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
