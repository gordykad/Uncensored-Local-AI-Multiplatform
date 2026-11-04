import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../controllers/model_controller.dart';
import '../services/model_manager.dart';
import '../services/model_pins_service.dart';
import '../services/mesh_service.dart';
import '../services/custom_connections_service.dart';
import '../models/ai_model_info.dart';
import '../widgets/model_card.dart';
import '../widgets/faithful/gravity.dart';
import '../widgets/faithful/trace_pickers.dart';
import '../widgets/faithful/controls_meta.dart';
import '../widgets/faithful/textfx.dart';

class ModelLibraryScreen extends StatelessWidget {
  final bool embedded;
  const ModelLibraryScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      return _ModelLibraryBody(showBackButton: false);
    }
    return Scaffold(
      backgroundColor: context.bg,
      body: _ModelLibraryBody(showBackButton: true),
    );
  }
}

enum _Filter { all, downloaded, uncensored, custom }

class _ModelLibraryBody extends StatefulWidget {
  final bool showBackButton;
  const _ModelLibraryBody({this.showBackButton = false});

  @override
  State<_ModelLibraryBody> createState() => _ModelLibraryBodyState();
}

class _ModelLibraryBodyState extends State<_ModelLibraryBody> {
  _Filter _filter = _Filter.all;
  // Ticket 30: fleet pins (config-fetched) + founder pin flags.
  final _pinsSvc = ModelPinsService();
  List<AiModelInfo> _pinned = [];
  Set<String> _flagged = {};
  // Ticket 31: mesh catalog + node models (fetched live, cached last-good).
  final _meshSvc = MeshService();
  final _connSvc = CustomConnectionsService();
  List<MeshSeat> _meshSeats = [];
  List<MeshNodeModel> _nodeModels = [];
  bool _meshStale = false;

  @override
  void initState() {
    super.initState();
    _flagged = _pinsSvc.flaggedPins();
    _pinsSvc.fetchPinned().then((p) {
      if (mounted) setState(() => _pinned = p);
    });
    if (_meshSvc.connectivityOn) {
      final before = _meshSvc.catalogFetchedAt;
      _meshSvc.fetchSeats().then((s) {
        if (mounted) {
          setState(() {
            _meshSeats = s;
            _meshStale = s.isNotEmpty && _meshSvc.catalogFetchedAt == before;
          });
        }
      });
      _meshSvc.fetchNodeModels().then((n) {
        if (mounted) setState(() => _nodeModels = n);
      });
    }
  }
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<ModelController>();
    final manager = Get.find<ModelManager>();

