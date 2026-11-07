#!/usr/bin/env python3
import argparse
import csv
import math
from collections import defaultdict

import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter, FixedLocator, NullFormatter, NullLocator

try:
    import scienceplots
    plt.style.use(["ieee"])
except ImportError:
    pass

plt.rcParams["font.family"] = "serif"
plt.rcParams["font.serif"] = ["Times New Roman", "Times", "DejaVu Serif"]

GROUP_ORDER = [
    "DATABASES",
    "GRAPHBIG",
    "PARSEC",
    "SPEC",
    "SPARKBENCH",
    "DACAPO",
    "RENAISSANCE",
]

GEOMEAN_GROUP = "GEOMEAN"

GROUP_LABELS = {
    "DATABASES": "DBs",
    "GRAPHBIG": "GraphBig",
    "PARSEC": "PARSEC-3.0",
    "SPEC": "SPEC CPU2017",
    "SPARKBENCH": "Spark Bench",
    "DACAPO": "DaCapo",
    "RENAISSANCE": "Renaissance",
    "GEOMEAN": "Geomean",
}

ABBR_MAP = {
    "connectedcomponent": "CC",
    "ConnectedComponent": "CC",
    "graphcoloring": "GraphColor",
    "scala-stm-bench": "STM-bench",
    "MatrixFactorization": "MatrixFact",
    "LinearRegression": "LinReg",
    "LogisticRegression": "LogReg",
    "TriangleCount": "TriCount",
    "DecisionTree": "DecTree",
    "PregelOperation": "Pregel",
    "ShortestPaths": "Shortest",
    "page-rank": "PageRank",
    "scala-doku": "Doku",
    "scala-kmeans": "KMeans",
    "neo4j-analytics": "Neo4j",
    "future-genetic": "Genetic",
    "finagle-chirper": "FinagleChirp",
    "finagle-http": "FinagleHTTP",
    "GeoMean_All": "GeoMean-All",
}


def load_rows(path):
    benchmark_rows = []
    geomean_rows = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            asic_key = "asic_deflate" if "asic_deflate" in row else "lz4_huffman"
            software_key = "software_deflate" if "software_deflate" in row else "deflate"
            parsed = {
                "suite": row["suite"],
                "benchmark": row["benchmark"],
                "row_type": row["row_type"],
                "asic_deflate": parse_float(row[asic_key]),
                "rst": parse_float(row["rst"]),
                "software_deflate": parse_float(row[software_key]),
            }
            if parsed["row_type"] == "benchmark":
                benchmark_rows.append(parsed)
            else:
                geomean_rows.append(parsed)
    return benchmark_rows, geomean_rows


def parse_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return float("nan")


def ordered_suites(suites):
    known = [suite for suite in GROUP_ORDER if suite in suites]
    unknown = sorted(suite for suite in suites if suite not in GROUP_ORDER)
    return known + unknown


def build_plot_lists(benchmark_rows, geomean_rows):
    bench_by_suite = defaultdict(list)
    for row in benchmark_rows:
        bench_by_suite[row["suite"]].append(row)

    suite_geos = [r for r in geomean_rows if r["row_type"] == "suite_geomean"]
    suite_order = ordered_suites(set(bench_by_suite.keys()) | {row["suite"] for row in suite_geos})

    all_rows = []
    for suite in suite_order:
        all_rows.extend(bench_by_suite.get(suite, []))

    suite_geos_by_suite = {row["suite"]: row for row in suite_geos}
    for suite in suite_order:
        if suite in suite_geos_by_suite:
            all_rows.append(suite_geos_by_suite[suite])

    overall = [r for r in geomean_rows if r["row_type"] == "overall_geomean"]
    all_rows.extend(overall)
    return all_rows, suite_order


def ratio_formatter(v, pos):
    if math.isclose(v, 100.0):
        return "1"
    if math.isclose(v, 300.0):
        return "3"
    if math.isclose(v, 1000.0):
        return "10"
    if math.isclose(v, 2500.0):
        return "25"
    return ""


def group_label(group):
    return GROUP_LABELS.get(group, group)


