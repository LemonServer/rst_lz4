# RST Hardware Status Memo (2026-04-04)

This repo contains a parameterized RTL implementation of an RST/CRAM-style dictionary compressor and decompressor, plus local simulation harnesses and remote Synopsys signoff flow support. The current packaged reviewer-facing synthesis baseline is the canonical `small` closeout bundle `reviewer_small_tops_split_closeout`, with the older `20260404_tiny_tops_ultra_retime_fastpoc_r3` run kept as historical context.

The reviewer-facing hardware paths are now split on purpose:

- standard/synthesis `small` uses the frozen signoff-era `m4_filelist.f` RTL baseline
- reviewer-facing experimental `large` uses the copied snapshot under `experimental/frozen_large/`

That split is intentional so experimental large-path work cannot mutate the small synthesis baseline.

## Parameter Tiers

The same RTL is compiled under several internal tiers in the frozen standard `rst_pkg.sv`, but the reviewer-facing surface now exposes only `small`, `medium`, and `large`. Public `small` maps onto the preserved synthesis-ready internal `tiny` configuration; the older internal `small` planning tier is intentionally hidden from reviewer commands. The experimental large verification path uses its own copied `rst_pkg.sv` under `experimental/frozen_large/`.

| Tier | Chunk bytes | Page chunks | Page bytes | Max dict entries | Dict storage | Decomp LIFOs | Banks (seq2/3/4/5) | Sets/bank | Ways | Count bits | FIFO depth |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: |
| `small` | 32 | 2 | 64 | 8 | 64 B | 2 | 2 / 2 / 2 / 2 | 2 | 2 | 6 | 16 |
| `medium` | 128 | 8 | 1024 | 32 | 128 B | 4 | 4 / 5 / 6 / 7 | 8 | 4 | 10 | 8 |
| `large` | 256 | 16 | 4096 | 63 | 128 B | 16 | 6 / 7 / 9 / 10 | 16 | 4 | 12 | 64 |

Across the frozen standard/synthesis path, the per-length update pipelines keep the same logical widths: seq2=`8`, seq3=`10`, seq4=`12`, seq5=`14`. The experimental large verification path carries its own copied large-path package and does not share this file.

## Models And Measurement Hooks

| Model / flow | What it covers | How trustworthy it is today |
| --- | --- | --- |
| RTL + SystemVerilog testbenches | Actual implemented compressor, decompressor, page wrappers, and packed dictionary path | Highest trust for current hardware behavior |
| Python hardware model (`new_hardware_sim_compressor.py`) | Current page-wrapper baseline semantics; used by `run_m4_golden_regression.py` | High trust for current baseline; this is the best software cross-check for current RTL |
| C++ `cram_impl.cpp` | Richer algorithmic/software reference | Useful for future features, but not exact to current RTL because it includes extra ratio boosters such as reuse/static-tree behavior |
| Python decompression latency model | Planning-oriented decompression model | Useful for exploration, not a signoff-quality functional oracle. Has some differences with the actual decompressor design (and a small bug related to chunking strategy). |

Easy measurements that can be regenerated now:

- Local, no Synopsys required: ratio, dictionary bits/count, compressed symbol count, compression/decompression cycles, and throughput via the round-trip testbenches plus `tools/run_m4_runtime_file_metrics.py`.
- Local, ratio-sensitive correctness check: `tools/run_m4_golden_regression.py` compares the `large` M4 hardware harness against the exact Python hardware model.
- Remote Synopsys/VCS flow: timing, area, hierarchy timing attribution, hierarchy area, and power (`activity`, `clock_only`, `zero_toggle`, and `activity - clock_only` as rough data-dependent dynamic).

## Canonical Small Baseline

Historical remote closeout reference: `20260404_tiny_tops_ultra_retime_fastpoc_r3`

Current canonical packaged closeout bundle: `reviewer_small_tops_split_closeout`

