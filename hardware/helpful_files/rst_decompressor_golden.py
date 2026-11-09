#!/usr/bin/env python3
"""Golden/reference Python model for the current SV decompressor path.

This module is intentionally aligned to the current RTL:
- `dict_packed` layout from `DictSerializer` / `DictDeserializer`
- valid-token compaction and even segment partitioning from `DecompressorTop`
- dual-issue stack expansion from `LifoExpander`
- page wrapper sequencing from `PageDecompressorTop`

Future-format work that follows `cram_cpp` lives separately in
`rst_decompressor_experimental.py`.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from typing import Sequence


DICT_COUNT_BITS = 6
DICT_LEN_BITS = 2
COMPACT_BLOCK_SIZE = 8


@dataclass(frozen=True)
class RstTierConfig:
    chunk_width: int = 256
    page_chunks: int = 16
    max_dict_entries: int = 63
    dict_storage_bits: int = 2 * 64 * 8
    decomp_lifos: int = 8
    max_seq_len: int = 5

    @property
    def page_width(self) -> int:
        return self.chunk_width * self.page_chunks

    @property
    def max_decomp_seg_tokens(self) -> int:
        return (self.chunk_width + self.decomp_lifos - 1) // self.decomp_lifos


DEFAULT_LARGE_TIER = RstTierConfig()


@dataclass(frozen=True)
class VSymbol:
    sym: int = 0
    valid: bool = False


@dataclass(frozen=True)
class GoldenEncodedPage:
    tier: RstTierConfig
    dict_packed: int
    dict_packed_bits: int
    dict_count: int
    dict_lens: list[int]
    dict_sequences: list[list[int]]
    compressed_chunks: list[list[int]]
    compressed_page: list[VSymbol]


@dataclass(frozen=True)
class ChunkDecompressionResult:
    ordered_tokens: list[int]
    segment_inputs: list[list[int]]
    segment_outputs: list[list[int]]
    out_count: int
    decompressed_chunk: list[int]


@dataclass(frozen=True)
class PageDecompressionResult:
    dict_count: int
    dict_lens: list[int]
    dict_sequences: list[list[int]]
    dict_packed_bits: int
    chunk_results: list[ChunkDecompressionResult]
    page_symbols: list[int]


def literal_sym(value: int) -> int:
    return value & 0x0FF


def code_sym(idx: int) -> int:
    return 0x100 | (idx & 0x0FF)


def sym_is_code(sym: int) -> bool:
    return bool(sym & 0x100)


def dict_len_encode(seq_len: int) -> int:
    if seq_len < 2 or seq_len > 5:
        raise ValueError(f"sequence length must be in [2, 5], got {seq_len}")
    return seq_len - 2


def dict_len_decode(encoded_len: int) -> int:
    if encoded_len < 0 or encoded_len > 3:
        raise ValueError(f"encoded length must be in [0, 3], got {encoded_len}")
    return encoded_len + 2


def pad_runtime_page(
    page_bytes: bytes,
    page_idx: int,
    tier: RstTierConfig = DEFAULT_LARGE_TIER,
) -> list[int]:
    """Mirror the runtime-harness page padding used by `m4_runtime_file_roundtrip_tb.sv`."""
    padded = []
    for lane in range(tier.page_width):
        if lane < len(page_bytes):
            padded.append(page_bytes[lane])
        else:
            padded.append((page_idx * 73 + lane * 29) & 0xFF)
    return padded


def pack_dict(
    dict_sequences: Sequence[Sequence[int]],
    dict_lens: Sequence[int] | None = None,
    tier: RstTierConfig = DEFAULT_LARGE_TIER,
) -> tuple[int, int]:
    """Pack logical dictionary entries into the current RTL `dict_packed` layout."""
    count = len(dict_sequences)
    if count > tier.max_dict_entries:
        raise ValueError(f"dict has {count} entries but tier allows {tier.max_dict_entries}")

    if dict_lens is None:
        dict_lens = [len(seq) for seq in dict_sequences]
    if len(dict_lens) != count:
        raise ValueError("dict_lens length must match dict_sequences length")

    header_bits = [format(count, f"0{DICT_COUNT_BITS}b")]
    payload_bits: list[str] = []

    for idx, (seq_len, seq) in enumerate(zip(dict_lens, dict_sequences)):
        if len(seq) != seq_len:
            raise ValueError(
                f"dict entry {idx} length mismatch: seq_len={seq_len} actual={len(seq)}"
            )
        if seq_len < 2 or seq_len > tier.max_seq_len:
            raise ValueError(
                f"dict entry {idx} length {seq_len} is outside current RTL bounds"
            )
        header_bits.append(format(dict_len_encode(seq_len), f"0{DICT_LEN_BITS}b"))
        for sym in seq:
            if sym < 0 or sym > 0x1FF:
                raise ValueError(f"dict entry {idx} has out-of-range symbol {sym}")
            payload_bits.append(format(sym, "09b"))

    used_bits = sum(len(bits) for bits in header_bits) + sum(len(bits) for bits in payload_bits)
    if used_bits > tier.dict_storage_bits:
        raise ValueError(
            f"packed dictionary uses {used_bits} bits but tier only provides "
            f"{tier.dict_storage_bits}"
        )

    bitstring = ("".join(header_bits) + "".join(payload_bits)).ljust(tier.dict_storage_bits, "0")
    return int(bitstring, 2), used_bits


def unpack_dict(
    dict_packed: int,
    tier: RstTierConfig = DEFAULT_LARGE_TIER,
) -> tuple[int, list[int], list[list[int]], int]:
    """Unpack the current RTL `dict_packed` integer into logical dictionary entries."""
    bitstring = format(dict_packed, f"0{tier.dict_storage_bits}b")
    dict_count = int(bitstring[:DICT_COUNT_BITS], 2)
    if dict_count > tier.max_dict_entries:
        raise ValueError(
            f"packed dictionary count {dict_count} exceeds tier max {tier.max_dict_entries}"
        )

    dict_lens = []
    pos = DICT_COUNT_BITS
    for _ in range(dict_count):
        dict_lens.append(dict_len_decode(int(bitstring[pos:pos + DICT_LEN_BITS], 2)))
        pos += DICT_LEN_BITS

    dict_sequences: list[list[int]] = []
    for seq_len in dict_lens:
        seq = []
        for _ in range(seq_len):
            next_pos = pos + 9
            if next_pos > len(bitstring):
                raise ValueError("packed dictionary payload ran out of bits")
            seq.append(int(bitstring[pos:next_pos], 2))
            pos = next_pos
        dict_sequences.append(seq)

    return dict_count, dict_lens, dict_sequences, pos


def build_compressed_page(
    compressed_chunks: Sequence[Sequence[int]],
    tier: RstTierConfig = DEFAULT_LARGE_TIER,
) -> list[VSymbol]:
    """Pack per-chunk symbol lists into the page-wide `vsym_t` view used by the RTL."""
    if len(compressed_chunks) > tier.page_chunks:
        raise ValueError(
            f"got {len(compressed_chunks)} chunks but tier only supports {tier.page_chunks}"
        )

    page = [VSymbol() for _ in range(tier.page_width)]
    for chunk_idx, chunk in enumerate(compressed_chunks):
        if len(chunk) > tier.chunk_width:
            raise ValueError(
                f"chunk {chunk_idx} has {len(chunk)} symbols but chunk width is {tier.chunk_width}"
            )
        base_idx = chunk_idx * tier.chunk_width
        for lane, sym in enumerate(chunk):
            page[base_idx + lane] = VSymbol(sym=sym, valid=True)
    return page


def compact_valid_tokens(
    compressed_chunk: Sequence[VSymbol],
    tier: RstTierConfig = DEFAULT_LARGE_TIER,
) -> list[int]:
    """Mirror the two-stage valid-token compaction in `DecompressorTop`."""
    if len(compressed_chunk) != tier.chunk_width:
        raise ValueError(
            f"compressed chunk length {len(compressed_chunk)} does not match "
            f"chunk width {tier.chunk_width}"
        )

    compact_blocks = (tier.chunk_width + COMPACT_BLOCK_SIZE - 1) // COMPACT_BLOCK_SIZE
    ordered_tokens: list[int] = []

    for block in range(compact_blocks):
        block_base = block * COMPACT_BLOCK_SIZE
        compacted_block = []
        for lane in range(COMPACT_BLOCK_SIZE):
            idx = block_base + lane
            if idx < tier.chunk_width and compressed_chunk[idx].valid:
                compacted_block.append(compressed_chunk[idx].sym)
        ordered_tokens.extend(compacted_block)

    return ordered_tokens


def split_evenly(tokens: Sequence[int], count: int) -> list[list[int]]:
    """Split tokens the same way the RTL and `cram_cpp` decompressor partition work."""
    base_len = len(tokens) // count
    remainder = len(tokens) % count
    segments = []
    read_idx = 0
    for seg in range(count):
        seg_len = base_len + (1 if seg < remainder else 0)
        segments.append(list(tokens[read_idx:read_idx + seg_len]))
        read_idx += seg_len
    return segments


def decompress_lifo_segment(
    compressed_tokens: Sequence[int],
    dict_sequences: Sequence[Sequence[int]],
    dict_count: int,
    tier: RstTierConfig = DEFAULT_LARGE_TIER,
) -> list[int]:
    """Faithfully model the current `LifoExpander` behavior for one segment."""
    if len(compressed_tokens) > tier.max_decomp_seg_tokens:
        raise ValueError(
            f"segment has {len(compressed_tokens)} tokens but cap is {tier.max_decomp_seg_tokens}"
        )

    stack = deque(compressed_tokens)
    output: list[int] = []

    while stack:
        if len(stack) > tier.chunk_width:
            raise RuntimeError(
                f"LIFO stack overflow: logical depth {len(stack)} exceeds {tier.chunk_width}"
            )

        top_sym = stack[0]
        top_is_code = sym_is_code(top_sym)

        below_sym = 0
        below_is_code = False
        dual_issue = False
        if len(stack) > 1:
            below_sym = stack[1]
            below_is_code = sym_is_code(below_sym)
            dual_issue = not (top_is_code and not below_is_code)

        consumed = 2 if len(stack) > 1 and dual_issue else 1

        top_sym = stack.popleft()
        if not top_is_code and len(output) < tier.chunk_width:
            output.append(top_sym)

        produced: list[int] = []
        if top_is_code:
            top_code_idx = top_sym & 0x0FF
            if top_code_idx < dict_count and top_code_idx < len(dict_sequences):
                produced.extend(dict_sequences[top_code_idx])

        if consumed == 2:
            below_sym = stack.popleft()
            if not below_is_code and len(output) < tier.chunk_width:
                output.append(below_sym)
            elif below_is_code:
                below_code_idx = below_sym & 0x0FF
                if below_code_idx < dict_count and below_code_idx < len(dict_sequences):
                    produced.extend(dict_sequences[below_code_idx])

        for sym in reversed(produced):
            stack.appendleft(sym)

    return output


def decompress_chunk(
    compressed_chunk: Sequence[VSymbol],
    dict_packed: int,
    tier: RstTierConfig = DEFAULT_LARGE_TIER,
) -> ChunkDecompressionResult:
    dict_count, dict_lens, dict_sequences, _dict_packed_bits = unpack_dict(dict_packed, tier)
    ordered_tokens = compact_valid_tokens(compressed_chunk, tier)
    segment_inputs = split_evenly(ordered_tokens, tier.decomp_lifos)
    segment_outputs = [
        decompress_lifo_segment(segment, dict_sequences, dict_count, tier)
        for segment in segment_inputs
    ]

    decompressed_chunk = [0] * tier.chunk_width
    write_idx = 0
    for segment_output in segment_outputs:
        if write_idx + len(segment_output) > tier.chunk_width:
            raise RuntimeError(
                f"chunk output overflow: write_idx={write_idx} len={len(segment_output)} "
                f"chunk_width={tier.chunk_width}"
            )
        decompressed_chunk[write_idx:write_idx + len(segment_output)] = segment_output
        write_idx += len(segment_output)

    return ChunkDecompressionResult(
        ordered_tokens=ordered_tokens,
        segment_inputs=segment_inputs,
        segment_outputs=segment_outputs,
        out_count=write_idx,
        decompressed_chunk=decompressed_chunk,
    )


def decompress_page(
    compressed_page: Sequence[VSymbol],
    dict_packed: int,
    tier: RstTierConfig = DEFAULT_LARGE_TIER,
) -> PageDecompressionResult:
    if len(compressed_page) != tier.page_width:
        raise ValueError(
            f"compressed page length {len(compressed_page)} does not match "
            f"page width {tier.page_width}"
        )

    dict_count, dict_lens, dict_sequences, dict_packed_bits = unpack_dict(dict_packed, tier)
    chunk_results = []
    page_symbols = [0] * tier.page_width

    for chunk_idx in range(tier.page_chunks):
        base_idx = chunk_idx * tier.chunk_width
        chunk_input = compressed_page[base_idx:base_idx + tier.chunk_width]
        chunk_result = decompress_chunk(chunk_input, dict_packed, tier)
        chunk_results.append(chunk_result)
        page_symbols[base_idx:base_idx + tier.chunk_width] = chunk_result.decompressed_chunk

    return PageDecompressionResult(
        dict_count=dict_count,
        dict_lens=dict_lens,
        dict_sequences=dict_sequences,
        dict_packed_bits=dict_packed_bits,
        chunk_results=chunk_results,
        page_symbols=page_symbols,
    )


def golden_encoded_page_from_model_details(
    details,
    tier: RstTierConfig = DEFAULT_LARGE_TIER,
) -> GoldenEncodedPage:
    """Build exact current-RTL decompressor inputs from Python compressor details."""
    dict_count = int(details.dict_count)
    dict_lens = [int(seq_len) for seq_len in getattr(details, "dict_lens", [])]
    dict_sequences = [
        [int(sym) for sym in seq] for seq in getattr(details, "dict_sequences", [])
    ]
    compressed_chunks = [
        [int(sym) for sym in chunk]
        for chunk in getattr(details, "compressed_chunk_symbols", [])
    ]

    if dict_count != len(dict_lens) or dict_count != len(dict_sequences):
        raise ValueError(
            "compressor details do not contain the logical dictionary needed for "
            "SV-aligned decompression"
        )

    dict_packed, dict_packed_bits = pack_dict(dict_sequences, dict_lens, tier)
    compressed_page = build_compressed_page(compressed_chunks, tier)

    return GoldenEncodedPage(
        tier=tier,
        dict_packed=dict_packed,
        dict_packed_bits=dict_packed_bits,
        dict_count=dict_count,
        dict_lens=dict_lens,
        dict_sequences=dict_sequences,
        compressed_chunks=compressed_chunks,
        compressed_page=compressed_page,
    )


def decompress_model_details(
    details,
    tier: RstTierConfig = DEFAULT_LARGE_TIER,
) -> PageDecompressionResult:
    encoded_page = golden_encoded_page_from_model_details(details, tier)
    return decompress_page(encoded_page.compressed_page, encoded_page.dict_packed, tier)
