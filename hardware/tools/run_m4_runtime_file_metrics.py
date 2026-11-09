#!/usr/bin/env python3
"""Run the tiered M4 runtime file harness and emit compact ratio/cycle metrics."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from m4_hardware_sim_common import (
    DEFAULT_LOG_DIR,
    DEFAULT_VERILATOR_BIN,
    build_runtime_harness,
    default_input_file,
    parse_hardware_log,
    repo_root,
    resolve_runtime_tier,
    resolve_repo_path,
    run_runtime_harness,
    runtime_log_path,
)
from run_m4_experimental_regression import (
    build_runtime_harness as build_experimental_runtime_harness,
    parse_hardware_log as parse_experimental_hardware_log,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build and run the tiered M4 runtime file harness on a real input file."
    )
    parser.add_argument(
        "input_file",
        nargs="?",
        type=Path,
        help="Input file to page and compress",
    )
    parser.add_argument(
        "--tier",
        choices=("small", "medium", "large"),
        default="small",
        help="Reviewer-facing RST tier to compile; large automatically uses the frozen large runtime path",
    )
    parser.add_argument(
        "--pages",
        type=int,
        default=16,
        help="Maximum number of pages to process (0 = until EOF)",
    )
    parser.add_argument(
        "--verilator-bin",
        default=DEFAULT_VERILATOR_BIN,
        help="Path to the Verilator binary",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        help="Verilator output directory (default: build/verilator/m4_runtime_<tier>)",
    )
    parser.add_argument(
        "--build-jobs",
        type=int,
        default=0,
        help="Verilator build parallelism (0 = auto)",
    )
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=DEFAULT_LOG_DIR,
        help="Directory for generated runtime logs",
    )
    parser.add_argument(
        "--write-json",
        type=Path,
        help="Optional path to write the parsed metrics as JSON",
    )
    parser.add_argument(
        "--write-log",
        type=Path,
        help="Optional path to write the raw simulator log",
    )
    parser.add_argument(
        "--vcd-out",
        type=Path,
        help="Optional VCD path to request from the runtime harness",
    )
    parser.add_argument(
        "--runtime-log",
        type=Path,
        help="Parse an existing runtime harness log instead of building and running Verilator",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = repo_root()
    use_experimental_runtime = args.tier == "large"
    mode_label = args.tier
    build_dir = args.build_dir or Path(f"build/verilator/m4_runtime_{mode_label}")
    parse_log = parse_experimental_hardware_log if use_experimental_runtime else parse_hardware_log

    if args.runtime_log is None and args.input_file is None:
        default_input = default_input_file(root)
        if not default_input.exists():
            raise RuntimeError("input_file is required unless --runtime-log is provided")
        args.input_file = default_input

    log_path = args.write_log
    if log_path is None and args.runtime_log is None:
        log_path = runtime_log_path(args.log_dir, args.input_file, mode_label, args.pages, root)
    build_dir_text = None
    input_file_text = None
    log_text = ""

    if args.runtime_log is not None:
        log_path = args.runtime_log.resolve()
        log_text = log_path.read_text(encoding="utf-8")
        input_file_text = str(args.input_file.resolve()) if args.input_file is not None else None
    else:
        print("Building runtime file harness...")
        if use_experimental_runtime:
            run_bin = build_experimental_runtime_harness(
                root,
                verilator_bin=args.verilator_bin,
                build_dir=build_dir,
                build_jobs=args.build_jobs,
            )
        else:
            run_bin = build_runtime_harness(
                root,
                verilator_bin=args.verilator_bin,
                build_dir=build_dir,
                tier=args.tier,
                build_jobs=args.build_jobs,
            )

        print("Running runtime file harness...")
        log_text = run_runtime_harness(
            root,
            run_bin=run_bin,
            input_file=args.input_file,
            pages=args.pages,
            log_path=log_path,
            vcd_out=args.vcd_out,
        )
        if log_text:
            print(log_text, end="")
        build_dir_text = str(resolve_repo_path(root, build_dir))
        input_file_text = str(args.input_file.resolve())

    pages, summary = parse_log(log_text)
    if args.pages > 0 and summary["pages"] != args.pages:
        raise RuntimeError(
            f"runtime harness processed {summary['pages']} pages, expected {args.pages}"
        )
    result = {
        "tier": args.tier,
        "runtime_variant": "frozen_large" if use_experimental_runtime else "standard",
        "input_file": input_file_text,
        "pages_requested": args.pages,
        "pages_observed": summary["pages"],
        "log_path": str(log_path),
        "build_dir": build_dir_text,
        "summary": summary,
        "pages": pages,
    }

    if args.write_json is not None:
        args.write_json.write_text(json.dumps(result, indent=2), encoding="utf-8")

    print("\nRuntime file metrics")
    print(
        f"  tier={args.tier} "
        f"pages={summary['pages']} input_bytes={summary['input_bytes']} "
        f"encoded_bits={summary['encoded_bits']} ratio={summary['ratio']:.4f}"
    )
    print(
        f"  comp_cycles={summary['comp_cycles']} decomp_cycles={summary['decomp_cycles']} "
        f"comp_Bpc={summary['comp_bpc']:.4f} decomp_Bpc={summary['decomp_bpc']:.4f}"
    )
    print(f"  hardware log: {log_path}")
    if args.write_json is not None:
        print(f"  json summary: {args.write_json}")
    if args.vcd_out is not None:
        print(f"  vcd file: {args.vcd_out.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
