# MemComp Baseline Subset

This artifact carries a trimmed MemComp checkout used only for the software-baseline
compression-ratio measurements in `regenerate_figures.sh`.

Shipped baseline algorithms:

- `lz4_huffman`: reviewer-facing ASIC Deflate baseline
- `deflate`: software Deflate baseline

Kept in this trimmed checkout:

- the main driver in `src/driver.c`
- shared plugin/layout definitions in `include/plugin_struct.h`
- the `lz4_huffman` codec plus its required headers
- the `deflate` codec plus the minimal in-tree zlib sources it builds against
- the shell/python helpers used by this artifact:
  - `runner.sh`
  - `MemComp_summarize_cr.py`

Intentionally removed from this artifact copy:

- unused compression plugins
- unused third-party vendor trees
- upstream docs, CI files, platform ports, and other development-only payloads

Artifact-facing usage:

```bash
make clean
make bootstrap driver
make lz4_huffman
make deflate
```

Then run the artifact helper:

```bash
bash runner.sh --compression "lz4_huffman deflate"
```

The output CSV is then summarized by `MemComp_summarize_cr.py` and merged into the
main paper-figure plotting pipeline.
