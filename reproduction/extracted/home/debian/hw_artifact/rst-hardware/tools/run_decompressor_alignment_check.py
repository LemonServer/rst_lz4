#!/usr/bin/env python3
"""Validate the milestone-1 aligned Python compressor/decompressor paths.

The main checks round-trip runtime-padded pages through:
1. the current SV-aligned golden compressor/decompressor path
2. the richer experimental compressor/decompressor path

It also keeps a compact literal/reuse smoke check for the experimental
`cram_cpp`-style format parser.
"""

from __future__ import annotations

import argparse
import json
import multiprocessing
import sys
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor, as_completed
from pathlib import Path

from m4_hardware_sim_common import default_input_file, repo_root
from run_m4_golden_regression import MODEL_CONFIG


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the milestone-1 decompressor alignment checks."
    )
    parser.add_argument(
        "input_file",
        nargs="?",
        type=Path,
        help="Input file to page (default: data/dacapo_avrora_rand1k)",
    )
    parser.add_argument(
        "--pages",
        type=int,
        default=4,
        help="Number of pages to validate (0 = all pages from the file)",
    )
    parser.add_argument(
        "--write-json",
        type=Path,
        help="Optional JSON summary output path",
    )
    parser.add_argument(
        "--jobs",
        type=int,
        default=0,
        help="Worker processes for page validation (0 = auto)",
    )
    return parser.parse_args()


def import_helpers(root: Path):
    sys.path.insert(0, str(root / "helpful_files"))
    sys.path.insert(0, str(root / "tools"))

    import rst_compressor_experimental as experimental_compressor
    import rst_compressor_golden as golden_compressor
    import rst_decompressor_experimental as experimental
    import rst_decompressor_golden as golden
    from gen_m4_file_pages import page_bytes

    return golden_compressor, experimental_compressor, experimental, golden, page_bytes


def page_mismatch(got: list[int], expected: list[int]) -> tuple[int, int, int] | None:
    for idx, (got_sym, want_sym) in enumerate(zip(got, expected)):
        if got_sym != want_sym:
            return idx, got_sym, want_sym
    if len(got) != len(expected):
        return min(len(got), len(expected)), -1, -1
    return None


def _mismatch_info(mismatch: tuple[int, int, int] | None) -> dict | None:
    if mismatch is None:
        return None
    return {
        "lane": mismatch[0],
        "got": mismatch[1],
        "expected": mismatch[2],
    }


def _page_alignment_worker(job: tuple[str, int, bytes]) -> dict:
    root_str, page_idx, raw_page = job
    root = Path(root_str)
    golden_compressor, experimental_compressor, experimental, golden, _page_bytes = import_helpers(root)

    padded_page = golden.pad_runtime_page(raw_page, page_idx, golden.DEFAULT_LARGE_TIER)
    _golden_encoded, _golden_cycles, golden_details = golden_compressor.cram_encode(
        bytes(padded_page),
        MODEL_CONFIG,
        return_details=True,
    )

    golden_encoded_page = golden.golden_encoded_page_from_model_details(golden_details)
    golden_decoded = golden.decompress_page(
        golden_encoded_page.compressed_page,
        golden_encoded_page.dict_packed,
    )
    golden_mismatch = page_mismatch(golden_decoded.page_symbols, padded_page)
    golden_status = "ok" if golden_mismatch is None else "mismatch"

    _experimental_encoded, _experimental_cycles, experimental_details = (
        experimental_compressor.cram_encode(
            bytes(padded_page),
            MODEL_CONFIG,
            return_details=True,
        )
    )
    experimental_decoded = experimental.decompress_experimental_page(
        experimental_details.encoded_page,
    )
    experimental_mismatch = page_mismatch(experimental_decoded.page_symbols, padded_page)
    experimental_status = "ok" if experimental_mismatch is None else "mismatch"

    return {
        "page_idx": page_idx,
        "raw_bytes": len(raw_page),
        "padded_bytes": len(padded_page),
        "golden": {
            "page_idx": page_idx,
            "raw_bytes": len(raw_page),
            "padded_bytes": len(padded_page),
            "dict_count": golden_details.dict_count,
            "dict_bits": golden_details.dict_bits,
            "dict_packed_bits": golden_encoded_page.dict_packed_bits,
            "compressed_symbols": golden_details.compressed_symbols,
            "chunk_symbol_counts": [len(chunk) for chunk in golden_encoded_page.compressed_chunks],
            "status": golden_status,
            "mismatch": _mismatch_info(golden_mismatch),
        },
        "experimental": {
            "page_idx": page_idx,
            "raw_bytes": len(raw_page),
            "padded_bytes": len(padded_page),
            "added_dict_entries": experimental_details.dict_count,
            "total_dict_entries": experimental_details.dict_total_entries,
            "dict_bits": experimental_details.dict_bits,
            "compressed_symbols": experimental_details.compressed_symbols,
            "chunk_bit_lengths": [
                len(chunk_bits)
                for chunk_bits in experimental_details.compressed_chunk_bitstrings
            ],
            "status": experimental_status,
            "mismatch": _mismatch_info(experimental_mismatch),
        },
    }


