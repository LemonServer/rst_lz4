#!/usr/bin/env python3
"""Recompute the ablation stage-V summary from full-RST C++ sweeps.

This is intentionally separate from the default artifact flow because rerunning
stage V over the full 88-dump, 5000-page corpus is significantly slower than
the rest of the paper-style figure regeneration path.
"""

from __future__ import annotations

import argparse
import csv
import math
import shlex
import subprocess
import sys
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


GROUP_ORDER = [
    "DATABASES",
    "GRAPHBIG",
    "PARSEC",
    "SPEC",
    "SPARKBENCH",
    "DACAPO",
    "RENAISSANCE",
]


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="Recompute the full-RST stage-V ablation summary from the C++ reference."
    )
    ap.add_argument(
        "--hw-root",
        required=True,
        help="Path to the hardware artifact root containing tools/rst_cpp_reference.py",
    )
    ap.add_argument("--dumps-dir", required=True, help="Directory containing dump files")
    ap.add_argument("--output", required=True, help="Output CSV path")
    ap.add_argument("--pages", type=int, default=5000, help="Pages per dump")
    ap.add_argument(
        "--memory-blocks",
        default="1,2,3,4",
        help="Comma-separated memory block counts to sweep (default: 1,2,3,4)",
    )
    ap.add_argument("--chunk-size", type=int, default=256, help="RST chunk size")
    ap.add_argument("--jobs", type=int, default=0, help="Parallel dump workers (0 = 4)")
    return ap.parse_args()


def load_cpp_helper(hw_root: Path) -> Path:
    sys.path.insert(0, str(hw_root / "tools"))
    from rst_cpp_reference import build_cpp_helper, resolve_cpp_root  # type: ignore

    cpp_root = resolve_cpp_root(hw_root)
    cpp_bin = build_cpp_helper(hw_root, cpp_root, hw_root / "build" / "ratio_alignment")
    return cpp_bin


def geomean(values: list[float]) -> float:
    positive = [value for value in values if value > 0.0 and not math.isnan(value)]
    if not positive:
        return float("nan")
    return math.exp(sum(math.log(value) for value in positive) / len(positive))


def run_one(cpp_bin: Path, dump_path: Path, pages: int, memory_blocks: int, chunk_size: int) -> dict:
    cmd = (
        f"{shlex.quote(str(cpp_bin))} "
        f"--input-file {shlex.quote(str(dump_path))} "
        f"--pages {pages} "
        f"--page-bytes 4096 "
        f"--chunk-size {chunk_size} "
        f"--memory-blocks {memory_blocks} "
        "| tail -n 1"
    )
    line = subprocess.check_output(["/bin/bash", "-lc", cmd], text=True).strip()
    if not line.startswith("[file summary] "):
        raise RuntimeError(f"unexpected output for {dump_path}: {line!r}")
    fields = dict(item.split("=") for item in line[len("[file summary] "):].split())
    suite = dump_path.stem.split("_", 1)[0]
    return {
        "suite": suite,
        "ratio": float(fields["ratio"]),
    }


def dictsize_for_blocks(memory_blocks: int) -> int:
    return memory_blocks * 64


def parse_memory_blocks(value: str) -> list[int]:
    blocks = []
    for item in value.split(","):
        item = item.strip()
        if not item:
            continue
        blocks.append(int(item))
    if not blocks:
        raise RuntimeError("expected at least one memory block count")
    return blocks


def summarize_rows(rows: list[dict]) -> float:
    by_suite: dict[str, list[float]] = defaultdict(list)
    for row in rows:
        by_suite[row["suite"]].append(row["ratio"])
    suite_geomeans = [geomean(by_suite[suite]) for suite in GROUP_ORDER if suite in by_suite]
    return geomean(suite_geomeans)


def main() -> None:
    args = parse_args()
    start_time = time.time()
    hw_root = Path(args.hw_root).resolve()
    dumps_dir = Path(args.dumps_dir).resolve()
    output = Path(args.output).resolve()
    cpp_bin = load_cpp_helper(hw_root)
    dumps = sorted(path for path in dumps_dir.iterdir() if path.is_file())
    jobs = args.jobs if args.jobs > 0 else 4
    worker_count = min(jobs, max(len(dumps), 1))
    memory_blocks_list = parse_memory_blocks(args.memory_blocks)

    print(
        "[stage-v] Starting full-RST ablation stage-V sweep: "
        f"{len(dumps)} dump(s), pages={args.pages}, memory_blocks={memory_blocks_list}, jobs={worker_count}",
        flush=True,
    )

    summary_rows = []
    for memory_blocks in memory_blocks_list:
        stage_start = time.time()
        print(
            "[stage-v] "
            f"memory_blocks={memory_blocks} (dict={dictsize_for_blocks(memory_blocks)}B): starting",
            flush=True,
        )
        rows = []
        with ThreadPoolExecutor(max_workers=worker_count) as executor:
            futures = {
                executor.submit(run_one, cpp_bin, dump, args.pages, memory_blocks, args.chunk_size): dump
                for dump in dumps
            }
            completed = 0
            for future in as_completed(futures):
                row = future.result()
                rows.append(row)
                completed += 1
                if completed == 1 or completed == len(dumps) or completed % 8 == 0:
                    elapsed = time.time() - stage_start
                    print(
                        "[stage-v] "
                        f"memory_blocks={memory_blocks}: {completed}/{len(dumps)} completed after {elapsed:.1f}s "
                        f"(latest suite={row['suite']} ratio={row['ratio']:.4f}x)",
                        flush=True,
                    )

        overall_geogeo = summarize_rows(rows)
        summary_rows.append(
            {
                "dictsize": dictsize_for_blocks(memory_blocks),
                "strategy": "utility",
                "num_suites": len(GROUP_ORDER),
                "overall_geogeo_CR": overall_geogeo,
                "config_label": f"full-rst:memory_blocks={memory_blocks}:pages={args.pages}",
            }
        )
        print(
            "[stage-v] "
            f"memory_blocks={memory_blocks} done: overall_geogeo_CR={overall_geogeo:.6f}x",
            flush=True,
        )

    summary_rows.sort(key=lambda row: row["dictsize"])
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["dictsize", "strategy", "num_suites", "overall_geogeo_CR", "config_label"],
        )
        writer.writeheader()
        writer.writerows(summary_rows)

    elapsed = time.time() - start_time
    print(f"[stage-v] Wrote {output}", flush=True)
    print(f"[stage-v] Finished in {elapsed:.1f}s", flush=True)


if __name__ == "__main__":
    main()
