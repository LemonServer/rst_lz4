#!/usr/bin/env python3
"""Run the large-tier golden regression over every dump in data/."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from m4_hardware_sim_common import (
    DEFAULT_LOG_DIR,
    DEFAULT_VERILATOR_BIN,
    build_runtime_harness,
    default_data_dir,
    discover_data_inputs,
    repo_root,
)
from run_m4_golden_regression import run_golden_regression


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the large-tier M4 golden regression over every dump in data/."
    )
    parser.add_argument(
        "inputs",
        nargs="*",
        type=Path,
        help="Optional explicit input files. If omitted, every dump in data/ is used.",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        help="Directory of dump files (default: data/)",
    )
    parser.add_argument("--pages", type=int, default=16, help="Number of 4KB pages to test (0 = until EOF)")
    parser.add_argument(
        "--verilator-bin",
        default=DEFAULT_VERILATOR_BIN,
        help="Path to the Verilator binary",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=Path("build/verilator/m4_runtime_large"),
        help="Verilator output directory",
    )
    parser.add_argument(
        "--build-jobs",
        type=int,
        default=0,
        help="Verilator build parallelism (0 = auto)",
    )
    parser.add_argument(
        "--jobs",
        type=int,
        default=0,
        help="Python model worker processes per dump (0 = auto)",
    )
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=DEFAULT_LOG_DIR,
        help="Directory for generated hardware logs",
    )
    parser.add_argument(
        "--write-json",
        type=Path,
        help="Optional path to write the suite summary as JSON",
    )
    parser.add_argument(
        "--fail-fast",
        action="store_true",
        help="Stop after the first failure",
    )
    return parser.parse_args()


def discover_inputs(root: Path, data_dir: Path) -> list[Path]:
    return discover_data_inputs(root, data_dir)


def main() -> int:
    args = parse_args()
    root = repo_root()
    if args.pages < 0:
        raise RuntimeError("--pages must be >= 0")

    inputs = [path.resolve() for path in args.inputs] if args.inputs else discover_inputs(
        root,
        args.data_dir or default_data_dir(root),
    )

    try:
        print("Building shared large-tier runtime harness...")
        run_bin = build_runtime_harness(
            root,
            verilator_bin=args.verilator_bin,
            build_dir=args.build_dir,
            tier="large",
            build_jobs=args.build_jobs,
        )
    except subprocess.CalledProcessError as exc:
        if exc.stdout:
            print(exc.stdout, end="", file=sys.stderr)
        if exc.stderr:
            print(exc.stderr, end="", file=sys.stderr)
        return 1

    results: list[dict] = []
    failures = 0

    for index, input_file in enumerate(inputs, start=1):
        print(f"[{index}/{len(inputs)}] {input_file}")
        try:
            result = run_golden_regression(
                input_file=input_file,
                pages_requested=args.pages,
                root=root,
                build_dir=args.build_dir,
                model_jobs=args.jobs,
                log_dir=args.log_dir,
                run_bin=run_bin,
                verbose=False,
            )
        except subprocess.CalledProcessError as exc:
            if exc.stdout:
                print(exc.stdout, end="", file=sys.stderr)
            if exc.stderr:
                print(exc.stderr, end="", file=sys.stderr)
            result = {
                "status": "FAIL",
                "input_file": str(input_file),
                "pages_requested": args.pages,
                "pages_observed": 0,
                "hardware_summary": {"ratio": 0.0, "encoded_bits": 0},
                "hardware_log": "",
                "mismatches": ["hardware harness execution failed"],
            }

        results.append(result)
        if result["status"] == "PASS":
            print(
                f"  PASS pages={result['pages_observed']} "
                f"ratio={result['hardware_summary']['ratio']:.4f}x "
                f"log={result['hardware_log']}"
            )
            continue

        failures += 1
        print(
            f"  FAIL pages={result['pages_observed']} "
            f"ratio={result['hardware_summary']['ratio']:.4f}x"
        )
        for mismatch in result["mismatches"][:5]:
            print(f"    {mismatch}")
        if args.fail_fast:
            break

    summary = {
        "status": "PASS" if failures == 0 else "FAIL",
        "inputs": [str(path) for path in inputs],
        "pages_requested": args.pages,
        "passed": len(results) - failures,
        "failed": failures,
        "results": results,
    }

    if args.write_json is not None:
        args.write_json.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    if failures == 0:
        print(f"\nPASS golden regression suite: {len(results)}/{len(results)} dump(s) matched the Python model.")
        return 0

    print(f"\nFAIL golden regression suite: {failures} of {len(results)} dump(s) failed.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
