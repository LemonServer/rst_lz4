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
    vals = [v for v in vals if v > 0 and not math.isnan(v)]
    if not vals:
        return float("nan")
    return math.exp(sum(math.log(v) for v in vals) / len(vals))


def parse_suite(path):
    name = os.path.splitext(os.path.basename(path))[0]
    if "_" not in name:
        return name
    return name.split("_", 1)[0]


def parse_dictsize(config_label):
    for part in config_label.split(":"):
        if part.startswith("dict="):
            return int(part.split("=", 1)[1])
    raise ValueError(f"missing dict size in config label: {config_label}")


def main():
    ap = argparse.ArgumentParser(description="Summarize deduped working-dump raw RST results by config.")
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    picked = OrderedDict()
    with open(args.input, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            path = row["file"]
            if "/working_dumps/" not in path:
                continue
            key = (row["config_label"], path)
            if key in picked:
                continue
            picked[key] = float(row["compression_ratio"])

    by_cfg = defaultdict(lambda: defaultdict(list))
    for (config_label, path), cr in picked.items():
        suite = parse_suite(path)
        by_cfg[config_label][suite].append(cr)

    summary_rows = []
    for config_label, suites in by_cfg.items():
        dictsize = parse_dictsize(config_label)
        suite_gms = [geomean(suites[s]) for s in GROUP_ORDER if s in suites]
        summary_rows.append({
            "dictsize": dictsize,
            "strategy": "utility",
            "num_suites": len(suite_gms),
            "overall_geogeo_CR": geomean(suite_gms),
            "config_label": config_label,
        })

    summary_rows.sort(key=lambda row: row["dictsize"])

    with open(args.output, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["dictsize", "strategy", "num_suites", "overall_geogeo_CR", "config_label"])
        for row in summary_rows:
            writer.writerow([
                row["dictsize"],
                row["strategy"],
                row["num_suites"],
                f"{row['overall_geogeo_CR']:.12f}",
                row["config_label"],
            ])


if __name__ == "__main__":
    main()
