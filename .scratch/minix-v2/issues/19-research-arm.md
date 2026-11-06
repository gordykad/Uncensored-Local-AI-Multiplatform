# 19 - research arm (MoE on phone)

Note on this file: the clone Claude was given has no `.scratch/` directory (not in the working tree, not in git history on any branch). This file was created fresh so the plan has a home. Astro should merge the section below into the canonical ticket 19 file, which this clone does not contain.

## 2026-11-05 - Claude plan: how MoE models become usable on the phone

Status of every claim below: "upstream" means read in the llamadart 0.17.5 source (downloaded from pub.dev into a scratch directory, not into the repo). "Estimate" means arithmetic from the packet's own figures and is not measured. "Unverified" means it needs the measurement protocol to settle.

### 1. What upstream says that changes the plan

1. The MoE expert cache does nothing useful on Apple silicon. `ModelParams.moeCacheBytes` documentation (lib/src/core/models/inference/model_params.dart, field `moeCacheBytes`) states: "GPUs that share system memory, such as Apple silicon, gain nothing from it." The app's settings text calls it "the speed lever for MoE models" (settings_screen.dart:1357). On an iPhone the cache is a second copy of hot experts in the same RAM. Treat it as a falsification test, not as the lever.
2. The cache still matters for one reason. llamadart sets `llama_model_params.use_extra_bufts = false` only when `moeCacheBytes > 0` (moe_expert_placement.dart, `applyMoeCacheModelParams`). That switch turns off llama.cpp CPU weight repacking. Repacked weights are copied into anonymous memory, so they cannot be paged back to flash and count against the jetsam footprint. Mapped weights stay file-backed and reclaimable. So a small cache budget (256 MB) is the only way llamadart exposes "repack off". Whether repack even touches IQ2_M tensors is unverified: the aarch64 repack kernels cover a limited set of quant types, and an IQ2_M file mixes types. Measure footprint with the cache at 0 and at 256 MB before believing either story.
3. `cpuMoeLayers != 0` on a model with no experts throws `LlamaUnsupportedException` after the model loads (llama_cpp_service.dart `_moeExpertPlacementProblem`, message "model has no experts. Leave them at 0."). The knob is global in this app, so one setting breaks every dense model. This is an app bug (see the audit), and it also means the matrix below must reset the knob between MoE and dense runs.
4. Hard validity rules, all upstream: `moeCacheBytes > 0` requires `cpuMoeLayers != 0` (`ModelParams.validate`); it requires `gpuLayers != 0` on a Metal or CUDA device (`moeCacheUnsupportedReason`); and it requires at least one layer that is both offloaded and host-expert (`moeCacheableLayerCount`). llama.cpp offloads the LAST layers and `cpuMoeLayers` keeps the FIRST ones, so a partial `gpuLayers` with a large `cpuMoeLayers` can leave zero cacheable layers and the load throws. Example: 36 layers, gpuLayers 20, cpuMoeLayers 16 gives firstOffloaded 17 and zero cacheable layers.
5. The app resolves `gpuLayers` 0 to 999 only when the file fits in 0.75 of current headroom (llm_service.dart, the `userGpuLayers == 0` block). A 10.38 GB file never qualifies on a 6 GB phone, so the stored value stays 0 unless set by hand, and any cache run then throws "offloads no layer". The matrix sets `gpuLayers` explicitly.

### 2. What is still unused (exact names)

llamadart, `ModelParams` (model_params.dart): `useMmap` (keep true, default), `useMlock` (never on a 6 GB device), `cacheTypeK` and `cacheTypeV` (KvCacheType; non-F16 needs `flashAttention` enabled; shrinks KV so more RAM remains for experts; the app sets neither), `batchSize` and `microBatchSize` (smaller micro-batch shrinks the compute buffer; the app leaves both at 0 = auto), `numberOfThreads` (the app uses 4 when the device reports more than 4 processors, which includes efficiency cores on A15; test 2 and 3), `kvUnified`, `maxParallelSequences` (keep 1), `contextSize` (run 2048 for the gate; the app default is higher).

llamadart bindings present but never set by `load_param_helpers.dart` or exposed in `ModelParams`: `llama_model_params.tensor_buft_overrides` with arbitrary patterns (llamadart only builds the first-N pattern in `cpuMoeOverridePatterns`; keeping the LAST layers' experts host-side, or alternating layers, is not reachable without a llamadart patch), `llama_model_params.lazy_mode` (enum `llama_lazy_mode` OFF/AUTO/ON at bindings.dart near line 12255; semantics in the pinned llama.cpp are unverified, read the header at commit 8642541 before using), `llama_model_params.no_host`, `llama_model_params.check_tensors`, `llama_context_params.offload_kqv`, `llama_context_params.swa_full` (relevant if Gemma's sliding-window layers inflate KV), `llama_context_params.cb_eval` (an eval callback; the only in-process way to log which experts each token routes to).

llama.cpp side, not reachable from llamadart today: per-expert routing statistics. A PC-side run with the pinned build's `llama-imatrix` can emit per-expert activation counts for MoE tensors (confirm on commit 8642541 before relying on it). That gives a hit-rate-versus-cache-size curve for a chat-like prompt set without touching a phone, and it is the cheapest way to learn how skewed routing is.

### 3. What will NOT work, and why

