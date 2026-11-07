# RST: Random-Access Hardware Sequence Compression — ISCA 2026 Artifact

This bundle boots a Debian 12 VM that already contains both reviewer flows:

- compression-ratio reproduction at `/home/debian/artifact`
- hardware verification at `/home/debian/hw_artifact/rst-hardware`

Host-side quick start:

```bash
./bootvm.sh
ssh -p 2222 debian@localhost
cat /home/debian/README.md
```

`bootvm.sh` now defaults to `8` vCPUs and `8 GiB` of guest RAM so the bundled
hardware flow has enough headroom even if it needs to rebuild a harness.
Override `CPUS` and `MEM` if you need a smaller or larger VM.

The bundled VM is configured for passwordless `debian` login over the forwarded localhost SSH port.
If your SSH client still prompts, just press Enter.

Inside the VM, the primary reviewer commands are:

```bash
cd /home/debian/artifact
bash regenerate_figures.sh

cd /home/debian/hw_artifact/rst-hardware
python3 tools/run_rst_verify.py
```

What the software commands mean:

- For the full paper-style figure flow, run `bash regenerate_figures.sh` without `--quick`. That full run is much slower, but it is the path intended to regenerate the complete figure set.
- On the current bundled VM, the full figure run is on the order of about `50` minutes.
- `bash regenerate_figures.sh --quick` is an optional smoke test. It checks that the software pipeline runs and emits example outputs quickly, but it does not regenerate the full paper-quality figure set.
- In particular, the `--quick` path should not be treated as a faithful reproduction of the final scatter plot. It uses a reduced representative dump subset and an approximate fast RST path for the main figure pipeline.
- The `--quick` run therefore produces visibly different main-figure ratios than the full run. Use it to validate the pipeline, not to cross-check paper numbers.
- By default, the full software flow renders the ablation stage-`V` bar from the bundled measured full-RST `5000`-page summary checkpoint rather than rerunning that multi-hour subexperiment inline.
- To recompute ablation stage `V` from scratch, run `bash regenerate_figures.sh --rerun-stage-v`. That is substantially slower than the default full run because it performs the `memory_blocks={1,2,3,4}` full-RST sweep over the full dump set.
- The bundled software corpus contains `88` dumps across `7` shipped suite prefixes: `DATABASES`, `GRAPHBIG`, `PARSEC`, `SPEC`, `SPARKBENCH`, `DACAPO`, and `RENAISSANCE`.
- If you point `--dumps DIR` at your own files, quick mode groups dumps by the basename prefix before the first underscore. Filenames without an underscore are treated as their own suite/benchmark.
- The exported full-run main-plot CSV uses reviewer-facing column names: `asic_deflate`, `rst`, and `software_deflate`.
- A few preserved helper/header filenames still use the older internal `cram` naming, but the reviewer-facing plots, CSVs, and docs use the paper terminology: `RST`, `asic_deflate`, and `software_deflate`.

If port `2222` is already in use on the host, launch QEMU on a different port:

```bash
SSH_PORT=2223 ./bootvm.sh
ssh -p 2223 debian@localhost
```

If you change the host checkout and want the guest to use that exact version:

- `bash sync_to_vm.sh` from this directory updates `/home/debian/artifact`
- `bash sync_to_vm.sh` from the hardware checkout updates `/home/debian/hw_artifact/rst-hardware`
- The bundled VM already carries the software Python environment. If `regenerate_figures.sh` reports a missing `.venv`, run `bash vm_bootstrap.sh` once inside `/home/debian/artifact` and retry.

Current reviewer notes:

- The bundled VM image is the intended reviewer environment.
- The default hardware reviewer command is `python3 tools/run_rst_verify.py`.
- The recommended broader hardware sweep inside the VM is:
  `python3 tools/run_rst_verify.py /home/debian/artifact/5kcorrectdumps --all-data --pages 256 --jobs 4 --skip-decompressor-check --skip-latency-measurement`
- That `256`-page broad sweep is the reviewer-scaled command for the bundled VM. The full `5000`-page paper-scale sweep is intentionally not the default because it is much slower.
- Expect that broader `256`-page sweep to take several hours on the bundled VM. Roughly `4-6` hours is a reasonable expectation.
- The artifact also bundles the merged paper-scale hardware summary from the off-VM `88`-dump `5000`-page run at:
  `/home/debian/hw_artifact/rst-hardware/evidence/full_suite_88x5000_summary.md`
- The software quick smoke test usually finishes in a few minutes on the bundled VM. Older “~30 minutes” wording should be ignored for `--quick`; that longer expectation applies to the full figure regeneration path instead.

Software tree layout:

- `5kcorrectdumps/`: main dump directory used by the scripts
- `MemComp/`: trimmed baseline compression framework for the ASIC Deflate and software Deflate baselines used by this artifact
- `ablation/`: RST ablation executables
- `rst_figures/`: plotting scripts plus CSV-to-plot helpers
- `generated/`: outputs created by `regenerate_figures.sh`
