#!/usr/bin/env python3
"""Generate shared static-tree helpers for the experimental SV format path."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "helpful_files"))

from rst_experimental_format import load_cram_cpp_tables


OUTPUT_PATH = ROOT / "experimental" / "experimental_huffman_pkg.sv"


def _case_pattern(bits: str, width: int) -> str:
    suffix = "?" * (width - len(bits))
    return f"{width}'b{bits}{suffix}"


def _emit_decoder_function(name: str, width: int, entries: list[tuple[int, str]]) -> list[str]:
    lines = [
        f"    function automatic huff_decode_t {name}(input logic [{width - 1}:0] window);",
        "        huff_decode_t result;",
        "        begin",
        "            result = '0;",
        "            casez (window)",
    ]
    for sym, bits in sorted(entries, key=lambda item: (len(item[1]), item[1], item[0])):
        lines.extend(
            [
                f"                {_case_pattern(bits, width)}: begin",
                "                    result.valid = 1'b1;",
                f"                    result.used = 4'd{len(bits)};",
                f"                    result.sym = symbol_t'(9'd{sym});",
                "                end",
            ]
        )
    lines.extend(
        [
            "                default: begin",
            "                end",
            "            endcase",
            f"            {name} = result;",
            "        end",
            "    endfunction",
            "",
        ]
    )
    return lines


def _emit_encode_function(name: str, width: int, entries: list[tuple[int, str]]) -> list[str]:
    lines = [
        f"    function automatic huff_code_t {name}(input symbol_t sym);",
        "        huff_code_t result;",
        "        begin",
        "            result = '0;",
        "            case (sym)",
    ]
    for sym, bits in sorted(entries, key=lambda item: item[0]):
        lines.extend(
            [
                f"                symbol_t'(9'd{sym}): begin",
                "                    result.valid = 1'b1;",
                f"                    result.used = 4'd{len(bits)};",
                f"                    result.bits = {width}'b{bits};",
                "                end",
            ]
        )
    lines.extend(
        [
            "                default: begin",
            "                end",
            "            endcase",
            f"            {name} = result;",
            "        end",
            "    endfunction",
            "",
        ]
    )
    return lines


def build_package() -> str:
    tables = load_cram_cpp_tables()
    dict_entries = sorted(tables.dict_encoder.items())
    chunk_entries = sorted(tables.chunk_encoder.items())

    dict_min_len = min(len(bits) for _sym, bits in dict_entries)
    dict_max_len = max(len(bits) for _sym, bits in dict_entries)
    chunk_min_len = min(len(bits) for _sym, bits in chunk_entries)
    chunk_max_len = max(len(bits) for _sym, bits in chunk_entries)
    code_max_len = max(dict_max_len, chunk_max_len)

    lines = [
        "`timescale 1ps / 1ps",
        "`default_nettype none",
        "",
        "package experimental_huffman_pkg;",
        "    import rst_pkg::*;",
        "",
        "    localparam int EXPERIMENTAL_FREE_DICT_ENTRIES = 2;",
        "    localparam int EXPERIMENTAL_REUSE_CODE_START = 63;",
        "    localparam int EXPERIMENTAL_REUSE_CODE_COUNT = 8;",
        f"    localparam int EXPERIMENTAL_CODE_MAX_LEN = {code_max_len};",
        f"    localparam int EXPERIMENTAL_DICT_MIN_CODE_LEN = {dict_min_len};",
        f"    localparam int EXPERIMENTAL_DICT_MAX_CODE_LEN = {dict_max_len};",
        f"    localparam int EXPERIMENTAL_CHUNK_MIN_CODE_LEN = {chunk_min_len};",
        f"    localparam int EXPERIMENTAL_CHUNK_MAX_CODE_LEN = {chunk_max_len};",
        "    localparam int EXPERIMENTAL_DICT_BITS_MAX = DICT_STORAGE_BITS;",
        "    localparam int EXPERIMENTAL_CHUNK_BITS_MAX = CHUNK_WIDTH * EXPERIMENTAL_CHUNK_MAX_CODE_LEN;",
        "    localparam int EXPERIMENTAL_CHUNK_BIT_COUNT_W = $clog2(EXPERIMENTAL_CHUNK_BITS_MAX + 1);",
        "    localparam int EXPERIMENTAL_DICT_MAX_DECODE_TOKENS =",
        "        (EXPERIMENTAL_DICT_BITS_MAX + EXPERIMENTAL_DICT_MIN_CODE_LEN - 1)",
        "        / EXPERIMENTAL_DICT_MIN_CODE_LEN;",
        "    localparam int EXPERIMENTAL_CHUNK_MAX_DECODE_TOKENS =",
        "        (EXPERIMENTAL_CHUNK_BITS_MAX + EXPERIMENTAL_CHUNK_MIN_CODE_LEN - 1)",
        "        / EXPERIMENTAL_CHUNK_MIN_CODE_LEN;",
        "    localparam int EXPERIMENTAL_DICT_RESOLVED_SYMBOLS_MAX = MAX_DICT_ENTRIES * MAX_SEQ_LEN;",
        "",
        "    typedef struct packed {",
        "        logic valid;",
        "        logic [3:0] used;",
        "        symbol_t sym;",
        "    } huff_decode_t;",
        "",
        "    typedef struct packed {",
        "        logic valid;",
        "        logic [3:0] used;",
        "        logic [EXPERIMENTAL_CODE_MAX_LEN - 1:0] bits;",
        "    } huff_code_t;",
        "",
        "    function automatic symbol_t experimental_literal_sym(input int value);",
        "        experimental_literal_sym = symbol_t'(value & 9'h0ff);",
        "    endfunction",
        "",
        "    function automatic symbol_t experimental_code_sym(input int idx);",
        "        experimental_code_sym = symbol_t'(9'h100 | (idx & 9'h0ff));",
        "    endfunction",
        "",
        "    function automatic logic experimental_sym_is_code(input symbol_t sym);",
        "        experimental_sym_is_code = sym[8];",
        "    endfunction",
        "",
        "    function automatic logic experimental_sym_is_reuse(input symbol_t sym);",
        "        int code_idx;",
        "        begin",
        "            code_idx = sym[7:0];",
        "            experimental_sym_is_reuse =",
        "                experimental_sym_is_code(sym)",
        "                && (code_idx >= EXPERIMENTAL_REUSE_CODE_START)",
        "                && (code_idx < (EXPERIMENTAL_REUSE_CODE_START + EXPERIMENTAL_REUSE_CODE_COUNT));",
        "        end",
        "    endfunction",
        "",
        "    function automatic int experimental_reuse_distance(input symbol_t sym);",
        "        experimental_reuse_distance =",
        "            int'(sym[7:0]) - EXPERIMENTAL_REUSE_CODE_START + 1;",
        "    endfunction",
        "",
        "    function automatic symbol_t experimental_reuse_symbol(input int distance);",
        "        experimental_reuse_symbol = experimental_code_sym(",
        "            EXPERIMENTAL_REUSE_CODE_START + distance - 1",
        "        );",
        "    endfunction",
        "",
    ]

    lines.extend(_emit_decoder_function("decode_dict_window", dict_max_len, dict_entries))
    lines.extend(_emit_decoder_function("decode_chunk_window", chunk_max_len, chunk_entries))
    lines.extend(_emit_encode_function("encode_dict_symbol", code_max_len, dict_entries))
    lines.extend(_emit_encode_function("encode_chunk_symbol", code_max_len, chunk_entries))
    lines.extend(
        [
            "    function automatic int experimental_dict_code_length(input symbol_t sym);",
            "        huff_code_t code;",
            "        begin",
            "            code = encode_dict_symbol(sym);",
            "            experimental_dict_code_length = int'(code.used);",
            "        end",
            "    endfunction",
            "",
            "    function automatic int experimental_chunk_code_length(input symbol_t sym);",
            "        huff_code_t code;",
            "        begin",
            "            code = encode_chunk_symbol(sym);",
            "            experimental_chunk_code_length = int'(code.used);",
            "        end",
            "    endfunction",
            "",
        ]
    )
    lines.append("endpackage")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    OUTPUT_PATH.write_text(build_package(), encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
