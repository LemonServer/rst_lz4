#!/usr/bin/env python3
"""Shared helpers for the milestone-1 experimental CRAM/RST format paths."""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
import re

from cram_cpp_vendor import vendored_cram_cpp_root

CRAM_CPP_ROOT = vendored_cram_cpp_root()
CRAM_TREE_HEADER = CRAM_CPP_ROOT / "cram_tree.h"
REUSE_CODE_START = 63
REUSE_CODE_COUNT = 8


def literal_sym(value: int) -> int:
    return value & 0x0FF


def code_sym(idx: int) -> int:
    return 0x100 | (idx & 0x0FF)


def sym_is_code(sym: int) -> bool:
    return bool(sym & 0x100)


def reuse_sym(distance: int) -> int:
    if distance < 1 or distance > REUSE_CODE_COUNT:
        raise ValueError(
            f"reuse distance must be in [1, {REUSE_CODE_COUNT}], got {distance}"
        )
    return code_sym(REUSE_CODE_START + distance - 1)


@dataclass(frozen=True)
class PrefixDecoder:
    by_length: dict[int, dict[str, int]]
    lengths: tuple[int, ...]


@dataclass(frozen=True)
class ExperimentalTables:
    dict_decoder: PrefixDecoder
    chunk_decoder: PrefixDecoder
    dict_encoder: dict[int, str]
    chunk_encoder: dict[int, str]


@dataclass(frozen=True)
class ExperimentalEncodedPage:
    dict_bits: str
    compressed_chunks: list[str]


def _parse_bc_array(
    header_text: str,
    array_name: str,
    expected_count: int | None = None,
) -> list[str]:
    array_re = re.compile(
        rf"static const std::array<BinaryCode, [^>]+> {array_name} = \{{\{{(?P<body>.*?)\}}\}};",
        re.S,
    )
    match = array_re.search(header_text)
    if match is None:
        raise RuntimeError(f"failed to locate {array_name} in {CRAM_TREE_HEADER}")

    codes = re.findall(r'BC\("([01]+)"\)', match.group("body"))
    if expected_count is not None and len(codes) != expected_count:
        raise RuntimeError(
            f"expected {expected_count} codes in {array_name}, found {len(codes)}"
        )
    return codes


def _build_prefix_decoder(code_map: dict[int, str]) -> PrefixDecoder:
    by_length: dict[int, dict[str, int]] = {}
    for sym, code_bits in code_map.items():
        by_length.setdefault(len(code_bits), {})[code_bits] = sym
    return PrefixDecoder(by_length=by_length, lengths=tuple(sorted(by_length)))


@lru_cache(maxsize=1)
def load_cram_cpp_tables(
    tree_header: Path = CRAM_TREE_HEADER,
) -> ExperimentalTables:
    header_text = tree_header.read_text(encoding="utf-8")

    lit_dict_codes = _parse_bc_array(header_text, "s_litByteDictCodes", 256)
    lit_chunk_codes = _parse_bc_array(header_text, "s_litByteChunkCodes", 256)
    sub_dict_codes = _parse_bc_array(header_text, "s_cramSubDictCodes")
    sub_chunk_codes = _parse_bc_array(header_text, "s_cramSubChunkCodes")

    dict_encoder = {literal_sym(idx): bits for idx, bits in enumerate(lit_dict_codes)}
    chunk_encoder = {literal_sym(idx): bits for idx, bits in enumerate(lit_chunk_codes)}

    for idx, bits in enumerate(sub_dict_codes):
        dict_encoder[code_sym(idx)] = bits
    for idx, bits in enumerate(sub_chunk_codes):
        chunk_encoder[code_sym(idx)] = bits

    return ExperimentalTables(
        dict_decoder=_build_prefix_decoder(dict_encoder),
        chunk_decoder=_build_prefix_decoder(chunk_encoder),
        dict_encoder=dict_encoder,
        chunk_encoder=chunk_encoder,
    )


def dict_symbol_bits(sym: int) -> str:
    return load_cram_cpp_tables().dict_encoder[sym]


def chunk_symbol_bits(sym: int) -> str:
    return load_cram_cpp_tables().chunk_encoder[sym]


def decode_prefixed_symbol(bits: str, decoder: PrefixDecoder) -> tuple[int, int]:
    for length in decoder.lengths:
        if len(bits) < length:
            continue
        prefix = bits[:length]
        value = decoder.by_length[length].get(prefix)
        if value is not None:
            return value, length
    raise ValueError(f"unable to decode prefix from remaining bits: {bits[:16]!r}")


def decode_prefixed_stream(bits: str, decoder: PrefixDecoder) -> list[int]:
    decoded = []
    pos = 0
    while pos < len(bits):
        value, used = decode_prefixed_symbol(bits[pos:], decoder)
        decoded.append(value)
        pos += used
    return decoded


def resolve_reuse_symbol(token: int, history: list[int]) -> int:
    if sym_is_code(token):
        code_idx = token & 0x0FF
        if REUSE_CODE_START <= code_idx < (REUSE_CODE_START + REUSE_CODE_COUNT):
            distance = code_idx - REUSE_CODE_START + 1
            if len(history) >= distance:
                return history[-distance]
    return token


def apply_reuse(tokens: list[int], seed_history: list[int] | None = None) -> list[int]:
    history = list(seed_history or [])
    resolved: list[int] = []
    for token in tokens:
        resolved_token = resolve_reuse_symbol(token, history)
        history.append(resolved_token)
        resolved.append(resolved_token)
    return resolved


def _best_reuse_token(
    symbol: int,
    history: list[int],
    encoder: dict[int, str],
) -> int:
    best_token = symbol
    best_length = len(encoder[symbol])

    for distance in range(1, REUSE_CODE_COUNT + 1):
        if len(history) < distance or history[-distance] != symbol:
            continue
        candidate = reuse_sym(distance)
        candidate_length = len(encoder[candidate])
        if candidate_length < best_length:
            best_token = candidate
            best_length = candidate_length

    return best_token


def encode_symbols_with_reuse(
    symbols: list[int],
    encoder: dict[int, str],
    *,
    seed_history: list[int] | None = None,
) -> tuple[str, list[int]]:
    history = list(seed_history or [])
    emitted_tokens = []
    emitted_bits = []

    for symbol in symbols:
        token = _best_reuse_token(symbol, history, encoder)
        emitted_tokens.append(token)
        emitted_bits.append(encoder[token])
        history.append(symbol)

    return "".join(emitted_bits), emitted_tokens


def encode_dict_symbols(
    symbols: list[int],
    *,
    seed_history: list[int] | None = None,
) -> tuple[str, list[int]]:
    return encode_symbols_with_reuse(
        symbols,
        load_cram_cpp_tables().dict_encoder,
        seed_history=seed_history,
    )


def encode_chunk_symbols(symbols: list[int]) -> tuple[str, list[int]]:
    return encode_symbols_with_reuse(symbols, load_cram_cpp_tables().chunk_encoder)
