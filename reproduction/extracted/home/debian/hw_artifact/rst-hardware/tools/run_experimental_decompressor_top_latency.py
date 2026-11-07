#!/usr/bin/env python3
"""Measure direct ExperimentalDecompressorTop chunk latency."""

from __future__ import annotations

import argparse
import json
import random
import statistics as st
import subprocess
import sys
from pathlib import Path

from m4_hardware_sim_common import (
    DEFAULT_VERILATOR_BIN,
    default_input_file,
    load_paged_input,
    repo_root,
    resolve_repo_path,
    verilator_supports_flag,
)
from run_m4_experimental_regression import MODEL_CONFIG


TIER_MACROS = {
    "tiny": "RST_TIER_TINY",
    "small": "RST_TIER_SMALL",
    "medium": "RST_TIER_MEDIUM",
    "large": "RST_TIER_LARGE",
}

CHUNK_WIDTH = 256
PAGE_CHUNKS = 16
MAX_DICT_ENTRIES = 63
MAX_SEQ_LEN = 5
DECOMP_LIFOS = 16
SYMBOL_BITS = 9
LEN_BITS = 3
LOGICAL_BLOCKS_PER_CHUNK = CHUNK_WIDTH // 64


def import_helpers(root: Path):
    sys.path.insert(0, str(root / "helpful_files"))
    sys.path.insert(0, str(root / "tools"))

    import rst_compressor_experimental as experimental_compressor
    import rst_decompressor_experimental as experimental_decompressor
    import rst_decompressor_golden as golden
    import rst_experimental_format as experimental_format

    return experimental_compressor, experimental_decompressor, golden, experimental_format


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Measure direct chunk-level latency of ExperimentalDecompressorTop "
            "using Python-preprocessed token streams."
        )
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
        default=16,
        help="Number of pages to measure (0 = all pages from the file)",
    )
    parser.add_argument(
        "--tier",
        choices=sorted(TIER_MACROS),
        default="large",
        help="RST tier macro used for the SV build",
    )
    parser.add_argument(
        "--verilator-bin",
        default=DEFAULT_VERILATOR_BIN,
        help="Path to the Verilator binary",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=Path("build/verilator/experimental_decompressor_top_latency"),
        help="Directory for the compiled simulation harness and generated stimuli",
    )
    parser.add_argument(
        "--hardware-json",
        type=Path,
        help=(
            "Optional JSON from tools/run_m4_experimental_regression.py --write-json "
            "to compare direct chunk latency against the full page path"
        ),
    )
    parser.add_argument(
        "--case-source",
        choices=("logical-chunks", "physical-blocks", "sampled-physical-blocks"),
        default="logical-chunks",
        help="What token windows to feed directly into ExperimentalDecompressorTop",
    )
    parser.add_argument(
        "--samples-per-page",
        type=int,
        default=10,
        help="Uniform-with-replacement physical-block samples per page when sampling",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=12345,
        help="RNG seed for sampled physical-block runs",
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
        "--skip-output-overflow",
        action="store_true",
        help=(
            "Skip cases whose decompressed output would exceed the 256-symbol "
            "ExperimentalDecompressorTop output contract"
        ),
    )
    parser.add_argument(
        "--write-json",
        type=Path,
        help="Optional JSON summary output path",
    )
    return parser.parse_args()


def run_cmd(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=cwd,
        check=True,
        text=True,
        capture_output=True,
    )


def pack_values(values: list[int], *, width: int, bits_per_value: int) -> str:
    if len(values) > width:
        raise ValueError(f"value count overflow: len={len(values)} width={width}")

    packed = 0
    value_mask = (1 << bits_per_value) - 1
    for idx, value in enumerate(values):
        packed |= (value & value_mask) << (idx * bits_per_value)

    total_bits = width * bits_per_value
    total_hex = (total_bits + 3) // 4
    return format(packed, f"0{total_hex}x")


def simulate_stack(expansions: dict[int, list[int]], initial_tokens: list[int]) -> int:
    stack = list(reversed(initial_tokens))
    cycles = 0

    while stack:
        top_is_code = stack[-1] in expansions
        below_is_code = (len(stack) >= 2) and (stack[-2] in expansions)
        ops_this_cycle = 1 if (len(stack) >= 2 and top_is_code and not below_is_code) else 2

        for _ in range(ops_this_cycle):
            if not stack:
                break
            token = stack.pop()
            if token in expansions:
                for child in reversed(expansions[token]):
                    stack.append(child)

        cycles += 1

    return cycles


