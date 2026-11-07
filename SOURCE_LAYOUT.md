# RST reproduction source repository

- `MemComp/`: ASIC Deflate and software Deflate baseline sources.
- `ablation/`, `rst_figures/`: software experiments and plotting scripts.
- `reproduction/extracted/home/debian/hw_artifact/rst-hardware/`: extracted RTL,
  C++ reference, hardware verification tools and documentation.
- `reproduction/`: native execution drivers, environment notes and compact evidence.

The hardware source layout is retained because an active RTL experiment uses it.
No paths were moved when Git was initialized.

VM images, Verilator executable distributions, build trees, object files, raw
memory datasets, simulation traces, and generated experiment directories are ignored.
The `compressor/generated/` RTL files are required source inputs and remain tracked.
External technology libraries are excluded; synthesis requires separately provided tools.

Git author identity is configured locally for this repository only.
