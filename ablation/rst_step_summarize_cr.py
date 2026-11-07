#!/usr/bin/env python3
import argparse, csv, math, os, re
from collections import defaultdict

UTIL_ORDER = {"select-first": 0, "savings": 1, "utility": 2}

def geomean(vals):
    vals = [v for v in vals if v > 0]
    if not vals:
        return float("nan")
    return math.exp(sum(math.log(v) for v in vals) / len(vals))

def parse_suite_bench(filepath):
    base = os.path.basename(filepath)
    name, _ = os.path.splitext(base)
    if "_" in name:
        suite, bench = name.split("_", 1)
    else:
        suite, bench = name, name
    return suite, bench

def parse_config(label):
    # Example: lz-bse:dict=64:util=select-first:cd=0
    m_dict = re.search(r"dict=(\d+)", label)
    m_util = re.search(r"util=([a-zA-Z\-]+)", label)
    dictsize = int(m_dict.group(1)) if m_dict else None
    util = m_util.group(1) if m_util else None
    return dictsize, util

def main():
    ap = argparse.ArgumentParser(description="Summarize per-config geogeo compression ratios.")
    ap.add_argument("-i", "--infile", required=True, help="Input CSV produced by the compressor.")
    ap.add_argument("-o", "--out", help="Optional output CSV for the summary.")
    args = ap.parse_args()

    # Data: config_label -> suite -> list of per-benchmark CRs
    config_suite_crs = defaultdict(lambda: defaultdict(list))
    config_meta = {}

    with open(args.infile, newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            label = row["config_label"]
            file = row["file"]
            try:
                cr = float(row["compression_ratio"])
            except:
                continue
            suite, bench = parse_suite_bench(file)
            config_suite_crs[label][suite].append(cr)
            if label not in config_meta:
                dictsize, util = parse_config(label)
                config_meta[label] = (dictsize, util)

    # Compute geogeo per config
    summary_rows = []
    for label, suite_map in config_suite_crs.items():
        # suite geomeans
        suite_gms = []
        for suite, crs in suite_map.items():
            gm = geomean(crs)
            if not math.isnan(gm):
                suite_gms.append((suite, gm))
        overall = geomean([gm for _, gm in suite_gms]) if suite_gms else float("nan")

        dictsize, util = config_meta.get(label, (None, None))
        summary_rows.append({
            "config_label": label,
            "dictsize": dictsize,
            "strategy": util,
            "num_suites": len(suite_gms),
            "overall_geogeo_CR": overall
        })

    # Pretty print sorted by dictsize then util strategy order
    summary_rows.sort(key=lambda x: (x["dictsize"] if x["dictsize"] is not None else 0,
                                     UTIL_ORDER.get(x["strategy"], 99)))
    print("\n=== Overall Compression Ratio (geogeo) per Configuration ===")
    print(f"{'dict':>6}  {'strategy':<13}  {'suites':>6}  {'CR (×)':>12}  label")
    for row in summary_rows:
        dictsize = row["dictsize"]
        strat = row["strategy"]
        suites = row["num_suites"]
        cr = row["overall_geogeo_CR"]
        cr_str = f"{cr:.6f}" if not math.isnan(cr) else "nan"
        print(f"{dictsize:>6}  {strat:<13}  {suites:>6}  {cr_str:>12}  {row['config_label']}")

    # Optional CSV
    if args.out:
        with open(args.out, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["dictsize", "strategy", "num_suites", "overall_geogeo_CR", "config_label"])
            for row in summary_rows:
                w.writerow([row["dictsize"], row["strategy"], row["num_suites"],
                            f"{row['overall_geogeo_CR']:.12f}" if not math.isnan(row["overall_geogeo_CR"]) else "nan",
                            row["config_label"]])

if __name__ == "__main__":
    main()
