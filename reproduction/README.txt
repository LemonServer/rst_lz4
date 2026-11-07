RST native reproduction on 10.134.141.91 (gult), 2026-11-07

Connection constraints: ONE SSH connection only. No tmux, screen, extra login,
SCP/SFTP connections, VM boot, sudo, or root. Reuse the current shell.
No credentials are stored here.

Setup performed:
- Created .venv with system site packages; installed matplotlib and SciencePlots.
- Read-only extraction of the bundled qcow2 using 7-Zip, no VM boot or mounts.
- Extracted hardware/reference sources and Verilator 5.046 under reproduction/extracted/.
- Built native RTL simulation harnesses in the hardware tree's build/native/.
- Added -DZ_HAVE_UNISTD_H to MemComp/src/compression/deflate/Makefile
  for GCC 16 compatibility. Original: reproduction/deflate.Makefile.original.
- Use verilator_bin directly; the host Perl launcher lacks FindBin.

Commands from artifact root, in the SAME existing SSH shell:
  bash reproduction/run_native.sh verify
  bash reproduction/run_native.sh quick
  bash reproduction/run_native.sh full
  bash reproduction/run_native.sh full-stage-v

verify: default 16-page large RTL roundtrip, C++ comparison, standalone SV
         decoder check and direct latency measurement. Two-job build setting.
quick: software smoke only; 7 representative dumps and APPROXIMATE RST.
full: 88-dump/5000-page C++ main figure; ablation stage V uses bundled checkpoint.
full-stage-v: also recomputes stage V instead of reusing the checkpoint.
The full commands can take much longer. They have not yet been executed here.
The wrapper preserves any prior generated/ directory before figure runs.
Run in foreground and keep the single SSH connection open until completion.

Evidence:
  reproduction/quick-run-fixed.log (PASS, exit 0, 43 seconds)
  generated/data/ and generated/figures/ (QUICK outputs, not full reproduction)
  reproduction/hardware-native.log
  reproduction/extracted/home/debian/hw_artifact/rst-hardware/build/native/default-result.json
  reproduction/python-packages.txt

Do not claim ASIC timing/area/power or full-suite results from this smoke test.
A 2.5 GHz conversion of RTL cycles is not a measurement of server or FPGA speed.
The original qcow2 image is unchanged.

Observed native verification: PASS (16/16 pages, dacapo_avrora_rand1k).
Hardware compression ratio: 6.5022x.
Compressor: 52721 cycles, 1.2431 B/cycle.
Decompressor: 11468 cycles, 5.7147 B/cycle.
Independent decoder check: 16/16 pages.
Critical 64B latency: 58.53 cycles = 23.41 ns at assumed 2.5 GHz.
Full chunk latency: 73.55 cycles = 29.42 ns at assumed 2.5 GHz.
These are one-workload smoke measurements, NOT 88-benchmark means.
Summary copy: reproduction/hardware-result.json.

C++ reference ratio: 6.5127x; hardware difference approximately -0.161%.
Temporary raw partition copy removed after successful extraction.

Full 88-dataset software reproduction including recomputed stage V: PASS, 2316 seconds.
Comparison: reproduction/full-comparison.json and reproduction/完整复现对比.txt.
Source and result archives transferred through this same SSH connection with SHA256 verification.