def main():
    ap = argparse.ArgumentParser(description="Plot the main compression figure from measured CSV data.")
    ap.add_argument("--input", required=True)
    ap.add_argument("--output-prefix", default="rst_vs_lz4huff_suite_scatter")
    args = ap.parse_args()

    benchmark_rows, geomean_rows = load_rows(args.input)
    plot_rows, suite_order = build_plot_lists(benchmark_rows, geomean_rows)

    x = list(range(len(plot_rows)))
    all_groups = []
    all_names = []
    asic_deflate_vals = []
    rst_vals = []
    software_deflate_vals = []
    for row in plot_rows:
        if row["row_type"] == "benchmark":
            all_groups.append(row["suite"])
            all_names.append(row["benchmark"])
        else:
            all_groups.append(GEOMEAN_GROUP)
            all_names.append("GeoMean_All" if row["row_type"] == "overall_geomean" else row["suite"])
        asic_deflate_vals.append(row["asic_deflate"] * 100.0)
        rst_vals.append(row["rst"] * 100.0)
        software_deflate_vals.append(
            row["software_deflate"] * 100.0 if not math.isnan(row["software_deflate"]) else None
        )

    xtick_labels = [ABBR_MAP.get(name, name) for name in all_names]

    fig, ax = plt.subplots(figsize=(7.16, 3.8))
    marker_size = 20
    marker_lw = 0.4

    ax.scatter(
        x,
        asic_deflate_vals,
        marker="s",
        s=marker_size,
        facecolors="none",
        edgecolors="tab:blue",
        linewidths=marker_lw,
        label="ASIC Deflate (LZ4 + Huffman)",
    )
    ax.scatter(
        x,
        rst_vals,
        marker="+",
        s=marker_size,
        color="tab:orange",
        linewidths=marker_lw,
        label="RST",
    )

    if any(v is not None for v in software_deflate_vals):
        x_deflate = [idx for idx, value in enumerate(software_deflate_vals) if value is not None]
        y_deflate = [value for value in software_deflate_vals if value is not None]
        ax.scatter(
            x_deflate,
            y_deflate,
            marker="x",
            s=marker_size,
            color="tab:green",
            linewidths=marker_lw,
            label="Deflate (Software)",
        )

    ax.set_yscale("log")
    ax.set_ylabel("Compression\nRatio (log-scale)")
    ax.set_xticks(x)
    ax.set_xticklabels(xtick_labels, rotation=90, fontsize=5)
    ax.set_ylim(80, 10000)
    ax.yaxis.set_major_locator(FixedLocator([100, 300, 1000, 2500]))
    ax.yaxis.set_minor_locator(NullLocator())
    ax.yaxis.set_major_formatter(FuncFormatter(ratio_formatter))
    ax.yaxis.set_minor_formatter(NullFormatter())

    group_bounds = {}
    for idx, group in enumerate(all_groups):
        group_bounds.setdefault(group, [idx, idx])
        group_bounds[group][1] = idx

    label_y = -.6
    arrow_y = label_y + 0.10
    for group in suite_order + [GEOMEAN_GROUP]:
        if group not in group_bounds:
            continue
        start, end = group_bounds[group]
        if group != GEOMEAN_GROUP:
            ax.axvline(end + 0.5, linestyle=":", linewidth=0.5, color="black", ymin=0.06, ymax=1.0)
        ax.annotate(
            "",
            xy=(end + 0.4, arrow_y),
            xytext=(start - 0.3, arrow_y),
            xycoords=ax.get_xaxis_transform(),
            textcoords=ax.get_xaxis_transform(),
            arrowprops=dict(arrowstyle="<->", linewidth=0.5, color="black", shrinkA=0, shrinkB=0),
        )
        mid = (start + end) / 2.0
        ax.text(mid, label_y, group_label(group), ha="center", va="top", transform=ax.get_xaxis_transform(), fontsize=7)

    ax.legend(loc="upper right", bbox_to_anchor=(1.0, 1.05), ncol=3, frameon=True, fancybox=True, framealpha=0.9, borderpad=0.6)
    ax.set_xlim(-0.5, len(all_names) - 0.5)
    fig.subplots_adjust(left=0.08, right=0.99, top=0.78, bottom=0.40)

    pdf_path = f"{args.output_prefix}.pdf"
    png_path = f"{args.output_prefix}.png"
    fig.savefig(pdf_path, bbox_inches="tight")
    fig.savefig(png_path, bbox_inches="tight", dpi=200)
    print(f"Wrote {pdf_path}")
    print(f"Wrote {png_path}")


if __name__ == "__main__":
    main()
