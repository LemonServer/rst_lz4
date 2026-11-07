# RST: Random-Access Hardware Sequence Compression — ISCA 2026 Artifact

## Quick Start

### Compression Ratio Reproduction (Fig. 18, Fig. 19)
cd /home/debian/artifact
bash regenerate_figures.sh
# Full paper-style figure regeneration. On the bundled VM this is roughly a 50-minute run.
# The bundled corpus contains 88 dumps across 7 shipped suite prefixes.
# By default, the ablation stage-V bar uses a bundled measured full-RST 5000-page summary checkpoint.
# The final exported main-plot CSV uses reviewer-facing columns: asic_deflate, rst, software_deflate.

### Optional Full Stage-V Rerun
cd /home/debian/artifact
bash regenerate_figures.sh --rerun-stage-v
# Recomputes ablation stage V from scratch using the full-RST C++ sweep.
# This is much slower than the default full run.

### Optional Software Smoke Test
cd /home/debian/artifact
bash regenerate_figures.sh --quick
# Fast smoke test only. Finishes in a few minutes and emits example outputs.
# It does not regenerate the full paper-quality figure set.
# Its main-figure ratios are intentionally not paper-faithful.

# The bundled VM should already contain the prepared Python environment.
# If regenerate_figures.sh reports a missing .venv, run:
#   bash vm_bootstrap.sh
# If you use --dumps DIR with your own files, quick mode groups dumps by the
# basename prefix before the first underscore. Filenames without an underscore
# are treated as their own suite/benchmark.

### Hardware Functional Verification
cd /home/debian/hw_artifact/rst-hardware
python3 tools/run_rst_verify.py
# Expected: a few to ~15 minutes depending on whether Verilator rebuilds.
# Shows end-to-end pass/fail plus ratio, throughput, decompressor decode, and direct latency metrics.

### Full Benchmark Suite (optional, longer)
cd /home/debian/hw_artifact/rst-hardware
python3 tools/run_rst_verify.py /home/debian/artifact/5kcorrectdumps --all-data --pages 256 --jobs 4 --skip-decompressor-check --skip-latency-measurement
# Reviewer-scaled broad sweep for the bundled VM.
# Expect several hours; roughly 4-6 hours is a reasonable expectation.
# The full 5000-page paper-scale sweep is much slower.
# Bundled paper-scale merged summary from the off-VM 88-dump 5000-page run:
#   /home/debian/hw_artifact/rst-hardware/evidence/full_suite_88x5000_summary.md

### Synthesis (requires Synopsys DC, optional)
See /home/debian/hw_artifact/rst-hardware/synthesis/SMALL_SIGNOFF_FLOW.md