    return Column(
      children: [
        // ── Top bar ──────────────────────────────────
        Container(
          padding: EdgeInsets.only(
            top: widget.showBackButton ? MediaQuery.of(context).padding.top : 0,
            left: 4,
            right: 4,
          ),
          decoration: BoxDecoration(
            color: context.bg,
            border: Border(
              bottom: BorderSide(color: context.border, width: 0.5),
            ),
          ),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                if (widget.showBackButton)
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.text),
                    onPressed: () => Get.back(),
                  ),
                if (!widget.showBackButton) const SizedBox(width: 12),
                BlurReveal(
                  text: 'Models',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: context.text,
                  ),
                ),
                const Spacer(),
                _ImportButton(ctrl: ctrl),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),

        // ── Search (ticket 08: #6 Search Input Group, live-filters) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SearchInputGroup(
            label: 'Models',
            controller: _searchCtrl,
            hint: 'Search models',
            onChanged: (q) => setState(() => _query = q.trim()),
          ),
        ),

        // ── Filter chips ─────────────────────────────
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _chip(context, 'All', _Filter.all),
              _chip(context, 'Downloaded', _Filter.downloaded),
              _chip(context, 'Uncensored', _Filter.uncensored),
              _chip(context, 'Custom', _Filter.custom),
            ],
          ),
        ),

        // ── Body ─────────────────────────────────────
        Expanded(
          child: Obx(() {
            final allCatalog = ctrl.catalog.toList();
            final downloaded = manager.downloadedModels.toList();
            final _ = manager.activeDownloads.length;
            // ignore: unused_local_variable
            final tick = manager.tick.value;

            // Apply filter
            List<AiModelInfo> filtered;
            switch (_filter) {
              case _Filter.downloaded:
                filtered = allCatalog
                    .where((m) => downloaded.contains(m.filename))
                    .toList();
                break;
              case _Filter.uncensored:
                filtered = allCatalog.where((m) => m.isUncensored).toList();
                break;
              case _Filter.custom:
                filtered = allCatalog.where((m) => m.isCustom).toList();
                break;
              case _Filter.all:
              default:
                filtered = allCatalog;
            }

            // Always sort the active model to the top if it's in the filtered list
            final activeFilename = ctrl.selectedModelFilename.value;
            if (activeFilename != null) {
              filtered.sort((a, b) {
                if (a.filename == activeFilename) return -1;
                if (b.filename == activeFilename) return 1;
                return 0; // maintain relative order for the rest
              });
            }

            if (_query.isNotEmpty) {
              filtered = filtered
                  .where((m) =>
                      m.name.toLowerCase().contains(_query.toLowerCase()))
                  .toList();
            }

            if (allCatalog.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: ChatThreadSkeleton(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No models in catalog.',
                      style: TextStyle(color: context.textD, fontSize: 14),
                    ),
                  ],
                ),
              );
            }

            if (filtered.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GravityStars(height: 150),
                    const SizedBox(height: 12),
                    Text(
                      'No models match this filter.',
                      style: TextStyle(color: context.textD, fontSize: 14),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // ── Pinned for the fleet (ticket 30) ─────
                if (_filter == _Filter.all && _query.isEmpty)
                  ..._pinnedSection(context, ctrl, manager, allCatalog,
                      downloaded),

                // ── Mesh seats + custom connections (ticket 31) ──
                if (_filter == _Filter.all && _query.isEmpty) ...[
                  ..._meshSection(context, ctrl),
                  ..._customSection(context, ctrl),
                ],

                // ── Local files not in catalog ──────────
                if (_filter == _Filter.all ||
                    _filter == _Filter.downloaded) ...[
                  ...downloaded
                      .where((f) => !allCatalog.any((m) => m.filename == f))
                      .map((f) => _localFileCard(context, ctrl, f)),
                ],

                // ── Count ───────────────────────────────
                _sectionTitle(
                  context,
                  '${_filter == _Filter.all ? "Available" : _filter.name[0].toUpperCase() + _filter.name.substring(1)} Models (${filtered.length})',
                ),
                const SizedBox(height: 12),

                // ── Model cards ─────────────────────────
                ...List.generate(filtered.length, (index) {
                  final model = filtered[index];
                  final isDl = downloaded.contains(model.filename);
                  final isActiveDownload = manager.isDownloading(
                    model.filename,
                  );
                  final dlState = manager.getDownloadState(model.filename);

                  return Column(
                    children: [
                      GestureDetector(
                        onLongPress: model.hasRemoteUrl
                            ? () => _pinSheet(context, model)
                            : null,
                        child: ModelCard(
                        model: model,
                        isDownloaded: isDl,
                        isCurrentlyDownloading: isActiveDownload,
                        downloadState: dlState,
                        isLoaded:
                            ctrl.selectedModelFilename.value ==
                                model.filename &&
                            ctrl.isModelLoaded,
                        isLoadingModel:
                            ctrl.loadingModelFilename.value == model.filename,
                        loadingStatusMsg: ctrl.loadingStatusMsg.value,
                        loadingProgress: ctrl.loadingProgress.value,
                        onDownload: () => ctrl.downloadModel(model),
                        onCancelDownload: () =>
                            ctrl.cancelDownload(model.filename),
                        onLoad: () => ctrl.loadModel(model.filename),
                        onDelete: () => _confirmDelete(context, ctrl, model),
                        onRemoveCustom: () =>
                            _confirmRemoveCustom(context, ctrl, model),
                        onAddLink: model.isCustom
                            ? () => _showSetLinkDialog(context, ctrl, model)
                            : null,
                        onCancelLoad: () => ctrl.cancelLoadModel(),
                        onUnload: () => ctrl.unloadCurrentModel(),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(
                    delay: Duration(milliseconds: index * 50),
                    duration: 250.ms,
                  );
                }),

                const SizedBox(height: 24),
              ],
            );
          }),
        ),
      ],
    );
  }

  List<Widget> _pinnedSection(
    BuildContext context,
    ModelController ctrl,
    ModelManager manager,
    List<AiModelInfo> catalog,
    List<String> downloaded,
  ) {
    final fresh = _pinned
        .where((p) => !catalog.any((m) => m.filename == p.filename))
        .toList();
    if (fresh.isEmpty) return const [];
    return [
      _sectionTitle(context, 'Pinned'),
      const SizedBox(height: 12),
      for (final p in fresh)
        ModelCard(
          model: p,
          isDownloaded: downloaded.contains(p.filename),
          isCurrentlyDownloading: manager.isDownloading(p.filename),
          downloadState: manager.getDownloadState(p.filename),
          isLoaded: ctrl.selectedModelFilename.value == p.filename &&
              ctrl.isModelLoaded,
          isLoadingModel: ctrl.loadingModelFilename.value == p.filename,
          loadingStatusMsg: ctrl.loadingStatusMsg.value,
          loadingProgress: ctrl.loadingProgress.value,
          onDownload: () => ctrl.downloadModel(p),
          onCancelDownload: () => ctrl.cancelDownload(p.filename),
          onLoad: () => ctrl.loadModel(p.filename),
          onDelete: () => _confirmDelete(context, ctrl, p),
          onRemoveCustom: () => _confirmRemoveCustom(context, ctrl, p),
          onAddLink: null,
          onCancelLoad: () => ctrl.cancelLoadModel(),
          onUnload: () => ctrl.unloadCurrentModel(),
        ),
      const SizedBox(height: 8),
    ];
  }

  // ── Ticket 31 sections ──────────────────────────────────────

  Widget _remoteRow(
    BuildContext context,
    ModelController ctrl, {
    required Map<String, dynamic> source,
    required String title,
    required String sub,
    required String badge,
    required Color badgeColor,
    required IconData icon,
  }) {
    final sel = ctrl.selectedRemote.value;
    final selected =
        sel != null && sel['kind'] == source['kind'] && sel['id'] == source['id'];
    return GestureDetector(
      onTap: () {
        if (selected) {
          ctrl.clearRemote();
        } else {
          ctrl.selectRemote(source);
        }
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.bgPanel,
            content: Text(
              selected
                  ? 'Back to your local models'
                  : '${source['label']} will answer in chat now',
              style: TextStyle(color: context.text),
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.bgPanel,
          border: Border.all(
              color: selected ? AppColors.accent : context.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: selected ? AppColors.accent : context.textM),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 13, color: context.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11, color: context.textM),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: badgeColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                    letterSpacing: 0.4),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              const Text(
                'Answering',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _meshSection(BuildContext context, ModelController ctrl) {
    if (!_meshSvc.connectivityOn) return const [];
    if (_meshSeats.isEmpty && _nodeModels.isEmpty) return const [];
    final widgets = <Widget>[
      _sectionTitle(context, 'Mesh - Astro OS lanes via your PC'),
      const SizedBox(height: 4),
      Text(
        _meshStale
            ? 'Cached catalog - your PC mesh is unreachable right now'
            : 'Live catalog from your PC mesh',
        style: TextStyle(fontSize: 11, color: context.textM),
      ),
      const SizedBox(height: 12),
    ];
    for (final nm in _nodeModels) {
      widgets.add(_remoteRow(
        context,
        ctrl,
        source: {
          'kind': 'mesh',
          'id': 'node:${nm.node}:${nm.name}',
          'label': nm.name,
          'model': nm.name,
        },
        title: nm.name,
        sub: 'On your ${nm.node} node',
        badge: 'NODE',
        badgeColor: AppColors.accent,
        icon: Icons.computer_outlined,
      ));
    }
    const groupOrder = ['paid', 'trial', 'free', 'local', 'compute'];
    final byGroup = <String, List<MeshSeat>>{};
    for (final s in _meshSeats) {
      byGroup.putIfAbsent(s.group, () => []).add(s);
    }
    for (final g in groupOrder) {
      final seats = byGroup[g];
      if (seats == null || seats.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(
          g.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textD,
              letterSpacing: 0.6),
        ),
      ));
      for (final s in seats) {
        widgets.add(_remoteRow(
          context,
          ctrl,
          source: {
            'kind': 'mesh',
            'id': 'mesh:${s.lane}:${s.model}',
            'label': s.model,
            'model': s.model,
          },
          title: s.model,
          sub: s.lane,
          badge: s.proven ? 'PROVEN' : 'UNVERIFIED',
          badgeColor: s.proven ? AppColors.green : context.textM,
          icon: Icons.hub_outlined,
        ));
      }
    }
    widgets.add(const SizedBox(height: 16));
    return widgets;
  }

  List<Widget> _customSection(BuildContext context, ModelController ctrl) {
    if (!_connSvc.connectivityOn) return const [];
    final conns = _connSvc.list();
    if (conns.isEmpty) return const [];
    final widgets = <Widget>[
      _sectionTitle(context, 'Custom connections'),
      const SizedBox(height: 4),
      Text(
        'Your own URL/API seats - they answer straight from this phone',
        style: TextStyle(fontSize: 11, color: context.textM),
      ),
      const SizedBox(height: 12),
    ];
    for (final c in conns) {
      widgets.add(_remoteRow(
        context,
        ctrl,
        source: {
          'kind': 'custom',
          'id': c.id,
          'label': c.name,
          'model': c.model,
        },
        title: c.name,
        sub: '${c.model} - ${c.type == 'ollama' ? 'Ollama API' : 'OpenAI API'}',
        badge: 'CUSTOM',
        badgeColor: AppColors.accent,
        icon: Icons.link_outlined,
      ));
    }
    widgets.add(const SizedBox(height: 16));
    return widgets;
  }

  void _pinSheet(BuildContext context, AiModelInfo model) {
    final isPinned = _flagged.contains(model.filename);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: AppColors.accent,
              ),
              title: Text(
                isPinned ? 'Unpin from the fleet' : 'Pin for everyone',
                style: TextStyle(color: context.text),
              ),
              subtitle: Text(
                isPinned
                    ? 'The offer leaves the fleet list when the shared config updates. Downloaded copies stay.'
                    : 'Everyone with MiniX sees this model in a Pinned section and chooses for themselves whether to download it.',
                style: TextStyle(color: context.textM, fontSize: 12),
              ),
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                await _pinsSvc.setFlagged(model.filename, !isPinned);
                setState(() => _flagged = _pinsSvc.flaggedPins());
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: context.bgPanel,
                    content: Text(
                      isPinned
                          ? 'Unpinned here. It leaves the fleet list when the config updates.'
                          : 'Pin flagged. It goes live for the fleet when the shared config updates.',
                      style: TextStyle(color: context.text),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, _Filter filter) {
    final selected = _filter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : context.textM,
          ),
        ),
        selected: selected,
        onSelected: (_) => setState(() => _filter = filter),
        selectedColor: AppColors.accent,
        backgroundColor: context.bgPanel,
        side: BorderSide(color: selected ? AppColors.accent : context.border),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _localFileCard(
    BuildContext context,
    ModelController ctrl,
    String filename,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 18, color: context.textM),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              filename,
              style: TextStyle(fontSize: 13, color: context.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => ctrl.loadModel(filename),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Load',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.textM,
        letterSpacing: 0.3,
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    ModelController ctrl,
    AiModelInfo model,
  ) {
    final keepNote = model.isCustom
        ? (model.hasRemoteUrl
            ? '\n\nIt stays in your library — you can redownload it anytime.'
            : '\n\nIt stays in your library, but without a download link it cannot be redownloaded.')
        : '';
    Get.dialog(
      AlertDialog(
        backgroundColor: context.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Model File', style: TextStyle(color: context.text)),
        content: Text(
          'Delete ${model.name}? (${model.sizeGb} GB will be freed)$keepNote',
          style: TextStyle(color: context.textM),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Cancel', style: TextStyle(color: context.textD)),
          ),
          ElevatedButton(
            onPressed: () {
              ctrl.deleteModel(model.filename);
              Get.back();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              elevation: 0,
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveCustom(
    BuildContext context,
    ModelController ctrl,
    AiModelInfo model,
  ) {
    Get.dialog(
      AlertDialog(
        backgroundColor: context.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Remove Custom Model',
          style: TextStyle(color: context.text),
        ),
        content: Text(
          'Remove "${model.name}" from your library?\nThis will also delete the downloaded file if any.',
          style: TextStyle(color: context.textM),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Cancel', style: TextStyle(color: context.textD)),
          ),
          ElevatedButton(
            onPressed: () {
              ctrl.deleteCustomModel(model);
              Get.back();
              Get.snackbar(
                'Removed',
                '${model.name} removed from library.',
                snackPosition: SnackPosition.BOTTOM,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              elevation: 0,
            ),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSetLinkDialog(
    BuildContext context,
    ModelController ctrl,
    AiModelInfo model,
  ) {
    final urlCtrl =
        TextEditingController(text: model.hasRemoteUrl ? model.url : '');

    Get.dialog(
      AlertDialog(
        backgroundColor: context.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Download Link', style: TextStyle(color: context.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attach a Hugging Face or GitHub link for "${model.name}" so it can be redownloaded after the file is deleted.',
              style: TextStyle(color: context.textM, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: TextStyle(color: context.text, fontSize: 14),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Download URL',
                labelStyle: TextStyle(color: context.textD, fontSize: 13),
                hintText: 'https://huggingface.co/.../model.gguf',
                hintStyle: TextStyle(color: context.textD.withOpacity(0.5)),
                filled: true,
                fillColor: context.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Cancel', style: TextStyle(color: context.textD)),
          ),
          ElevatedButton(
            onPressed: () {
              final url = urlCtrl.text.trim();
              if (url.isEmpty) {
                Get.snackbar(
                  'Missing URL',
                  'Paste a download link first.',
                  snackPosition: SnackPosition.BOTTOM,
                );
                return;
              }
              Get.back();
              ctrl.setCustomModelUrl(model, url);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Save Link',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill button for the import action
class _ImportButton extends StatelessWidget {
  final ModelController ctrl;
  const _ImportButton({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _showImportOptions(context),
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 18, color: Colors.white),
              SizedBox(width: 4),
              Text(
                'Import',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.textD,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Import Model',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.text,
                ),
              ),
              const SizedBox(height: 16),
              _importTile(
                context,
                icon: Icons.file_open_rounded,
                color: AppColors.accentHi,
                title: 'Import .gguf File',
                subtitle: 'Select a single model file',
                onTap: () {
                  Navigator.pop(context);
                  ctrl.importModelFromFile();
                },
              ),
              _importTile(
                context,
                icon: Icons.folder_open_rounded,
                color: AppColors.green,
                title: 'Import from Folder',
                subtitle: 'Scan folder for .gguf files',
                onTap: () {
                  Navigator.pop(context);
                  ctrl.importFromDirectory();
                },
              ),
              _importTile(
                context,
                icon: Icons.link_rounded,
                color: AppColors.orange,
                title: 'Add from URL',
                subtitle: 'Download a .gguf model from a URL',
                onTap: () {
                  Navigator.pop(context);
                  _showAddUrlDialog(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _importTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: TextStyle(color: context.text, fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: context.textD, fontSize: 12),
      ),
      onTap: onTap,
    );
  }

  void _showAddUrlDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    Get.dialog(
      AlertDialog(
        backgroundColor: context.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add Model from URL',
          style: TextStyle(color: context.text),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: context.text, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Model Name',
                labelStyle: TextStyle(color: context.textD, fontSize: 13),
                hintText: 'e.g. Mistral 7B Uncensored',
                hintStyle: TextStyle(color: context.textD.withOpacity(0.5)),
                filled: true,
                fillColor: context.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: TextStyle(color: context.text, fontSize: 14),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Download URL',
                labelStyle: TextStyle(color: context.textD, fontSize: 13),
                hintText: 'https://huggingface.co/.../model.gguf',
                hintStyle: TextStyle(color: context.textD.withOpacity(0.5)),
                filled: true,
                fillColor: context.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Cancel', style: TextStyle(color: context.textD)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isEmpty || url.isEmpty) {
                Get.snackbar(
                  'Missing Info',
                  'Please enter both name and URL.',
                  snackPosition: SnackPosition.BOTTOM,
                );
                return;
              }
              if (!url.startsWith('http')) {
                Get.snackbar(
                  'Invalid URL',
                  'URL must start with http:// or https://',
                  snackPosition: SnackPosition.BOTTOM,
                );
                return;
              }
              Get.back();
              ctrl.addCustomUrlModel(name: name, url: url);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Add Model',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
