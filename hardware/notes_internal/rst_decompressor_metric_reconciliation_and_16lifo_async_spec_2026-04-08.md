# Decompressor Metric Reconciliation And 16-LIFO Async Spec

## Why The Current Artifact Numbers Diverged From The Old Paper Figures

- The old low latency number was not a full-`256B` chunk-completion metric. It was effectively a sampled compressed-access proxy. The current artifact path was timing full chunk/page completion, which is a harder object.
- The old Python flow also reported segment/sample cycles directly and, in older downstream use, that was too easily compared as if it were always a `256B` block. That scaling was not defensible.
- Sampling bias existed, but it was secondary. The dominant mismatch was measuring different objects: sampled compressed-window service versus full chunk completion.
- The current artifact throughput gap was also amplified by the page wrapper being stop-and-wait: it waits for the slowest LIFO segment on every chunk before launching the next chunk. That is not a steady-state throughput path.

## Chosen Plan

- Increase large-tier decompressor LIFOs from `8` to `16`.
- Keep chunk partitioning logic unchanged for now.
- Change the page wrapper to an async/steady-state launch model across chunks within a page.
- Report decompressor latency as average critical `64B` block availability, not full `256B` chunk completion.

## Modeled Expectations

- `16` LIFOs, no repartition change, average critical `64B` latency:
  - current chunk-space model: `41.59` stack cycles = `16.64 ns`
  - old sampled-window proxy: `42.30` stack cycles = `16.92 ns`
- `16` LIFOs, serialized page wrapper throughput:
  - `10.51 GB/s` conservative artifact-style estimate
- `16` LIFOs, async page wrapper throughput:
  - `14.56 GB/s` conservative artifact-style estimate
  - `18.76 GB/s` raw decompressor-side steady-state model

Interpretation:

- The `16`-LIFO change by itself is enough to recover the target latency band once latency is measured as average critical `64B` availability.
- The async page wrapper is the throughput-critical change. Without it, `16` LIFOs are still short on throughput.

## Post-Implementation Note

- The async `16`-LIFO page wrapper was implemented and clears the throughput target on the current reviewer-facing SV path.
- On a direct `16`-page `dacapo_avrora_rand1k` runtime run, page decompression measured `5.7147 B/cycle`, or about `14.29 GB/s` at `2.5 GHz`.
- The chunk-level SV latency harness was then updated to match the Python critical-`64B` accounting more closely by tracking per-segment literal timestamps, not just segment completion.
- On the same `16` pages:
  - Python chunk model, `16` LIFOs: `59.35` cycles average critical `64B`
  - Direct SV chunk harness, `16` LIFOs: `63.35` cycles average critical `64B`
  - Direct SV chunk harness, full chunk completion: `81.70` cycles
- So the latency path is no longer grossly mismatched. The remaining gap to the Python model is about `4` cycles on this run, which is consistent with fixed chunk-wrapper overhead rather than a broken measurement contract.

## Final Official-Suite Verification

- Sweep: official merged `88`-dump suite at `data/5kcorrectdumps`
- Sample size: requested `5000` pages per dump, with `435461` selected pages across the merged run
- Throughput path: reviewer-facing runtime SV path with end-to-end round-trip checking enabled in the runtime testbench
- Latency path: direct chunk SV harness measuring average critical `64B` block availability

Observed geomeans:

- Suite geomean-of-geomeans throughput: `18.0227 GB/s` (`7.2091 B/cycle`)
- Benchmark geomean throughput: `18.5625 GB/s` (`7.4250 B/cycle`)
- Average critical `64B` latency, suite geomean-of-geomeans: `44.9486` cycles = `17.9795 ns`
- Average critical `64B` latency, benchmark geomean: `42.4946` cycles = `16.9978 ns`
- Full `256B` chunk completion latency, suite geomean-of-geomeans: `55.6931` cycles = `22.2772 ns`
- Full `256B` chunk completion latency, benchmark geomean: `52.0082` cycles = `20.8033 ns`

Interpretation:

- The implemented `16`-LIFO async path clears the throughput goal with margin on the merged official suite.
- The implemented average critical `64B` latency also clears the relaxed `<19 ns` goal on the merged official suite.
- The older modeled `~16.6-16.9 ns` expectation was optimistic relative to final SV, but the final measured path still lands in the desired latency band.

## SystemVerilog Change Spec

### 1. Increase LIFO count

- File: [rst_pkg.sv](/private/tmp/rst_artifact_decomp_gap/rst_pkg.sv)
- Change large-tier and default `DECOMP_LIFOS` from `8` to `16`.
- This also updates `MAX_DECOMP_SEG_TOKENS = (CHUNK_WIDTH + DECOMP_LIFOS - 1) / DECOMP_LIFOS`.

### 2. Replace stop-and-wait page scheduling with async lane scheduling

- File: [experimental_page_decompressor_top.sv](/private/tmp/rst_artifact_decomp_gap/decompressor/experimental_page_decompressor_top.sv)
- Today this wrapper is strictly serialized:
  - load one chunk
  - start one `ExperimentalDecompressorTop`
  - wait for `chunk_done`
  - copy the chunk output
  - move to the next chunk
- That serialization is the throughput bottleneck. The async path must allow lane `i` of chunk `N+1` to begin as soon as lane `i` finishes chunk `N`, without waiting for the slowest lane of chunk `N`.

Implement it as a page-scoped scheduler, not by trying to reuse the current monolithic `chunk_done` interface:

- Decode the page dictionary once at page start and hold `dict_seqs/dict_lens/dict_count` for the whole page.
- Parse each chunk once, compact valid tokens once, and compute the normal even split for `16` LIFOs.
- Maintain `16` persistent decompressor lanes across the page. Each lane owns one FIFO/queue of segment work items.
- Each work item should at least carry:
  - `chunk_idx`
  - `seg_idx`
  - segment input symbols
  - segment input count
  - segment output base offset within the chunk
- A lane launches its next queued segment immediately after its current segment finishes.
- When a segment completes, write its output into page storage for that chunk at the precomputed chunk-local offset.
- Track per-chunk completed-segment count; a chunk is logically complete once all `16` segments have returned.
- The page is done once all chunks have all segments complete.

### 3. Do not depend on per-chunk global done for steady-state throughput

- The current [experimental_page_decompressor_top.sv](/private/tmp/rst_artifact_decomp_gap/decompressor/experimental_page_decompressor_top.sv) `WAIT_CHUNK` state is exactly what must be removed from the steady-state path.
- A wrapper that still waits for whole-chunk completion before launching any part of the next chunk will not realize the modeled throughput gain.

## Verification Targets

- Functional output must remain bit-identical to the current serialized page decompressor.
- Reviewer-facing throughput target for the new path: approximately `14.6 GB/s` or better on the official suite under the current conservative accounting.
- Reviewer-facing latency target for the new path: below `19 ns` average critical `64B` block latency on the official suite.
