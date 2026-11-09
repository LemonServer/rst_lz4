#!/usr/bin/env python3
"""Run the large-tier M4 runtime harness and compare it against the exact Python model."""

from __future__ import annotations

import argparse
import json
import multiprocessing
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict
from pathlib import Path

from m4_hardware_sim_common import (
    DEFAULT_LOG_DIR,
    DEFAULT_VERILATOR_BIN,
    build_runtime_harness,
    default_input_file,
    load_paged_input,
    parse_hardware_log,
    repo_root,
    resolve_repo_path,
    run_runtime_harness,
    runtime_log_path,
)


MODEL_CONFIG = {
    "memory_blocks": 2,
    "chunk_size": 256,
    "apply_free_substitutions": False,
    "static_tree_codes_per_cycle": 0,
    "seq_len_2": {"banks": 6, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
    "seq_len_3": {"banks": 7, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
    "seq_len_4": {"banks": 9, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
    "seq_len_5": {"banks": 10, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare the large-tier M4 runtime harness against the exact Python hardware model."
    )
    parser.add_argument(
        "input_file",
        nargs="?",
        type=Path,
        help="Input file to page and compress (default: data/dacapo_avrora_rand1k)",
    )
    parser.add_argument(
        "page_count",
        nargs="?",
        type=int,
        help="Optional positional page-count shorthand (same as --pages)",
    )
    parser.add_argument("--pages", type=int, help="Number of 4KB pages to test (0 = until EOF)")
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
        help="Python model worker processes (0 = auto)",
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
        help="Optional path to write the regression summary as JSON",
    )
    return parser.parse_args()


def _resolve_input_file(args: argparse.Namespace, root: Path) -> Path:
    if args.input_file is not None:
        return args.input_file.resolve()
    default_input = default_input_file(root)
    if default_input.exists():
        return default_input
    raise RuntimeError("input_file is required because the default data/dacapo_avrora_rand1k is missing")


def _resolve_pages(args: argparse.Namespace) -> int:
    pages = args.pages if args.pages is not None else args.page_count
    if pages is None:
        pages = 16
    if pages < 0:
        raise RuntimeError("--pages must be >= 0")
    return pages


def load_input_pages(input_file: Path, pages_requested: int, root: Path) -> tuple[int, list[bytes]]:
    loaded = load_paged_input(root, input_file, pages_requested)
    return loaded.page_width, loaded.pages


def _model_page_worker(job: tuple[str, int, bytes]) -> dict:
    root_str, page_idx, page = job
    helpful_dir = Path(root_str) / "helpful_files"
    sys.path.insert(0, str(helpful_dir))
    import new_hardware_sim_compressor as sim_module

    _result, _cycles, details = sim_module.cram_encode(page, MODEL_CONFIG, return_details=True)
    return {
        "page_idx": page_idx,
        "valid_bytes": len(page),
        "dict_count": details.dict_count,
        "dict_bits": details.dict_bits,
        "comp_syms": details.compressed_symbols,
        "raw_bits": len(page) * 8,
        "encoded_bits": details.encoded_bits,
        "ratio": (len(page) * 8) / details.encoded_bits if details.encoded_bits else 0.0,
        "details": asdict(details),
    }


def model_page_details(
    pages: list[bytes],
    *,
    page_width: int,
    root: Path,
    jobs: int,
    verbose: bool,
) -> tuple[list[dict], dict]:
    worker_count = min(len(pages), jobs if jobs > 0 else (multiprocessing.cpu_count() or 1))
    model_pages: list[dict] = []

    if verbose:
        print(f"Running Python hardware model with {worker_count} worker(s)...")

    if worker_count <= 1:
        for index, page in enumerate(pages, start=1):
            page_info = _model_page_worker((str(root), index, page))
            model_pages.append(page_info)
            if verbose:
                print(
                    f"  [model {index}/{len(pages)}] page {page_info['page_idx']}/{len(pages)} "
                    f"ratio={page_info['ratio']:.4f} encoded_bits={page_info['encoded_bits']}"
                )
    else:
        completed = 0
        with ThreadPoolExecutor(max_workers=worker_count) as executor:
            futures = {
                executor.submit(_model_page_worker, (str(root), index, page)): index
                for index, page in enumerate(pages, start=1)
            }
            for future in as_completed(futures):
                page_info = future.result()
                model_pages.append(page_info)
                completed += 1
                if verbose:
                    print(
                        f"  [model {completed}/{len(pages)}] page {page_info['page_idx']}/{len(pages)} "
                        f"ratio={page_info['ratio']:.4f} encoded_bits={page_info['encoded_bits']}"
                    )

    model_pages.sort(key=lambda item: item["page_idx"])
    total_encoded_bits = sum(page["encoded_bits"] for page in model_pages)
    total_raw_bits = sum(page["raw_bits"] for page in model_pages)
    total_bytes = sum(page["valid_bytes"] for page in model_pages)

    summary = {
        "input_bytes": total_bytes,
        "padded_bytes": len(model_pages) * page_width,
        "pages": len(model_pages),
        "raw_bits": total_raw_bits,
        "encoded_bits": total_encoded_bits,
        "ratio": (total_raw_bits / total_encoded_bits) if total_encoded_bits else 0.0,
    }
    return model_pages, summary


def compare_results(
    hw_pages: list[dict],
    hw_summary: dict,
    model_pages: list[dict],
    model_summary: dict,
) -> list[str]:
    mismatches: list[str] = []

    if len(hw_pages) != len(model_pages):
        mismatches.append(
            f"page count mismatch: hardware={len(hw_pages)} model={len(model_pages)}"
        )
        return mismatches

    for hw_page, model_page in zip(hw_pages, model_pages):
        page_idx = hw_page["page_idx"]
        if hw_page["page_idx"] != model_page["page_idx"]:
            mismatches.append(
                f"page order mismatch: hardware={hw_page['page_idx']} model={model_page['page_idx']}"
            )
        if hw_page.get("page_total") not in (None, len(model_pages)):
            mismatches.append(
                f"page {page_idx} page_total mismatch: hardware={hw_page['page_total']} model={len(model_pages)}"
            )
        for field in ("valid_bytes", "dict_count", "dict_bits", "comp_syms", "raw_bits", "encoded_bits"):
            if hw_page[field] != model_page[field]:
                mismatches.append(
                    f"page {page_idx} {field} mismatch: hardware={hw_page[field]} model={model_page[field]}"
                )

    for field in ("input_bytes", "padded_bytes", "pages", "raw_bits", "encoded_bits"):
        if hw_summary[field] != model_summary[field]:
            mismatches.append(
                f"file summary {field} mismatch: hardware={hw_summary[field]} model={model_summary[field]}"
            )

    return mismatches


def run_golden_regression(
    *,
    input_file: Path,
    pages_requested: int,
    root: Path,
    verilator_bin: str = DEFAULT_VERILATOR_BIN,
    build_dir: Path = Path("build/verilator/m4_runtime_large"),
    build_jobs: int = 0,
    model_jobs: int = 0,
    log_dir: Path = DEFAULT_LOG_DIR,
    run_bin: Path | None = None,
    verbose: bool = True,
) -> dict:
    page_width, pages = load_input_pages(input_file, pages_requested, root)
    if run_bin is None:
        if verbose:
            print("Building large-tier runtime harness...")
        run_bin = build_runtime_harness(
            root,
            verilator_bin=verilator_bin,
            build_dir=build_dir,
            tier="large",
            build_jobs=build_jobs,
        )

    log_path = runtime_log_path(log_dir, input_file, "large_golden", len(pages), root)
    if verbose:
        print("Running hardware harness...")
    log_text = run_runtime_harness(
        root,
        run_bin=run_bin,
        input_file=input_file,
        pages=len(pages),
        log_path=log_path,
    )
    if verbose and log_text:
        print(log_text, end="")

    hw_pages, hw_summary = parse_hardware_log(log_text)
    model_pages, model_summary = model_page_details(
        pages,
        page_width=page_width,
        root=root,
        jobs=model_jobs,
        verbose=verbose,
    )
    mismatches = compare_results(hw_pages, hw_summary, model_pages, model_summary)

    result = {
        "status": "PASS" if not mismatches else "FAIL",
        "input_file": str(input_file.resolve()),
        "pages_requested": pages_requested,
        "pages_observed": hw_summary["pages"],
        "build_dir": str(resolve_repo_path(root, build_dir)),
        "hardware_log": str(log_path),
        "hardware_summary": hw_summary,
        "model_summary": model_summary,
        "mismatches": mismatches,
    }

    if mismatches:
        if verbose:
            print("\nFAIL large-tier golden regression")
            print(f"  input: {input_file.resolve()}")
            print(f"  pages: {hw_summary['pages']}")
            print(f"  hardware ratio: {hw_summary['ratio']:.4f}x")
            print(f"  model ratio: {model_summary['ratio']:.4f}x")
            for mismatch in mismatches[:20]:
                print(f"  mismatch: {mismatch}")
            if len(mismatches) > 20:
                print(f"  mismatch: ... and {len(mismatches) - 20} more")
            print(f"  hardware log: {log_path}")
        return result

    if verbose:
        print("\nPASS large-tier golden regression")
        print(f"  input: {input_file.resolve()}")
        print(f"  pages: {hw_summary['pages']}")
        print(f"  hardware ratio: {hw_summary['ratio']:.4f}x")
        print(f"  model ratio: {model_summary['ratio']:.4f}x")
        print(f"  encoded bits: {hw_summary['encoded_bits']}")
        print(f"  hardware log: {log_path}")
    return result


def print_command_failure(exc: subprocess.CalledProcessError) -> None:
    print("\nFAIL large-tier golden regression", file=sys.stderr)
    if exc.stdout:
        print(exc.stdout, end="", file=sys.stderr)
    if exc.stderr:
        print(exc.stderr, end="", file=sys.stderr)


def main() -> int:
    args = parse_args()
    root = repo_root()
    input_file = _resolve_input_file(args, root)
    pages_requested = _resolve_pages(args)

    try:
        result = run_golden_regression(
            input_file=input_file,
            pages_requested=pages_requested,
            root=root,
            verilator_bin=args.verilator_bin,
            build_dir=args.build_dir,
            build_jobs=args.build_jobs,
            model_jobs=args.jobs,
            log_dir=args.log_dir,
            verbose=True,
        )
    except subprocess.CalledProcessError as exc:
        print_command_failure(exc)
        return 1

    if args.write_json is not None:
        args.write_json.write_text(json.dumps(result, indent=2), encoding="utf-8")

    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
