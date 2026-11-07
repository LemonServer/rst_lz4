## Small Synthesis Evidence

This is the reviewer-facing synthesis evidence path for this checkout. The packaged
reproducible synthesis flow is intentionally narrow: the public `small` tier is the
synthesis-ready 64-byte page configuration carried in-tree under the historical
internal `tiny` package/file names.

The important source boundary is now explicit:

- reviewer-facing `small` synthesis and standard runtime stay on the frozen signoff-era `m4_filelist.f` RTL
- reviewer-facing experimental `large` verification runs from `experimental/frozen_large/`

So large experimental work no longer shares compressor RTL files with the small synthesis path.

### What This Checkout Supports

- Historical remote closeout reference: `20260404_tiny_tops_ultra_retime_fastpoc_r3`
- Current canonical packaged closeout: `reviewer_small_tops_split_closeout`
- The historical April 4 directory itself is **not** synced into this checkout.
- The compact packaged quick-look for that canonical closeout lives under:
  - `evidence/signoff_summary.md`
  - `evidence/signoff_summary.json`
  - `evidence/reviewer_small_tops_split_closeout_reports_clean_20260409.tar.gz`
- The packaged artifact includes the reviewer-facing `small` rerun kit for Synopsys DC:
  `synthesis/configs/rst_pkg_tiny.sv`, `synthesis/libs/asap7_db/`,
  `synthesis/scripts/run_dc_smoke_batch.sh`, `synthesis/scripts/synth_parser_smoke.tcl`,
  `synthesis/scripts/common_setup.tcl`, `synthesis/scripts/inventory_dc_batch.py`,
  `synthesis/scripts/build_signoff_bundle.py`, and
  `synthesis/scripts/run_small_signoff_closeout.sh`.
- The optional page-top power helpers are also bundled:
  `synthesis/scripts/run_runtime_file_power_capture.sh`,
  `synthesis/scripts/power_from_saif.tcl`, and `synthesis/scripts/filter_saif.py`.
- The checked-in raw DC summaries that a reviewer can inspect directly today still live under
  the historical internal `tiny` batch directories:
  - `synthesis/results/parser_smoke_batches/20260402_tiny_m7b3_assembly/`
  - `synthesis/results/parser_smoke_batches/20260402_tiny_m7b2_refresh/`
- Reviewer-facing `medium` and `large` synthesis flows are not promised here as one-command
  reproducible artifact paths.

### Packaged Rerun Boundary

- Fresh reviewer-facing `small` timing/area reruns are supported from the packaged artifact if the
  reviewer provides `dc_shell` and uses the bundled ASAP7 `.db` files.
- Fresh reviewer-facing `small` compact closeout bundles are supported from the packaged artifact if
  the reviewer provides `dc_shell`; add `vcs` plus `vcd2saif` for page-top power, and Verilator if
  runtime metrics should be regenerated inside the wrapper.
- Internally, the DC flow still uses the synthesis-ready `rst_pkg_tiny.sv` package and the
  accepted internal `tiny` batch naming.
- The smallest packaged DC rerun that covers all four reviewer-facing tops is the `tops_only`
  profile in `run_dc_smoke_batch.sh`.
- The canonical packaged closeout result now comes from the generic rerun path rooted at
  `reviewer_small_tops_split_closeout`.
- Activity-based page-top power reruns are optional and require `vcs` plus `vcd2saif` in addition
  to `dc_shell`.

### Units And Interpretation

- Timing and slack are reported in `ps` in the current DC environment. The reviewer-facing `small`
  target clock period is `400 ps`.
- Power is reported in `mW`.
- Area values come from DC `Design Area` / `report_area` totals using the in-tree ASAP7 `.db`
  library set. Treat them as ASAP7 synthesized cell-area proxies for comparing runs in the same
  flow, not as routed silicon area claims.
- For the page tops, `activity - clock_only` is the easiest workload-dependent dynamic figure to
  cite.

### Canonical Small Closeout Snapshot

These are the current canonical reviewer-facing `small` headline numbers from the packaged fast-POC
closeout bundle `reviewer_small_tops_split_closeout`:

| Top | ASAP7 cell area (DC Design Area) | Slack | Power context |
| --- | ---: | ---: | --- |
| `PageCompressorTop` | `613903.4` | `0.00 ps` | `117.835 mW` activity, `114.627 mW` clock-only, `3.208 mW` activity-minus-clock-only |
| `PageDecompressorTop` | `90773.9` | `0.00 ps` | `18.233 mW` activity, `14.222 mW` clock-only, `4.011 mW` activity-minus-clock-only |
| `CompressorTop` | `638968.8` | `0.00 ps` | No bundled power figure cited here |
| `DecompressorTop` | `71174.7` | `0.01 ps` | No bundled power figure cited here |

Functional context from the reviewer-facing `small` runtime harness on
`data/dacapo_avrora_rand1k` with `16` pages:

- ratio: `1.8208x`
- compressor throughput: `0.1415 B/cycle`
- decompressor throughput: `1.2005 B/cycle`

### Fast Reviewer Path

1. Read the current reviewer-facing `small` summary:

```bash
sed -n '33,60p' docs/rst_status_memo_2026-04-04.md
sed -n '1,120p' evidence/signoff_summary.md
```

