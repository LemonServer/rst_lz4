#!/usr/bin/env python3
import argparse
import csv


DEFAULT_DISPLAY_MAP = {
    80: 64,
}


def main():
    ap = argparse.ArgumentParser(description="Build measured ablation plotting data.")
    ap.add_argument("--stage", nargs=2, action="append", metavar=("LABEL", "SUMMARY_CSV"), required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument(
        "--display-dict-alias",
        action="append",
        default=[],
        metavar="SRC=DST",
        help="Map a measured dict size to a displayed dict size (default: 80=64).",
    )
    args = ap.parse_args()

    display_map = dict(DEFAULT_DISPLAY_MAP)
    for item in args.display_dict_alias:
        src_str, dst_str = item.split("=", 1)
        display_map[int(src_str)] = int(dst_str)

    rows = []
    for label, path in args.stage:
        stage_rows = []
        with open(path, newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                strategy = row.get("strategy")
                if strategy and strategy != "utility":
                    continue
                try:
                    dictsize = int(row["dictsize"])
                    cr = float(row["overall_geogeo_CR"])
                except (KeyError, TypeError, ValueError):
                    continue
                stage_rows.append({
                    "stage": label,
                    "dictsize": dictsize,
                    "display_dictsize": display_map.get(dictsize, dictsize),
                    "cr": cr,
                })
        stage_rows.sort(key=lambda r: (r["display_dictsize"], r["dictsize"]))
        rows.extend(stage_rows)

    with open(args.output, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["stage", "dictsize", "display_dictsize", "compression_ratio"])
        for row in rows:
            writer.writerow([
                row["stage"],
                row["dictsize"],
                row["display_dictsize"],
                f"{row['cr']:.6f}",
            ])


if __name__ == "__main__":
    main()
