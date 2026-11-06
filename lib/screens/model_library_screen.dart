import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/type_scale.dart';
import '../controllers/model_controller.dart';
import '../services/model_manager.dart';
import '../services/model_classifier.dart';
import '../services/model_pins_service.dart';
import '../services/mesh_service.dart';
import '../services/haptics.dart';
import '../services/custom_connections_service.dart';
import '../models/ai_model_info.dart';
import '../widgets/model_card.dart';
import '../widgets/glass_folder.dart';
import '../widgets/tab_header.dart';
import '../widgets/faithful/gravity.dart';
import '../widgets/faithful/trace_pickers.dart';

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

enum _Filter {
  all,
  downloaded,
  uncensored,
  custom,
  chat,
  code,
  vision,
  reasoning,
  base,
}

class _ModelLibraryBody extends StatefulWidget {
  final bool showBackButton;
  const _ModelLibraryBody({this.showBackButton = false});

  @override
  State<_ModelLibraryBody> createState() => _ModelLibraryBodyState();
}

class _ModelLibraryBodyState extends State<_ModelLibraryBody> {
  _Filter _filter = _Filter.all;
  // Claude audit: a PageController built inside the builder
  // resets the Collections carousel to page one on every rebuild
  // (rebuilds fire every second during a download). It lives in
  // state and dies with it.
  final _collectionsPager = PageController(viewportFraction: 0.94);

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
  bool _meshTried = false;

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
            _meshTried = true;
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
  // Set when a folder file pick focuses the list on one model;
  // drives the "From <folder>" bar with the way back to the
  // full page (Kai hit a dead end here on 1.16.0).
  ({String collection, String model})? _folderFocus;
  int _collectionsPage = 0;