2. Inspect the checked-in DC batch summaries that are reproducible from this checkout:

```bash
sed -n '1,120p' synthesis/results/parser_smoke_batches/20260402_tiny_m7b3_assembly/inventory_table.txt
sed -n '1,120p' synthesis/results/parser_smoke_batches/20260402_tiny_m7b3_assembly/qor_summary.txt
sed -n '1,160p' synthesis/results/parser_smoke_batches/20260402_tiny_m7b3_assembly/timing_summary.txt
```

```bash
sed -n '1,120p' synthesis/results/parser_smoke_batches/20260402_tiny_m7b2_refresh/inventory_table.txt
sed -n '1,120p' synthesis/results/parser_smoke_batches/20260402_tiny_m7b2_refresh/qor_summary.txt
sed -n '1,160p' synthesis/results/parser_smoke_batches/20260402_tiny_m7b2_refresh/timing_summary.txt
```

The first checked-in batch carries `CompressorTop`, `DecompressorTop`, and `PageCompressorTop`.
The second checked-in batch carries `PageDecompressorTop` plus supporting leaf-block results.

3. Regenerate the reviewer-facing `small` runtime context locally:

```bash
mkdir -p "$PWD/build/small_perf_context"
python3 tools/run_m4_runtime_file_metrics.py \
  data/dacapo_avrora_rand1k \
  --tier small \
  --pages 16 \
  --write-json "$PWD/build/small_perf_context/small_runtime_file_metrics_16pages.json" \
  --write-log "$PWD/build/small_perf_context/small_runtime_file_metrics_16pages.log"
```

4. Optionally package the checked-in batch summaries into compact markdown:

```bash
python3 synthesis/scripts/build_signoff_bundle.py \
  --batch-label 20260402_tiny_m7b3_assembly \
  --output-dir "$PWD/build/reviewer_small/20260402_tiny_m7b3_assembly" \
  --perf-json "$PWD/build/small_perf_context/small_runtime_file_metrics_16pages.json"
```

```bash
python3 synthesis/scripts/build_signoff_bundle.py \
  --batch-label 20260402_tiny_m7b2_refresh \
  --top PageDecompressorTop \
  --output-dir "$PWD/build/reviewer_small/20260402_tiny_m7b2_refresh" \
  --perf-json "$PWD/build/small_perf_context/small_runtime_file_metrics_16pages.json"
```

5. Optionally rerun a fresh reviewer-facing `small` top-level DC batch from the packaged artifact:

```bash
bash synthesis/scripts/run_dc_smoke_batch.sh \
  --fast-poc \
  --clock-period 0.4 \
  --compile-mode ultra_retime \
  small tops_only reviewer_small_tops
```

```bash
bash synthesis/scripts/run_dc_smoke_batch.sh --summarize-only reviewer_small_tops
python3 synthesis/scripts/build_signoff_bundle.py \
  --batch-label reviewer_small_tops \
  --output-dir "$PWD/build/reviewer_small/reviewer_small_tops"
```

The `tops_only` profile is the smallest bundled rerun that covers `CompressorTop`,
`DecompressorTop`, `PageCompressorTop`, and `PageDecompressorTop` in one batch.

6. Regenerate the compact canonical closeout bundle from an existing batch using generic tool names:

```bash
bash synthesis/scripts/run_small_signoff_closeout.sh \
  --batch-label reviewer_small_tops_split \
  --output-dir "$PWD/build/reviewer_small/reviewer_small_tops_split_closeout" \
  --input-file "$PWD/data/dacapo_avrora_rand1k" \
  --python python3 \
  --verilator-bin verilator \
  --vcs vcs \
  --vcd2saif vcd2saif
```

Skip runtime-metric regeneration or page-top power if those tools are unavailable:

```bash
bash synthesis/scripts/run_small_signoff_closeout.sh \
  --batch-label reviewer_small_tops_split \
  --output-dir "$PWD/build/reviewer_small/reviewer_small_tops_split_closeout" \
  --input-file "$PWD/data/dacapo_avrora_rand1k" \
  --python python3 \
  --skip-runtime-metrics
```

7. Export the canonical small evidence bundle for transfer or archival:

```bash
tar --exclude='*/runtime_capture.vcd' --exclude='*/simv*' -czf \
  "$PWD/build/reviewer_small/reviewer_small_tops_split_closeout_reports.tar.gz" \
  -C "$PWD" \
  "synthesis/results/parser_smoke_batches/reviewer_small_tops_split" \
  "build/reviewer_small/reviewer_small_tops_split_closeout"
```

### Remote Regeneration Boundary

- The historical April 4 closeout batch is still a useful remote reference point.
- The in-tree April 2 batch directories are the current bundled raw-report path.
- The packaged artifact carries the DC rerun scripts, TCL, historical internal `tiny` config, and
  ASAP7 `.db` files needed to make fresh local reviewer-facing `small` batches.
- Rebuilding the canonical packaged closeout evidence requires a Linux Synopsys/VCS setup only for
  the optional page-top power and runtime-capture steps.
- Activity-based page-top power reruns still require external `vcs` and `vcd2saif`; DC alone is
  enough only for timing/area/QoR reruns and summary regeneration.
