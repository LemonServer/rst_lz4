#!/usr/bin/env python3
"""Run the richer SV runtime path against the richer Python model."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from m4_hardware_sim_common import (
    DEFAULT_LOG_DIR,
    DEFAULT_VERILATOR_BIN,
    PageShard,
    default_input_file,
    derive_summary_from_pages,
    ensure_parent,
    is_stale_verilator_cache,
    load_paged_input,
    repo_root,
    resolve_repo_path,
    run_cmd,
    run_cmd_streaming,
    runtime_log_path,
    shard_page_inputs,
    verilator_supports_flag,
)


RE_PAGE_PREFIXES = ("[verify page ", "[exp page ")
RE_SUMMARY_PREFIXES = ("[verify file summary] ", "[exp file summary] ")

MODEL_CONFIG = {
    "memory_blocks": 2,
    "chunk_size": 256,
    "min_cycles_per_iteration": 16,
    "static_tree_codes_per_cycle": 0,
}
PAGE_WIDTH_BYTES = 4096


def is_rebuild_worthy_verilator_failure(exc: subprocess.CalledProcessError) -> bool:
    combined = (exc.stdout or "") + (exc.stderr or "")
    return is_stale_verilator_cache(exc) or (
        ("unable to read PCH file" in combined) or ("PCH file" in combined and "not found" in combined)
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare the large-tier richer SV runtime path against the richer Python model."
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
        default=Path("build/verilator/m4_runtime_richer_large"),
        help="Verilator output directory",
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


def load_runtime_pages(input_file: Path, pages_requested: int, root: Path) -> tuple[int, list[bytes]]:
    loaded = load_paged_input(root, input_file, pages_requested)
    return loaded.page_width, loaded.pages


def parse_keyvals(line: str, prefix: str) -> dict[str, str]:
    if prefix and not line.startswith(prefix):
        raise ValueError(f"line does not start with {prefix!r}: {line}")
    payload = line[len(prefix):].strip()
    fields: dict[str, str] = {}
    for token in payload.split():
        key, value = token.split("=", 1)
        fields[key] = value
    return fields


def _matching_prefix(line: str, prefixes: tuple[str, ...]) -> str | None:
    for prefix in prefixes:
        if line.startswith(prefix):
            return prefix
    return None


def parse_hardware_log(log_text: str) -> tuple[list[dict], dict]:
    pages: list[dict] = []
    summary: dict | None = None

    for raw_line in log_text.splitlines():
        line = raw_line.strip()
        page_prefix = _matching_prefix(line, RE_PAGE_PREFIXES)
        if page_prefix is not None:
            bracket_idx = line.index("]")
            page_label = line[len(page_prefix):bracket_idx]
            if "/" in page_label:
                page_idx_text, page_total_text = page_label.split("/", 1)
                page_total = int(page_total_text)
            else:
                page_idx_text = page_label
                page_total = None

            page_info = parse_keyvals(line[bracket_idx + 2 :], "")
            page = {
                "page_idx": int(page_idx_text),
                "page_total": page_total,
                "valid_bytes": int(page_info["valid_bytes"]),
                "comp_syms": int(page_info["comp_syms"]),
                "total_dict_entries": int(page_info["total_dict_entries"]),
                "stored_dict_count": int(page_info["stored_dict_count"]),
                "dict_bits": int(page_info["dict_bits"]),
                "raw_bits": int(page_info["raw_bits"]),
                "encoded_bits": int(page_info["encoded_bits"]),
                "ratio": float(page_info["ratio"]),
                "comp_cycles": int(page_info["comp_cycles"]),
                "decomp_cycles": int(page_info["decomp_cycles"]),
                "comp_bpc": float(page_info["comp_Bpc"]),
                "decomp_bpc": float(page_info["decomp_Bpc"]),
            }
            pages.append(page)
            continue

        summary_prefix = _matching_prefix(line, RE_SUMMARY_PREFIXES)
        if summary_prefix is not None:
            summary_info = parse_keyvals(line, summary_prefix)
            summary = {
                "input_bytes": int(summary_info["input_bytes"]),
                "padded_bytes": int(summary_info["padded_bytes"]),
                "pages": int(summary_info["pages"]),
                "raw_bits": int(summary_info["raw_bits"]),
                "encoded_bits": int(summary_info["encoded_bits"]),
                "ratio": float(summary_info["ratio"]),
                "comp_cycles": int(summary_info["comp_cycles"]),
                "decomp_cycles": int(summary_info["decomp_cycles"]),
                "total_cycles": int(summary_info["total_cycles"]),
                "comp_bpc": float(summary_info["comp_Bpc"]),
                "decomp_bpc": float(summary_info["decomp_Bpc"]),
            }

    if summary is None or (summary.get("pages", 0) == 0 and pages):
        if not pages:
            raise RuntimeError("Did not find any [verify page ...] lines in hardware output")
        input_bytes = sum(page["valid_bytes"] for page in pages)
        raw_bits = sum(page["raw_bits"] for page in pages)
        encoded_bits = sum(page["encoded_bits"] for page in pages)
        comp_cycles = sum(page["comp_cycles"] for page in pages)
        decomp_cycles = sum(page["decomp_cycles"] for page in pages)
        summary = {
            "input_bytes": input_bytes,
            "padded_bytes": len(pages) * PAGE_WIDTH_BYTES,
            "pages": len(pages),
            "raw_bits": raw_bits,
            "encoded_bits": encoded_bits,
            "ratio": (raw_bits / encoded_bits) if encoded_bits else 0.0,
            "comp_cycles": comp_cycles,
            "decomp_cycles": decomp_cycles,
            "total_cycles": comp_cycles + decomp_cycles,
            "comp_bpc": (input_bytes / comp_cycles) if comp_cycles else 0.0,
            "decomp_bpc": (input_bytes / decomp_cycles) if decomp_cycles else 0.0,
        }
    return pages, summary


def format_hardware_page_line(page: dict) -> str:
    page_total = page.get("page_total")
    if page_total is not None:
        prefix = f"[verify page {page['page_idx']}/{page_total}]"
    else:
        prefix = f"[verify page {page['page_idx']}]"
    return (
        f"{prefix} "
        f"valid_bytes={page['valid_bytes']} "
        f"comp_syms={page['comp_syms']} "
        f"total_dict_entries={page['total_dict_entries']} "
        f"stored_dict_count={page['stored_dict_count']} "
        f"dict_bits={page['dict_bits']} "
        f"raw_bits={page['raw_bits']} "
        f"encoded_bits={page['encoded_bits']} "
        f"ratio={page['ratio']:.4f} "
        f"comp_cycles={page['comp_cycles']} "
        f"decomp_cycles={page['decomp_cycles']} "
        f"comp_Bpc={page['comp_bpc']:.4f} "
        f"decomp_Bpc={page['decomp_bpc']:.4f}"
    )


def format_hardware_summary_line(summary: dict) -> str:
    return (
        "[verify file summary] "
        f"input_bytes={summary['input_bytes']} "
        f"padded_bytes={summary['padded_bytes']} "
        f"pages={summary['pages']} "
        f"raw_bits={summary['raw_bits']} "
        f"encoded_bits={summary['encoded_bits']} "
        f"ratio={summary['ratio']:.4f} "
        f"comp_cycles={summary['comp_cycles']} "
        f"decomp_cycles={summary['decomp_cycles']} "
        f"total_cycles={summary['total_cycles']} "
        f"comp_Bpc={summary['comp_bpc']:.4f} "
        f"decomp_Bpc={summary['decomp_bpc']:.4f}"
    )


def build_merged_hardware_log(input_file: Path, pages: list[dict], summary: dict, shard_count: int) -> str:
    lines = [
        "[runtime file harness] "
        f"input_file={input_file.resolve()} "
        f"max_pages={summary['pages']} "
        f"expect_pages={summary['pages']} "
        f"shard_count={shard_count}",
    ]
    lines.extend(format_hardware_page_line(page) for page in pages)
    lines.append(format_hardware_summary_line(summary))
    lines.append("tb_M4ExperimentalRuntimeFileCompressorTop passed")
    return "\n".join(lines) + "\n"


def shard_log_path(log_dir: Path, input_file: Path, total_pages: int, shard: PageShard, root: Path) -> Path:
    merged_log = runtime_log_path(log_dir, input_file, "large_verify", total_pages, root)
    suffix = f"_shard{shard.shard_idx + 1:02d}of{shard.shard_count:02d}"
    return ensure_parent(merged_log.with_name(f"{merged_log.stem}{suffix}{merged_log.suffix}"))


def _remap_shard_page(page: dict, shard: PageShard, total_pages: int) -> dict:
    remapped = dict(page)
    remapped["page_idx"] = shard.start_page + page["page_idx"]
    remapped["page_total"] = total_pages
    return remapped


def _run_hardware_roundtrip_shard(
    *,
    input_file: Path,
    root: Path,
    run_bin: Path,
    log_dir: Path,
    shard: PageShard,
    total_pages: int,
) -> dict:
    log_path = shard_log_path(log_dir, input_file, total_pages, shard, root)
    log_text = run_runtime_harness(
        root,
        run_bin=run_bin,
        input_file=input_file,
        pages=shard.page_count,
        log_path=log_path,
        stream_output=False,
        start_page_idx=shard.start_page,
    )
    local_pages, _local_summary = parse_hardware_log(log_text)
    merged_pages = [_remap_shard_page(page, shard, total_pages) for page in local_pages]
    return {
        "shard_idx": shard.shard_idx,
        "page_start": shard.start_page,
        "page_end": shard.end_page,
        "page_count": shard.page_count,
        "hardware_log": str(log_path),
        "hardware_pages": merged_pages,
        "hardware_summary": derive_summary_from_pages(merged_pages),
    }


def run_hardware_roundtrip(
    *,
    input_file: Path,
    pages_requested: int,
    root: Path,
    verilator_bin: str,
    build_dir: Path,
    build_jobs: int,
    log_dir: Path,
    raw_pages: list[bytes] | None = None,
    run_bin: Path | None = None,
    page_shards: int = 1,
    verbose: bool = True,
) -> dict:
    if raw_pages is None:
        _page_width, raw_pages = load_runtime_pages(input_file, pages_requested, root)

    if run_bin is None and verbose:
        print("Building large-tier runtime round-trip harness...")
    if run_bin is None:
        run_bin = build_runtime_harness(
            root,
            verilator_bin=verilator_bin,
            build_dir=build_dir,
            build_jobs=build_jobs,
        )

    actual_shards = min(max(page_shards, 1), max(len(raw_pages), 1))
    log_path = runtime_log_path(log_dir, input_file, "large_verify", len(raw_pages), root)

    if actual_shards == 1 or len(raw_pages) <= 1:
        if verbose:
            print("Running hardware round-trip harness...")
        log_text = run_runtime_harness(
            root,
            run_bin=run_bin,
            input_file=input_file,
            pages=len(raw_pages),
            log_path=log_path,
            stream_output=verbose,
        )
        hw_pages, hw_summary = parse_hardware_log(log_text)
        shards = None
    else:
        page_shard_inputs = shard_page_inputs(raw_pages, actual_shards)
        if verbose:
            print(f"Running hardware round-trip harness across {len(page_shard_inputs)} page shard(s)...")

        shard_results: list[dict] = []
        with ThreadPoolExecutor(max_workers=len(page_shard_inputs)) as executor:
            futures = {
                executor.submit(
                    _run_hardware_roundtrip_shard,
                    input_file=input_file,
                    root=root,
                    run_bin=run_bin,
                    log_dir=log_dir,
                    shard=shard,
                    total_pages=len(raw_pages),
                ): shard
                for shard in page_shard_inputs
            }
            completed = 0
            for future in as_completed(futures):
                shard_result = future.result()
                completed += 1
                if verbose:
                    print(
                        f"  [hardware shard {completed}/{len(page_shard_inputs)} complete] "
                        f"pages={shard_result['page_start'] + 1}-{shard_result['page_end']}"
                    )
                shard_results.append(shard_result)

        shard_results.sort(key=lambda item: item["page_start"])
        hw_pages = [page for shard_result in shard_results for page in shard_result["hardware_pages"]]
        hw_summary = derive_summary_from_pages(hw_pages)
        ensure_parent(log_path).write_text(
            build_merged_hardware_log(input_file, hw_pages, hw_summary, len(page_shard_inputs)),
            encoding="utf-8",
        )
        shards = [
            {
                "shard_idx": shard_result["shard_idx"],
                "page_start": shard_result["page_start"] + 1,
                "page_end": shard_result["page_end"],
                "page_count": shard_result["page_count"],
                "hardware_log": shard_result["hardware_log"],
            }
            for shard_result in shard_results
        ]

    return {
        "status": "PASS",
        "input_file": str(input_file.resolve()),
        "pages_requested": pages_requested,
        "pages_observed": hw_summary["pages"],
        "build_dir": str(resolve_repo_path(root, build_dir)),
        "hardware_log": str(log_path),
        "hardware_pages": hw_pages,
        "hardware_summary": hw_summary,
        "shard_count": actual_shards,
        **({"shards": shards} if shards is not None else {}),
        "raw_pages": raw_pages,
    }


def build_runtime_harness(
    root: Path,
    *,
    verilator_bin: str,
    build_dir: Path,
    build_jobs: int,
    verilate_jobs: int = 0,
) -> Path:
    build_dir_path = resolve_repo_path(root, build_dir)
    build_dir_path.mkdir(parents=True, exist_ok=True)
    run_bin = build_dir_path / "Vtb_M4ExperimentalRuntimeFileCompressorTop"
    verilator_cmd = [
        verilator_bin,
        "-sv",
        "--binary",
        "--build-jobs",
        str(max(build_jobs, 0)),
        "--verilate-jobs",
        str(max(verilate_jobs, 0)),
        "--timing",
        "-Wno-WIDTH",
        "-Wno-LATCH",
        "-Wno-UNOPTFLAT",
        "-Wno-IMPLICITSTATIC",
        "-DRST_TIER_LARGE",
        "-DRST_EXPERIMENTAL_FREE_PREFIX",
        "--top-module",
        "tb_M4ExperimentalRuntimeFileCompressorTop",
        "-Mdir",
        str(build_dir_path),
        "-f",
        "experimental/frozen_large/m4_experimental_runtime_filelist.f",
        "experimental/frozen_large/m4_runtime_file_experimental_tb.sv",
    ]
    if verilator_supports_flag(verilator_bin, "--quiet-build"):
        verilator_cmd.insert(3, "--quiet-build")

    if run_bin.exists():
        return run_bin

    print(
        "  building large-tier runtime harness with Verilator "
        f"(build dir: {build_dir_path})...",
        flush=True,
    )

    try:
        run_cmd(verilator_cmd, root)
    except subprocess.CalledProcessError as exc:
        if not is_rebuild_worthy_verilator_failure(exc):
            raise
        shutil.rmtree(build_dir_path, ignore_errors=True)
        build_dir_path.mkdir(parents=True, exist_ok=True)
        print("  retrying large-tier runtime harness build after clearing stale Verilator cache...", flush=True)
        run_cmd(verilator_cmd, root)
    print("  built large-tier runtime harness", flush=True)
    return run_bin


def run_runtime_harness(
    root: Path,
    *,
    run_bin: Path,
    input_file: Path,
    pages: int,
    log_path: Path,
    stream_output: bool = False,
    start_page_idx: int = 0,
) -> str:
    run_cmdline = [
        str(run_bin.resolve()),
        f"+INPUT_FILE={input_file.resolve()}",
    ]
    if pages >= 0:
        run_cmdline.append(f"+MAX_PAGES={pages}")
        if pages > 0:
            run_cmdline.append(f"+EXPECT_PAGES={pages}")
    if start_page_idx > 0:
        run_cmdline.append(f"+START_PAGE_IDX={start_page_idx}")

    if stream_output:
        run = run_cmd_streaming(run_cmdline, root, log_path=log_path)
    else:
        run = run_cmd(run_cmdline, root)
        ensure_parent(log_path).write_text(run.stdout, encoding="utf-8")
    return run.stdout


def model_page_details(raw_pages: list[bytes], *, root: Path) -> tuple[list[dict], dict]:
    helpful_dir = root / "helpful_files"
    sys.path.insert(0, str(helpful_dir))

    import rst_compressor_experimental as experimental
    import rst_decompressor_golden as golden

    model_pages: list[dict] = []
    for page_idx, raw_page in enumerate(raw_pages, start=1):
        padded_page = bytes(golden.pad_runtime_page(raw_page, page_idx - 1, golden.DEFAULT_LARGE_TIER))
        _result, _cycles, details = experimental.cram_encode(
            padded_page,
            MODEL_CONFIG,
            return_details=True,
        )
        model_pages.append(
            {
                "page_idx": page_idx,
                "valid_bytes": len(raw_page),
                "comp_syms": details.compressed_symbols,
                "total_dict_entries": details.dict_total_entries,
                "stored_dict_count": details.dict_count,
                "dict_bits": details.dict_bits,
                "raw_bits": len(raw_page) * 8,
                "encoded_bits": details.encoded_bits,
                "ratio": (len(raw_page) * 8) / details.encoded_bits if details.encoded_bits else 0.0,
                "details": {
                    "dict_sequences": details.dict_sequences,
                    "compressed_chunk_bit_lengths": [len(bits) for bits in details.compressed_chunk_bitstrings],
                },
            }
        )

    total_encoded_bits = sum(page["encoded_bits"] for page in model_pages)
    total_raw_bits = sum(page["raw_bits"] for page in model_pages)
    total_input_bytes = sum(page["valid_bytes"] for page in model_pages)
    summary = {
        "input_bytes": total_input_bytes,
        "padded_bytes": len(model_pages) * 4096,
        "pages": len(model_pages),
        "raw_bits": total_raw_bits,
        "encoded_bits": total_encoded_bits,
        "ratio": (total_raw_bits / total_encoded_bits) if total_encoded_bits else 0.0,
    }
    return model_pages, summary


def compare_results(hw_pages: list[dict], hw_summary: dict, model_pages: list[dict], model_summary: dict) -> list[str]:
    mismatches: list[str] = []

    if len(hw_pages) != len(model_pages):
        mismatches.append(f"page count mismatch: hardware={len(hw_pages)} model={len(model_pages)}")
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
        for field in (
            "valid_bytes",
            "comp_syms",
            "total_dict_entries",
            "stored_dict_count",
            "dict_bits",
            "raw_bits",
            "encoded_bits",
        ):
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


def run_experimental_regression(
    *,
    input_file: Path,
    pages_requested: int,
    root: Path,
    verilator_bin: str,
    build_dir: Path,
    build_jobs: int,
    log_dir: Path,
    strict_model_match: bool = True,
    verbose: bool = True,
) -> dict:
    roundtrip_result = run_hardware_roundtrip(
        input_file=input_file,
        pages_requested=pages_requested,
        root=root,
        verilator_bin=verilator_bin,
        build_dir=build_dir,
        build_jobs=build_jobs,
        log_dir=log_dir,
        verbose=verbose,
    )
    raw_pages = roundtrip_result.pop("raw_pages")
    hw_pages = roundtrip_result["hardware_pages"]
    hw_summary = roundtrip_result["hardware_summary"]

    if verbose:
        print("Running richer Python cross-check...")
    model_pages, model_summary = model_page_details(raw_pages, root=root)
    mismatches = compare_results(hw_pages, hw_summary, model_pages, model_summary)
    model_match = not mismatches

    result = dict(roundtrip_result)
    result.update(
        {
            "status": "PASS" if (model_match or not strict_model_match) else "FAIL",
            "model_summary": model_summary,
            "python_model_match": model_match,
            "strict_model_match": strict_model_match,
            "mismatches": mismatches,
        }
    )
    return result


def print_command_failure(exc: subprocess.CalledProcessError) -> None:
    print("\nFAIL large-tier richer regression", file=sys.stderr)
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
        result = run_experimental_regression(
            input_file=input_file,
            pages_requested=pages_requested,
            root=root,
            verilator_bin=args.verilator_bin,
            build_dir=args.build_dir,
            build_jobs=args.build_jobs,
            log_dir=args.log_dir,
            verbose=True,
        )
    except subprocess.CalledProcessError as exc:
        print_command_failure(exc)
        return 1

    if args.write_json is not None:
        ensure_parent(args.write_json).write_text(json.dumps(result, indent=2), encoding="utf-8")

    if result["status"] == "PASS":
        print("\nPASS large-tier richer regression")
        print(f"  input: {input_file.resolve()}")
        print(f"  pages: {result['hardware_summary']['pages']}")
        print(f"  hardware ratio: {result['hardware_summary']['ratio']:.4f}x")
        print(f"  model ratio: {result['model_summary']['ratio']:.4f}x")
        print(f"  encoded bits: {result['hardware_summary']['encoded_bits']}")
        print(
            "  compressor: "
            f"{result['hardware_summary']['comp_cycles']} cycles "
            f"({result['hardware_summary']['comp_bpc']:.4f} B/cycle)"
        )
        print(
            "  decompressor: "
            f"{result['hardware_summary']['decomp_cycles']} cycles "
            f"({result['hardware_summary']['decomp_bpc']:.4f} B/cycle)"
        )
        print(f"  hardware log: {result['hardware_log']}")
        return 0

    print("\nFAIL large-tier richer regression")
    print(f"  input: {input_file.resolve()}")
    print(f"  pages: {result['hardware_summary']['pages']}")
    print(f"  hardware ratio: {result['hardware_summary']['ratio']:.4f}x")
    print(f"  model ratio: {result['model_summary']['ratio']:.4f}x")
    print(
        "  compressor: "
        f"{result['hardware_summary']['comp_cycles']} cycles "
        f"({result['hardware_summary']['comp_bpc']:.4f} B/cycle)"
    )
    print(
        "  decompressor: "
        f"{result['hardware_summary']['decomp_cycles']} cycles "
        f"({result['hardware_summary']['decomp_bpc']:.4f} B/cycle)"
    )
    for mismatch in result["mismatches"][:20]:
        print(f"  mismatch: {mismatch}")
    if len(result["mismatches"]) > 20:
        print(f"  mismatch: ... and {len(result['mismatches']) - 20} more")
    print(f"  hardware log: {result['hardware_log']}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
