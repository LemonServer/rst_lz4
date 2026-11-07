#!/usr/bin/env python3
import argparse, csv, math, os
from collections import defaultdict, OrderedDict

DISPLAY_NAMES = {
    "lz4_huffman": "asic_deflate",
    "deflate": "software_deflate",
}


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


def load_csv(path):
    """Strip repeated header lines and timing lines, return algos and clean rows."""
    fixed = {"file name", "file size", "elf", "zero pages"}
    algos = []
    rows = []

    with open(path, newline="") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("Time spent"):
                continue
            fields = next(csv.reader([line]))
            fields = [f.strip() for f in fields]
            if fields and fields[0] == "file name":
                algos = [c for c in fields if c and c not in fixed]
                continue
            if fields and fields[0]:
                rows.append(fields)

    return algos, rows


def display_algo_name(name):
    return DISPLAY_NAMES.get(name, name)


def main():
    ap = argparse.ArgumentParser(description="Per-benchmark CR report with geogeo summary.")
    ap.add_argument("-i", "--infile", required=True, help="Input CSV from driver.")
    ap.add_argument("-o", "--out", required=True, help="Output CSV file.")
    args = ap.parse_args()

    algos, rows = load_csv(args.infile)

    if not algos:
        print("ERROR: No algorithm columns found.")
        return

    # Collect: suite -> bench -> algo -> cr
    # Use OrderedDict to preserve insertion order
    data = OrderedDict()  # suite -> OrderedDict(bench -> {algo: cr})

    for fields in rows:
        if len(fields) < 4 + len(algos):
            continue
        filepath = fields[0]
        suite, bench = parse_suite_bench(filepath)
        if suite not in data:
            data[suite] = OrderedDict()
        if bench not in data[suite]:
            data[suite][bench] = {}
        for i, algo in enumerate(algos):
            try:
                cr = float(fields[4 + i])
            except (ValueError, IndexError):
                cr = float("nan")
            data[suite][bench][algo] = cr

    # Build CSV rows
    # Columns: suite, benchmark, <algo1>, <algo2>, ...
    # Then after each suite's benchmarks: a suite geomean row
    # At the end: overall geogeo row

    # suite -> algo -> [cr per bench]
    suite_crs = defaultdict(lambda: defaultdict(list))
    # algo -> [suite geomeans]
    overall_suite_gms = defaultdict(list)

    with open(args.out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["suite", "benchmark"] + [display_algo_name(algo) for algo in algos])

        for suite, benches in data.items():
            for bench, algo_crs in benches.items():
                row = [suite, bench]
                for algo in algos:
                    cr = algo_crs.get(algo, float("nan"))
                    row.append(f"{cr:.6f}" if not math.isnan(cr) else "nan")
                    if not math.isnan(cr) and cr > 0:
                        suite_crs[suite][algo].append(cr)
                w.writerow(row)

            # Suite geomean row
            suite_gm_row = [suite, "GEOMEAN"]
            for algo in algos:
                gm = geomean(suite_crs[suite][algo])
                suite_gm_row.append(f"{gm:.6f}" if not math.isnan(gm) else "nan")
                if not math.isnan(gm):
                    overall_suite_gms[algo].append(gm)

        # Overall geogeo row
        geogeo_row = ["ALL", "GEOGEO"]
        for algo in algos:
            gg = geomean(overall_suite_gms[algo])
            geogeo_row.append(f"{gg:.6f}" if not math.isnan(gg) else "nan")
        w.writerow(geogeo_row)

    print(f"Written to: {args.out}")

    # Also print geogeo summary to console
    print("\n=== Geogeo Compression Ratio per Algorithm ===")
    print(f"{'algorithm':<24}  {'GEOGEO':>12}")
    print("-" * 38)
    for algo in algos:
        gg = geomean(overall_suite_gms[algo])
        label = display_algo_name(algo)
        print(f"{label:<24}  {gg:>12.6f}" if not math.isnan(gg) else f"{label:<24}  {'nan':>12}")


if __name__ == "__main__":
    main()