def run_experimental_smoke(experimental) -> dict:
    experimental.load_cram_cpp_tables()

    page = experimental.ExperimentalEncodedPage(
        dict_bits="000000",
        compressed_chunks=[
            experimental.chunk_symbol_bits(ord("A"))
            + experimental.chunk_symbol_bits(experimental.code_sym(63))
            + experimental.chunk_symbol_bits(ord("B"))
        ],
    )
    result = experimental.decompress_experimental_page(page)
    expected = [ord("A"), ord("A"), ord("B")]
    if result.page_symbols != expected:
        raise RuntimeError(
            f"experimental smoke mismatch: got={result.page_symbols!r} expected={expected!r}"
        )

    return {
        "passed": True,
        "decoded_symbols": result.page_symbols,
    }


def main() -> int:
    args = parse_args()
    root = repo_root()
    input_file = args.input_file.resolve() if args.input_file is not None else default_input_file(root)
    golden_compressor, experimental_compressor, experimental, golden, page_bytes = import_helpers(root)

    raw_pages = page_bytes(input_file.read_bytes())
    if args.pages > 0:
        raw_pages = raw_pages[:args.pages]
    if not raw_pages:
        raise RuntimeError("no pages produced from the input file")

    worker_count = min(
        len(raw_pages),
        args.jobs if args.jobs > 0 else (multiprocessing.cpu_count() or 1),
    )
    print(f"Running alignment checks with {worker_count} worker(s) across {len(raw_pages)} page(s)...")

    worker_results = []
    if worker_count <= 1:
        for page_idx, raw_page in enumerate(raw_pages):
            result = _page_alignment_worker((str(root), page_idx, raw_page))
            worker_results.append(result)
            print(
                f"  [page {page_idx + 1}/{len(raw_pages)}] "
                f"golden={result['golden']['status']} "
                f"experimental={result['experimental']['status']}"
            )
    else:
        completed = 0
        try:
            executor_cm = ProcessPoolExecutor(max_workers=worker_count)
            executor_label = "process"
        except (OSError, PermissionError) as exc:
            print(
                "Process workers unavailable in this environment; "
                f"falling back to thread workers ({exc})."
            )
            executor_cm = ThreadPoolExecutor(max_workers=worker_count)
            executor_label = "thread"

        with executor_cm as executor:
            print(f"Using {executor_label} workers for page validation.")
            futures = {
                executor.submit(_page_alignment_worker, (str(root), page_idx, raw_page)): page_idx
                for page_idx, raw_page in enumerate(raw_pages)
            }
            for future in as_completed(futures):
                result = future.result()
                worker_results.append(result)
                completed += 1
                if (
                    completed <= 4
                    or completed == len(raw_pages)
                    or completed % 32 == 0
                    or result["golden"]["status"] != "ok"
                    or result["experimental"]["status"] != "ok"
                ):
                    print(
                        f"  [page {completed}/{len(raw_pages)} complete] "
                        f"src_page={result['page_idx'] + 1} "
                        f"golden={result['golden']['status']} "
                        f"experimental={result['experimental']['status']}"
                    )

    worker_results.sort(key=lambda item: item["page_idx"])
    golden_results = [item["golden"] for item in worker_results]
    experimental_results = [item["experimental"] for item in worker_results]

    experimental_smoke = run_experimental_smoke(experimental)
    golden_failures = [result for result in golden_results if result["status"] != "ok"]
    experimental_failures = [result for result in experimental_results if result["status"] != "ok"]

    summary = {
        "input_file": str(input_file),
        "pages_checked": len(raw_pages),
        "golden_failures": len(golden_failures),
        "experimental_failures": len(experimental_failures),
        "golden_pages": golden_results,
        "experimental_pages": experimental_results,
        "experimental_smoke": experimental_smoke,
    }

    if args.write_json is not None:
        args.write_json.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    if golden_failures or experimental_failures:
        print(
            "\nFAIL alignment checks: "
            f"golden_failures={len(golden_failures)} "
            f"experimental_failures={len(experimental_failures)}"
        )
        return 1

    print(
        f"\nPASS golden alignment: {len(golden_results)}/{len(golden_results)} page(s) matched "
        "the SV-aligned golden path"
    )
    print(
        "PASS experimental alignment: "
        f"{len(experimental_results)}/{len(experimental_results)} page(s) round-tripped "
        "through the experimental format"
    )
    print(
        "PASS experimental smoke: decoded literal/reuse chunk with the `cram_cpp` static tables"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
