#!/usr/bin/env python3
"""Experimental compressor-side model aligned to cram_cpp ratio behavior.

This path is intentionally separate from the artifact-facing baseline model.
It focuses on compression ratio fidelity rather than exact hardware timing.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
from dataclasses import dataclass
from math import ceil

from new_hardware_sim_compressor import (
    DEFAULT_CHUNK_SIZE,
    HashTable,
    MAX_SEQ_LEN,
    CodeByte,
    LitByte,
    find_updates2,
    init_count_chunked,
    make_replacements_chunked,
    read_file_in_chunks,
    split_page_chunks,
    total_chunk_symbols,
)
from rst_experimental_format import (
    ExperimentalEncodedPage,
    chunk_symbol_bits,
    code_sym,
    dict_symbol_bits,
    encode_chunk_symbols,
    encode_dict_symbols,
    literal_sym,
)


FREE_DICT_SEQUENCES = (
    (literal_sym(0), literal_sym(0)),
    (code_sym(0), code_sym(0)),
)

EXPERIMENTAL_HASH_TABLE_PARAMS = {
    "seq_len_2": {"banks": 6, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
    "seq_len_3": {"banks": 7, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
    "seq_len_4": {"banks": 9, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
    "seq_len_5": {"banks": 10, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
}


@dataclass(frozen=True)
class ExperimentalEncodeDetails:
    raw_bytes: int
    dict_count: int
    dict_total_entries: int
    dict_bits: int
    compressed_symbols: int
    encoded_bits: int
    dict_bytes: int
    compressed_bytes: int
    dict_bitstring: str
    compressed_chunk_bitstrings: list[str]
    dict_sequences: list[list[int]]
    encoded_page: ExperimentalEncodedPage


@dataclass(frozen=True)
class ReplacementEvent:
    pre_replace_idx: int
    post_replace_idx: int
    sequence_len: int


def dict_symbol_bit_length(symbol) -> int:
    return len(dict_symbol_bits(symbol_to_int(symbol)))


def chunk_symbol_bit_length(symbol) -> int:
    return len(chunk_symbol_bits(symbol_to_int(symbol)))


def symbol_to_int(symbol) -> int:
    if isinstance(symbol, int):
        return symbol
    return int(symbol.value)


def sequence_to_ints(sequence: tuple[object, ...] | list[object]) -> list[int]:
    return [symbol_to_int(symbol) for symbol in sequence]


def full_recount_candidate(chunks: list[list[object]]) -> dict[tuple[object, ...], int]:
    table: dict[tuple[object, ...], int] = {}
    for chunk in chunks:
        for start in range(len(chunk)):
            for seq_len in range(2, MAX_SEQ_LEN + 1):
                end = start + seq_len
                if end > len(chunk):
                    break
                seq = tuple(chunk[start:end])
                table[seq] = table.get(seq, 0) + 9 * (seq_len - 1)
    return table


def update_global_count_map_incremental(
    table: dict[tuple[object, ...], int],
    old_chunks: list[list[object]],
    new_chunks: list[list[object]],
    events: list[list[ReplacementEvent]],
) -> None:
    for old_chunk, new_chunk, chunk_events in zip(old_chunks, new_chunks, events):
        local_updates: dict[tuple[object, ...], int] = {}
        for event in chunk_events:
            incs, decs = find_updates2(
                event.pre_replace_idx,
                event.post_replace_idx,
                old_chunk,
                new_chunk,
                event.sequence_len,
            )
            for seq, valid in incs:
                if valid:
                    local_updates[seq] = local_updates.get(seq, 0) + 9 * (len(seq) - 1)
            for seq, valid in decs:
                if valid:
                    local_updates[seq] = local_updates.get(seq, 0) - 9 * (len(seq) - 1)

        for seq, delta in local_updates.items():
            if seq in table:
                table[seq] += delta
            elif delta > 0:
                table[seq] = delta


def find_best_candidate_from_global(
    table: dict[tuple[object, ...], int],
    total_bits: int,
) -> tuple[object, ...]:
    best_seq: tuple[object, ...] = ()
    best_score = float("-inf")

    for seq, score in table.items():
        seq_len = len(seq)
        dict_size = 9 * seq_len + 2
        final_score = (score - dict_size) / dict_size
        if final_score <= best_score:
            continue

        true_size = sum(dict_symbol_bit_length(symbol) for symbol in seq)
        if true_size <= total_bits:
            best_score = final_score
            best_seq = seq

    return best_seq


def build_hash_table_config(config: dict, chunk_size: int) -> dict:
    hash_table_config = {
        "memory_blocks": config.get("memory_blocks", 2),
        "chunk_size": chunk_size,
        "min_cycles_per_iteration": config.get("min_cycles_per_iteration", 16),
        "static_tree_codes_per_cycle": config.get("static_tree_codes_per_cycle", 0),
        "update_sites_per_cycle": config.get("update_sites_per_cycle", 1),
        "top_uses_actual_count": config.get("top_uses_actual_count", False),
    }
    for key, value in EXPERIMENTAL_HASH_TABLE_PARAMS.items():
        hash_table_config[key] = config.get(key, value)
    return hash_table_config


def find_best_candidate_from_hash_table(
    hash_table: HashTable,
    chunks: list[list[object]],
) -> tuple[tuple[object, ...], int]:
    best_seq, _ = hash_table.top_chunked(chunks)
    if not best_seq:
        return (), 0
    best_count = hash_table.sub_tables[len(best_seq)].top()[1]
    return best_seq, best_count


def apply_best_sequence(
    chunks: list[list[object]],
    best_seq: tuple[object, ...],
    code: CodeByte,
) -> tuple[list[list[object]], list[list[ReplacementEvent]], int]:
    dict_entry_size = 2 + sum(dict_symbol_bit_length(symbol) for symbol in best_seq)
    new_chunks: list[list[object]] = []
    all_events: list[list[ReplacementEvent]] = []

    for chunk in chunks:
        new_chunk: list[object] = []
        chunk_events: list[ReplacementEvent] = []
        idx = 0
        while idx < len(chunk):
            matched = False
            if idx + len(best_seq) <= len(chunk):
                matched = all(chunk[idx + offset] == best_seq[offset] for offset in range(len(best_seq)))
            if matched:
                chunk_events.append(
                    ReplacementEvent(
                        pre_replace_idx=idx,
                        post_replace_idx=len(new_chunk),
                        sequence_len=len(best_seq),
                    )
                )
                new_chunk.append(code)
                idx += len(best_seq)
                continue
            new_chunk.append(chunk[idx])
            idx += 1
        new_chunks.append(new_chunk)
        all_events.append(chunk_events)

    return new_chunks, all_events, dict_entry_size


def encode_dict_sequence_bit_length(
    seq_used: tuple[object, ...],
    subs_flat: list[object],
) -> int:
    bitstring, _ = encode_dict_symbols(
        sequence_to_ints(seq_used),
        seed_history=sequence_to_ints(subs_flat),
    )
    return len(bitstring)


def encode_chunk_bit_length(chunk: list[object]) -> int:
    bitstring, _ = encode_chunk_symbols(sequence_to_ints(chunk))
    return len(bitstring)


def build_experimental_encoded_page(
    stored_subs: list[tuple[object, ...]],
    compressed_chunks: list[list[object]],
) -> tuple[ExperimentalEncodedPage, list[list[int]]]:
    dict_sequences = [list(seq) for seq in FREE_DICT_SEQUENCES]
    dict_history = [sym for seq in FREE_DICT_SEQUENCES for sym in seq]
    dict_payload_bits = []

    for seq in stored_subs:
        numeric_seq = sequence_to_ints(seq)
        seq_bits, _ = encode_dict_symbols(numeric_seq, seed_history=dict_history)
        dict_payload_bits.append(seq_bits)
        dict_history.extend(numeric_seq)
        dict_sequences.append(numeric_seq)

    dict_header = format(len(stored_subs), "06b")
    dict_lengths = "".join(format(len(seq) - 2, "02b") for seq in stored_subs)
    dict_bitstring = dict_header + dict_lengths + "".join(dict_payload_bits)

    compressed_chunk_bitstrings = []
    for chunk in compressed_chunks:
        chunk_bits, _ = encode_chunk_symbols(sequence_to_ints(chunk))
        compressed_chunk_bitstrings.append(chunk_bits)

    return (
        ExperimentalEncodedPage(
            dict_bits=dict_bitstring,
            compressed_chunks=compressed_chunk_bitstrings,
        ),
        dict_sequences,
    )


def cram_encode_chunked(page_bytes: bytes, config: dict, return_details: bool = False):
    memory_blocks = config.get("memory_blocks", 2)
    chunk_size = config.get("chunk_size", DEFAULT_CHUNK_SIZE)
    min_iter_cycles = config.get("min_cycles_per_iteration", 16)
    static_tree_codes_per_cycle = config.get("static_tree_codes_per_cycle", 0)

    page = [LitByte(b) for b in page_bytes]
    chunks = split_page_chunks(page, chunk_size) if chunk_size and chunk_size > 0 else [page]

    total_bits_budget = memory_blocks * 64 * 8 - 6
    total_cycles = 0
    compressed_chunks = chunks

    stored_subs: list[tuple[object, ...]] = []
    subs_flat: list[object] = []
    dict_symbol_bits = 0
    # Mirror the SV bootstrap path: apply the two free substitutions first,
    # then drive subsequent choices from the same finite hash-table view the
    # RTL maintains rather than from an unbounded global recount.
    for next_code, best_seq in enumerate(((LitByte(0), LitByte(0)), (CodeByte(0), CodeByte(0)))):
        compressed_chunks, _replacement_events, _ = apply_best_sequence(
            compressed_chunks,
            best_seq,
            CodeByte(next_code),
        )
        total_cycles += min_iter_cycles
        subs_flat.extend(best_seq)

    hash_table = HashTable(build_hash_table_config(config, chunk_size))
    init_count_chunked(hash_table, compressed_chunks)

    next_code = 2
    while next_code <= 62:
        best_seq, best_count = find_best_candidate_from_hash_table(hash_table, compressed_chunks)
        if not best_seq:
            break

        dict_entry_size = 2 + encode_dict_sequence_bit_length(best_seq, subs_flat)
        active_utility = best_count * (9 * (len(best_seq) - 1)) - dict_entry_size

        if (total_bits_budget - dict_entry_size) < 0:
            break
        if active_utility <= 0:
            break

        compressed_chunks, _cycles = make_replacements_chunked(
            hash_table,
            compressed_chunks,
            best_seq,
            CodeByte(next_code),
        )
        total_cycles += min_iter_cycles
        total_bits_budget -= dict_entry_size
        stored_subs.append(best_seq)
        dict_symbol_bits += dict_entry_size - 2
        subs_flat.extend(best_seq)
        next_code += 1

    count = len(stored_subs)
    dict_bits = 6 + 2 * count + dict_symbol_bits
    chunk_bit_lengths = [encode_chunk_bit_length(chunk) for chunk in compressed_chunks]
    compressed_bits = sum(chunk_bit_lengths)
    compressed_symbols = total_chunk_symbols(compressed_chunks)

    if static_tree_codes_per_cycle > 0 and compressed_symbols:
        total_cycles += ceil(compressed_symbols / static_tree_codes_per_cycle)

    dict_bytes = ceil(dict_bits / 8) if dict_bits else 0
    compressed_bytes = sum(ceil(bit_length / 8) for bit_length in chunk_bit_lengths)
    result = bytes(dict_bytes + compressed_bytes)

    encoded_page, dict_sequences = build_experimental_encoded_page(stored_subs, compressed_chunks)
    if len(encoded_page.dict_bits) != dict_bits:
        raise RuntimeError(
            f"dict bit count mismatch: computed={dict_bits} encoded={len(encoded_page.dict_bits)}"
        )
    encoded_chunk_lengths = [len(chunk_bits) for chunk_bits in encoded_page.compressed_chunks]
    if encoded_chunk_lengths != chunk_bit_lengths:
        raise RuntimeError(
            f"chunk bit count mismatch: computed={chunk_bit_lengths} encoded={encoded_chunk_lengths}"
        )

    if return_details:
        details = ExperimentalEncodeDetails(
            raw_bytes=len(page_bytes),
            dict_count=count,
            dict_total_entries=len(dict_sequences),
            dict_bits=dict_bits,
            compressed_symbols=compressed_symbols,
            encoded_bits=dict_bits + compressed_bits,
            dict_bytes=dict_bytes,
            compressed_bytes=compressed_bytes,
            dict_bitstring=encoded_page.dict_bits,
            compressed_chunk_bitstrings=list(encoded_page.compressed_chunks),
            dict_sequences=dict_sequences,
            encoded_page=encoded_page,
        )
        return result, total_cycles, details

    return result, total_cycles


def cram_encode(page_bytes: bytes, config: dict, return_details: bool = False):
    return cram_encode_chunked(page_bytes, config, return_details=return_details)


def run_benchmark(filepath: str, config: dict) -> dict:
    num_pages = config.get("pages_per_benchmark", 100)
    pages = read_file_in_chunks(filepath)
    sample = pages[:num_pages]

    results = {
        "benchmark_file": os.path.basename(filepath),
        "pages_processed": 0,
        "total_cycles": 0,
        "total_original_size": 0,
        "total_compressed_size": 0,
        "compression_ratios": [],
    }

    for page in sample:
        try:
            compressed, cycles = cram_encode(page, config)
            original_size = len(page)
            compressed_size = len(compressed)
            results["pages_processed"] += 1
            results["total_cycles"] += cycles
            results["total_original_size"] += original_size
            results["total_compressed_size"] += compressed_size
            if compressed_size:
                results["compression_ratios"].append(original_size / compressed_size)
        except Exception as exc:
            print(f"Error processing page in {filepath}: {exc}")

    if results["pages_processed"] > 0:
        results["avg_cycles_per_page"] = results["total_cycles"] / results["pages_processed"]
        if results["total_compressed_size"] > 0:
            results["overall_compression_ratio"] = (
                results["total_original_size"] / results["total_compressed_size"]
            )
        else:
            results["overall_compression_ratio"] = 0.0

    return results


def main():
    parser = argparse.ArgumentParser(description="Experimental CRAM ratio-aligned benchmark driver")
    parser.add_argument("config_path", help="Path to JSON configuration file")
    parser.add_argument("input_dir", help="Directory containing benchmark files")
    parser.add_argument("output_path", help="Path to output JSON results file")
    args = parser.parse_args()

    with open(args.config_path, "r", encoding="utf-8") as config_file:
        config = json.load(config_file)

    all_results = {"config": config, "benchmarks": {}}
    pattern = os.path.join(args.input_dir, "*")
    for filepath in sorted(glob.glob(pattern)):
        if not os.path.isfile(filepath):
            continue
        label = os.path.basename(filepath)
        print(f"Running {label}...")
        result = run_benchmark(filepath, config)
        all_results["benchmarks"][label] = result
        print(f"  Processed: {result['pages_processed']} pages")
        print(f"  Avg cycles: {result.get('avg_cycles_per_page', 0):.2f}")
        print(f"  Compression ratio: {result.get('overall_compression_ratio', 0):.4f}")

    with open(args.output_path, "w", encoding="utf-8") as output_file:
        json.dump(all_results, output_file, indent=2)

    print(f"\nResults written to {args.output_path}")


if __name__ == "__main__":
    main()
