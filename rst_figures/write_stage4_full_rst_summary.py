#!/usr/bin/env python3
"""Emit the bundled measured full-RST stage-V ablation summary checkpoint.

These values come from the full-RST C++ reference sweep over the 88 working
dump files, using 5000 pages per dump and memory_blocks={1,2,3,4}, then taking
the suite geomean-of-geomeans in the same suite order used by the paper plots.

This script is the default stage-V path in ``regenerate_figures.sh`` because it
keeps the reviewer-facing full figure flow practical. Use
``build_full_rst_stage4_summary.py`` to recompute stage V from scratch.
"""

from __future__ import annotations

import argparse
import csv


ROWS = [
    (64, "utility", 7, 3.095199, "full-rst:memory_blocks=1:pages=5000"),
    (128, "utility", 7, 3.420740, "full-rst:memory_blocks=2:pages=5000"),
    (192, "utility", 7, 3.541648, "full-rst:memory_blocks=3:pages=5000"),
    (256, "utility", 7, 3.561355, "full-rst:memory_blocks=4:pages=5000"),
]


def main() -> None:
    ap = argparse.ArgumentParser(description="Write the measured full-RST stage-V summary CSV.")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    with open(args.output, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["dictsize", "strategy", "num_suites", "overall_geogeo_CR", "config_label"])
        for dictsize, strategy, num_suites, cr, label in ROWS:
            writer.writerow([dictsize, strategy, num_suites, f"{cr:.12f}", label])


if __name__ == "__main__":
    main()
