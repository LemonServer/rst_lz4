#!/usr/bin/env python3
import argparse
import csv
import math
import os
from collections import OrderedDict, defaultdict


GROUP_ORDER = [
    "DATABASES",
    "GRAPHBIG",
    "PARSEC",
    "SPEC",
    "SPARKBENCH",
    "DACAPO",
    "RENAISSANCE",
]


def geomean(vals):
    vals = [v for v in vals if v is not None and not math.isnan(v) and v > 0]
    if not vals:
        return float("nan")
    return math.exp(sum(math.log(v) for v in vals) / len(vals))


def parse_suite_bench_from_path(path):
    name = os.path.splitext(os.path.basename(path))[0]
    if "_" in name:
        return name.split("_", 1)
    return name, name


def load_memcomp_summary(path):
    rows = OrderedDict()
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            suite = row["suite"]
            bench = row["benchmark"]
            if bench == "GEOMEAN" or suite == "ALL":
                continue
            key = f"{suite}_{bench}"
            parsed = {"suite": suite, "benchmark": bench}
            for col, value in row.items():
                if col in {"suite", "benchmark"}:
                    continue
                try:
                    parsed[col] = float(value)
                except (TypeError, ValueError):
                    parsed[col] = float("nan")
            rows[key] = parsed
    return rows


def column_exists(memcomp_rows, column):
    if not memcomp_rows:
        return False
    sample = next(iter(memcomp_rows.values()))
    return column in sample


def load_rst_raw(path, wanted_config):
    rows = {}
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["config_label"] != wanted_config:
                continue
            suite, bench = parse_suite_bench_from_path(row["file"])
            key = f"{suite}_{bench}"
            rows[key] = {
                "suite": suite,
                "benchmark": bench,
                "rst": float(row["compression_ratio"]),
            }
    return rows


def load_rst_full(path):
    rows = {}
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = f"{row['suite']}_{row['benchmark']}"
            rows[key] = {
                "suite": row["suite"],
                "benchmark": row["benchmark"],
                "rst": float(row["rst_full"]),
            }
    return rows


def suite_sort_key(suite):
    try:
        return GROUP_ORDER.index(suite)
    except ValueError:
        return len(GROUP_ORDER)


def ordered_suites(suites):
    known = [suite for suite in GROUP_ORDER if suite in suites]
    unknown = sorted(suite for suite in suites if suite not in GROUP_ORDER)
    return known + unknown


def main():
    ap = argparse.ArgumentParser(description="Build measured main-figure plotting data.")
    ap.add_argument("--memcomp-summary", required=True)
    ap.add_argument("--rst-raw")
    ap.add_argument("--rst-full")
    ap.add_argument("--rst-config", default="lz-bse:dict=128:util=utility:cd=1")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    if not args.rst_raw and not args.rst_full:
        raise SystemExit("one of --rst-raw or --rst-full is required")

    memcomp = load_memcomp_summary(args.memcomp_summary)
    if args.rst_full:
        rst = load_rst_full(args.rst_full)
    else:
        rst = load_rst_raw(args.rst_raw, args.rst_config)

    asic_deflate_col = "asic_deflate" if column_exists(memcomp, "asic_deflate") else "lz4_huffman"
    software_deflate_col = "software_deflate" if column_exists(memcomp, "software_deflate") else None
    if software_deflate_col is None and deflate_col_exists(memcomp):
        software_deflate_col = "deflate"

    merged = []
    for key, mrow in memcomp.items():
        if key not in rst:
            continue
        merged.append({
            "suite": mrow["suite"],
            "benchmark": mrow["benchmark"],
            "asic_deflate": mrow.get(asic_deflate_col, float("nan")),
            "rst": rst[key]["rst"],
            "software_deflate": mrow.get(software_deflate_col, float("nan")) if software_deflate_col else float("nan"),
            "row_type": "benchmark",
        })

    merged.sort(key=lambda r: (suite_sort_key(r["suite"]), r["suite"], r["benchmark"]))

    suite_vals = defaultdict(lambda: {"asic_deflate": [], "rst": [], "software_deflate": []})
    for row in merged:
        suite_vals[row["suite"]]["asic_deflate"].append(row["asic_deflate"])
        suite_vals[row["suite"]]["rst"].append(row["rst"])
        if not math.isnan(row["software_deflate"]):
            suite_vals[row["suite"]]["software_deflate"].append(row["software_deflate"])

    geomean_rows = []
    for suite in ordered_suites(suite_vals.keys()):
        if suite not in suite_vals:
            continue
        vals = suite_vals[suite]
        geomean_rows.append({
            "suite": suite,
            "benchmark": "GEOMEAN",
            "asic_deflate": geomean(vals["asic_deflate"]),
            "rst": geomean(vals["rst"]),
            "software_deflate": geomean(vals["software_deflate"]) if vals["software_deflate"] else float("nan"),
            "row_type": "suite_geomean",
        })

    overall = {
        "suite": "ALL",
        "benchmark": "GEOGEO",
        "asic_deflate": geomean([r["asic_deflate"] for r in geomean_rows]),
        "rst": geomean([r["rst"] for r in geomean_rows]),
        "software_deflate": geomean(
            [r["software_deflate"] for r in geomean_rows if not math.isnan(r["software_deflate"])]
        ),
        "row_type": "overall_geomean",
    }

    with open(args.output, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["suite", "benchmark", "row_type", "asic_deflate", "rst", "software_deflate"])
        for row in merged + geomean_rows + [overall]:
            writer.writerow([
                row["suite"],
                row["benchmark"],
                row["row_type"],
                fmt(row["asic_deflate"]),
                fmt(row["rst"]),
                fmt(row["software_deflate"]),
            ])


def deflate_col_exists(memcomp_rows):
    return column_exists(memcomp_rows, "deflate")


def fmt(value):
    if value is None or math.isnan(value):
        return "nan"
    return f"{value:.6f}"


if __name__ == "__main__":
    main()