def even_split(tokens: list[int], count: int = DECOMP_LIFOS) -> list[list[int]]:
    base_len = len(tokens) // count
    remainder = len(tokens) % count
    segments = []
    read_idx = 0

    for seg in range(count):
        seg_len = base_len + (1 if seg < remainder else 0)
        segments.append(tokens[read_idx:read_idx + seg_len])
        read_idx += seg_len

    return segments


def simulate_segment(expansions: dict[int, list[int]], tokens: list[int]) -> tuple[int, list[int]]:
    seg_cycles = [simulate_stack(expansions, segment) for segment in even_split(tokens)]
    return (max(seg_cycles) if seg_cycles else 0, seg_cycles)


def decompress_window(
    tokens: list[int],
    *,
    dict_sequences: list[list[int]],
    dict_count: int,
    golden,
) -> list[int]:
    segment_inputs = golden.split_evenly(tokens, DECOMP_LIFOS)
    segment_outputs = [
        golden.decompress_lifo_segment(
            segment,
            dict_sequences,
            dict_count,
            golden.DEFAULT_LARGE_TIER,
        )
        for segment in segment_inputs
    ]
    return [sym for segment_output in segment_outputs for sym in segment_output]


def build_physical_blocks(
    *,
    compressed_chunk_bitstrings: list[str],
    experimental_format,
    physical_capacity_bits: int,
) -> list[dict]:
    chunk_decoder = experimental_format.load_cram_cpp_tables().chunk_decoder
    physical_blocks: list[dict] = []
    current_tokens: list[int] = []
    current_bits = 0

    for chunk_idx, chunk_bits in enumerate(compressed_chunk_bitstrings):
        unresolved_tokens = experimental_format.decode_prefixed_stream(chunk_bits, chunk_decoder)
        resolved_tokens = experimental_format.apply_reuse(unresolved_tokens)

        for token_idx, (unresolved_token, resolved_token) in enumerate(
            zip(unresolved_tokens, resolved_tokens, strict=True)
        ):
            token_bits = len(experimental_format.chunk_symbol_bits(unresolved_token))
            if token_bits > physical_capacity_bits:
                raise RuntimeError(
                    f"single token exceeds physical block capacity: bits={token_bits} "
                    f"capacity={physical_capacity_bits}"
                )

            if current_tokens and (current_bits + token_bits > physical_capacity_bits):
                physical_blocks.append(
                    {
                        "tokens": current_tokens,
                        "packed_bits": current_bits,
                    }
                )
                current_tokens = []
                current_bits = 0

            current_tokens.append(resolved_token)
            current_bits += token_bits

    if current_tokens:
        physical_blocks.append(
            {
                "tokens": current_tokens,
                "packed_bits": current_bits,
            }
        )

    return physical_blocks


def load_hardware_chunk_cycle_avg(hardware_json: Path) -> float:
    parsed = json.loads(hardware_json.read_text(encoding="utf-8"))
    pages = parsed.get("hardware_pages")
    if not isinstance(pages, list):
        raise RuntimeError(f"hardware JSON missing hardware_pages: {hardware_json}")

    total_cycles = sum(int(page["decomp_cycles"]) for page in pages)
    total_chunks = len(pages) * PAGE_CHUNKS
    if total_chunks == 0:
        raise RuntimeError(f"hardware JSON has no page samples: {hardware_json}")
    return total_cycles / total_chunks


