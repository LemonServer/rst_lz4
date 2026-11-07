#!/usr/bin/env python3
"""Analyze chunk-vs-physical-block decompressor latency on the experimental path."""

from __future__ import annotations

import argparse
import json
import random
import statistics as st
import sys
from pathlib import Path

from m4_hardware_sim_common import default_input_file, load_paged_input, repo_root
from run_m4_experimental_regression import MODEL_CONFIG

HELPFUL_DIR = repo_root() / "helpful_files"
if str(HELPFUL_DIR) not in sys.path:
    sys.path.insert(0, str(HELPFUL_DIR))

from rst_compressor_experimental import cram_encode  # noqa: E402
from rst_experimental_format import (  # noqa: E402
    apply_reuse,
    chunk_symbol_bits,
    code_sym,
    decode_prefixed_stream,
    load_cram_cpp_tables,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compare full logical-chunk decompressor stack latency against "
            "sampled 64B compressed-block latency on the experimental path."
        )
    )
    parser.add_argument(
        "input_file",
        nargs="?",
        type=Path,
        help="Input file to page and compress (default: data/dacapo_avrora_rand1k)",
    )
    parser.add_argument(
        "--pages",
        type=int,
        default=16,
        help="Maximum number of pages to analyze (0 = until EOF)",
    )
    parser.add_argument(
        "--samples-per-page",
        type=int,
        default=10,
        help="Uniform-with-replacement physical-block samples per page",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=12345,
        help="RNG seed for block sampling",
    )
    parser.add_argument(
        "--physical-block-bytes",
        type=int,
        default=64,
        help="Compressed physical block size in bytes",
    )
    parser.add_argument(
        "--physical-block-overhead-bits",
        type=int,
        default=6,
        help="Per-physical-block metadata overhead in bits",
    )
    parser.add_argument(
        "--hardware-json",
        type=Path,
        help=(
            "Optional JSON from tools/run_m4_experimental_regression.py --write-json "
            "to estimate fixed non-stack hardware overhead"
        ),
    )
    parser.add_argument(
        "--write-json",
        type=Path,
        help="Optional output path for the full analysis JSON",
    )
    return parser.parse_args()


def resolve_input_file(args: argparse.Namespace, root: Path) -> Path:
    if args.input_file is not None:
        return args.input_file.resolve()
    default_input = default_input_file(root)
    if default_input.exists():
        return default_input
    raise RuntimeError("input_file is required because the default dataset is missing")


def simulate_stack(expansions: dict[int, list[int]], initial_tokens: list[int]) -> int:
    stack = list(reversed(initial_tokens))
    cycles = 0

    while stack:
        def is_code(token: int) -> bool:
            return token in expansions

        if len(stack) >= 2 and is_code(stack[-1]) and not is_code(stack[-2]):
            ops_this_cycle = 1
        else:
            ops_this_cycle = 2

        for _ in range(ops_this_cycle):
            if not stack:
                break

            token = stack.pop()
            if is_code(token):
                for child in reversed(expansions[token]):
                    stack.append(child)

        cycles += 1

    return cycles


def even_split(tokens: list[int], count: int = 8) -> list[list[int]]:
    base_len = len(tokens) // count
    remainder = len(tokens) % count
    segments = []
    read_idx = 0

    for seg in range(count):
        seg_len = base_len + (1 if seg < remainder else 0)
        segments.append(tokens[read_idx:read_idx + seg_len])
        read_idx += seg_len

    return segments


def simulate_segment(expansions: dict[int, list[int]], tokens: list[int]) -> int:
    if not tokens:
        return 0
    return max(simulate_stack(expansions, segment) for segment in even_split(tokens))


def load_hardware_pages(hardware_json: Path) -> list[dict]:
    parsed = json.loads(hardware_json.read_text(encoding="utf-8"))
    pages = parsed.get("hardware_pages")
    if not isinstance(pages, list):
        raise RuntimeError(f"hardware JSON missing hardware_pages: {hardware_json}")
    return pages


