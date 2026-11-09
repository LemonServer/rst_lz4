#!/usr/bin/env python3
"""Resolve and validate the vendored cram_cpp reference subset."""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
VENDORED_CRAM_CPP_RELATIVE_ROOT = Path("third_party") / "cram_cpp"
REQUIRED_CRAM_CPP_RELATIVE_PATHS = (
    Path("cram_impl.cpp"),
    Path("cram_impl.h"),
    Path("cram_tree.cpp"),
    Path("cram_tree.h"),
    Path("cram_types.h"),
    Path("tsl/robin_growth_policy.h"),
    Path("tsl/robin_hash.h"),
    Path("tsl/robin_map.h"),
)


def required_cram_cpp_files(root: Path) -> tuple[Path, ...]:
    resolved_root = root.resolve()
    return tuple(resolved_root / relative for relative in REQUIRED_CRAM_CPP_RELATIVE_PATHS)


def validate_cram_cpp_root(root: Path) -> Path:
    resolved_root = root.resolve()
    missing = [
        path.relative_to(resolved_root).as_posix()
        for path in required_cram_cpp_files(resolved_root)
        if not path.is_file()
    ]
    if missing:
        raise FileNotFoundError(
            f"incomplete cram_cpp reference under {resolved_root}; "
            f"missing: {', '.join(missing)}"
        )
    return resolved_root


def vendored_cram_cpp_root(repo_root: Path = REPO_ROOT) -> Path:
    return validate_cram_cpp_root(repo_root.resolve() / VENDORED_CRAM_CPP_RELATIVE_ROOT)