  @override
  void dispose() {
    _wakePoll?.cancel();
    _folderCardTimer?.cancel();
    _searchCtrl.dispose();
    _collectionsPager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<ModelController>();
    final manager = Get.find<ModelManager>();

    return Column(
      children: [
        // ── Top bar (shared TabHeader, audit P2-10) ──
        TabHeader(
          title: 'Models',
          showBackButton: widget.showBackButton,
          topInset:
              widget.showBackButton ? MediaQuery.of(context).padding.top : 0,
          trailing: [_ImportButton(ctrl: ctrl), const SizedBox(width: 8)],
        ),

        // ── Search (ticket 08: #6 Search Input Group, live-filters) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SearchInputGroup(
            label: 'Search',
            controller: _searchCtrl,
            hint: 'Search models',
            onChanged: (q) => setState(() => _query = q.trim()),
          ),
        ),

        // ── Filter chips ─────────────────────────────
        // UI audit 2026-11-06 (Claude P3-5): the row scrolls past
        // the right edge with no cue; a ShaderMask fade on the
        // trailing edge says there is more.
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Colors.black, Colors.black, Colors.transparent],
              stops: [0.0, 0.92, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _chip(context, 'All', _Filter.all),
              _chip(context, 'Downloaded', _Filter.downloaded),
              _chip(context, 'Uncensored', _Filter.uncensored),
              _chip(context, 'Custom', _Filter.custom),
              // Ticket 25: capability tag filters.
              _chip(context, 'Chat', _Filter.chat),
              _chip(context, 'Code', _Filter.code),
              _chip(context, 'Vision', _Filter.vision),
              _chip(context, 'Reasoning', _Filter.reasoning),
              _chip(context, 'Base', _Filter.base),
            ],
            ),
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
              case _Filter.chat:
              case _Filter.code:
              case _Filter.vision:
              case _Filter.reasoning:
              case _Filter.base:
                filtered = allCatalog
                    .where((m) => m.tags.contains(_filter.name))
                    .toList();
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
                  .where(
                    (m) => m.name.toLowerCase().contains(_query.toLowerCase()),
                  )
                  .toList();
            }

            if (allCatalog.isEmpty) {
              // UI audit 2026-11-06 (Codex P2-23): an empty catalog
              // is a state with a next step, not a loading skeleton
              // that never resolves.
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No models yet.',
                      style: TextStyle(color: context.text, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Import a GGUF file to get started.',
                      style: TextStyle(color: context.textD, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    // The same import affordance the header carries.
                    _ImportButton(ctrl: ctrl),
                  ],
                ),
              );
            }

            if (filtered.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TickerMode(
                      enabled: !RM.off(context),
                      child: const GravityStars(height: 150),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _query.isNotEmpty
                          ? 'No models match "$_query".'
                          : 'No models match this filter.',
                      style: TextStyle(color: context.textD, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _query = '';
                          _filter = _Filter.all;
                        });
                      },
                      child: const Text('Clear search and filters'),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // ── Glass folder collections (ticket 25) ──
                // The Astro OS pack, byte-identical, one folder per
                // tag collection. Picking a file filters the list
                // below to that model's card.
                if (_filter == _Filter.all && _query.isEmpty) ...[
                  _sectionTitle(context, 'Collections'),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 404,
                    child: Builder(
                      builder: (context) {
                        final cols = _collections(allCatalog, _meshSeats);
                        return PageView.builder(
                          controller: _collectionsPager,
                          itemCount: cols.length,
                          onPageChanged: (i) {
                            _folderCardTimer?.cancel();
                            setState(() => _collectionsPage = i);
                          },
                          itemBuilder: (context, i) {
                            final c = cols[i];
                            return Center(
                              child: GlassFolderPack(
                                label: c.label,
                                meta:
                                    '${c.files.length} ${c.files.length == 1 ? 'model' : 'models'}',
                                seed: 3 + c.index * 4,
                                files: [
                                  for (final f in c.files)
                                    (name: f.name, meta: f.meta),
                                ],
                                onOpenChange: (open) {
                                  _folderCardTimer?.cancel();
                                  if (!open) return;
                                  // Kai's 1.20.7 note: the contents
                                  // card waits for the FULL fan-out.
                                  // The pack's fan transitions run
                                  // ~1.2s plus a 40ms-per-depth
                                  // stagger; 1.4s read a tiny bit
                                  // late on Kai's phone (1.20.8), so
                                  // the card fires at 1.25s, right
                                  // on the visible settle.
                                  _folderCardTimer = Timer(
                                    const Duration(milliseconds: 1250),
                                    () {
                                      if (!mounted) return;
                                      _folderContentsCard(
                                        context,
                                        ctrl,
                                        c.label,
                                        c.files,
                                      );
                                    },
                                  );
                                },
                                onFileSelect: (idx) {
                                  // A file tap inside the window
                                  // means Kai already picked — the
                                  // pending card stands down.
                                  _folderCardTimer?.cancel();
                                  if (idx < 0 || idx >= c.files.length) {
                                    return;
                                  }
                                  final file = c.files[idx];
                                  final seat = file.seat;
                                  if (seat != null) {
                                    // Ticket 34: a fleet file opens
                                    // its provider's fleet sheet,
                                    // pre-filtered to that seat.
                                    _fleetSheet(
                                      context,
                                      ctrl,
                                      seat.lane,
                                      initialQuery: seat.model,
                                    );
                                    return;
                                  }
                                  final name = file.name;
                                  _searchCtrl.text = name;
                                  setState(() {
                                    _folderFocus = (
                                      collection: c.label,
                                      model: name,
                                    );
                                    _query = name;
                                  });
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Folder focus bar: the way back ──────
                  // UI audit 2026-11-06 (Claude P2-9, Codex P2-21):
                  // the pager gets dots + arrows (swipe is not the
                  // only door), and the caption says plainly that a
                  // folder previews its latest four while the full
                  // collection lives in the list below.
                  Builder(
                    builder: (context) {
                      final cols = _collections(allCatalog, _meshSeats);
                      if (cols.length < 2 && cols.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final count = cols.isEmpty
                          ? 0
                          : cols[_collectionsPage.clamp(0, cols.length - 1)]
                              .files
                              .length;
                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Previous collection',
                                icon: const Icon(Icons.chevron_left_rounded,
                                    size: 20),
                                color: context.textM,
                                onPressed: _collectionsPage > 0
                                    ? () => _collectionsPager.previousPage(
                                          duration:
                                              const Duration(milliseconds: 250),
                                          curve: Curves.easeOut,
                                        )
                                    : null,
                              ),
                              for (var i = 0; i < cols.length; i++)
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i == _collectionsPage
                                        ? context.text
                                        : context.border,
                                  ),
                                ),
                              IconButton(
                                tooltip: 'Next collection',
                                icon: const Icon(Icons.chevron_right_rounded,
                                    size: 20),
                                color: context.textM,
                                onPressed: _collectionsPage < cols.length - 1
                                    ? () => _collectionsPager.nextPage(
                                          duration:
                                              const Duration(milliseconds: 250),
                                          curve: Curves.easeOut,
                                        )
                                    : null,
                              ),
                            ],
                          ),
                          if (count > 4)
                            Text(
                              'Folder previews the latest 4 · all $count are in the list below',
                              style: TextStyle(
                                  color: context.textD, fontSize: 11),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                if (_folderFocus != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    // UI audit 2026-11-06 P2-2: the folder focus bar
                    // is state, not an action; neutral chrome.
                    decoration: BoxDecoration(
                      color: context.bgInput,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_open_outlined,
                          size: 16,
                          color: AppColors.accentHi,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'From ${_folderFocus!.collection}: ${_folderFocus!.model}',
                            style: TextStyle(fontSize: 12, color: context.text),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() {
                              _folderFocus = null;
                              _query = '';
                            });
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Show all',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accentHi,
                                ),
                              ),
                              SizedBox(width: 4),
                                Icon(
                                  Icons.close,
                                  size: 14,
                                  color: AppColors.accentHi,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Ticket 34 home layout ─────────────────
                // Folder, then what is ON the phone, then pins,
                // then the catalog, then the fleet. The locals
                // used to sit under ~290 inline mesh rows.
                if (_filter == _Filter.all && _query.isEmpty) ...[
                  if (downloaded.isNotEmpty) ...[
                    _sectionTitle(
                      context,
                      'On This Phone (${downloaded.length})',
                    ),
                    const SizedBox(height: 12),
                    ..._catalogCards(
                      context,
                      ctrl,
                      manager,
                      _downloadedFirst(allCatalog, downloaded, ctrl),
                      downloaded,
                    ),
                    ...downloaded
                        .where(
                          (f) => !allCatalog.any((m) => m.filename == f),
                        )
                        .map((f) => _localFileCard(context, ctrl, f)),
                    const SizedBox(height: 8),
                  ],

                  // ── Pinned for the fleet (ticket 30) ────
                  ..._pinnedSection(
                    context,
                    ctrl,
                    manager,
                    allCatalog,
                    downloaded,
                  ),

                  // ── Catalog: everything not on the phone ─
                  if (filtered.any(
                    (m) => !downloaded.contains(m.filename),
                  )) ...[
                    _sectionTitle(
                      context,
                      'Catalog Models (${filtered.where((m) => !downloaded.contains(m.filename)).length})',
                    ),
                    const SizedBox(height: 12),
                    ..._catalogCards(
                      context,
                      ctrl,
                      manager,
                      filtered
                          .where((m) => !downloaded.contains(m.filename))
                          .toList(),
                      downloaded,
                    ),
                  ],

                  // ── Mesh + custom (ticket 31), now last ──
                  ..._meshSection(context, ctrl),
                  ..._customSection(context, ctrl),
                ] else ...[
                  // ── Filtered / searching: one flat list ──
                  if (_filter == _Filter.all ||
                      _filter == _Filter.downloaded) ...[
                    ...downloaded
                        .where(
                          (f) => !allCatalog.any((m) => m.filename == f),
                        )
                        .map((f) => _localFileCard(context, ctrl, f)),
                  ],
                  _sectionTitle(
                    context,
                    '${_filter == _Filter.all ? "Available" : _filter.name[0].toUpperCase() + _filter.name.substring(1)} Models (${filtered.length})',
                  ),
                  const SizedBox(height: 12),
                  ..._catalogCards(context, ctrl, manager, filtered, downloaded),
                ],

                const SizedBox(height: 24),
              ],
            );
          }),
        ),
      ],
    );
  }

  /// Ticket 34: the downloaded slice of the catalog for the On
  /// This Phone section, loaded model first (same convention the
  /// flat list has always used).
  List<AiModelInfo> _downloadedFirst(
    List<AiModelInfo> all,
    List<String> downloaded,
    ModelController ctrl,
  ) {
    final out = all.where((m) => downloaded.contains(m.filename)).toList();
    final active = ctrl.selectedModelFilename.value;
    if (active != null) {
      out.sort((a, b) {
        if (a.filename == active) return -1;
        if (b.filename == active) return 1;
        return 0;
      });
    }
    return out;
  }

  /// One catalog card per model, exactly as the flat list has
  /// always rendered it. Ticket 34 extracted this so the On This
  /// Phone section and the catalog list share one implementation.
  List<Widget> _catalogCards(
    BuildContext context,
    ModelController ctrl,
    ModelManager manager,
    List<AiModelInfo> models,
    List<String> downloaded,
  ) {
    return List.generate(models.length, (index) {
      final model = models[index];
      final isDl = downloaded.contains(model.filename);
      final isActiveDownload = manager.isDownloading(model.filename);
      final dlState = manager.getDownloadState(model.filename);

      return Column(
        children: [
          GestureDetector(
            onLongPress: model.hasRemoteUrl
                ? () => _pinSheet(context, model)
                : model.isCustom
                ? () => _tagEditor(context, model)
                : null,
            child: ModelCard(
              onMore: model.hasRemoteUrl
                  ? () => _pinSheet(context, model)
                  : model.isCustom
                  ? () => _tagEditor(context, model)
                  : null,
              model: model,
              isDownloaded: isDl,
              isCurrentlyDownloading: isActiveDownload,
              downloadState: dlState,
              isLoaded:
                  ctrl.selectedModelFilename.value == model.filename &&
                  ctrl.isModelLoaded,
              isLoadingModel: ctrl.loadingModelFilename.value == model.filename,
              loadingStatusMsg: ctrl.loadingStatusMsg.value,
              loadingProgress: ctrl.loadingProgress.value,
              onDownload: () => ctrl.downloadModel(model),
              onCancelDownload: () => ctrl.cancelDownload(model.filename),
              onLoad: () => ctrl.loadModel(model.filename),
              onDelete: () => _confirmDelete(context, ctrl, model),
              onRemoveCustom: () => _confirmRemoveCustom(context, ctrl, model),
              onAddLink: model.isCustom
                  ? () => _showSetLinkDialog(context, ctrl, model)
                  : null,
              onCancelLoad: () => ctrl.cancelLoadModel(),
              onUnload: () => ctrl.unloadCurrentModel(),
            ),
          ),
        ],
      ).animate().fadeIn(
        // UI audit 2026-11-06 P2-7: no stagger under
        // Reduce Motion (zero delay + duration = static).
        delay: RM.off(context)
            ? Duration.zero
            : Duration(milliseconds: index * 50),
        duration: RM.off(context) ? Duration.zero : 250.ms,
      );
    });
  }

  /// Ticket 25: folder collections — All Models plus one folder
  /// per capability tag that has at least one model.
  List<
    ({
      String label,
      List<({String name, String meta, AiModelInfo? model, MeshSeat? seat})>
      files,
      int index,
    })
  >
  _collections(List<AiModelInfo> all, List<MeshSeat> seats) {
    ({String name, String meta, AiModelInfo? model, MeshSeat? seat}) modelFile(
      AiModelInfo m,
    ) => (
      name: m.name,
      meta: '${m.sizeGb} GB · ${_quantOf(m.filename)}',
      model: m,
      seat: null,
    );
    ({String name, String meta, AiModelInfo? model, MeshSeat? seat}) seatFile(
      MeshSeat s,
    ) => (name: s.model, meta: '${s.lane} · Mesh', model: null, seat: s);
    final orderedSeats = MeshService.pickerOrder(seats);
    final out =
        <
          ({
            String label,
            List<
              ({String name, String meta, AiModelInfo? model, MeshSeat? seat})
            >
            files,
            int index,
          })
        >[
          (
            label: 'All Models',
            files: [
              for (final m in all) modelFile(m),
              for (final s in orderedSeats) seatFile(s),
            ],
            index: 0,
          ),
        ];
    var i = 1;
    for (final t in ModelClassifier.tagOrder) {
      final files = [
        for (final m in all)
          if (m.tags.contains(t)) modelFile(m),
        for (final s in orderedSeats)
          if (ModelClassifier.classifyRemoteTags(s.model).contains(t))
            seatFile(s),
      ];
      if (files.isEmpty) continue;
      out.add((
        label: '${t[0].toUpperCase()}${t.substring(1)}',
        files: files,
        index: i++,
      ));
    }
    return out;
  }

  static String _quantOf(String filename) {
    final m = RegExp(
      r'(IQ\d+(_[A-Z0-9]+)?|Q\d+(_K(_[SMLX]+)?|_\d+)?|F16|BF16|F32)',
      caseSensitive: false,
    ).firstMatch(filename);
    return m?.group(0)?.toUpperCase() ?? 'GGUF';
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
          isLoaded:
              ctrl.selectedModelFilename.value == p.filename &&
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
    VoidCallback? tapOverride,
    VoidCallback? onLongPress,
    bool dimmed = false,
    Widget? trailing,
  }) {
    final sel = ctrl.selectedRemote.value;
    final selected =
        sel != null &&
        sel['kind'] == source['kind'] &&
        sel['id'] == source['id'];
    return GestureDetector(
      onLongPress: onLongPress,
      onTap:
          tapOverride ??
          () {
            TapFx.select();
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
            color: selected ? AppColors.accent : context.border,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppColors.accent : context.textM,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      color: dimmed ? context.textM : context.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 11,
                      color: dimmed ? context.textD : context.textM,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  letterSpacing: 0.4,
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              const Text(
                'Answering',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  // UI audit 2026-11-06 P2-5: accent at 11pt is
                  // 3.8:1; accentHi passes at 4.9:1.
                  color: AppColors.accentHi,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Sync build (mesh 0.20): the star flip, shared by seat + node rows.
  Widget _star(BuildContext context, String model, bool fav) {
    return IconButton(
      // UI audit 2026-11-06: 44pt target + a named favorite toggle.
      tooltip: fav ? 'Remove from favorites' : 'Add to favorites',
      icon: Icon(
        fav ? Icons.star : Icons.star_border,
        size: 19,
        color: fav ? AppColors.accentHi : context.textD,
      ),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      onPressed: () async {
        TapFx.select();
        final ok = await _meshSvc.setModelFavorite(model, !fav);
        if (!mounted || !ok) return;
        setState(() {
          _meshSeats = _meshSvc.cachedSeats();
          _nodeModels = _meshSvc.cachedNodeModels();
        });
      },
    );
  }

  Widget _boxPill(
    BuildContext context,
    String label,
    Color color,
    VoidCallback? onTap,
  ) {
    // UI audit 2026-11-06: pills get a 44pt hit area (visual unchanged).
    return Semantics(
      button: onTap != null,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(12),
        ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _wakeWarming = false;
  Timer? _wakePoll;

  /// 1.20.7: pending folder-contents card, armed when a folder
  /// fans out and cancelled by a file tap, a page swipe, or the
  /// folder closing again.
  Timer? _folderCardTimer;

  void _startWakePoll() {
    _wakePoll?.cancel();
    _wakePoll = Timer.periodic(const Duration(seconds: 12), (_) async {
      final n = await _meshSvc.fetchNodeModels();
      if (!mounted) return;
      setState(() => _nodeModels = n);
      if (n.any((m) => m.node == 'aws' && m.name == 'wakebox32b')) {
        _wakePoll?.cancel();
        setState(() => _wakeWarming = false);
      }
    });
  }

  Widget _wakeboxAsleepRow(BuildContext context, ModelController ctrl) {
    return _remoteRow(
      context,
      ctrl,
      source: const {
        'kind': 'mesh',
        'id': 'node:aws:wakebox32b',
        'label': 'wakebox32b',
        'model': 'wakebox32b',
      },
      title: 'wakebox32b',
      sub: 'AWS node · asleep',
      badge: _wakeWarming ? 'WAKING' : 'ASLEEP',
      badgeColor: AppColors.orange,
      icon: Icons.cloud_outlined,
      trailing: _boxPill(
        context,
        _wakeWarming ? 'Warming…' : 'Warm',
        AppColors.accentHi,
        _wakeWarming
            ? null
            : () async {
                TapFx.select();
                setState(() => _wakeWarming = true);
                final ok = await _meshSvc.wakeBox();
                if (!mounted) return;
                if (ok) {
                  _startWakePoll();
                } else {
                  setState(() => _wakeWarming = false);
                }
              },
      ),
    );
  }

  List<Widget> _meshSection(BuildContext context, ModelController ctrl) {
    if (!_meshSvc.connectivityOn) return const [];
    if (_meshSeats.isEmpty && _nodeModels.isEmpty) {
      // Never silently absent: if a fetch ran and nothing has ever
      // come back (and there is no cache to show), say so out loud.
      if (_meshTried && _meshSvc.catalogFetchedAt == null) {
        return [
          _sectionTitle(context, 'Mesh · Astro OS lanes via your PC'),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.bgPanel,
              border: Border.all(color: context.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Mesh unreachable at ${_meshSvc.address}. Check Settings, Mesh, and that your PC is on and on the same tailnet.',
              style: TextStyle(fontSize: 12, color: context.textM),
            ),
          ),
        ];
      }
      // Catalog is empty but the gateway has answered before: the
      // wake box row still belongs here (asleep is its home state).
      return [
        _sectionTitle(context, 'Mesh · Astro OS lanes via your PC'),
        const SizedBox(height: 12),
        _wakeboxAsleepRow(context, ctrl),
        const SizedBox(height: 16),
      ];
    }
    final widgets = <Widget>[
      _sectionTitle(context, 'Mesh · Astro OS lanes via your PC'),
      const SizedBox(height: 4),
      Text(
        _meshStale
            ? 'Cached catalog · your PC mesh is unreachable right now'
            : 'Live catalog from your PC mesh',
        style: TextStyle(fontSize: 11, color: context.textM),
      ),
      const SizedBox(height: 12),
    ];
    var sawWakebox = false;
    for (final nm in MeshService.favoritesFirst(
      _nodeModels,
      (n) => n.favorite,
    )) {
      final isWakebox = nm.node == 'aws' && nm.name == 'wakebox32b';
      if (isWakebox) sawWakebox = true;
      widgets.add(
        _remoteRow(
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isWakebox)
                _boxPill(context, 'Stop', AppColors.red, () async {
                  TapFx.select();
                  final ok = await _meshSvc.sleepBox();
                  if (!mounted || !ok) return;
                  final n = await _meshSvc.fetchNodeModels();
                  if (mounted) setState(() => _nodeModels = n);
                }),
              _star(context, nm.name, nm.favorite),
            ],
          ),
        ),
      );
    }
    if (!sawWakebox) {
      widgets.add(_wakeboxAsleepRow(context, ctrl));
    }
    // Ticket 34: one card per provider; the fleet itself lives
    // in the fleet sheet, not unrolled down this page.
    const groupOrder = ['paid', 'trial', 'free', 'local', 'compute'];
    final byGroup = <String, List<MeshSeat>>{};
    for (final s in _meshSeats) {
      byGroup.putIfAbsent(s.group, () => []).add(s);
    }
    for (final g in groupOrder) {
      final seats = byGroup[g];
      if (seats == null || seats.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(
            g.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textD,
              letterSpacing: 0.6,
            ),
          ),
        ),
      );
      final lanes = <String>[];
      for (final s in seats) {
        if (!lanes.contains(s.lane)) lanes.add(s.lane);
      }
      lanes.sort();
      for (final lane in lanes) {
        final laneSeats = seats.where((s) => s.lane == lane).toList();
        final starred = laneSeats.where((s) => s.favorite).length;
        widgets.add(
          _remoteRow(
            context,
            ctrl,
            source: {'kind': 'provider', 'id': 'provider:$lane'},
            title: lane,
            sub:
                '${laneSeats.length} seats${starred > 0 ? ' · $starred starred' : ''}',
            badge: g.toUpperCase(),
            badgeColor: AppColors.accent,
            icon: Icons.hub_outlined,
            trailing: Icon(
              Icons.chevron_right,
              size: 20,
              color: context.textD,
            ),
            tapOverride: () => _fleetSheet(context, ctrl, lane),
          ),
        );
      }
    }
    widgets.add(const SizedBox(height: 16));
    return widgets;
  }

  /// Ticket 34: one mesh seat's row — the exact row the Models
  /// page used to unroll inline for every seat; it now renders
  /// inside the provider's fleet sheet.
  Widget _seatRow(BuildContext context, ModelController ctrl, MeshSeat s) {
    return _remoteRow(
      context,
      ctrl,
      source: {
        'kind': 'mesh',
        'id': 'mesh:${s.lane}:${s.model}',
        'label': s.model,
        'model': s.model,
      },
      // UI audit 2026-11-06 (Claude P2-9, Codex P2-17): the
      // seat options were long-press only; a visible button
      // opens the same sheet.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _star(context, s.model, s.favorite),
          IconButton(
            tooltip: 'Seat options',
            icon: Icon(AppIcons.more, size: 20, color: context.textM),
            onPressed: () => _seatVerifySheet(context, s),
          ),
        ],
      ),
      title: s.model,
      sub: s.dead
          ? '${s.lane} · Not working, tap to retry'
          : s.isBlocked && s.blocked != null
          ? '${s.lane} · ${s.blocked}'
          : s.lane,
      badge: s.dead
          ? 'NOT WORKING'
          : s.isBlocked
          ? 'BLOCKED'
          : s.isVerified
          ? (s.proven ? 'PROVEN' : 'VERIFIED')
          : 'UNTESTED',
      badgeColor: s.dead || s.isBlocked
          ? AppColors.red
          : s.isVerified
          ? AppColors.green
          : AppColors.orange,
      icon: Icons.hub_outlined,
      dimmed: s.isBlocked || s.dead,
      tapOverride: s.dead
          ? () async {
              // Retrying a dead seat: the tag clears and the
              // seat answers in chat — Kai's smoke test decides
              // if it earns its place back.
              TapFx.select();
              await _meshSvc.setModelDead(s.model, false);
              ctrl.selectRemote({
                'kind': 'mesh',
                'id': 'mesh:${s.lane}:${s.model}',
                'label': s.model,
                'model': s.model,
              });
              if (!context.mounted) return;
              setState(() => _meshSeats = _meshSvc.cachedSeats());
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: context.bgPanel,
                  content: Text(
                    'Retrying ${s.model}. Not-working mark cleared',
                    style: TextStyle(color: context.text),
                  ),
                ),
              );
            }
          : s.isBlocked
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: context.bgPanel,
                  content: Text(
                    s.blocked ?? 'Unavailable on this gateway',
                    style: TextStyle(color: context.text),
                  ),
                ),
              );
            }
          : null,
      onLongPress: () => _seatVerifySheet(context, s),
    );
  }

  /// 1.20.7: the card that pops once a folder's fan-out has
  /// fully played — every model in the folder, searchable.
  /// Picking a local model lands on its card in the list (the
  /// same focus a fanned-file tap gives); picking a fleet seat
  /// opens its provider's fleet sheet filtered to it.
  void _folderContentsCard(
    BuildContext context,
    ModelController ctrl,
    String label,
    List<({String name, String meta, AiModelInfo? model, MeshSeat? seat})>
    files,
  ) {
    final searchCtrl = TextEditingController();
    var query = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final q = query.trim().toLowerCase();
          final shown = q.isEmpty
              ? files
              : files.where((f) => f.name.toLowerCase().contains(q)).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetCtx).size.height * 0.92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: sheetCtx.text,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      '${files.length} ${files.length == 1 ? 'model' : 'models'} in this collection',
                      style: TextStyle(fontSize: 12, color: sheetCtx.textM),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: (v) => setSheet(() => query = v),
                      style: TextStyle(color: sheetCtx.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search this collection',
                        hintStyle: TextStyle(color: sheetCtx.textD),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: sheetCtx.textD,
                        ),
                        filled: true,
                        fillColor: sheetCtx.bgInput,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: sheetCtx.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: sheetCtx.border),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      itemCount: shown.length,
                      itemBuilder: (rowCtx, i) {
                        final f = shown[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          title: Text(
                            f.name,
                            style: TextStyle(
                              color: sheetCtx.text,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            f.meta,
                            style: TextStyle(
                              color: sheetCtx.textM,
                              fontSize: 11,
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: sheetCtx.textD,
                          ),
                          onTap: () {
                            Navigator.of(sheetCtx).pop();
                            final seat = f.seat;
                            if (seat != null) {
                              _fleetSheet(
                                context,
                                ctrl,
                                seat.lane,
                                initialQuery: seat.model,
                              );
                              return;
                            }
                            _searchCtrl.text = f.name;
                            setState(() {
                              _folderFocus = (
                                collection: label,
                                model: f.name,
                              );
                              _query = f.name;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) => searchCtrl.dispose());
  }

  /// Ticket 34: one provider's whole fleet in a sheet of its
  /// own — search at the top, favorites first (pickerOrder), the
  /// same seat rows the page used to unroll inline. Row actions
  /// refresh the gateway cache through the existing handlers;
  /// the sheet re-reads the cache on every rebuild, and a
  /// pointer-up schedules one rebuild so stars and selection
  /// highlights land without a reopen.
  void _fleetSheet(
    BuildContext context,
    ModelController ctrl,
    String lane, {
    String? initialQuery,
  }) {
    final searchCtrl = TextEditingController(text: initialQuery ?? '');
    var query = (initialQuery ?? '').trim().toLowerCase();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final seats = MeshService.pickerOrder(
            _meshSvc
                .cachedSeats()
                .where(
                  (s) =>
                      s.lane == lane &&
                      (query.isEmpty || s.model.toLowerCase().contains(query)),
                )
                .toList(),
          );
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetCtx).size.height * 0.92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Text(
                      lane,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: sheetCtx.text,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      '${seats.length} seats via your PC mesh',
                      style: TextStyle(fontSize: 12, color: sheetCtx.textM),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: (v) =>
                          setSheet(() => query = v.trim().toLowerCase()),
                      style: TextStyle(color: sheetCtx.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search this fleet',
                        hintStyle: TextStyle(color: sheetCtx.textD),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: sheetCtx.textD,
                        ),
                        filled: true,
                        fillColor: sheetCtx.bgInput,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: sheetCtx.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: sheetCtx.border),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Listener(
                      onPointerUp: (_) => Future.delayed(
                        const Duration(milliseconds: 350),
                        () {
                          if (sheetCtx.mounted) setSheet(() {});
                        },
                      ),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        children: [
                          for (final s in seats) _seatRow(sheetCtx, ctrl, s),
                          if (seats.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Text(
                                'No seats match.',
                                style: TextStyle(
                                  color: sheetCtx.textD,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      searchCtrl.dispose();
      if (mounted) {
        setState(() {
          _meshSeats = _meshSvc.cachedSeats();
          _nodeModels = _meshSvc.cachedNodeModels();
        });
      }
    });
  }

  /// Mesh 0.17: Kai smoke-tests unverified seats by picking them;
  /// when one earns it he flips it verified - the same flip the
  /// console toggle makes (POST /mesh/model-prefs on the gateway).
  /// Ticket 25: manual tag editor. Saving marks the record
  /// tagsSource 'manual' — the classifier never overwrites it.
  void _tagEditor(BuildContext context, AiModelInfo model) {
    final selected = model.tags.toSet();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'File ${model.name} into collections',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Each tag is a folder above. Hand-filed models stay where you put them · auto-classifying never overwrites them.',
                  style: TextStyle(fontSize: 12, color: context.textM),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in ModelClassifier.tagOrder)
                      FilterChip(
                        label: Text(
                          t.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            color: selected.contains(t)
                                ? Colors.white
                                : context.textM,
                          ),
                        ),
                        selected: selected.contains(t),
                        onSelected: (on) => setSheet(
                          () => on ? selected.add(t) : selected.remove(t),
                        ),
                        selectedColor: AppColors.accent,
                        backgroundColor: context.bgPanel,
                        side: BorderSide(
                          color: selected.contains(t)
                              ? AppColors.accent
                              : context.border,
                        ),
                        showCheckmark: false,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.text,
                          side: BorderSide(color: context.border),
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          TapFx.select();
                          final tags = ModelClassifier.tagOrder
                              .where(selected.contains)
                              .toList();
                          Get.find<ModelManager>().setModelTags(model, tags);
                          setState(() {});
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _seatVerifySheet(BuildContext context, MeshSeat s) {
    final target = !s.verifiedOverride;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!s.proven)
              ListTile(
                leading: Icon(
                  target ? Icons.verified_outlined : Icons.undo_outlined,
                  color: context.textM,
                  size: 20,
                ),
                title: Text(
                  target ? 'Mark verified' : 'Unmark verified',
                  style: TextStyle(fontSize: 14, color: context.text),
                ),
                subtitle: Text(
                  s.model,
                  style: TextStyle(fontSize: 11, color: context.textM),
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final ok = await _meshSvc.setModelVerified(s.model, target);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: context.bgPanel,
                      content: Text(
                        ok
                            ? (target
                                  ? '${s.model} marked verified'
                                  : '${s.model} unmarked')
                            : 'The mesh did not accept the flip · is the PC gateway up?',
                        style: TextStyle(color: context.text),
                      ),
                    ),
                  );
                  if (ok) {
                    _meshSvc.fetchSeats().then((s) {
                      if (mounted) setState(() => _meshSeats = s);
                    });
                  }
                },
              ),
            // Kai (1.14.1): "Dead Rn" — tag a seat that doesn't work;
            // it sinks to the bottom of the list until retried.
            ListTile(
              leading: Icon(
                s.dead ? Icons.replay_outlined : Icons.dangerous_outlined,
                color: s.dead ? AppColors.accentHi : AppColors.red,
                size: 20,
              ),
              title: Text(
                s.dead ? 'Clear not-working mark (retry)' : 'Mark not working',
                style: TextStyle(fontSize: 14, color: context.text),
              ),
              subtitle: Text(
                s.dead
                    ? 'Back in rotation · pick it to smoke-test it again'
                    : 'Not working right now · park it at the bottom',
                style: TextStyle(fontSize: 11, color: context.textM),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                TapFx.select();
                await _meshSvc.setModelDead(s.model, !s.dead);
                if (!context.mounted) return;
                setState(() => _meshSeats = _meshSvc.cachedSeats());
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: context.bgPanel,
                    content: Text(
                      s.dead
                          ? '${s.model} is back in rotation'
                          : '${s.model} marked not working. Parked at the bottom',
                      style: TextStyle(color: context.text),
                    ),
                  ),
                );
              },
            ),
            // Visible way out (Codex P2-18).
            ListTile(
              leading: Icon(Icons.close_rounded, color: context.textM, size: 20),
              title: Text(
                'Cancel',
                style: TextStyle(fontSize: 14, color: context.text),
              ),
              onTap: () => Navigator.pop(sheetCtx),
            ),
          ],
        ),
      ),
    );
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
      widgets.add(
        _remoteRow(
          context,
          ctrl,
          source: {
            'kind': 'custom',
            'id': c.id,
            'label': c.name,
            'model': c.model,
          },
          title: c.name,
          sub:
              '${c.model} - ${c.type == 'ollama' ? 'Ollama API' : 'OpenAI API'}',
          badge: 'CUSTOM',
          badgeColor: AppColors.accent,
          icon: Icons.link_outlined,
        ),
      );
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
                AppIcons.pin,
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
            // Ticket 25 (Kai, 1.16.1): filing a model into the
            // folder collections lives in the long-press menu for
            // EVERY model — collections are the tags, and the
            // classifier never overwrites hand-filed ones.
            ListTile(
              leading: const Icon(
                Icons.sell_outlined,
                color: AppColors.accentHi,
              ),
              title: Text(
                'Collections & tags',
                style: TextStyle(color: context.text),
              ),
              subtitle: Text(
                model.tags.isEmpty
                    ? 'No tags yet'
                    : model.tags.map((t) => t.toUpperCase()).join(' · '),
                style: TextStyle(color: context.textM, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _tagEditor(context, model);
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
        // UI audit 2026-11-06 P1-7: padded target (was shrinkWrap).
        materialTapTargetSize: MaterialTapTargetSize.padded,
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
              // UI audit 2026-11-06 P1-8: action color, not green.
              backgroundColor: AppColors.accent,
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
              ? '\n\nIt stays in your library. You can redownload it anytime.'
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
              backgroundColor: AppColors.redDeep,
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
              backgroundColor: AppColors.redDeep,
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
    final urlCtrl = TextEditingController(
      text: model.hasRemoteUrl ? model.url : '',
    );

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