| Top | ASAP7 cell area (DC Design Area) | Slack | Power context |
| --- | ---: | ---: | --- |
| `PageCompressorTop` | `613903.4` | `0.00 ps` | `117.835 mW` activity, `114.627 mW` clock-only, `3.208 mW` activity-minus-clock-only |
| `PageDecompressorTop` | `90773.9` | `0.00 ps` | `18.233 mW` activity, `14.222 mW` clock-only, `4.011 mW` activity-minus-clock-only |
| `CompressorTop` | `638968.8` | `0.00 ps` | No bundled power figure cited here |
| `DecompressorTop` | `71174.7` | `0.01 ps` | No bundled power figure cited here |

Functional/perf context from the current reviewer-facing `small` runtime harness: `16` pages, ratio `1.8208x`, compressor throughput `0.1415 B/cycle`, decompressor throughput `1.2005 B/cycle`.

Interpretation note: timing/slack values above are in `ps`, power is in `mW`, and the area figures are DC `Design Area` totals from the ASAP7 library setup retained in this repo. They are useful for same-flow synthesized comparisons, not a routed silicon area claim.

Planning note: this canonical reviewer-facing `small` bundle is effectively at the target but not margin-rich. All four tops are now reported at or within rounding of zero slack in the fast-POC closeout flow.

Reviewer packaging note: the historical April 4 closeout remains a useful remote reference, but the current canonical packaged reviewer path is the synced April 2 batch material plus the generic rerun/closeout kit summarized in `synthesis/SMALL_SIGNOFF_FLOW.md`.
The compact packaged quick-look for that path now also lives in `evidence/signoff_summary.{md,json}`.

## 1. Works Now / Ready Now

- The simulation-capable hardware baseline is real and coherent. The repo has a chunk compressor (`CompressorTop`), page compressor (`PageCompressorTop`), chunk decompressor (`DecompressorTop`), page decompressor (`PageDecompressorTop`), and packed dictionary serializer/deserializer (`dict_packed_codec.sv`).
- The packed dictionary path is already implemented and validated. Some older design notes still describe serialization as post-MVP, but the current RTL is ahead of those notes and should be treated as authoritative.
- The current RTL implements the core sequence-substitution flow for sequence lengths `2` through `5`, with per-length update pipelines, hashed/banked count tracking, top-candidate selection, substitution, packed dictionary generation, and segmented decompression using multiple LIFOs.
- Page mode is implemented as a shared page dictionary over `PAGE_CHUNKS` chunk invocations. This is important: the page wrappers are not just independent per-chunk codecs.
- The shared artifact branch is currently based on `codex-artifact-deadline-integration`, with Hubble's convergence fix merged.
- Local validation infrastructure is already in place. The practical top-level gates are the chunk/page round-trip testbenches, `tools/run_rst_verify.py`, the runtime file harness, the dictionary packing round-trip bench, and the internal Python-model cross-check in `tools/run_m4_golden_regression.py`.
- The local scripting surface is enough for fast engineering iteration. Main entry points are `tools/run_rst_verify.py`, `tools/run_m4_runtime_file_metrics.py`, `tools/run_m4_golden_regression.py`, and the small page-generation helpers in `tools/`.
- Trustworthiness is uneven but usable. RTL plus the main round-trip benches are the strongest gates for implemented behavior, the Python hardware model is the best software cross-check for the current baseline, and the standalone hash-table testbench should not be treated as a strong signoff gate by itself.
- Current local checkpoints after the convergence fix are better anchored in the reviewer flow itself: the bundled `avrora` `16`-page run passes at about `6.5022x`, the quick bundled-data `88`-dump `x 8`-page pass is `88/88` with pooled ratio about `3.3426x`, and the broader remote-machine `88`-dump `x 100`-page pass is also `88/88`.
- The current official broad-run reference is now the merged full-suite `88`-dump `5000`-page pass summarized in `evidence/full_suite_88x5000_summary.{md,json,stdout}`.
- The most useful paper-style ratio number from that merged run is the suite geomean-of-geomeans: `3.4109x` (hardware) versus `3.4242x` (C++), delta about `-0.390%`. The corresponding per-benchmark geomean ratio is `3.1963x` (hardware) versus `3.2090x` (C++).
- The same merged full-suite run also provides the current bundled decompressor-side headline metrics: suite geomean-of-geomeans throughput `7.2091 B/cycle` / `18.0227 GB/s @ 2.5 GHz`, average critical `64B` latency `44.9486` cycles / `17.9795 ns`, and full-chunk completion `55.6931` cycles / `22.2772 ns`.
- The older `100`-page provisional remote wording is now superseded by that merged `5000`-page summary and should not be treated as the current artifact source of truth.
- Reviewer-facing docs should treat the C++ comparison as an informational metric cross-check. The stricter mismatch-failure mode is intentionally hidden now.

