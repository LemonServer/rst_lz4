#!/usr/bin/env python3
import argparse
import csv
import shlex
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def parse_args():
    ap = argparse.ArgumentParser(description="Build per-benchmark full-RST main-figure data from the C++ reference.")
    ap.add_argument("--hw-root", required=True, help="Path to the hardware artifact root containing tools/rst_cpp_reference.py")
    ap.add_argument("--dumps-dir", required=True, help="Directory containing dump files")
    ap.add_argument("--output", required=True, help="Output CSV path")
    ap.add_argument("--pages", type=int, default=5000, help="Pages per dump")
    ap.add_argument("--memory-blocks", type=int, default=2, help="RST dictionary memory blocks")
    ap.add_argument("--chunk-size", type=int, default=256, help="RST chunk size")
    ap.add_argument("--jobs", type=int, default=0, help="Parallel dump workers (0 = 4)")
    return ap.parse_args()


def load_cpp_helper(hw_root: Path):
    sys.path.insert(0, str(hw_root / "tools"))
    from rst_cpp_reference import build_cpp_helper, resolve_cpp_root  # type: ignore

    cpp_root = resolve_cpp_root(hw_root)
    cpp_bin = build_cpp_helper(hw_root, cpp_root, hw_root / "build" / "ratio_alignment")
    return cpp_bin


def run_one(cpp_bin: Path, dump_path: Path, pages: int, memory_blocks: int, chunk_size: int):
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
    name = dump_path.stem
    suite, bench = name.split("_", 1) if "_" in name else (name, name)
    return {
        "suite": suite,
        "benchmark": bench,
        "file": str(dump_path),
        "pages": int(fields["pages"]),
        "input_bytes": int(fields["input_bytes"]),
        "dict_bits": int(fields["dict_bits"]),
        "encoded_bits": int(fields["encoded_bits"]),
        "rst_full": float(fields["ratio"]),
    }


def main():
    args = parse_args()
    start_time = time.time()
    hw_root = Path(args.hw_root).resolve()
    dumps_dir = Path(args.dumps_dir).resolve()
    output = Path(args.output).resolve()
    cpp_bin = load_cpp_helper(hw_root)
    dumps = sorted(path for path in dumps_dir.iterdir() if path.is_file())
    jobs = args.jobs if args.jobs > 0 else 4
    worker_count = min(jobs, max(len(dumps), 1))

    print(
        "[full-rst] Starting per-benchmark full-RST sweep: "
        f"{len(dumps)} dump(s), pages={args.pages}, memory_blocks={args.memory_blocks}, jobs={worker_count}",
        flush=True,
    )

    rows = []
    with ThreadPoolExecutor(max_workers=worker_count) as executor:
        futures = {
            executor.submit(run_one, cpp_bin, dump, args.pages, args.memory_blocks, args.chunk_size): dump
            for dump in dumps
        }
        completed = 0
        for future in as_completed(futures):
            row = future.result()
            rows.append(row)
            completed += 1
            if completed == 1 or completed == len(dumps) or completed % 8 == 0:
                elapsed = time.time() - start_time
                print(
                    "[full-rst] "
                    f"{completed}/{len(dumps)} completed after {elapsed:.1f}s "
                    f"(latest: {row['suite']}_{row['benchmark']} ratio={row['rst_full']:.4f}x)",
                    flush=True,
                )

    rows.sort(key=lambda row: (row["suite"], row["benchmark"]))
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["suite", "benchmark", "file", "pages", "input_bytes", "dict_bits", "encoded_bits", "rst_full"],
        )
        writer.writeheader()
        writer.writerows(rows)

    elapsed = time.time() - start_time
    print(f"[full-rst] Wrote {output}", flush=True)
    print(f"[full-rst] Finished in {elapsed:.1f}s", flush=True)


if __name__ == "__main__":
    main()
