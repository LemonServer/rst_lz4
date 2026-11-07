#!/usr/bin/env python3
"""Experimental Python decompressor for the richer `cram_cpp`-style format.

This path is intentionally separate from the milestone-1 golden model:
- it accepts exact `cram_cpp`-style dictionary/chunk bitstrings
- it understands static Huffman trees by parsing the vendored
  `third_party/cram_cpp/cram_tree.h`
- it applies reuse-code semantics and the free substitutions used by `cram_cpp`

It does not replace the current SV-aligned golden path in
`rst_decompressor_golden.py`.
"""

from __future__ import annotations

from dataclasses import dataclass

from rst_decompressor_golden import (
    DEFAULT_LARGE_TIER,
    RstTierConfig,
    decompress_lifo_segment,
    split_evenly,
)
from rst_experimental_format import (
    ExperimentalEncodedPage,
    apply_reuse,
    chunk_symbol_bits,
    code_sym,
    decode_prefixed_stream,
    literal_sym,
    load_cram_cpp_tables,
)


@dataclass(frozen=True)
class ExperimentalDict:
    added_entries: int
    dict_count: int
    dict_sequences: list[list[int]]
    resolved_symbols: list[int]


@dataclass(frozen=True)
class ExperimentalPageDecodeResult:
    dict_parse: ExperimentalDict
    chunk_tokens: list[list[int]]
    chunk_outputs: list[list[int]]
    page_symbols: list[int]


def parse_experimental_dict(dict_bits: str) -> ExperimentalDict:
    if len(dict_bits) < 6:
        raise ValueError("dict_bits is too short to contain the count header")

    added_entries = int(dict_bits[:6], 2)
    pos = 6

    lengths = [2, 2]
    for _ in range(added_entries):
        if pos + 2 > len(dict_bits):
            raise ValueError("dict_bits ended while reading explicit entry lengths")
        lengths.append(int(dict_bits[pos:pos + 2], 2) + 2)
        pos += 2

    seed_history = [literal_sym(0), literal_sym(0), code_sym(0), code_sym(0)]
    payload_tokens = decode_prefixed_stream(dict_bits[pos:], load_cram_cpp_tables().dict_decoder)
    resolved_payload = apply_reuse(payload_tokens, seed_history=seed_history)
    resolved_symbols = seed_history + resolved_payload

    dict_sequences = []
    payload_pos = 0
    for seq_len in lengths:
        if payload_pos + seq_len > len(resolved_symbols):
            raise ValueError(
                "dict_bits decoded successfully but did not provide enough symbols "
                "for all dictionary entries"
            )
        dict_sequences.append(resolved_symbols[payload_pos:payload_pos + seq_len])
        payload_pos += seq_len

    return ExperimentalDict(
        added_entries=added_entries,
        dict_count=len(dict_sequences),
        dict_sequences=dict_sequences,
        resolved_symbols=resolved_symbols,
    )


def decode_experimental_chunk(chunk_bits: str) -> list[int]:
    payload_tokens = decode_prefixed_stream(chunk_bits, load_cram_cpp_tables().chunk_decoder)
    return apply_reuse(payload_tokens)


def decompress_experimental_page(
    encoded_page: ExperimentalEncodedPage,
    tier: RstTierConfig = DEFAULT_LARGE_TIER,
    *,
    decomp_lifos: int | None = None,
) -> ExperimentalPageDecodeResult:
    dict_parse = parse_experimental_dict(encoded_page.dict_bits)
    lifo_count = decomp_lifos if decomp_lifos is not None else tier.decomp_lifos

    chunk_tokens = []
    chunk_outputs = []
    page_symbols: list[int] = []

    for chunk_bits in encoded_page.compressed_chunks:
        tokens = decode_experimental_chunk(chunk_bits)
        chunk_tokens.append(tokens)

        segment_inputs = split_evenly(tokens, lifo_count)
        segment_outputs = [
            decompress_lifo_segment(segment, dict_parse.dict_sequences, dict_parse.dict_count, tier)
            for segment in segment_inputs
        ]
        chunk_output = [sym for segment in segment_outputs for sym in segment]
        chunk_outputs.append(chunk_output)
        page_symbols.extend(chunk_output)

    return ExperimentalPageDecodeResult(
        dict_parse=dict_parse,
        chunk_tokens=chunk_tokens,
        chunk_outputs=chunk_outputs,
        page_symbols=page_symbols,
    )