## 2. Works, But Depends On Remote / Synopsys Infrastructure Or Extra Setup

- The signoff and measurement flow exists. The packaged artifact now includes the reviewer-facing `small` DC rerun entry points `synthesis/scripts/run_dc_smoke_batch.sh`, `synthesis/scripts/synth_parser_smoke.tcl`, `synthesis/scripts/common_setup.tcl`, `synthesis/scripts/inventory_dc_batch.py`, `synthesis/scripts/build_signoff_bundle.py`, and `synthesis/scripts/run_small_signoff_closeout.sh`. The compact cleaned evidence bundle is now also kept in-tree under `evidence/`.
- Timing and area are straightforward to regenerate remotely from DC batches. The flow also supports hierarchy timing mining from mapped `.ddc` outputs, which is how the current small-context scaling note was produced.
- Power is supported, but activity-based reruns still need the fuller remote toolchain: VCS runtime capture produces VCD, `vcd2saif` produces per-top SAIF, and DC then reports `activity`, `clock_only`, and `zero_toggle`. For the current page-top reviewer-facing `small` bundle, the most useful planning number is usually `activity - clock_only`, because clock power dominates at the `400 ps` target.
- Reuse infrastructure exists, but should not be treated as part of the main path. The repo already documents that parameter-aware DDC reuse is not trustworthy yet for key parameterized blocks such as `UpdatePipelineN`, `SeqHasher`, `SeqSorter`, `FIFO`, and `LifoExpander`.
- Rough `small` planning context already exists from the synced runbook notes even though the accepted mapped tops are remote-mined rather than locally bundled. The dominant `small` misses are about `-568 ps` to `-576 ps`, spread across `hash_table`, `pipe_seq2`-`pipe_seq5`, `update_gen`, and `init_gen`, which points to the hash-table update/write cone rather than just sorter/grouper staging. Secondary misses still exist in `dict_serializer` (about `-461 ps` to `-469 ps`) and `MatchFilterReplace` / result-selection control (roughly `-155 ps` to `-216 ps`).
- Before the deadline, only the reviewer-facing `small` path is packaged as reviewer-usable synthesis evidence. Larger tiers remain engineering context, not one-command reviewer promises.
- Larger-machine suite/geomean runtime tables are still pending and should be dropped in later as replacements for placeholder wording, not layered on as conflicting headline numbers.

## 3. Missing, Partial, Or Likely Time-Consuming Next Steps

- Several algorithmic features are still intentionally absent from the current simulation-capable hardware baseline: static tree, reuse symbols / reuse codes, location dictionary, hardcoded entries such as `Code0={Lit0,Lit0}` and `Code1={Code0,Code0}`, AABAA-specific truncation handling, dual-site / two-sites-per-cycle substitution, and the extra ratio-booster behavior present in the richer software reference.
- These omissions matter for planning because they are not just documentation gaps; they change compression behavior. In other words, the current hardware is a narrower, cleaner baseline than the full software algorithm.
- Feature effort is likely to split cleanly into two categories. Simulation-only feature work is about `5 hours` if the change is localized and does not disturb the current timing-critical update/hash/decompressor cones. The same feature plus `tiny` timing cleanup is about `10` additional hours.
- Scaling timing-sensitive work beyond `tiny` is its own cost center. A good heuristic is about `10 hours` each to carry closure from `tiny` to `small`, then to `medium`, then to `large`. That is a planning heuristic, not a promise.
- The next time-consuming hardware step is probably not “one more small boundary tweak.” The current evidence points toward a deeper pipeline cut in the hash-table update/write path if the goal is real `small` top closure.
- A separate documentation/ops gap remains: if a coauthor or advisor needs a self-contained evidence bundle inside the repo, the accepted `fastpoc_r3` signoff outputs still need to be synced in. Today the repo has the flow and the accepted headline numbers, but not the full accepted remote artifact set.
