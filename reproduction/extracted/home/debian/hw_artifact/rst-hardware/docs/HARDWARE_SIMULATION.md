# Hardware Verification Guide

This repo is packaged so a reviewer can reproduce the large-tier hardware verification flow directly from repo root.

## Quick Start

Run the default reviewer flow:

```bash
python3 tools/run_rst_verify.py
```

That command uses:

- input: `data/dacapo_avrora_rand1k`
- tier: `large`
- pages: `16`
- Verilator: `verilator` from `PATH` by default

Expected success summary:

- `PASS reviewer verification`
- `pages: 16`
- `hardware ratio: about 6.5022x`
- standalone SV decompressor decode passes
- direct chunk-level decompressor latency is reported

What the default command checks:

1. Builds the large-tier SystemVerilog round-trip harness.
2. Runs the end-to-end hardware round-trip on the bundled dump.
3. Runs an aggregate C++ metric cross-check in parallel.
4. Runs the standalone SV decompressor decode check.
5. Reports direct decompressor latency using the dedicated chunk-level harness.

The reviewer-facing summary intentionally keeps the C++ comparison informational. Exact mismatch counts are not part of the reviewer report.

## Broader Sweep

The larger `88`-dump corpus is stored once with the software artifact under:

```text
/home/debian/artifact/5kcorrectdumps
```

For a reviewer-scaled broad sweep inside the bundled VM, use:

```bash
python3 tools/run_rst_verify.py /home/debian/artifact/5kcorrectdumps --all-data --pages 256 --jobs 4 --skip-decompressor-check --skip-latency-measurement
```

Why those skip flags are recommended:

- the broad sweep is mainly for ratio validation across the suite
- rerunning the standalone decompressor decode and direct latency harness on every dump adds a lot of extra time without changing the main reviewer verdict

Runtime expectation on the bundled `8 vCPU / 8 GiB` VM:

- expect several hours
- roughly `4-6` hours is a reasonable expectation for the full `88`-dump, `256`-page sweep

This reviewer-scaled `256`-page run is the recommended broad sweep for the bundled VM. The full `5000`-page paper-scale sweep is intentionally not the default reviewer path.

For the bundled paper-scale reference summary from the merged off-VM `88`-dump
`5000`-page run, see:

- `evidence/full_suite_88x5000_summary.md`
- `evidence/full_suite_88x5000_summary.json`
- `evidence/full_suite_88x5000_summary.stdout`

Most useful bundled full-suite numbers:

- pooled hardware ratio: `2.7285x`
- benchmark geomean ratio: `3.1963x` hardware vs `3.2090x` C++
- suite geomean-of-geomeans ratio: `3.4109x` hardware vs `3.4242x` C++ (`-0.390%`)
- suite geomean-of-geomeans compressor throughput: `1.5486 B/cycle` = `3.8716 GB/s @ 2.5 GHz`
- suite geomean-of-geomeans decompressor throughput: `7.2091 B/cycle` = `18.0227 GB/s @ 2.5 GHz`
- suite geomean-of-geomeans decompressor critical-`64B` latency: `44.95` cycles = `17.98 ns`
- suite geomean-of-geomeans decompressor full-chunk latency: `55.69` cycles = `22.28 ns`

## Runtime Notes

- The first run is dominated by Verilator compile plus simulation.
- Reruns reuse the cached build directories under `build/verilator/`.
- Logs are written under `build/rst_verify/logs/`.
- When `--jobs` is greater than `1`, the runner shards the selected pages across multiple hardware instances and merges the results back into one summary.
- The C++ reference helper is built under `build/rst_verify/reference_cpp/`.

Local validation used Verilator `5.046`.
Debian 12's packaged `verilator 5.006-3` is not sufficient for this RTL.
The bundled VM is already configured with a newer working Verilator.

## Custom Inputs

Run a custom file with the default `16` pages:

```bash
python3 tools/run_rst_verify.py data/my_input.bin
```

Run a custom file with an explicit page count:

```bash
python3 tools/run_rst_verify.py data/my_input.bin 32
```

Run the whole file:

```bash
python3 tools/run_rst_verify.py data/my_input.bin --pages 0
```

Process every dump in a directory:

```bash
python3 tools/run_rst_verify.py /path/to/dumps --all-data --pages 64
```

Write a JSON summary:

```bash
python3 tools/run_rst_verify.py --write-json build/rst_verify/summary.json
```

## Synthesis Evidence

The primary reviewer gate in this repo is still the large-tier verification flow above.
The packaged synthesis evidence path is narrower and intentionally limited to reviewer-facing `small`.

Start with:

- `synthesis/SMALL_SIGNOFF_FLOW.md`
- `docs/rst_status_memo_2026-04-04.md`
- `evidence/signoff_summary.md`

The packaged artifact includes:

- the reviewer-facing `small` DC rerun kit
- the trimmed ASAP7 `.db` files under `synthesis/libs/asap7_db/`
- the checked-in synthesis evidence directories under `synthesis/results/parser_smoke_batches/`
- the generic `synthesis/scripts/run_small_signoff_closeout.sh` wrapper
- the cleaned compact evidence archive under `evidence/reviewer_small_tops_split_closeout_reports_clean_20260409.tar.gz`

The public reviewer-facing tier name is `small`.
Some underlying filenames still retain the historical internal `tiny` naming because that is the preserved DC/synthesis-ready path.
Likewise, a few helper/reference filenames still retain the older internal `cram` naming, but the reviewer-facing flows and reported metrics use the `RST` terminology from the paper.

## Notes

- Run everything from repo root.
- The default reviewer verdict comes from the end-to-end hardware round-trip plus the reported ratio and throughput metrics.
- The broad sweep command above is a scaled reviewer check, not the paper-scale full sweep.
