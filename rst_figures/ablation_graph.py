#!/usr/bin/env python3
import argparse
import csv
import math
from collections import OrderedDict

import matplotlib.pyplot as plt
from matplotlib.patches import Patch

try:
    import scienceplots
    plt.style.use(["ieee", "grid"])
except ImportError:
    pass

plt.rcParams["font.family"] = "serif"
plt.rcParams["font.serif"] = ["Times New Roman", "DejaVu Serif"]


def load_rows(path):
    stage_order = []
    dictsizes = []
    values = OrderedDict()

    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stage = row["stage"]
            dictsize = int(row.get("display_dictsize") or row["dictsize"])
            cr = float(row["compression_ratio"])
            if stage not in values:
                values[stage] = {}
                stage_order.append(stage)
            values[stage][dictsize] = cr
            if dictsize not in dictsizes:
                dictsizes.append(dictsize)

    dictsizes.sort()
    return stage_order, dictsizes, values


def main():
    ap = argparse.ArgumentParser(description="Plot ablation figure from measured summary CSVs.")
    ap.add_argument("--input", required=True)
    ap.add_argument("--output-prefix", default="fig_cr_ablation_dictsize")
    ap.add_argument("--ymax", type=float, default=None)
    args = ap.parse_args()

    stage_order, dictsizes, values = load_rows(args.input)

    stage_colors = ["#4878CF", "#6ACC65", "#D65F5F", "#B47CC7", "#8C8C8C"]
    x = list(range(len(dictsizes)))

    fig, ax = plt.subplots(figsize=(3.4, 1.6))
    fig.subplots_adjust(top=0.75, bottom=0.20, left=0.16, right=0.97)

    cumulative = []
    previous = [1.0] * len(dictsizes)
    for stage in stage_order:
        stage_vals = []
        for idx, dictsize in enumerate(dictsizes):
            current = values[stage].get(dictsize, float("nan"))
            if math.isnan(current):
                stage_vals.append(float("nan"))
                continue
            increment = current - previous[idx]
            previous[idx] = current
            stage_vals.append(increment)
        cumulative.append((stage, stage_vals))

    bottoms = [1.0] * len(dictsizes)
    for idx, (stage, increments) in enumerate(cumulative):
        ax.bar(
            x,
            increments,
            width=0.55,
            bottom=bottoms,
            color=stage_colors[idx % len(stage_colors)],
            edgecolor="black",
            linewidth=0.4,
            label=stage,
        )
        bottoms = [
            bottom if math.isnan(inc) else bottom + inc
            for bottom, inc in zip(bottoms, increments)
        ]

    ax.set_ylabel("Comp. Ratio", fontsize=6)
    ax.set_xticks(x)
    ax.set_xticklabels([f"{d} B" for d in dictsizes], fontsize=7)
    ax.set_xlabel("Dictionary Size", fontsize=6)
    ax.tick_params(axis="y", labelsize=7)
    ax.grid(axis="y", linestyle="--", linewidth=0.5)
    ymax = args.ymax if args.ymax is not None else max(bottoms) * 1.08
    ax.set_ylim(1.0, ymax)
    top_tick = max(1, int(math.floor(ymax + 1e-9)))
    ax.set_yticks(list(range(1, top_tick + 1)))

    legend_handles = [
        Patch(
            facecolor=stage_colors[idx % len(stage_colors)],
            edgecolor="#333333",
            linewidth=0.5,
            label=stage,
        )
        for idx, stage in enumerate(stage_order)
    ]
    ax.legend(
        handles=legend_handles,
        loc="lower left",
        bbox_to_anchor=(0.0, 1.01),
        bbox_transform=ax.transAxes,
        ncol=2,
        fontsize=5,
        frameon=True,
        borderpad=0.3,
        handlelength=2.2,
        handleheight=1.6,
        columnspacing=0.6,
        handletextpad=0.4,
    )

    pdf_path = f"{args.output_prefix}.pdf"
    png_path = f"{args.output_prefix}.png"
    fig.savefig(pdf_path)
    fig.savefig(png_path, dpi=200)
    print(f"Wrote {pdf_path}")
    print(f"Wrote {png_path}")


if __name__ == "__main__":
    main()