def main() -> int:
    args = parse_args()
    root = repo_root()
    if args.pages < 0:
        raise RuntimeError("--pages must be >= 0")

    input_file = resolve_input_file(args, root)
    loaded = load_paged_input(root, input_file, args.pages)
    rng = random.Random(args.seed)
    chunk_decoder = load_cram_cpp_tables().chunk_decoder
    physical_capacity_bits = args.physical_block_bytes * 8 - args.physical_block_overhead_bits
    hardware_pages = load_hardware_pages(args.hardware_json) if args.hardware_json is not None else None

    page_results: list[dict] = []
    all_logical_chunk_cycles: list[int] = []
    all_physical_block_cycles: list[int] = []
    all_sampled_block_cycles: list[int] = []
    per_page_overhead_cycles: list[int] = []

    for page_idx, raw_page in enumerate(loaded.pages, start=1):
        _encoded, _cycles, details = cram_encode(bytes(raw_page), MODEL_CONFIG, return_details=True)
        expansions = {code_sym(idx): seq for idx, seq in enumerate(details.dict_sequences)}

        logical_chunk_cycles: list[int] = []
        logical_chunk_token_counts: list[int] = []
        page_stream: list[tuple[int, int]] = []

        for chunk_bits in details.compressed_chunk_bitstrings:
            unresolved_tokens = decode_prefixed_stream(chunk_bits, chunk_decoder)
            resolved_tokens = apply_reuse(unresolved_tokens)

            logical_chunk_cycles.append(simulate_segment(expansions, resolved_tokens))
            logical_chunk_token_counts.append(len(resolved_tokens))

            # Pack blocks using the true encoded token bit lengths, but model
            # the token stream after the chunk decoder has already resolved any
            # local reuse codes. That matches a Python-preprocessed feed into
            # ExperimentalDecompressorTop rather than a standalone bitstream
            # decode from the middle of the page.
            for unresolved, resolved in zip(unresolved_tokens, resolved_tokens):
                page_stream.append((resolved, len(chunk_symbol_bits(unresolved))))

        physical_blocks: list[list[int]] = []
        current_block: list[int] = []
        current_bits = 0
        for resolved_token, token_bits in page_stream:
            if current_block and (current_bits + token_bits > physical_capacity_bits):
                physical_blocks.append(current_block)
                current_block = []
                current_bits = 0
            current_block.append(resolved_token)
            current_bits += token_bits
        if current_block:
            physical_blocks.append(current_block)

        physical_block_cycles = [simulate_segment(expansions, block) for block in physical_blocks]
        sampled_block_cycles = [
            physical_block_cycles[rng.randrange(len(physical_block_cycles))]
            for _ in range(args.samples_per_page)
        ] if physical_block_cycles else []

        logical_stack_sum = sum(logical_chunk_cycles)
        page_result = {
            "page_idx": page_idx,
            "logical_chunk_cycles": logical_chunk_cycles,
            "logical_chunk_token_counts": logical_chunk_token_counts,
            "logical_chunk_cycle_avg": (
                sum(logical_chunk_cycles) / len(logical_chunk_cycles) if logical_chunk_cycles else 0.0
            ),
            "physical_block_count": len(physical_blocks),
            "physical_block_token_counts": [len(block) for block in physical_blocks],
            "physical_block_cycles": physical_block_cycles,
            "physical_block_cycle_avg": (
                sum(physical_block_cycles) / len(physical_block_cycles) if physical_block_cycles else 0.0
            ),
            "sampled_block_cycles": sampled_block_cycles,
            "sampled_block_cycle_avg": (
                sum(sampled_block_cycles) / len(sampled_block_cycles) if sampled_block_cycles else 0.0
            ),
        }

        if hardware_pages is not None and page_idx <= len(hardware_pages):
            hardware_cycles = int(hardware_pages[page_idx - 1]["decomp_cycles"])
            page_result["hardware_page_cycles"] = hardware_cycles
            page_result["non_stack_overhead_cycles"] = hardware_cycles - logical_stack_sum
            per_page_overhead_cycles.append(page_result["non_stack_overhead_cycles"])

        page_results.append(page_result)
        all_logical_chunk_cycles.extend(logical_chunk_cycles)
        all_physical_block_cycles.extend(physical_block_cycles)
        all_sampled_block_cycles.extend(sampled_block_cycles)

    summary = {
        "input_file": str(input_file),
        "pages": len(page_results),
        "physical_capacity_bits": physical_capacity_bits,
        "logical_chunk_cycle_avg": (
            sum(all_logical_chunk_cycles) / len(all_logical_chunk_cycles) if all_logical_chunk_cycles else 0.0
        ),
        "logical_chunk_cycle_median": st.median(all_logical_chunk_cycles) if all_logical_chunk_cycles else 0.0,
        "physical_block_cycle_avg": (
            sum(all_physical_block_cycles) / len(all_physical_block_cycles) if all_physical_block_cycles else 0.0
        ),
        "physical_block_cycle_median": (
            st.median(all_physical_block_cycles) if all_physical_block_cycles else 0.0
        ),
        "sampled_block_cycle_avg": (
            sum(all_sampled_block_cycles) / len(all_sampled_block_cycles) if all_sampled_block_cycles else 0.0
        ),
        "sampled_block_cycle_median": (
            st.median(all_sampled_block_cycles) if all_sampled_block_cycles else 0.0
        ),
        "logical_chunk_token_avg": (
            sum(sum(page["logical_chunk_token_counts"]) for page in page_results) /
            sum(len(page["logical_chunk_token_counts"]) for page in page_results)
            if page_results else 0.0
        ),
        "physical_block_token_avg": (
            sum(sum(page["physical_block_token_counts"]) for page in page_results) /
            sum(len(page["physical_block_token_counts"]) for page in page_results)
            if page_results and any(page["physical_block_token_counts"] for page in page_results) else 0.0
        ),
        "physical_blocks_per_page_avg": (
            sum(page["physical_block_count"] for page in page_results) / len(page_results)
            if page_results else 0.0
        ),
        "sampled_blocks": len(all_sampled_block_cycles),
    }

    if per_page_overhead_cycles:
        total_chunks = sum(len(page["logical_chunk_cycles"]) for page in page_results)
        summary["non_stack_overhead_per_page_avg"] = sum(per_page_overhead_cycles) / len(per_page_overhead_cycles)
        summary["non_stack_overhead_per_chunk_avg"] = sum(per_page_overhead_cycles) / total_chunks
        summary["sampled_block_hw_cycle_estimate_avg"] = (
            summary["sampled_block_cycle_avg"] + summary["non_stack_overhead_per_chunk_avg"]
        )

    result = {
        "summary": summary,
        "pages": page_results,
    }

    if args.write_json is not None:
        args.write_json.write_text(json.dumps(result, indent=2), encoding="utf-8")

    print("Experimental Decompressor Latency Analysis")
    print(f"  input={input_file}")
    print(f"  pages={summary['pages']} physical_capacity_bits={physical_capacity_bits}")
    print(
        "  logical_chunk_stack_cycles="
        f"{summary['logical_chunk_cycle_avg']:.2f} avg, {summary['logical_chunk_cycle_median']:.2f} median"
    )
    print(
        "  physical_block_stack_cycles="
        f"{summary['physical_block_cycle_avg']:.2f} avg, {summary['physical_block_cycle_median']:.2f} median"
    )
    print(
        "  sampled_block_stack_cycles="
        f"{summary['sampled_block_cycle_avg']:.2f} avg, {summary['sampled_block_cycle_median']:.2f} median "
        f"({summary['sampled_blocks']} samples)"
    )
    print(
        "  token_counts="
        f"{summary['logical_chunk_token_avg']:.2f} logical avg, "
        f"{summary['physical_block_token_avg']:.2f} physical avg"
    )
    print(f"  physical_blocks_per_page={summary['physical_blocks_per_page_avg']:.2f}")
    if "non_stack_overhead_per_chunk_avg" in summary:
        print(
            "  estimated_non_stack_overhead="
            f"{summary['non_stack_overhead_per_chunk_avg']:.2f} cycles/chunk"
        )
        print(
            "  sampled_block_hw_cycle_estimate="
            f"{summary['sampled_block_hw_cycle_estimate_avg']:.2f} cycles"
        )
    if args.write_json is not None:
        print(f"  json={args.write_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
