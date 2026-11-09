#!/usr/bin/env python3
"""Analyze coarse output-budget upper bounds for LIFO pending symbols.

This script models two cases:

1. Current design:
   Each LIFO receives its whole compressed-token segment up front.

2. Proposed refill-on-empty design:
   Each LIFO starts empty and, whenever it becomes empty, it accepts at most
   ``LIFO_INPUT_WIDTH`` tokens from a per-segment input buffer.

Definitions:
    W = chunk width (final literal count per chunk)
    L = number of LIFOs
    K = total compressed-token count in the chunk
    I = LIFO_INPUT_WIDTH

The decompressor partitions the K compressed tokens as evenly as possible, so
the largest segment receives exactly ``ceil(K / L)`` tokens.

Every live stack symbol corresponds to at least one future output literal.
Therefore, at every point in time:

    pending_stack_symbols <= remaining_output_literals_for_that_work_item

Using the fact that every compressed token outside the target segment/batch
must still contribute at least one literal, we get conservative bounds:

Current design, conditioned on K:
    current_bound(W, L, K) = W - K + ceil(K / L)

Refill-on-empty design, conditioned on K and I:
    refill_bound(W, L, K, I) = W - K + min(I, ceil(K / L))

Important caveat:
    these expressions ignore top-of-stack ordering, dual-issue behavior, and
    the fact that only a bounded number of expansion-producing symbols can
    appear consecutively before literals must surface. They are useful as quick
    screens, but they are not exact stack-depth bounds for the actual RTL.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from typing import Iterable


def parse_int_list(raw: str) -> list[int]:
    values: list[int] = []
    for piece in raw.split(","):
        piece = piece.strip()
        if not piece:
            continue
        values.append(int(piece))
    return values


def ceil_div(numer: int, denom: int) -> int:
    return (numer + denom - 1) // denom


def max_segment_tokens(total_compressed_tokens: int, lifos: int) -> int:
    return ceil_div(total_compressed_tokens, lifos)


def current_bound(chunk_width: int, lifos: int, total_compressed_tokens: int) -> int:
    return chunk_width - total_compressed_tokens + max_segment_tokens(total_compressed_tokens, lifos)


def refill_bound(
    chunk_width: int,
    lifos: int,
    total_compressed_tokens: int,
    lifo_input_width: int,
) -> int:
    batch_tokens = min(lifo_input_width, max_segment_tokens(total_compressed_tokens, lifos))
    return chunk_width - total_compressed_tokens + batch_tokens


@dataclass(frozen=True)
class BoundRow:
    total_compressed_tokens: int
    segment_token_cap: int
    current_design_bound: int
    refill_bounds: dict[int, int]


def make_rows(
    chunk_width: int,
    lifos: int,
    total_compressed_tokens: Iterable[int],
    lifo_input_widths: list[int],
) -> list[BoundRow]:
    rows: list[BoundRow] = []
    for k in total_compressed_tokens:
        rows.append(
            BoundRow(
                total_compressed_tokens=k,
                segment_token_cap=max_segment_tokens(k, lifos),
                current_design_bound=current_bound(chunk_width, lifos, k),
                refill_bounds={
                    width: refill_bound(chunk_width, lifos, k, width)
                    for width in lifo_input_widths
                },
            )
        )
    return rows


def max_over_range(rows: list[BoundRow], lifo_input_widths: list[int]) -> tuple[int, dict[int, int]]:
    current_max = max(row.current_design_bound for row in rows)
    refill_max = {
        width: max(row.refill_bounds[width] for row in rows)
        for width in lifo_input_widths
    }
    return current_max, refill_max


def choose_sample_points(k_min: int, k_max: int, lifos: int) -> list[int]:
    candidates = {
        k_min,
        k_max,
        max(k_min, k_max - 1),
        max(k_min, k_max - lifos),
        max(k_min, k_max - 2 * lifos),
        max(k_min, (k_min + k_max) // 2),
        max(k_min, lifos),
        max(k_min, 2 * lifos),
    }
    return sorted(candidates, reverse=True)


def render_table(rows: list[BoundRow], lifo_input_widths: list[int]) -> str:
    headers = [
        "K",
        "seg_cap",
        "current",
        *[f"refill_I{width}" for width in lifo_input_widths],
    ]

    body: list[list[str]] = []
    for row in rows:
        body.append(
            [
                str(row.total_compressed_tokens),
                str(row.segment_token_cap),
                str(row.current_design_bound),
                *[str(row.refill_bounds[width]) for width in lifo_input_widths],
            ]
        )

    widths = [
        max(len(header), *(len(line[idx]) for line in body)) if body else len(header)
        for idx, header in enumerate(headers)
    ]

    lines = [
        "  ".join(header.ljust(widths[idx]) for idx, header in enumerate(headers)),
        "  ".join("-" * width for width in widths),
    ]
    for line in body:
        lines.append("  ".join(cell.ljust(widths[idx]) for idx, cell in enumerate(line)))
    return "\n".join(lines)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chunk-width", type=int, default=256, help="Final literal count per chunk")
    parser.add_argument("--lifos", type=int, default=8, help="Number of decompressor LIFOs")
    parser.add_argument(
        "--input-widths",
        type=str,
        default="4,8,10,16,32",
        help="Comma-separated LIFO refill widths to evaluate",
    )
    parser.add_argument(
        "--compressed-min",
        type=int,
        default=1,
        help="Minimum total compressed-token count K to consider",
    )
    parser.add_argument(
        "--compressed-max",
        type=int,
        default=None,
        help="Maximum total compressed-token count K to consider (default: chunk width)",
    )
    parser.add_argument(
        "--sample-k",
        type=str,
        default="",
        help="Optional comma-separated sample K values for the printed table",
    )
    parser.add_argument(
        "--show-all",
        action="store_true",
        help="Print every K in the selected range instead of representative samples",
    )
    parser.add_argument(
        "--emit-const",
        type=int,
        default=None,
        metavar="I",
        help=(
            "Print only the coarse refill-on-empty upper bound for "
            "LIFO_INPUT_WIDTH=I over the selected K range"
        ),
    )
    return parser


def main() -> int:
    args = build_arg_parser().parse_args()

    chunk_width = args.chunk_width
    lifos = args.lifos
    input_widths = sorted(set(parse_int_list(args.input_widths)))
    compressed_min = args.compressed_min
    compressed_max = args.compressed_max if args.compressed_max is not None else chunk_width

    if chunk_width <= 0:
        raise SystemExit("--chunk-width must be positive")
    if lifos <= 0:
        raise SystemExit("--lifos must be positive")
    if compressed_min <= 0:
        raise SystemExit("--compressed-min must be positive")
    if compressed_max < compressed_min:
        raise SystemExit("--compressed-max must be >= --compressed-min")
    if compressed_max > chunk_width:
        raise SystemExit("--compressed-max must be <= --chunk-width")
    if any(width <= 0 for width in input_widths):
        raise SystemExit("--input-widths must all be positive")

    if args.emit_const is not None:
        emit_width = args.emit_const
        if emit_width <= 0:
            raise SystemExit("--emit-const expects a positive LIFO_INPUT_WIDTH")
        worst_case = refill_bound(chunk_width, lifos, compressed_min, emit_width)
        print(worst_case)
        return 0

    k_values = list(range(compressed_min, compressed_max + 1))
    full_rows = make_rows(chunk_width, lifos, k_values, input_widths)
    current_max, refill_max = max_over_range(full_rows, input_widths)

    print("LIFO output-budget upper-bound analysis")
    print(f"  chunk_width            = {chunk_width}")
    print(f"  lifos                  = {lifos}")
    print(f"  compressed_tokens K    = [{compressed_min}, {compressed_max}]")
    print()
    print("Conservative pending-symbol upper bounds over the selected K range")
    print(f"  current design         = {current_max}")
    for width in input_widths:
        print(f"  refill-on-empty I={width:<3} = {refill_max[width]}")
    print()

    if compressed_min == 1:
        print(
            "Note: because K is allowed to reach 1 here, this coarse upper bound "
            "reaches the full chunk width for both designs."
        )
        print()

    print(
        "Note: these are not exact RTL stack-depth bounds; they ignore the "
        "forced literal-drain behavior caused by LIFO ordering."
    )
    print()

    if args.show_all:
        table_rows = full_rows
    else:
        if args.sample_k:
            sample_k = parse_int_list(args.sample_k)
        else:
            sample_k = choose_sample_points(compressed_min, compressed_max, lifos)
        sample_k = [k for k in sample_k if compressed_min <= k <= compressed_max]
        table_rows = make_rows(chunk_width, lifos, sample_k, input_widths)

    print(render_table(table_rows, input_widths))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