def write_stimulus(path: Path, cases: list[dict]) -> None:
    lines = [str(len(cases))]
    for case in cases:
        lines.extend(
            [
                case["label"],
                str(len(case["tokens"])),
                pack_values(case["tokens"], width=CHUNK_WIDTH, bits_per_value=SYMBOL_BITS),
                str(len(case["expected_output"])),
                pack_values(case["expected_output"], width=CHUNK_WIDTH, bits_per_value=SYMBOL_BITS),
                str(case["dict_count"]),
                pack_values(case["dict_lens"], width=MAX_DICT_ENTRIES, bits_per_value=LEN_BITS),
                pack_values(
                    case["dict_seq_flat"],
                    width=MAX_DICT_ENTRIES * MAX_SEQ_LEN,
                    bits_per_value=SYMBOL_BITS,
                ),
            ]
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_sim_binary(root: Path, build_dir: Path, tier: str, verilator_bin: str) -> Path:
    macro = TIER_MACROS[tier]
    build_dir.mkdir(parents=True, exist_ok=True)
    output_path = build_dir / "Vtb_ExperimentalDecompressorTop"
    cmd = [
        verilator_bin,
        "-sv",
        "--binary",
        "--timing",
        "-Wno-WIDTH",
        "-Wno-LATCH",
        "-Wno-UNOPTFLAT",
        "-Wno-IMPLICITSTATIC",
        "-Wno-WIDTHCONCAT",
        f"-D{macro}",
        "--top-module",
        "tb_ExperimentalDecompressorTop",
        "-Mdir",
        str(build_dir),
        "-f",
        "experimental/frozen_large/experimental_decompressor_filelist.f",
        "experimental/frozen_large/decompressor/experimental_decompressor_top_tb.sv",
    ]
    if verilator_supports_flag(verilator_bin, "--quiet-build"):
        cmd.insert(4, "--quiet-build")
    run_cmd(cmd, root)
    return output_path


def parse_result_file(path: Path) -> dict[str, dict]:
    results: dict[str, dict] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        fields = line.split()
        if len(fields) != 10 + (2 * DECOMP_LIFOS) + LOGICAL_BLOCKS_PER_CHUNK:
            raise RuntimeError(f"unexpected result line: {line}")

        (
            case_idx,
            label,
            cycles,
            state_idle,
            state_compact,
            state_prep,
            state_launch,
            state_wait,
            state_done,
            out_count,
            *tail_fields,
        ) = fields

        seg_done_cycles = tail_fields[:DECOMP_LIFOS]
        seg_out_counts = tail_fields[DECOMP_LIFOS:(2 * DECOMP_LIFOS)]
        block_ready_cycles = tail_fields[(2 * DECOMP_LIFOS):]

        results[label] = {
            "case_idx": int(case_idx),
            "rtl_cycles": int(cycles),
            "state_idle_cycles": int(state_idle),
            "state_compact_cycles": int(state_compact),
            "state_prep_cycles": int(state_prep),
            "state_launch_cycles": int(state_launch),
            "state_wait_cycles": int(state_wait),
            "state_done_cycles": int(state_done),
            "out_count": int(out_count),
            "seg_done_cycles": [int(value) for value in seg_done_cycles],
            "seg_out_counts": [int(value) for value in seg_out_counts],
            "block_ready_cycles": [int(value) for value in block_ready_cycles],
            "critical64_cycles_avg": (
                sum(int(value) for value in block_ready_cycles) / LOGICAL_BLOCKS_PER_CHUNK
            ),
        }
    return results


def resolve_input_file(args: argparse.Namespace, root: Path) -> Path:
    if args.input_file is not None:
        return args.input_file.resolve()
    default_input = default_input_file(root)
    if default_input.exists():
        return default_input
    raise RuntimeError("input_file is required because the default dataset is missing")


def main() -> int:
    args = parse_args()
    if args.tier != "large":
        raise RuntimeError("direct ExperimentalDecompressorTop latency is currently wired for large tier")
    if args.samples_per_page < 0:
        raise RuntimeError("--samples-per-page must be >= 0")
    if args.physical_block_overhead_bits < 0:
        raise RuntimeError("--physical-block-overhead-bits must be >= 0")

    root = repo_root()
    input_file = resolve_input_file(args, root)
    build_dir = resolve_repo_path(root, args.build_dir)
    (
        experimental_compressor,
        experimental_decompressor,
        golden,
        experimental_format,
    ) = import_helpers(root)
    rng = random.Random(args.seed)
    physical_capacity_bits = args.physical_block_bytes * 8 - args.physical_block_overhead_bits
    if physical_capacity_bits <= 0:
        raise RuntimeError(
            f"physical block capacity must be positive, got {physical_capacity_bits}"
        )

    loaded = load_paged_input(root, input_file, args.pages)
    cases: list[dict] = []
    skipped_output_overflow_lengths: list[int] = []

    for page_idx, raw_page in enumerate(loaded.pages):
        _encoded, _cycles, details = experimental_compressor.cram_encode(
            bytes(raw_page),
            MODEL_CONFIG,
            return_details=True,
        )

        dict_count = len(details.dict_sequences)
        dict_lens = [0] * MAX_DICT_ENTRIES
        dict_seq_flat = [0] * (MAX_DICT_ENTRIES * MAX_SEQ_LEN)
        for dict_idx, sequence in enumerate(details.dict_sequences):
            dict_lens[dict_idx] = len(sequence)
            for sym_idx, symbol in enumerate(sequence):
                dict_seq_flat[dict_idx * MAX_SEQ_LEN + sym_idx] = symbol

        expansions = {256 + idx: sequence for idx, sequence in enumerate(details.dict_sequences)}

        page_cases: list[dict] = []
        def append_case(label: str, *, tokens: list[int], source_idx: int, packed_bits: int | None = None) -> None:
            expected_output = decompress_window(
                tokens,
                dict_sequences=details.dict_sequences,
                dict_count=dict_count,
                golden=golden,
            )
            if len(expected_output) > CHUNK_WIDTH:
                if args.skip_output_overflow:
                    skipped_output_overflow_lengths.append(len(expected_output))
                    return
                raise RuntimeError(
                    f"{label} expands to {len(expected_output)} output symbols, "
                    f"which exceeds ExperimentalDecompressorTop width {CHUNK_WIDTH}"
                )

            stack_cycles, seg_stack_cycles = simulate_segment(expansions, tokens)
            case = {
                "label": label,
                "page_idx": page_idx,
                "source_idx": source_idx,
                "dict_count": dict_count,
                "dict_lens": dict_lens,
                "dict_seq_flat": dict_seq_flat,
                "tokens": tokens,
                "expected_output": expected_output,
                "stack_cycles": stack_cycles,
                "seg_stack_cycles": seg_stack_cycles,
                "token_count": len(tokens),
            }
            if packed_bits is not None:
                case["packed_bits"] = packed_bits
            page_cases.append(case)

        if args.case_source == "logical-chunks":
            for chunk_idx, chunk_bits in enumerate(details.compressed_chunk_bitstrings):
                tokens = experimental_decompressor.decode_experimental_chunk(chunk_bits)
                append_case(
                    f"page{page_idx:04d}_chunk{chunk_idx:02d}",
                    tokens=tokens,
                    source_idx=chunk_idx,
                )
        else:
            physical_blocks = build_physical_blocks(
                compressed_chunk_bitstrings=details.compressed_chunk_bitstrings,
                experimental_format=experimental_format,
                physical_capacity_bits=physical_capacity_bits,
            )
            selected_blocks: list[tuple[int, dict]] = []
            if args.case_source == "physical-blocks":
                selected_blocks = list(enumerate(physical_blocks))
            else:
                selected_blocks = [
                    (block_idx, physical_blocks[block_idx])
                    for block_idx in (
                        rng.randrange(len(physical_blocks)) for _ in range(args.samples_per_page)
                    )
                ]

            for case_idx_on_page, (block_idx, block) in enumerate(selected_blocks):
                tokens = list(block["tokens"])
                label_suffix = (
                    f"physblk{block_idx:02d}"
                    if args.case_source == "physical-blocks"
                    else f"sample{case_idx_on_page:02d}_src{block_idx:02d}"
                )
                append_case(
                    f"page{page_idx:04d}_{label_suffix}",
                    tokens=tokens,
                    source_idx=block_idx,
                    packed_bits=int(block["packed_bits"]),
                )

        cases.extend(page_cases)

    stim_path = build_dir / "stimuli" / "direct_chunk_cases.txt"
    result_path = build_dir / "results" / "direct_chunk_results.txt"
    write_stimulus(stim_path, cases)
    sim_bin = build_sim_binary(root, build_dir, args.tier, args.verilator_bin)

    result_path.parent.mkdir(parents=True, exist_ok=True)
    run = run_cmd(
        [
            str(sim_bin),
            f"+STIM_FILE={stim_path.resolve()}",
            f"+RESULT_FILE={result_path.resolve()}",
        ],
        root,
    )
    if "[experimental-direct] PASS" not in run.stdout:
        raise RuntimeError(f"simulator did not report pass:\n{run.stdout}")

    measured = parse_result_file(result_path)
    if len(measured) != len(cases):
        raise RuntimeError(f"result count mismatch: got {len(measured)} expected {len(cases)}")

    hardware_chunk_cycle_avg = (
        load_hardware_chunk_cycle_avg(args.hardware_json.resolve())
        if args.hardware_json is not None and args.case_source == "logical-chunks"
        else None
    )

    case_results: list[dict] = []
    for idx, case in enumerate(cases):
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
                f"state accounting mismatch for {case['label']}: states={state_sum} rtl={rtl['rtl_cycles']}"
            )

        case_result = {
            **case,
            **rtl,
            "rtl_minus_stack_cycles": rtl["rtl_cycles"] - case["stack_cycles"],
        }
        case_results.append(case_result)

    def avg(field: str) -> float:
        return sum(case[field] for case in case_results) / len(case_results) if case_results else 0.0

    summary = {
        "input_file": str(input_file),
        "case_source": args.case_source,
        "page_count": len(loaded.pages),
        "case_count": len(case_results),
        "stack_cycle_avg": avg("stack_cycles"),
        "stack_cycle_median": st.median(case["stack_cycles"] for case in case_results) if case_results else 0.0,
        "rtl_cycle_avg": avg("rtl_cycles"),
        "rtl_cycle_median": st.median(case["rtl_cycles"] for case in case_results) if case_results else 0.0,
        "critical64_cycle_avg": avg("critical64_cycles_avg"),
        "critical64_cycle_median": (
            st.median(case["critical64_cycles_avg"] for case in case_results) if case_results else 0.0
        ),
        "rtl_minus_stack_avg": avg("rtl_minus_stack_cycles"),
        "state_compact_avg": avg("state_compact_cycles"),
        "state_prep_avg": avg("state_prep_cycles"),
        "state_launch_avg": avg("state_launch_cycles"),
        "state_wait_avg": avg("state_wait_cycles"),
        "state_done_avg": avg("state_done_cycles"),
        "token_count_avg": avg("token_count"),
    }
    if case_results and "packed_bits" in case_results[0]:
        summary["packed_bits_avg"] = avg("packed_bits")
        summary["physical_capacity_bits"] = physical_capacity_bits
    if skipped_output_overflow_lengths:
        summary["skipped_output_overflow_cases"] = len(skipped_output_overflow_lengths)
        summary["skipped_output_overflow_avg_len"] = (
            sum(skipped_output_overflow_lengths) / len(skipped_output_overflow_lengths)
        )
        summary["skipped_output_overflow_max_len"] = max(skipped_output_overflow_lengths)
    if hardware_chunk_cycle_avg is not None:
        summary["hardware_chunk_cycle_avg"] = hardware_chunk_cycle_avg
        summary["hardware_minus_direct_avg"] = hardware_chunk_cycle_avg - summary["rtl_cycle_avg"]

    result = {
        "summary": summary,
        "cases": case_results,
        "sim_stdout": run.stdout.strip(),
        "stimulus": str(stim_path),
        "result_file": str(result_path),
        "sim_bin": str(sim_bin),
    }

    if args.write_json is not None:
        args.write_json.write_text(json.dumps(result, indent=2), encoding="utf-8")

    print("Direct ExperimentalDecompressorTop Latency")
    print(f"  input={input_file}")
    print(
        f"  source={summary['case_source']} pages={summary['page_count']} cases={summary['case_count']}"
    )
    print(
        "  stack_cycles="
        f"{summary['stack_cycle_avg']:.2f} avg, {summary['stack_cycle_median']:.2f} median"
    )
    print(
        "  rtl_cycles="
        f"{summary['rtl_cycle_avg']:.2f} avg, {summary['rtl_cycle_median']:.2f} median"
    )
    print(
        "  critical64_cycles="
        f"{summary['critical64_cycle_avg']:.2f} avg, {summary['critical64_cycle_median']:.2f} median"
    )
    print(f"  rtl_minus_stack={summary['rtl_minus_stack_avg']:.2f} avg")
    print(
        "  state_cycles="
        f"compact {summary['state_compact_avg']:.2f}, "
        f"prep {summary['state_prep_avg']:.2f}, "
        f"launch {summary['state_launch_avg']:.2f}, "
        f"wait {summary['state_wait_avg']:.2f}, "
        f"done {summary['state_done_avg']:.2f}"
    )
    print(f"  token_count={summary['token_count_avg']:.2f} avg")
    if "packed_bits_avg" in summary:
        print(
            f"  packed_bits={summary['packed_bits_avg']:.2f} avg "
            f"(capacity {summary['physical_capacity_bits']})"
        )
    if "skipped_output_overflow_cases" in summary:
        print(
            "  skipped_output_overflow="
            f"{summary['skipped_output_overflow_cases']} cases, "
            f"{summary['skipped_output_overflow_avg_len']:.2f} avg output symbols, "
            f"max {summary['skipped_output_overflow_max_len']}"
        )
    if hardware_chunk_cycle_avg is not None:
        print(f"  hardware_chunk_cycles={summary['hardware_chunk_cycle_avg']:.2f} avg")
        print(f"  hardware_minus_direct={summary['hardware_minus_direct_avg']:.2f} avg")
    if args.write_json is not None:
        print(f"  json={args.write_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
