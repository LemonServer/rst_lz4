# Full 88-Dump `5000`-Page Hardware Summary

This note captures the merged paper-scale hardware verification summary from the
off-VM `88`-dump run over `data/5kcorrectdumps` with `5000` requested pages per
dump. It is bundled here as artifact evidence because the packaged VM instead
documents a reviewer-scaled `256`-page broad sweep.

Companion files:

- `evidence/full_suite_88x5000_summary.json`
- `evidence/full_suite_88x5000_summary.stdout`

## Top-Level Result

- Status: `PASS reviewer verification suite`
- Inputs: `88/88` passed
- Requested pages per dump: `5000`
- Selected pages across the merged run: `435461`
- Short files: `1`
- Pooled hardware ratio: `2.7285x`

## Paper-Style Aggregate Metrics

Suite geomean-of-geomeans:

- ratio: `3.4109x` hardware vs `3.4242x` C++, delta `-0.390%`
- compressor throughput: `1.5486 B/cycle` = `3.8716 GB/s @ 2.5 GHz`
- decompressor throughput: `7.2091 B/cycle` = `18.0227 GB/s @ 2.5 GHz`
- decompressor critical-`64B` latency: `44.95` cycles/block = `17.98 ns/block @ 2.5 GHz`
- decompressor full-chunk latency: `55.69` cycles/chunk = `22.28 ns/chunk @ 2.5 GHz`

Benchmark geomeans:

- ratio: `3.1963x` hardware vs `3.2090x` C++
- compressor throughput: `1.5433 B/cycle` = `3.8582 GB/s @ 2.5 GHz`
- decompressor throughput: `7.4250 B/cycle` = `18.5625 GB/s @ 2.5 GHz`
- decompressor critical-`64B` latency: `42.49` cycles/block = `17.00 ns/block @ 2.5 GHz`
- decompressor full-chunk latency: `52.01` cycles/chunk = `20.80 ns/chunk @ 2.5 GHz`

## Per-Suite Ratio Geomeans

| Suite | Inputs | Hardware ratio | C++ ratio |
| --- | ---: | ---: | ---: |
| `DACAPO` | `12` | `4.4244x` | `4.4386x` |
| `DATABASES` | `5` | `4.4620x` | `4.4906x` |
| `GRAPHBIG` | `7` | `4.7975x` | `4.8077x` |
| `PARSEC` | `16` | `2.2634x` | `2.2776x` |
| `RENAISSANCE` | `25` | `3.2469x` | `3.2604x` |
| `SPARKBENCH` | `11` | `2.9385x` | `2.9492x` |
| `SPEC` | `12` | `2.6259x` | `2.6301x` |

## Interpretation

- This is the best bundled paper-scale hardware summary in the artifact.
- It supersedes the older provisional `100`-page remote checkpoints that were
  previously referenced in the status memo.
- The bundled VM still documents the `256`-page broad sweep as the practical
  reviewer rerun path; this merged summary exists so the paper-facing final
  numbers are visible inside the artifact without requiring a multi-hour cluster
  rerun.
