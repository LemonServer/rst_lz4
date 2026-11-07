#!/usr/bin/env python3
"""Remove simple per-signal SAIF subtrees by exact signal name.

This is intended for activity-cleanup cases such as stripping a top-level clock
signal that vcd2saif annotated with an unusable toggle rate.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Remove exact-name SAIF signal subtrees from a SAIF file."
    )
    parser.add_argument("--input", required=True, type=Path, help="Input SAIF file")
    parser.add_argument("--output", required=True, type=Path, help="Output SAIF file")
    parser.add_argument(
        "--strip-name",
        action="append",
        dest="strip_names",
        default=[],
        help="Exact signal name to remove when it appears as a simple '(name' subtree opener",
    )
    return parser.parse_args()


def paren_delta(line: str) -> int:
    return line.count("(") - line.count(")")


def leading_symbol(line: str) -> str | None:
    stripped = line.strip()
    if not stripped.startswith("("):
        return None
    if ")" in stripped.split(None, 1)[0]:
        return None
    symbol = stripped[1:]
    if not symbol:
        return None
    if any(ch.isspace() or ch in "()" for ch in symbol):
        return None
    return symbol


def filter_saif_lines(lines: list[str], strip_names: set[str]) -> tuple[list[str], dict[str, int]]:
    out: list[str] = []
    skip_depth = 0
    skip_name: str | None = None
    removed: dict[str, int] = {name: 0 for name in sorted(strip_names)}

    for line in lines:
        if skip_depth > 0:
            skip_depth += paren_delta(line)
            if skip_depth <= 0:
                skip_depth = 0
                skip_name = None
            continue

        symbol = leading_symbol(line)
        if symbol is not None and symbol in strip_names:
            skip_name = symbol
            removed[skip_name] += 1
            skip_depth = paren_delta(line)
            if skip_depth <= 0:
                skip_depth = 0
                skip_name = None
            continue

        out.append(line)

    return out, removed


def main() -> int:
    args = parse_args()
    if not args.strip_names:
        raise SystemExit("at least one --strip-name is required")

    lines = args.input.read_text(encoding="utf-8").splitlines(keepends=True)
    filtered, removed = filter_saif_lines(lines, set(args.strip_names))
    args.output.write_text("".join(filtered), encoding="utf-8")

    removed_total = sum(removed.values())
    print(f"Filtered SAIF: {args.input} -> {args.output}")
    print(f"Removed subtrees: {removed_total}")
    for name, count in removed.items():
        print(f"  {name}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
