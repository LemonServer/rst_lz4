#!/usr/bin/env python3
"""Reviewer-facing verification entry point for the richer large-tier hardware flow."""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from m4_hardware_sim_common import (
    DEFAULT_DATASET_NAME,
    DEFAULT_VERILATOR_BIN,
    LoadedPageInput,
    default_data_dir,
    discover_data_inputs,
    ensure_parent,
    load_paged_input,
    relative_repo_path,
    repo_root,
    resolve_repo_member,
    resolve_repo_path,
)
from rst_cpp_reference import build_cpp_helper, resolve_cpp_root, run_cpp_model
import run_experimental_decompressor_top_latency as direct_latency
from run_experimental_sv_decompressor_check import (
    build_sim_binary as build_page_decompressor_harness,
    run_sv_decompressor_check,
)
from run_m4_experimental_regression import build_runtime_harness, run_hardware_roundtrip


CPP_CHUNK_SIZE = 256
CPP_MEMORY_BLOCKS = 2
PAGE_BYTES = 4096
DEFAULT_LOG_DIR = Path("build/rst_verify/logs")
DEFAULT_ROUNDTRIP_BUILD_DIR = Path("build/verilator/rst_verify_large")
DEFAULT_DECOMPRESSOR_BUILD_DIR = Path("build/verilator/rst_verify_decompressor")
DEFAULT_LATENCY_BUILD_DIR = Path("build/verilator/rst_verify_decompressor_latency")
DEFAULT_CPP_BUILD_DIR = Path("build/rst_verify/reference_cpp")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run the reviewer-facing RST verification flow: "
            "large-tier SystemVerilog round-trip, "
            "C++ reference comparison, and decompressor decode checks."
        )
    )
    parser.add_argument(
        "input_path",
        nargs="?",
        type=Path,
        help=(
            "Input file to verify, or a data directory to scan. "
            f"Defaults to data/{DEFAULT_DATASET_NAME}."
        ),
    )
    parser.add_argument(
        "page_count",
        nargs="?",
        type=int,
        help="Optional positional page-count shorthand (same as --pages)",
    )
    parser.add_argument("--pages", type=int, help="Number of 4KB pages to verify (0 = until EOF)")
    parser.add_argument(
        "--all-data",
        action="store_true",
        help="Run every dump under data/ (or the provided directory path).",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        help="Directory of dump files used with --all-data (default: data/).",
    )
    parser.add_argument(
        "--jobs",
        type=int,
        default=0,
        help="Overall parallelism hint for verification tasks (0 = auto)",
    )
    parser.add_argument(
        "--build-jobs",
        type=int,
        default=0,
        help="Verilator build parallelism (0 = auto or --jobs if set)",
    )
    parser.add_argument(
        "--verilator-bin",
        default=DEFAULT_VERILATOR_BIN,
        help="Path to the Verilator binary",
    )
    parser.add_argument(
        "--roundtrip-build-dir",
        type=Path,
        default=DEFAULT_ROUNDTRIP_BUILD_DIR,
        help="Verilator output directory for the runtime round-trip harness",
    )
    parser.add_argument(
        "--decompressor-build-dir",
        type=Path,
        default=DEFAULT_DECOMPRESSOR_BUILD_DIR,
        help="Verilator output directory for the decompressor-only harness",
    )
    parser.add_argument(
        "--cpp-root",
        type=Path,
        help="Path to the vendored CRAM C++ reference sources",
    )
    parser.add_argument(
        "--latency-pages",
        type=int,
        default=8,
        help=(
            "Pages per input used for direct chunk-level decompressor latency "
            "measurement (0 = all selected pages)"
        ),
    )
    parser.add_argument(
        "--latency-build-dir",
        type=Path,
        default=DEFAULT_LATENCY_BUILD_DIR,
        help="Verilator output directory for the direct chunk-level latency harness",
    )
    parser.add_argument(
        "--cpp-build-dir",
        type=Path,
        default=DEFAULT_CPP_BUILD_DIR,
        help="Directory used to build the local C++ reference helper",
    )
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=DEFAULT_LOG_DIR,
        help="Directory for generated hardware logs",
    )
    parser.add_argument(
        "--strict-reference-match",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--skip-decompressor-check",
        action="store_true",
        help=(
            "Skip the standalone SV decompressor decode cross-check. "
            "Useful for faster large-batch metric sweeps; the main hardware round-trip still runs."
        ),
    )
    parser.add_argument(
        "--skip-latency-measurement",
        action="store_true",
        help=(
            "Skip the direct chunk-level decompressor latency harness. "
            "By default the suite reports critical-64B block availability, not page completion latency."
        ),
    )
    parser.add_argument(
        "--write-json",
        type=Path,
        help="Optional path to write the combined verification summary as JSON",
    )
    return parser.parse_args()


def _resolve_pages(args: argparse.Namespace) -> int:
    pages = args.pages if args.pages is not None else args.page_count
    if pages is None:
        pages = 16
    if pages < 0:
        raise RuntimeError("--pages must be >= 0")
    return pages


def _effective_build_jobs(args: argparse.Namespace) -> int:
    if args.build_jobs > 0:
        return args.build_jobs
    return max(args.jobs, 0)


def _display_path(root: Path, path_like: str | Path) -> str:
    path = resolve_repo_path(root, Path(path_like))
    try:
        return relative_repo_path(root, path)
    except RuntimeError:
        return str(path)


def _rewrite_path_fields(root: Path, payload: dict, *fields: str) -> dict:
    normalized = dict(payload)
    for field in fields:
        value = normalized.get(field)
        if value:
            normalized[field] = _display_path(root, value)
    return normalized


def _rewrite_path_list(root: Path, payloads: list[dict], *fields: str) -> list[dict]:
    return [_rewrite_path_fields(root, payload, *fields) for payload in payloads]


def _effective_job_budget(job_hint: int, selected_pages: int) -> int:
    if selected_pages <= 0:
        return 1
    if job_hint > 0:
        return job_hint
    cpu_count = os.cpu_count() or 2
    return max(2, min(cpu_count, max(selected_pages * 2, 2)))


