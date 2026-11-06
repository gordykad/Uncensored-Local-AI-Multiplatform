# Claude Packet — MiniX audit + MoE plan (Kai's order, 2026-11-05)

Repo: this clone (gordykad/Uncensored-Local-AI-Multiplatform).
Work from branch `minix/b1181-stack` (pull it first). READ-ONLY:
report findings, change nothing.

## Load first (Skill tool, before any work)
- `graphify` (~/.claude/skills/graphify) — then BUILD the graph for
  this repo (none exists yet): run `extract <repo root>` (that is
  the exact verb; there is no `build` verb), then run one real
  `query` (e.g. query "model loading path") and quote its output
  in your report header as proof the graph is live. Reads after
  that: `query`, `path`, `explain`, `affected`, `god-nodes`.
- `code-review` (~/.claude/skills/code-review) — audit discipline.

## Job 0 — Debug the code written since the last audit
Full range: `git diff origin/minix/b1142-verstr...HEAD --stat`
(the last code-audited state was 1.14.2; everything after is new).
Files that carry the new code:
- lib/services/model_classifier.dart (new), model_manager.dart
- lib/widgets/glass_folder.dart (new), assets/glass_folder_pack.html
- lib/screens/model_library_screen.dart, lib/widgets/model_card.dart
- ios/Runner/DownloadActivity.swift (new), ios/MiniXLiveActivity/
  (new target), ios/Runner/AppDelegate.swift, project.pbxproj
- lib/services/chat_storage_service.dart, lib/services/llm_service.dart
- lib/screens/settings_screen.dart, lib/app_version.dart (new),
  lib/services/local_api_server_service.dart
Debug it like it will crash on the owner's phone tonight: trace
the download lifecycle end to end (Dart manager + native engine +
Live Activity hooks), the GGUF header parser on truncated/corrupt
files, the WebView bridge contract both directions, and every
iOS-version-sensitive API in the Swift (this code already burned
two builds on iOS-17-only ActivityKit shapes against a 16.4
deployment target — sweep ALL Swift for the same class:
ActivityContent, dismissal .after, any 17+ symbol without an
availability guard). Findings feed Job 1's report.

## Job 1 — Audit the rapid-fire stack
Diffs to audit against their tickets in `.scratch/minix-v2/issues/`:
- Ticket 25 classifier (25-import-auto-labels.md): lib/services/
  model_classifier.dart, model_manager.dart tag paths,
  assets/models_catalog.json tags.
- Ticket 25 folder (same ticket): lib/widgets/glass_folder.dart,
  the Collections field in lib/screens/model_library_screen.dart,
  assets/glass_folder_pack.html wiring (postMessage bridge).
- Ticket 23 (23-live-activity-downloads.md): ios/Runner/
  DownloadActivity.swift, the MiniXLiveActivity extension target,
  AppDelegate.swift hooks, project.pbxproj target wiring.
- Tickets 12+19 knobs (12-repack-switch.md, 19-research-arm.md,
  incl. the 2026-11-05 investigation notes appended to both):
  chat_storage_service.dart MoE fields, llm_service.dart
  ModelParams construction, settings_screen.dart controls.
Hunt: correctness bugs, lifecycle/resource leaks (WebView
controllers, Activity objects), persistence mistakes (Hive keys,
overrides), races at download transitions, anything that breaks
the shipped 34/34 IPA audit's assumptions. Output: findings ranked
by severity, file:line each, one line per finding on impact. No
fixes — Astro merges.

## Job 2 — How do MoE models finally work on a phone in this app?
Context, all verified (do not re-derive): the app is Flutter +
llamadart 0.17.5, whose pinned llama.cpp is 0.8.0 (commit
8642541). llamadart ships moe_expert_placement.dart:
ModelParams.cpuMoeLayers (tensor_buft_overrides keep the first N
layers' experts in host memory) and ModelParams.moeCacheBytes
(llama.cpp MoE expert cache, qualified on Metal; setting it
forces use_extra_bufts=false, i.e. CPU repack off). Both knobs
are now wired into the app's load path with settings controls.
Models: Gemma 4 26B A4B IQ2_M (10.38 GB) and Qwen3.6-35B-A3B
IQ2_M. Floor device: iPhone 14, A15, 6 GB RAM, flash reads
~0.35-0.5 GB/s during large-model work; fleet also has iPhone 11
(4 GB) and 17 Pro Max (12 GB). Gate 2 bar: 26B IQ2_M at >= 2
tok/s sustained on the iPhone 14, full answers on the 11.
Question: the concrete plan to make MoE models genuinely usable
in this app — the config matrix to run first (cpuMoeLayers x
moeCacheBytes x gpuLayers), what in llama.cpp/llamadart we are
still not using (name the exact params/files), what will NOT
work and why, and the measurement protocol that proves it.
Write the plan into `.scratch/minix-v2/issues/19-research-arm.md`
as a new dated section, and summarize it in your final message.

## House rules for this run
- Caveman voice is already the default; keep output terse.
- Token economy: excerpts over whole files, diffs over rewrites.
- If a named skill is missing, say so in the report and proceed.
