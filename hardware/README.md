# RST Hardware Verification Artifact

This checkout is the reviewer-facing hardware subtree shipped inside the unified ISCA 2026 artifact VM.

The primary reviewer command from repo root is:

```bash
python3 tools/run_rst_verify.py
```

That default run:

- builds the large-tier SystemVerilog round-trip harness
- runs the bundled `data/dacapo_avrora_rand1k` dump for `16` pages
- reports end-to-end hardware ratio and throughput
- runs an aggregate C++ ratio cross-check in parallel
- runs the standalone SV decompressor decode check
- reports direct chunk-level decompressor latency

Expected default result on the bundled dump:

- `PASS reviewer verification`
- `pages: 16`
- `hardware ratio: about 6.5022x`

The broader `88`-dump corpus is stored once with the software artifact at `/home/debian/artifact/5kcorrectdumps`.
For a reviewer-scaled broad sweep inside the bundled VM, use:

```bash
python3 tools/run_rst_verify.py /home/debian/artifact/5kcorrectdumps --all-data --pages 256 --jobs 4 --skip-decompressor-check --skip-latency-measurement
```

That broader sweep is intended for ratio validation, not for rerunning every standalone sub-check on every dump.
On the bundled `8 vCPU / 8 GiB` VM, expect that command to take several hours; roughly `4-6` hours is a reasonable expectation.

The artifact also bundles a paper-scale merged summary from an off-VM `88`-dump
`5000`-page run:

- `evidence/full_suite_88x5000_summary.md`
- `evidence/full_suite_88x5000_summary.json`
- `evidence/full_suite_88x5000_summary.stdout`

Headline paper-style numbers from that merged run:

- suite geomean-of-geomeans ratio: `3.4109x` hardware vs `3.4242x` C++ (`-0.390%`)
- suite geomean-of-geomeans compressor throughput: `1.5486 B/cycle` = `3.8716 GB/s @ 2.5 GHz`
- suite geomean-of-geomeans decompressor throughput: `7.2091 B/cycle` = `18.0227 GB/s @ 2.5 GHz`
- suite geomean-of-geomeans decompressor critical-`64B` latency: `44.95` cycles = `17.98 ns`
- suite geomean-of-geomeans decompressor full-chunk latency: `55.69` cycles = `22.28 ns`

Source-tree boundary:

- reviewer-facing `small` synthesis and standard runtime stay on the frozen `m4_filelist.f` baseline
- reviewer-facing `large` verification uses the copied snapshot under `experimental/frozen_large/`

So large-path verification changes do not mutate the packaged `small` synthesis baseline.

Useful reviewer-facing paths:

- `docs/HARDWARE_SIMULATION.md`
- `synthesis/SMALL_SIGNOFF_FLOW.md`
- `docs/rst_status_memo_2026-04-04.md`
- `evidence/signoff_summary.md`
- `evidence/full_suite_88x5000_summary.md`

Repo surface:

- `compressor/`, `decompressor/`: RTL, generated blocks, and testbenches
- `experimental/frozen_large/`: copied large-tier verification RTL snapshot
- `tools/`: reviewer entry points and measurement helpers
- `synthesis/`: reviewer-facing `small` synthesis evidence and rerun scripts
- `evidence/`: compact packaged `small` closeout summaries
- `third_party/cram_cpp/`: vendored C++ ratio cross-check/reference implementation

The reviewer-facing output intentionally keeps the C++ comparison at the summary-ratio level. Exact page-by-page mismatch counts are not part of the reviewer report.