def _parallel_plan(job_hint: int, selected_pages: int) -> dict:
    job_budget = _effective_job_budget(job_hint, selected_pages)
    if selected_pages <= 1:
        return {
            "requested_jobs": job_hint,
            "effective_job_budget": job_budget,
            "stage_parallel": job_budget > 1,
            "hardware_shards": 1,
            "decompressor_shards": 1,
            "cpp_parallel": job_budget > 1,
        }

    if job_budget <= 1:
        return {
            "requested_jobs": job_hint,
            "effective_job_budget": job_budget,
            "stage_parallel": False,
            "hardware_shards": 1,
            "decompressor_shards": 1,
            "cpp_parallel": False,
        }

    hardware_shards = min(selected_pages, max(1, (job_budget + 1) // 2))
    decompressor_shards = min(selected_pages, max(1, job_budget - hardware_shards))
    return {
        "requested_jobs": job_hint,
        "effective_job_budget": job_budget,
        "stage_parallel": True,
        "hardware_shards": hardware_shards,
        "decompressor_shards": decompressor_shards,
        "cpp_parallel": True,
    }


def _resolve_targets(args: argparse.Namespace, root: Path) -> tuple[str, str, list[Path]]:
    if args.all_data and args.input_path is not None and args.data_dir is not None:
        raise RuntimeError("pass either a positional directory or --data-dir with --all-data, not both")

    if args.all_data:
        data_dir = args.input_path or args.data_dir or default_data_dir(root)
        resolved_dir = resolve_repo_path(root, data_dir)
        if not resolved_dir.is_dir():
            raise RuntimeError(f"data directory not found: {_display_path(root, resolved_dir)}")
        return "directory", _display_path(root, resolved_dir), discover_data_inputs(root, resolved_dir)

    if args.data_dir is not None:
        raise RuntimeError("--data-dir requires --all-data")

    if args.input_path is None:
        default_input = root / "data" / DEFAULT_DATASET_NAME
        if not default_input.exists():
            raise RuntimeError(f"default input is missing: data/{DEFAULT_DATASET_NAME}")
        resolved_input = resolve_repo_member(root, default_input, label="input file")
        return "single", relative_repo_path(root, resolved_input), [resolved_input]

    resolved_input = resolve_repo_path(root, args.input_path)
    if resolved_input.is_dir():
        return "directory", _display_path(root, resolved_input), discover_data_inputs(root, resolved_input)
    if not resolved_input.is_file():
        raise RuntimeError(f"input file not found: {_display_path(root, resolved_input)}")
    return "single", _display_path(root, resolved_input), [resolved_input]


def compare_hardware_to_cpp(hw_pages: list[dict], hw_summary: dict, cpp_pages: list[dict], cpp_summary: dict) -> list[str]:
    mismatches: list[str] = []

    if len(hw_pages) != len(cpp_pages):
        mismatches.append(
            f"page count mismatch: hardware={len(hw_pages)} reference={len(cpp_pages)}"
        )
        return mismatches

    for hw_page, cpp_page in zip(hw_pages, cpp_pages):
        page_idx = hw_page["page_idx"]
        if page_idx != cpp_page["page_idx"]:
            mismatches.append(
                f"page order mismatch: hardware={page_idx} reference={cpp_page['page_idx']}"
            )
        if hw_page.get("page_total") not in (None, len(cpp_pages)):
            mismatches.append(
                f"page {page_idx} page_total mismatch: hardware={hw_page['page_total']} reference={len(cpp_pages)}"
            )
        if hw_page["valid_bytes"] != cpp_page["valid_bytes"]:
            mismatches.append(
                f"page {page_idx} valid_bytes mismatch: hardware={hw_page['valid_bytes']} reference={cpp_page['valid_bytes']}"
            )
        if hw_page["stored_dict_count"] != cpp_page["dict_count"]:
            mismatches.append(
                f"page {page_idx} stored_dict_count mismatch: hardware={hw_page['stored_dict_count']} reference={cpp_page['dict_count']}"
            )
        if hw_page["dict_bits"] != cpp_page["dict_bits"]:
            mismatches.append(
                f"page {page_idx} dict_bits mismatch: hardware={hw_page['dict_bits']} reference={cpp_page['dict_bits']}"
            )
        if hw_page["encoded_bits"] != cpp_page["encoded_bits"]:
            mismatches.append(
                f"page {page_idx} encoded_bits mismatch: hardware={hw_page['encoded_bits']} reference={cpp_page['encoded_bits']}"
            )

    if hw_summary["input_bytes"] != cpp_summary["input_bytes"]:
        mismatches.append(
            f"file summary input_bytes mismatch: hardware={hw_summary['input_bytes']} reference={cpp_summary['input_bytes']}"
        )
    if hw_summary["pages"] != cpp_summary["pages"]:
        mismatches.append(
            f"file summary pages mismatch: hardware={hw_summary['pages']} reference={cpp_summary['pages']}"
        )
    if hw_summary["raw_bits"] != cpp_summary["raw_bits"]:
        mismatches.append(
            f"file summary raw_bits mismatch: hardware={hw_summary['raw_bits']} reference={cpp_summary['raw_bits']}"
        )
    if hw_summary["encoded_bits"] != cpp_summary["encoded_bits"]:
        mismatches.append(
            f"file summary encoded_bits mismatch: hardware={hw_summary['encoded_bits']} reference={cpp_summary['encoded_bits']}"
        )

    total_hw_dict_bits = sum(page["dict_bits"] for page in hw_pages)
    if total_hw_dict_bits != cpp_summary["dict_bits"]:
        mismatches.append(
            f"file summary dict_bits mismatch: hardware={total_hw_dict_bits} reference={cpp_summary['dict_bits']}"
        )

    return mismatches


def _prepare_shared_artifacts(args: argparse.Namespace, root: Path, build_jobs: int) -> dict:
    roundtrip_build_dir = resolve_repo_member(root, args.roundtrip_build_dir, label="round-trip build directory")
    decompressor_build_dir = resolve_repo_member(
        root,
        args.decompressor_build_dir,
        label="decompressor build directory",
    )
    latency_build_dir = resolve_repo_member(
        root,
        args.latency_build_dir,
        label="latency build directory",
    )
    cpp_root = resolve_repo_member(root, resolve_cpp_root(root, args.cpp_root), label="C++ reference root")
    cpp_build_dir = resolve_repo_member(root, args.cpp_build_dir, label="C++ build directory")
    log_dir = resolve_repo_member(root, args.log_dir, label="log directory")

    build_budget = build_jobs if build_jobs > 0 else max(os.cpu_count() or 2, 2)
    runtime_build_jobs = max(1, (build_budget + 1) // 2)
    decompressor_build_jobs = max(1, build_budget // 2)
    runtime_verilate_jobs = runtime_build_jobs
    decompressor_verilate_jobs = decompressor_build_jobs
    need_decompressor = not args.skip_decompressor_check
    need_latency = not args.skip_latency_measurement
    runtime_bin = roundtrip_build_dir / "Vtb_M4ExperimentalRuntimeFileCompressorTop"
    decompressor_bin = decompressor_build_dir / "Vtb_ExperimentalPageDecompressorTop"
    latency_bin = latency_build_dir / "Vtb_ExperimentalDecompressorTop"
    cpp_bin = cpp_build_dir / "cram_cpp_page_metrics"

    print("Preparing shared verification artifacts...", flush=True)
    print(
        "  runtime harness cache: "
        + ("hit" if runtime_bin.exists() else "miss (cold Verilator build can take several minutes)"),
        flush=True,
    )
    if need_decompressor:
        print(
            "  decompressor harness cache: "
            + ("hit" if decompressor_bin.exists() else "miss"),
            flush=True,
        )
    if need_latency:
        print(
            "  latency harness cache: "
            + ("hit" if latency_bin.exists() else "miss"),
            flush=True,
        )
    print(
        "  C++ helper cache: " + ("hit" if cpp_bin.exists() else "miss"),
        flush=True,
    )
    steps = ["runtime", "C++ helper"]
    if need_decompressor:
        steps.append("decompressor")
    if need_latency:
        steps.append("latency")
    print(
        "  building "
        + "/".join(steps)
        + " artifacts in parallel "
        f"(runtime jobs={runtime_build_jobs}, decompressor jobs={decompressor_build_jobs})...",
        flush=True,
    )
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {
            executor.submit(
                build_runtime_harness,
                root,
                verilator_bin=args.verilator_bin,
                build_dir=roundtrip_build_dir,
                build_jobs=runtime_build_jobs,
                verilate_jobs=runtime_verilate_jobs,
            ): "large-tier runtime harness",
            executor.submit(
                build_cpp_helper,
                root,
                cpp_root,
                cpp_build_dir,
            ): "C++ reference helper",
        }
        if need_decompressor:
            futures[
                executor.submit(
                    build_page_decompressor_harness,
                    root,
                    decompressor_build_dir,
                    "large",
                    args.verilator_bin,
                    decompressor_build_jobs,
                    decompressor_verilate_jobs,
                )
            ] = "large-tier decompressor harness"
        if need_latency:
            futures[
                executor.submit(
                    direct_latency.build_sim_binary,
                    root,
                    latency_build_dir,
                    "large",
                    args.verilator_bin,
                )
            ] = "large-tier direct latency harness"
        built_artifacts: dict[str, Path] = {}
        for future in as_completed(futures):
            label = futures[future]
            built_artifacts[label] = future.result()
            print(f"  ready: {label}", flush=True)

    run_bin = built_artifacts["large-tier runtime harness"]
    sim_bin = built_artifacts.get("large-tier decompressor harness")
    latency_bin = built_artifacts.get("large-tier direct latency harness")
    cpp_bin = built_artifacts["C++ reference helper"]

    return {
        "roundtrip_build_dir": roundtrip_build_dir,
        "decompressor_build_dir": decompressor_build_dir,
        "latency_build_dir": latency_build_dir,
        "cpp_root": cpp_root,
        "cpp_build_dir": cpp_build_dir,
        "log_dir": log_dir,
        "run_bin": run_bin,
        "sim_bin": sim_bin,
        "latency_bin": latency_bin,
        "cpp_bin": cpp_bin,
    }


def _zero_hardware_summary() -> dict:
    return {
        "input_bytes": 0,
        "padded_bytes": 0,
        "pages": 0,
        "raw_bits": 0,
        "encoded_bits": 0,
        "ratio": 0.0,
        "comp_cycles": 0,
        "decomp_cycles": 0,
        "total_cycles": 0,
        "comp_bpc": 0.0,
        "decomp_bpc": 0.0,
    }


def _zero_latency_summary() -> dict:
    return {
        "page_count": 0,
        "case_count": 0,
        "critical64_cycle_avg": 0.0,
        "critical64_cycle_median": 0.0,
        "rtl_cycle_avg": 0.0,
        "rtl_cycle_median": 0.0,
    }


def _failure_reason(exc: Exception) -> str:
    if isinstance(exc, subprocess.CalledProcessError):
        output = ((exc.stdout or "") + "\n" + (exc.stderr or "")).strip()
        first_line = output.splitlines()[0].strip() if output else ""
        if first_line:
            return f"subprocess failed (exit {exc.returncode}): {first_line}"
        return f"subprocess failed (exit {exc.returncode})"
    return str(exc)


def _build_failure_result(
    *,
    root: Path,
    loaded_input: LoadedPageInput,
    pages_requested: int,
    reason: str,
) -> dict:
    input_file = _display_path(root, loaded_input.input_file)
    return {
        "status": "FAIL",
        "input_file": input_file,
        "pages_requested": pages_requested,
        "input_accounting": loaded_input.accounting(pages_requested),
        "hardware_roundtrip": {
            "status": "FAIL",
            "input_file": input_file,
            "pages_requested": pages_requested,
            "pages_observed": 0,
            "build_dir": "",
            "hardware_log": "",
            "hardware_pages": [],
            "hardware_summary": _zero_hardware_summary(),
        },
        "reference_check": {
            "status": "INFO",
            "informational": True,
            "cpp_root": "",
            "cpp_bin": "",
            "reference_summary": {},
            "failure_reason": reason,
        },
        "decompressor_decode": {
            "status": "FAIL",
            "input_file": input_file,
            "pages": [],
            "page_count": 0,
            "sim_bin": "",
            "build_dir": "",
            "failure_reason": reason,
        },
        "decompressor_latency": {
            "status": "FAIL",
            "input_file": input_file,
            "page_count": 0,
            "case_count": 0,
            "sim_bin": "",
            "build_dir": "",
            "summary": _zero_latency_summary(),
            "failure_reason": reason,
        },
        "failure_reason": reason,
    }


def _skipped_decompressor_result(*, root: Path, input_file: Path, build_dir: Path, sim_bin: Path | None) -> dict:
    return {
        "status": "SKIPPED",
        "input_file": _display_path(root, input_file),
        "pages": [],
        "page_count": 0,
        "sim_bin": _display_path(root, sim_bin) if sim_bin else "",
        "build_dir": _display_path(root, build_dir),
        "skipped": True,
        "skip_reason": "--skip-decompressor-check",
    }


def _skipped_latency_result(*, root: Path, input_file: Path, build_dir: Path, sim_bin: Path | None) -> dict:
    return {
        "status": "SKIPPED",
        "input_file": _display_path(root, input_file),
        "page_count": 0,
        "case_count": 0,
        "sim_bin": _display_path(root, sim_bin) if sim_bin else "",
        "build_dir": _display_path(root, build_dir),
        "summary": _zero_latency_summary(),
        "skipped": True,
        "skip_reason": "--skip-latency-measurement",
    }


def _safe_latency_stem(root: Path, input_file: Path) -> str:
    return _display_path(root, input_file).replace("/", "__").replace(".", "_")


def _run_direct_latency_measurement(
    *,
    args: argparse.Namespace,
    root: Path,
    loaded_input: LoadedPageInput,
    build_dir: Path,
    sim_bin: Path,
) -> dict:
    if args.latency_pages < 0:
        raise RuntimeError("--latency-pages must be >= 0")

    sample_pages = loaded_input.pages if args.latency_pages == 0 else loaded_input.pages[: args.latency_pages]
    if not sample_pages:
        return {
            "status": "SKIPPED",
            "input_file": _display_path(root, loaded_input.input_file),
            "page_count": 0,
            "case_count": 0,
            "sim_bin": _display_path(root, sim_bin),
            "build_dir": _display_path(root, build_dir),
            "summary": _zero_latency_summary(),
            "skipped": True,
            "skip_reason": "no selected pages",
        }

    (
        experimental_compressor,
        experimental_decompressor,
        golden,
        _experimental_format,
    ) = direct_latency.import_helpers(root)

    cases: list[dict] = []
    for page_idx, raw_page in enumerate(sample_pages):
        _encoded, _cycles, details = experimental_compressor.cram_encode(
            bytes(raw_page),
            direct_latency.MODEL_CONFIG,
            return_details=True,
        )

        dict_count = len(details.dict_sequences)
        dict_lens = [0] * direct_latency.MAX_DICT_ENTRIES
        dict_seq_flat = [0] * (direct_latency.MAX_DICT_ENTRIES * direct_latency.MAX_SEQ_LEN)
        for dict_idx, sequence in enumerate(details.dict_sequences):
            dict_lens[dict_idx] = len(sequence)
            for sym_idx, symbol in enumerate(sequence):
                dict_seq_flat[dict_idx * direct_latency.MAX_SEQ_LEN + sym_idx] = symbol

        expansions = {256 + idx: sequence for idx, sequence in enumerate(details.dict_sequences)}

        for chunk_idx, chunk_bits in enumerate(details.compressed_chunk_bitstrings):
            tokens = experimental_decompressor.decode_experimental_chunk(chunk_bits)
            expected_output = direct_latency.decompress_window(
                tokens,
                dict_sequences=details.dict_sequences,
                dict_count=dict_count,
                golden=golden,
            )
            if len(expected_output) > direct_latency.CHUNK_WIDTH:
                raise RuntimeError(
                    f"direct latency case page={page_idx} chunk={chunk_idx} expands to "
                    f"{len(expected_output)} symbols, exceeding width {direct_latency.CHUNK_WIDTH}"
                )

            stack_cycles, seg_stack_cycles = direct_latency.simulate_segment(expansions, tokens)
            cases.append(
                {
                    "label": f"page{page_idx:04d}_chunk{chunk_idx:02d}",
                    "page_idx": page_idx,
                    "source_idx": chunk_idx,
                    "dict_count": dict_count,
                    "dict_lens": dict_lens,
                    "dict_seq_flat": dict_seq_flat,
                    "tokens": tokens,
                    "expected_output": expected_output,
                    "stack_cycles": stack_cycles,
                    "seg_stack_cycles": seg_stack_cycles,
                    "token_count": len(tokens),
                }
            )

    safe_stem = _safe_latency_stem(root, loaded_input.input_file)
    stim_path = build_dir / "stimuli" / f"{safe_stem}_direct_chunk_cases.txt"
    result_path = build_dir / "results" / f"{safe_stem}_direct_chunk_results.txt"
    direct_latency.write_stimulus(stim_path, cases)
    result_path.parent.mkdir(parents=True, exist_ok=True)

    run = subprocess.run(
        [
            str(sim_bin),
            f"+STIM_FILE={stim_path.resolve()}",
            f"+RESULT_FILE={result_path.resolve()}",
        ],
        cwd=root,
        check=True,
        text=True,
        capture_output=True,
    )
    if "[experimental-direct] PASS" not in run.stdout:
        raise RuntimeError(f"latency simulator did not report pass:\n{run.stdout}")

    measured = direct_latency.parse_result_file(result_path)
    if len(measured) != len(cases):
        raise RuntimeError(f"latency result count mismatch: got {len(measured)} expected {len(cases)}")

    case_results: list[dict] = []
    for case in cases:
        rtl = measured[case["label"]]
        state_sum = (
            rtl["state_idle_cycles"]
            + rtl["state_compact_cycles"]
            + rtl["state_prep_cycles"]
            + rtl["state_launch_cycles"]
            + rtl["state_wait_cycles"]
            + rtl["state_done_cycles"]
        )
        if state_sum != rtl["rtl_cycles"]:
            raise RuntimeError(
                f"latency state accounting mismatch for {case['label']}: "
                f"states={state_sum} rtl={rtl['rtl_cycles']}"
            )
        case_results.append(
            {
                **case,
                **rtl,
                "rtl_minus_stack_cycles": rtl["rtl_cycles"] - case["stack_cycles"],
            }
        )

    def avg(field: str) -> float:
        return sum(case[field] for case in case_results) / len(case_results) if case_results else 0.0

    summary = {
        "input_file": relative_repo_path(root, loaded_input.input_file),
        "page_count": len(sample_pages),
        "case_count": len(case_results),
        "stack_cycle_avg": avg("stack_cycles"),
        "stack_cycle_median": None,
        "rtl_cycle_avg": avg("rtl_cycles"),
        "rtl_cycle_median": None,
        "critical64_cycle_avg": avg("critical64_cycles_avg"),
        "critical64_cycle_median": None,
        "rtl_minus_stack_avg": avg("rtl_minus_stack_cycles"),
    }
    if case_results:
        rtl_cycles = sorted(case["rtl_cycles"] for case in case_results)
        stack_cycles = sorted(case["stack_cycles"] for case in case_results)
        critical64_cycles = sorted(case["critical64_cycles_avg"] for case in case_results)
        mid = len(case_results) // 2
        if len(case_results) % 2:
            summary["rtl_cycle_median"] = rtl_cycles[mid]
            summary["stack_cycle_median"] = stack_cycles[mid]
            summary["critical64_cycle_median"] = critical64_cycles[mid]
        else:
            summary["rtl_cycle_median"] = (rtl_cycles[mid - 1] + rtl_cycles[mid]) / 2.0
            summary["stack_cycle_median"] = (stack_cycles[mid - 1] + stack_cycles[mid]) / 2.0
            summary["critical64_cycle_median"] = (
                critical64_cycles[mid - 1] + critical64_cycles[mid]
            ) / 2.0

    return {
        "status": "PASS",
        "input_file": _display_path(root, loaded_input.input_file),
        "page_count": len(sample_pages),
        "case_count": len(case_results),
        "sim_bin": _display_path(root, sim_bin),
        "build_dir": _display_path(root, build_dir),
        "stimulus": _display_path(root, stim_path),
        "result_file": _display_path(root, result_path),
        "summary": summary,
    }


def _verify_input(
    *,
    args: argparse.Namespace,
    root: Path,
    loaded_input: LoadedPageInput,
    pages_requested: int,
    artifacts: dict,
) -> dict:
    input_file = loaded_input.input_file
    parallel = _parallel_plan(args.jobs, len(loaded_input.pages))

    if parallel["stage_parallel"]:
        with ThreadPoolExecutor(max_workers=4) as executor:
            roundtrip_future = executor.submit(
                run_hardware_roundtrip,
                input_file=input_file,
                pages_requested=pages_requested,
                root=root,
                verilator_bin=args.verilator_bin,
                build_dir=artifacts["roundtrip_build_dir"],
                build_jobs=0,
                log_dir=artifacts["log_dir"],
                raw_pages=loaded_input.pages,
                run_bin=artifacts["run_bin"],
                page_shards=parallel["hardware_shards"],
                verbose=False,
            )
            cpp_future = executor.submit(
                run_cpp_model,
                artifacts["cpp_bin"],
                input_file,
                pages=len(loaded_input.pages),
                chunk_size=CPP_CHUNK_SIZE,
                memory_blocks=CPP_MEMORY_BLOCKS,
                page_bytes=PAGE_BYTES,
                runtime_pad=True,
            )
            decompressor_future = None
            latency_future = None
            if not args.skip_decompressor_check:
                decompressor_future = executor.submit(
                    run_sv_decompressor_check,
                    input_file=input_file,
                    pages_requested=pages_requested,
                    root=root,
                    tier="large",
                    verilator_bin=args.verilator_bin,
                    build_dir=artifacts["decompressor_build_dir"],
                    raw_pages=loaded_input.pages,
                    sim_bin=artifacts["sim_bin"],
                    page_shards=parallel["decompressor_shards"],
                    verbose=False,
                )
            if not args.skip_latency_measurement:
                latency_future = executor.submit(
                    _run_direct_latency_measurement,
                    args=args,
                    root=root,
                    loaded_input=loaded_input,
                    build_dir=artifacts["latency_build_dir"],
                    sim_bin=artifacts["latency_bin"],
                )
            roundtrip_result = roundtrip_future.result()
            if decompressor_future is not None:
                decompressor_result = decompressor_future.result()
            else:
                decompressor_result = _skipped_decompressor_result(
                    root=root,
                    input_file=input_file,
                    build_dir=artifacts["decompressor_build_dir"],
                    sim_bin=artifacts["sim_bin"],
                )
            if latency_future is not None:
                latency_result = latency_future.result()
            else:
                latency_result = _skipped_latency_result(
                    root=root,
                    input_file=input_file,
                    build_dir=artifacts["latency_build_dir"],
                    sim_bin=artifacts["latency_bin"],
                )
            cpp_pages, cpp_summary = cpp_future.result()
    else:
        roundtrip_result = run_hardware_roundtrip(
            input_file=input_file,
            pages_requested=pages_requested,
            root=root,
            verilator_bin=args.verilator_bin,
            build_dir=artifacts["roundtrip_build_dir"],
            build_jobs=0,
            log_dir=artifacts["log_dir"],
            raw_pages=loaded_input.pages,
            run_bin=artifacts["run_bin"],
            page_shards=1,
            verbose=False,
        )
        if args.skip_decompressor_check:
            decompressor_result = _skipped_decompressor_result(
                root=root,
                input_file=input_file,
                build_dir=artifacts["decompressor_build_dir"],
                sim_bin=artifacts["sim_bin"],
            )
        else:
            decompressor_result = run_sv_decompressor_check(
                input_file=input_file,
                pages_requested=pages_requested,
                root=root,
                tier="large",
                verilator_bin=args.verilator_bin,
                build_dir=artifacts["decompressor_build_dir"],
                raw_pages=loaded_input.pages,
                sim_bin=artifacts["sim_bin"],
                page_shards=1,
                verbose=False,
            )
        if args.skip_latency_measurement:
            latency_result = _skipped_latency_result(
                root=root,
                input_file=input_file,
                build_dir=artifacts["latency_build_dir"],
                sim_bin=artifacts["latency_bin"],
            )
        else:
            latency_result = _run_direct_latency_measurement(
                args=args,
                root=root,
                loaded_input=loaded_input,
                build_dir=artifacts["latency_build_dir"],
                sim_bin=artifacts["latency_bin"],
            )
        cpp_pages, cpp_summary = run_cpp_model(
            artifacts["cpp_bin"],
            input_file,
            pages=len(loaded_input.pages),
            chunk_size=CPP_CHUNK_SIZE,
            memory_blocks=CPP_MEMORY_BLOCKS,
            page_bytes=PAGE_BYTES,
            runtime_pad=True,
        )

    roundtrip_result.pop("raw_pages", None)
    roundtrip_result = _rewrite_path_fields(
        root,
        roundtrip_result,
        "input_file",
        "build_dir",
        "hardware_log",
    )
    if "shards" in roundtrip_result:
        roundtrip_result["shards"] = _rewrite_path_list(root, roundtrip_result["shards"], "hardware_log")

    decompressor_result = _rewrite_path_fields(
        root,
        decompressor_result,
        "input_file",
        "sim_bin",
        "build_dir",
    )
    latency_result = _rewrite_path_fields(
        root,
        latency_result,
        "input_file",
        "sim_bin",
        "build_dir",
        "stimulus",
        "result_file",
    )

    reference_mismatches = compare_hardware_to_cpp(
        roundtrip_result["hardware_pages"],
        roundtrip_result["hardware_summary"],
        cpp_pages,
        cpp_summary,
    )
    reference_failure_reason = None
    if reference_mismatches and args.strict_reference_match:
        reference_failure_reason = (
            f"strict reference mismatch ({len(reference_mismatches)} difference(s))"
        )
    overall_ok = (
        roundtrip_result["status"] == "PASS"
        and decompressor_result["status"] in {"PASS", "SKIPPED"}
        and latency_result["status"] in {"PASS", "SKIPPED"}
        and reference_failure_reason is None
    )

    failure_reason = reference_failure_reason if reference_failure_reason is not None else None
    return {
        "status": "PASS" if overall_ok else "FAIL",
        "input_file": _display_path(root, input_file),
        "pages_requested": pages_requested,
        "input_accounting": loaded_input.accounting(pages_requested),
        "parallel": parallel,
        "hardware_roundtrip": roundtrip_result,
        "reference_check": {
            "status": "INFO",
            "informational": True,
            "cpp_root": _display_path(root, artifacts["cpp_root"]),
            "cpp_bin": _display_path(root, artifacts["cpp_bin"]),
            "reference_summary": cpp_summary,
            **({"failure_reason": reference_failure_reason} if reference_failure_reason else {}),
        },
        "decompressor_decode": decompressor_result,
        "decompressor_latency": latency_result,
        **({"failure_reason": failure_reason} if failure_reason else {}),
    }


def _aggregate_results(results: list[dict]) -> dict:
    total_raw_bits = 0
    total_encoded_bits = 0
    total_comp_cycles = 0
    total_decomp_cycles = 0

    for result in results:
        hw_summary = result.get("hardware_roundtrip", {}).get("hardware_summary", {})
        total_raw_bits += hw_summary.get("raw_bits", 0)
        total_encoded_bits += hw_summary.get("encoded_bits", 0)
        total_comp_cycles += hw_summary.get("comp_cycles", 0)
        total_decomp_cycles += hw_summary.get("decomp_cycles", 0)

    return {
        "inputs": len(results),
        "passed": sum(1 for result in results if result["status"] == "PASS"),
        "failed": sum(1 for result in results if result["status"] != "PASS"),
        "selected_pages": sum(result["input_accounting"].get("selected_pages", 0) for result in results),
        "selected_bytes": sum(result["input_accounting"].get("selected_bytes", 0) for result in results),
        "ignored_tail_bytes": sum(result["input_accounting"].get("ignored_tail_bytes", 0) for result in results),
        "short_input_count": sum(
            1
            for result in results
            if result["pages_requested"] > 0
            and result["input_accounting"].get("file_pages", 0) < result["pages_requested"]
        ),
        "inputs_with_partial_final_page": sum(
            1 for result in results if result["input_accounting"].get("selected_trailing_bytes", 0) > 0
        ),
        "inputs_truncated_by_page_limit": sum(
            1 for result in results if result["input_accounting"].get("truncated_by_page_limit", False)
        ),
        "raw_bits": total_raw_bits,
        "encoded_bits": total_encoded_bits,
        "ratio": (total_raw_bits / total_encoded_bits) if total_encoded_bits else 0.0,
        "comp_cycles": total_comp_cycles,
        "decomp_cycles": total_decomp_cycles,
    }


def _geometric_mean(values: list[float]) -> float | None:
    positive = [value for value in values if value and value > 0.0]
    if not positive:
        return None
    return math.exp(sum(math.log(value) for value in positive) / len(positive))


def _reference_ratio(result: dict) -> float | None:
    summary = result.get("reference_check", {}).get("reference_summary", {})
    ratio = summary.get("ratio")
    if ratio is not None:
        return float(ratio)
    raw_bits = summary.get("raw_bits", 0)
    encoded_bits = summary.get("encoded_bits", 0)
    if raw_bits and encoded_bits:
        return raw_bits / encoded_bits
    return None


def _suite_name(result: dict) -> str | None:
    name = Path(result["input_file"]).stem
    if "_" not in name:
        return None
    return name.split("_", 1)[0]


def _paper_metric_summary(results: list[dict]) -> dict | None:
    passed = [result for result in results if result["status"] == "PASS"]
    if not passed:
        return None

    ratio_hw_bench = []
    ratio_cpp_bench = []
    comp_bpc_bench = []
    decomp_bpc_bench = []
    decomp_critical64_bench = []
    decomp_full_chunk_bench = []
    hw_ratio_suite: dict[str, list[float]] = {}
    cpp_ratio_suite: dict[str, list[float]] = {}
    comp_bpc_suite: dict[str, list[float]] = {}
    decomp_bpc_suite: dict[str, list[float]] = {}
    decomp_critical64_suite: dict[str, list[float]] = {}
    decomp_full_chunk_suite: dict[str, list[float]] = {}

    for result in passed:
        hw_summary = result.get("hardware_roundtrip", {}).get("hardware_summary", {})
        hw_ratio = hw_summary.get("ratio")
        cpp_ratio = _reference_ratio(result)
        suite = _suite_name(result)
        comp_bpc = hw_summary.get("comp_bpc")
        decomp_bpc = hw_summary.get("decomp_bpc")
        latency_summary = result.get("decompressor_latency", {}).get("summary", {})
        decomp_critical64 = latency_summary.get("critical64_cycle_avg")
        decomp_full_chunk = latency_summary.get("rtl_cycle_avg")

        if hw_ratio and hw_ratio > 0.0:
            ratio_hw_bench.append(hw_ratio)
            if suite is not None:
                hw_ratio_suite.setdefault(suite, []).append(hw_ratio)
        if cpp_ratio and cpp_ratio > 0.0:
            ratio_cpp_bench.append(cpp_ratio)
            if suite is not None:
                cpp_ratio_suite.setdefault(suite, []).append(cpp_ratio)
        if comp_bpc and comp_bpc > 0.0:
            comp_bpc_bench.append(comp_bpc)
            if suite is not None:
                comp_bpc_suite.setdefault(suite, []).append(comp_bpc)
        if decomp_bpc and decomp_bpc > 0.0:
            decomp_bpc_bench.append(decomp_bpc)
            if suite is not None:
                decomp_bpc_suite.setdefault(suite, []).append(decomp_bpc)
        if decomp_critical64 and decomp_critical64 > 0.0:
            decomp_critical64_bench.append(decomp_critical64)
            if suite is not None:
                decomp_critical64_suite.setdefault(suite, []).append(decomp_critical64)
        if decomp_full_chunk and decomp_full_chunk > 0.0:
            decomp_full_chunk_bench.append(decomp_full_chunk)
            if suite is not None:
                decomp_full_chunk_suite.setdefault(suite, []).append(decomp_full_chunk)

    bench_ratio_hw_gmean = _geometric_mean(ratio_hw_bench)
    bench_ratio_cpp_gmean = _geometric_mean(ratio_cpp_bench)
    bench_comp_bpc_gmean = _geometric_mean(comp_bpc_bench)
    bench_decomp_bpc_gmean = _geometric_mean(decomp_bpc_bench)
    bench_decomp_critical64_gmean = _geometric_mean(decomp_critical64_bench)
    bench_decomp_full_chunk_gmean = _geometric_mean(decomp_full_chunk_bench)

    suite_rows = []
    for suite in sorted(
        set(hw_ratio_suite)
        | set(cpp_ratio_suite)
        | set(comp_bpc_suite)
        | set(decomp_bpc_suite)
        | set(decomp_critical64_suite)
        | set(decomp_full_chunk_suite)
    ):
        hw_suite_gmean = _geometric_mean(hw_ratio_suite.get(suite, []))
        cpp_suite_gmean = _geometric_mean(cpp_ratio_suite.get(suite, []))
        comp_suite_gmean = _geometric_mean(comp_bpc_suite.get(suite, []))
        decomp_suite_gmean = _geometric_mean(decomp_bpc_suite.get(suite, []))
        latency_suite_gmean = _geometric_mean(decomp_critical64_suite.get(suite, []))
        full_chunk_suite_gmean = _geometric_mean(decomp_full_chunk_suite.get(suite, []))
        suite_rows.append(
            {
                "suite": suite,
                "hardware_ratio_geomean": hw_suite_gmean,
                "cpp_ratio_geomean": cpp_suite_gmean,
                "compressor_bpc_geomean": comp_suite_gmean,
                "decompressor_bpc_geomean": decomp_suite_gmean,
                "decompressor_critical64_cycles_geomean": latency_suite_gmean,
                "decompressor_full_chunk_cycles_geomean": full_chunk_suite_gmean,
                "inputs": len(hw_ratio_suite.get(suite, [])),
            }
        )

    suite_ratio_hw_geogeo = _geometric_mean(
        [row["hardware_ratio_geomean"] for row in suite_rows if row["hardware_ratio_geomean"]]
    )
    suite_ratio_cpp_geogeo = _geometric_mean(
        [row["cpp_ratio_geomean"] for row in suite_rows if row["cpp_ratio_geomean"]]
    )
    suite_comp_bpc_geogeo = _geometric_mean(
        [row["compressor_bpc_geomean"] for row in suite_rows if row["compressor_bpc_geomean"]]
    )
    suite_decomp_bpc_geogeo = _geometric_mean(
        [row["decompressor_bpc_geomean"] for row in suite_rows if row["decompressor_bpc_geomean"]]
    )
    suite_decomp_critical64_geogeo = _geometric_mean(
        [
            row["decompressor_critical64_cycles_geomean"]
            for row in suite_rows
            if row["decompressor_critical64_cycles_geomean"]
        ]
    )
    suite_decomp_full_chunk_geogeo = _geometric_mean(
        [
            row["decompressor_full_chunk_cycles_geomean"]
            for row in suite_rows
            if row["decompressor_full_chunk_cycles_geomean"]
        ]
    )
    ratio_delta_pct = None
    if suite_ratio_hw_geogeo and suite_ratio_cpp_geogeo:
        ratio_delta_pct = (suite_ratio_hw_geogeo / suite_ratio_cpp_geogeo - 1.0) * 100.0

    return {
        "benchmark_geomeans": {
            "ratio": {
                "hardware": bench_ratio_hw_gmean,
                "cpp": bench_ratio_cpp_gmean,
            },
            "compressor_bpc": bench_comp_bpc_gmean,
            "decompressor_bpc": bench_decomp_bpc_gmean,
            "decompressor_critical64_cycles": bench_decomp_critical64_gmean,
            "decompressor_full_chunk_cycles": bench_decomp_full_chunk_gmean,
        },
        "suite_geomeans": suite_rows,
        "suite_geomean_of_geomeans": {
            "ratio": {
                "hardware": suite_ratio_hw_geogeo,
                "cpp": suite_ratio_cpp_geogeo,
                "delta_pct": ratio_delta_pct,
            },
            "compressor_bpc": suite_comp_bpc_geogeo,
            "decompressor_bpc": suite_decomp_bpc_geogeo,
            "decompressor_critical64_cycles": suite_decomp_critical64_geogeo,
            "decompressor_full_chunk_cycles": suite_decomp_full_chunk_geogeo,
        },
    }


def _directory_summaries(results: list[dict]) -> list[dict]:
    directories = sorted({Path(result["input_file"]).parent.as_posix() for result in results})
    if directories == ["."]:
        return []

    summaries: list[dict] = []
    for directory in directories:
        directory_results = [
            result for result in results if Path(result["input_file"]).parent.as_posix() == directory
        ]
        summary = _aggregate_results(directory_results)
        summary["directory"] = directory
        summaries.append(summary)
    return summaries


def _format_accounting_note(result: dict) -> str:
    accounting = result["input_accounting"]
    notes: list[str] = []

    if result["pages_requested"] > 0 and accounting["file_pages"] < result["pages_requested"]:
        notes.append(f"short file {accounting['selected_pages']}/{result['pages_requested']} page(s)")
    if accounting["selected_trailing_bytes"] > 0:
        notes.append(f"final partial page={accounting['selected_trailing_bytes']}B")
    if accounting["ignored_tail_bytes"] > 0:
        notes.append(f"ignored tail={accounting['ignored_tail_bytes']}B")

    return "; ".join(notes)


def _result_failure_reason(result: dict) -> str:
    reason = result.get("failure_reason")
    if reason:
        return reason

    hardware_result = result.get("hardware_roundtrip", {})
    if hardware_result.get("status") != "PASS":
        return "hardware round-trip failed"

    decompressor_result = result.get("decompressor_decode", {})
    if decompressor_result.get("status") != "PASS":
        return decompressor_result.get("failure_reason", "decompressor decode failed")

    latency_result = result.get("decompressor_latency", {})
    if latency_result.get("status") not in {"PASS", "SKIPPED"}:
        return latency_result.get("failure_reason", "decompressor latency measurement failed")

    return "verification failed"


def _parallel_status_line(result: dict) -> str | None:
    parallel = result.get("parallel", {})
    hardware_shards = parallel.get("hardware_shards", 1)
    decompressor_shards = parallel.get("decompressor_shards", 1)
    if hardware_shards <= 1 and decompressor_shards <= 1:
        return None
    cpp_mode = "overlapped" if parallel.get("cpp_parallel") else "serial"
    return (
        f"hardware shards={hardware_shards}, "
        f"decompressor shards={decompressor_shards}, "
        f"C++={cpp_mode}"
    )


def _print_single_result(result: dict) -> None:
    hw_summary = result["hardware_roundtrip"]["hardware_summary"]
    decompressor_result = result["decompressor_decode"]
    latency_result = result.get("decompressor_latency", {})
    note = _format_accounting_note(result)
    parallel_note = _parallel_status_line(result)

    print(f"\n{result['status']} reviewer verification")
    print(f"  input: {result['input_file']}")
    print(f"  pages: {hw_summary.get('pages', 0)}")
    if note:
        print(f"  input accounting: {note}")
    if parallel_note:
        print(f"  parallel: {parallel_note}")

    if result.get("failure_reason"):
        print(f"  failure: {result['failure_reason']}")
    else:
        print(f"  hardware ratio: {hw_summary['ratio']:.4f}x")
        print(
            "  compressor: "
            f"{hw_summary['comp_cycles']} cycles "
            f"({hw_summary['comp_bpc']:.4f} B/cycle)"
        )
        print(
            "  decompressor: "
            f"{hw_summary['decomp_cycles']} cycles "
            f"({hw_summary['decomp_bpc']:.4f} B/cycle)"
        )
        print(
            "  decompressor decode: "
            + (
                "skipped (--skip-decompressor-check)"
                if decompressor_result.get("status") == "SKIPPED"
                else f"{decompressor_result['page_count']}/{decompressor_result['page_count']} page(s)"
            )
        )
        latency_summary = latency_result.get("summary", {})
        if latency_result.get("status") == "SKIPPED":
            print("  decompressor critical-64B latency: skipped (--skip-latency-measurement)")
        elif latency_summary.get("critical64_cycle_avg") is not None:
            print(
                "  decompressor critical-64B latency: "
                f"{latency_summary['critical64_cycle_avg']:.2f} cycles/block "
                f"({latency_summary['critical64_cycle_avg'] / 2.5:.2f} ns/block @ 2.5 GHz)"
            )
        if latency_summary.get("rtl_cycle_avg") is not None and latency_result.get("status") == "PASS":
            print(
                "  decompressor full-chunk latency: "
                f"{latency_summary['rtl_cycle_avg']:.2f} cycles/chunk "
                f"({latency_summary['rtl_cycle_avg'] / 2.5:.2f} ns/chunk @ 2.5 GHz)"
            )

    hardware_log = result["hardware_roundtrip"].get("hardware_log")
    if hardware_log:
        print(f"  hardware log: {hardware_log}")

def _print_suite_progress(index: int, total: int, result: dict) -> None:
    hw_summary = result["hardware_roundtrip"]["hardware_summary"]
    parallel = result.get("parallel", {})
    line = (
        f"[{index}/{total}] {result['status']} {result['input_file']} "
        f"pages={hw_summary.get('pages', 0)} "
        f"ratio={hw_summary.get('ratio', 0.0):.4f}x"
    )
    if parallel.get("hardware_shards", 1) > 1 or parallel.get("decompressor_shards", 1) > 1:
        line += (
            f" hw_shards={parallel.get('hardware_shards', 1)}"
            f" dec_shards={parallel.get('decompressor_shards', 1)}"
        )
    print(line)

    note = _format_accounting_note(result)
    if note:
        print(f"      input accounting: {note}")

    if result.get("failure_reason"):
        print(f"      failure: {result['failure_reason']}")
        return


def _print_suite_summary(target: str, results: list[dict]) -> None:
    aggregate = _aggregate_results(results)
    directory_summaries = _directory_summaries(results)
    paper_summary = _paper_metric_summary(results)
    status = "PASS" if aggregate["failed"] == 0 else "FAIL"

    print(f"\n{status} reviewer verification suite")
    print(f"  target: {target}")
    print(f"  inputs: {aggregate['passed']}/{aggregate['inputs']} passed")
    print(f"  pages: {aggregate['selected_pages']}")
    print(f"  pooled hardware ratio: {aggregate['ratio']:.4f}x")
    if paper_summary is not None:
        bench = paper_summary["benchmark_geomeans"]
        suite = paper_summary["suite_geomean_of_geomeans"]
        bench_ratio = bench["ratio"]
        suite_ratio = suite["ratio"]
        if bench_ratio["hardware"] is not None and bench_ratio["cpp"] is not None:
            print(
                "  benchmark geomean ratio: "
                f"{bench_ratio['hardware']:.4f}x (hardware) vs {bench_ratio['cpp']:.4f}x (C++)"
            )
        if suite_ratio["hardware"] is not None and suite_ratio["cpp"] is not None:
            delta = suite_ratio["delta_pct"]
            delta_text = f" [delta: {delta:+.3f}%]" if delta is not None else ""
            print(
                "  suite geomean-of-geomeans: "
                f"{suite_ratio['hardware']:.4f}x (hardware) vs {suite_ratio['cpp']:.4f}x (C++)"
                f"{delta_text}"
            )
        if bench["compressor_bpc"] is not None:
            print(
                "  benchmark geomean compressor throughput: "
                f"{bench['compressor_bpc']:.4f} B/cycle "
                f"({bench['compressor_bpc'] * 2.5:.4f} GB/s @ 2.5 GHz)"
            )
        if bench["decompressor_bpc"] is not None:
            print(
                "  benchmark geomean decompressor throughput: "
                f"{bench['decompressor_bpc']:.4f} B/cycle "
                f"({bench['decompressor_bpc'] * 2.5:.4f} GB/s @ 2.5 GHz)"
            )
        if bench["decompressor_critical64_cycles"] is not None:
            print(
                "  benchmark geomean decompressor critical-64B latency: "
                f"{bench['decompressor_critical64_cycles']:.2f} cycles/block "
                f"({bench['decompressor_critical64_cycles'] / 2.5:.2f} ns/block @ 2.5 GHz)"
            )
        if bench["decompressor_full_chunk_cycles"] is not None:
            print(
                "  benchmark geomean decompressor full-chunk latency: "
                f"{bench['decompressor_full_chunk_cycles']:.2f} cycles/chunk "
                f"({bench['decompressor_full_chunk_cycles'] / 2.5:.2f} ns/chunk @ 2.5 GHz)"
            )
        if suite["compressor_bpc"] is not None:
            print(
                "  suite geomean-of-geomeans compressor throughput: "
                f"{suite['compressor_bpc']:.4f} B/cycle "
                f"({suite['compressor_bpc'] * 2.5:.4f} GB/s @ 2.5 GHz)"
            )
        if suite["decompressor_bpc"] is not None:
            print(
                "  suite geomean-of-geomeans decompressor throughput: "
                f"{suite['decompressor_bpc']:.4f} B/cycle "
                f"({suite['decompressor_bpc'] * 2.5:.4f} GB/s @ 2.5 GHz)"
            )
        if suite["decompressor_critical64_cycles"] is not None:
            print(
                "  suite geomean-of-geomeans decompressor critical-64B latency: "
                f"{suite['decompressor_critical64_cycles']:.2f} cycles/block "
                f"({suite['decompressor_critical64_cycles'] / 2.5:.2f} ns/block @ 2.5 GHz)"
            )
        if suite["decompressor_full_chunk_cycles"] is not None:
            print(
                "  suite geomean-of-geomeans decompressor full-chunk latency: "
                f"{suite['decompressor_full_chunk_cycles']:.2f} cycles/chunk "
                f"({suite['decompressor_full_chunk_cycles'] / 2.5:.2f} ns/chunk @ 2.5 GHz)"
            )

    accounting_notes: list[str] = []
    if aggregate["short_input_count"] > 0:
        accounting_notes.append(f"short files={aggregate['short_input_count']}")
    if aggregate["inputs_with_partial_final_page"] > 0:
        accounting_notes.append(f"partial final pages={aggregate['inputs_with_partial_final_page']}")
    if aggregate["inputs_truncated_by_page_limit"] > 0:
        accounting_notes.append(
            f"page-limited inputs={aggregate['inputs_truncated_by_page_limit']} "
            f"(ignored tail={aggregate['ignored_tail_bytes']}B)"
        )
    if accounting_notes:
        print(f"  input accounting: {'; '.join(accounting_notes)}")

    if directory_summaries:
        print("  directories:")
        for summary in directory_summaries:
            print(
                f"    {summary['directory']}: "
                f"{summary['passed']}/{summary['inputs']} passed, "
                f"ratio={summary['ratio']:.4f}x"
            )

    failures = [result for result in results if result["status"] != "PASS"]
    for result in failures[:10]:
        print(f"  failure: {result['input_file']} :: {_result_failure_reason(result)}")
    if len(failures) > 10:
        print(f"  failure: ... and {len(failures) - 10} more")


def print_command_failure(exc: subprocess.CalledProcessError) -> None:
    print("\nFAIL reviewer verification", file=sys.stderr)
    if exc.stdout:
        print(exc.stdout, end="", file=sys.stderr)
    if exc.stderr:
        print(exc.stderr, end="", file=sys.stderr)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(line_buffering=True)
    args = parse_args()
    root = repo_root()

    try:
        mode, target, inputs = _resolve_targets(args, root)
        pages_requested = _resolve_pages(args)
        build_jobs = _effective_build_jobs(args)
        write_json_path = (
            resolve_repo_member(root, args.write_json, label="JSON output path")
            if args.write_json is not None
            else None
        )

        artifacts = _prepare_shared_artifacts(args, root, build_jobs)

        if mode == "single":
            loaded_input = load_paged_input(root, inputs[0], pages_requested)
            result = _verify_input(
                args=args,
                root=root,
                loaded_input=loaded_input,
                pages_requested=pages_requested,
                artifacts=artifacts,
            )
            if write_json_path is not None:
                ensure_parent(write_json_path).write_text(json.dumps(result, indent=2), encoding="utf-8")
            _print_single_result(result)
            return 0 if result["status"] == "PASS" else 1

        print(f"Running reviewer verification across {len(inputs)} dump(s) from {target}...")
        results: list[dict] = []
        for index, input_file in enumerate(inputs, start=1):
            loaded_input = load_paged_input(root, input_file, pages_requested)
            print(
                f"[{index}/{len(inputs)}] starting {loaded_input.input_file.name} "
                f"({len(loaded_input.pages)} page(s) loaded)",
                flush=True,
            )
            try:
                result = _verify_input(
                    args=args,
                    root=root,
                    loaded_input=loaded_input,
                    pages_requested=pages_requested,
                    artifacts=artifacts,
                )
            except (RuntimeError, subprocess.CalledProcessError) as exc:
                result = _build_failure_result(
                    root=root,
                    loaded_input=loaded_input,
                    pages_requested=pages_requested,
                    reason=_failure_reason(exc),
                )
            results.append(result)
            _print_suite_progress(index, len(inputs), result)

        summary = {
            "status": "PASS" if all(result["status"] == "PASS" for result in results) else "FAIL",
            "mode": "directory",
            "target": target,
            "pages_requested": pages_requested,
            "aggregate": _aggregate_results(results),
            "paper_metric_summary": _paper_metric_summary(results),
            "directories": _directory_summaries(results),
            "results": results,
        }
        if write_json_path is not None:
            ensure_parent(write_json_path).write_text(json.dumps(summary, indent=2), encoding="utf-8")

        _print_suite_summary(target, results)
        return 0 if summary["status"] == "PASS" else 1
    except subprocess.CalledProcessError as exc:
        print_command_failure(exc)
        return 1
    except RuntimeError as exc:
        print("\nFAIL reviewer verification", file=sys.stderr)
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