- The expert cache as a speed gain on iPhone: upstream says unified memory gains nothing (section 1.1).
- Speculative decoding and MTP (`loadMtp`, `SpeculativeDecodingStrategy.mtp`): verifying several draft tokens in one batch touches the union of their experts, which means more flash reads per accepted token when decode is flash-bound.
- Vulkan or OpenCL cache paths: not on iOS; the cache throws outside Metal and CUDA.
- Full offload (`gpuLayers` 999, `cpuMoeLayers` 0) of a 10.38 GB file on a 6 GB phone: expect jetsam or page thrash. It stays in the matrix as the baseline that proves it.
- Partial `gpuLayers` combined with a cache budget when `cpuMoeLayers` does not overlap the offloaded tail (section 1.4).
- `useMlock`: pins pages the phone cannot spare.
- 2 tok/s on the iPhone 11 (4 GB): the usable resident set there is a fraction of the 6 GB case; the realistic target is the stated one, full answers, at whatever speed.
- Qwen3.6-35B-A3B IQ2_M is a larger file than the Gemma 26B, so it is strictly harder on the same devices. Run Gemma first; run Qwen only if Gemma passes.

### 4. Why 2 tok/s is hard (estimate, not measured)

Packet figures: file 10.38 GB, flash reads 0.35 to 0.5 GB/s, Gemma 4 26B A4B means about 4B active of 26B total. Active weights per token are about 4/26 of the file, roughly 1.6 GB (an upper bound; the shared, non-expert part is resident and costs no flash). If every active byte came from flash: 1.6 GB at 0.5 GB/s is 3.2 s per token, at 0.35 GB/s 4.6 s per token, so about 0.2 to 0.3 tok/s. For 2 tok/s the flash time per token must stay under 0.5 s, which is at most about 0.25 GB of misses per token at the fast end of the range. That needs roughly 85 percent or more of active-expert bytes served from RAM. Whether the iPhone 14 can hold enough experts to reach that hit rate depends on the jetsam limit with the increased-memory-limit entitlement (Runner.entitlements has `com.apple.developer.kernel.increased-memory-limit` and `extended-virtual-addressing`), on KV and compute buffers, and on how skewed routing is. All three are unmeasured. This section is a falsifiable bar, not a prediction that the bar is met.

### 5. First config matrix (Gemma 4 26B A4B IQ2_M, iPhone 14)

Fixed for every cell: contextSize 2048, useMmap true, useMlock false, flashAttention auto, cache types default, microBatchSize left auto, threads 3. Reboot the phone before each cold set. Stored MoE settings must be reset to Off/Off before loading any dense model.

| Cell | gpuLayers | cpuMoeLayers | moeCacheBytes | Purpose |
|---|---|---|---|---|
| A | 999 | 0 | 0 | Baseline: prove full offload fails or thrashes |
| B | 0 | 0 | 0 | CPU-only baseline (compare to the B1 1.50 tok/s figure only if the same model) |
| C | 999 | -1 | 0 | All experts host, repack ON: footprint trap test |
| D | 999 | -1 | 256 MB | All experts host, repack OFF: footprint and speed vs C |
| E | 999 | 16 | 256 MB | Half-ish experts host (set the number to about half the layer count read from the header) |
| F | 999 | 8 | 256 MB | Fewer host layers |
| G | 999 | -1 | 1024 MB | Only if D shows any cache signal; tests whether size matters at all |

Then, on the best cell only: threads 2, 3, 4, 6; contextSize 2048 versus 4096; `cacheTypeK`/`cacheTypeV` q8_0 with flash on, to see how much RAM the KV shrink returns. Cells that upstream rules reject (cache with `cpuMoeLayers` 0, cache with `gpuLayers` 0, partial offload with zero cacheable layers) are excluded on purpose. Before the run, read `n_layer`, `expert_count` and `expert_used_count` from the GGUF header (use the PC `llama-gguf` tool; the app's own parser reads only name, architecture and context length, and returns nothing at all when the metadata runs past its 4 MB read) and replace the placeholder "half-ish" number.

### 6. Measurement protocol

Per cell, three repetitions, report median and worst:

1. Prompt set, temperature 0, fixed seed: a 32-token prompt, a 256-token prompt, a 1k-token prompt; generate 128 tokens each.
2. Record from the app's existing Diagnostics/METER lines: load time, time to first token, prefill tok/s, decode tok/s over tokens 1 to 32 and over tokens 96 to 128, `headroomBytes` minimum during the run (AppDelegate `os_proc_available_memory`), `mtlAlloc`, `thermal` state at start and end.
3. Record from Xcode Instruments on the same build: memory footprint peak (VM Tracker), page-in rate (File Activity or the VM fault counters), and any jetsam event in the device's analytics logs. A cell that is jetsammed in any repetition fails.
4. Sustained run: ten back-to-back 256-token answers (about five minutes), not a single answer, so thermal throttling shows up. Low Power Mode off, screen on, same charge state every cell.
5. Cold versus warm: cold is after a reboot; warm is a second answer in the same session. Report both. Gate 2 uses cold sustained numbers, because that is what a user sees after relaunch.
6. Pass bars: Gate 2 passes when the median sustained decode is at least 2 tok/s on the iPhone 14 in 3 of 3 repetitions with no jetsam. On the iPhone 11 the bar is complete answers (a full 256-token answer without termination) in 3 of 3 repetitions. The 17 Pro Max runs the same matrix as a ceiling reference, not as a gate.
7. Before the phone runs: the PC `llama-imatrix` expert-count pass from section 2, to know the routing skew and to draw the hit-rate-versus-cache-size curve. If the curve says a 2 GB resident expert set cannot reach 85 percent hit, stop and tell Kai the 26B IQ2_M cannot meet Gate 2 on that device; the fallbacks (a smaller MoE, a lower quant) are Kai's call, not this ticket's.

### 7. App changes this plan needs (each is a separate finding in the audit)

Per-model scoping of the MoE knobs (dense models must not receive them); a guard so the cache cannot be chosen with layers Off or on a CPU backend; correcting the cache help text; a parser that also reads `block_count` and `expert_count` so the app can scope the knobs by architecture; a PC-side routing-statistics run before any phone time.
