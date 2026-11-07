#!/usr/bin/env python3
"""Shared helpers for the C++ CRAM reference used by verification flows."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

from m4_hardware_sim_common import resolve_repo_path


CPP_PAGE_RE = re.compile(
    r"^\[page (?P<page_idx>\d+)/(?P<page_total>\d+)\] "
    r"valid_bytes=(?P<valid_bytes>\d+) "
    r"dict_count=(?P<dict_count>\d+) "
    r"dict_bits=(?P<dict_bits>\d+) "
    r"encoded_bits=(?P<encoded_bits>\d+) "
    r"ratio=(?P<ratio>[0-9.]+)$"
)
CPP_SUMMARY_RE = re.compile(
    r"^\[file summary\] "
    r"input_bytes=(?P<input_bytes>\d+) "
    r"pages=(?P<pages>\d+) "
    r"dict_bits=(?P<dict_bits>\d+) "
    r"encoded_bits=(?P<encoded_bits>\d+) "
    r"ratio=(?P<ratio>[0-9.]+)$"
)
CPP_ROOT_CANDIDATES = (
    Path("reference_cpp/cram_cpp"),
    Path("third_party/cram_cpp"),
)


def resolve_cpp_root(root: Path, cpp_root: Path | None = None) -> Path:
    if cpp_root is not None:
        resolved = resolve_repo_path(root, cpp_root)
        _validate_cpp_root(resolved)
        return resolved

    for candidate in CPP_ROOT_CANDIDATES:
        resolved = (root / candidate).resolve()
        if _is_valid_cpp_root(resolved):
            return resolved

    searched = ", ".join(str((root / candidate).resolve()) for candidate in CPP_ROOT_CANDIDATES)
    raise RuntimeError(
        "unable to locate the CRAM C++ reference sources; searched "
        f"{searched}. Pass --cpp-root to override."
    )


def _is_valid_cpp_root(cpp_root: Path) -> bool:
    return all(
        (cpp_root / name).is_file()
        for name in ("cram_impl.cpp", "cram_impl.h", "cram_tree.cpp", "cram_tree.h", "cram_types.h")
    )


def _validate_cpp_root(cpp_root: Path) -> None:
    if not _is_valid_cpp_root(cpp_root):
        raise RuntimeError(
            "invalid CRAM C++ reference root: "
            f"{cpp_root} (expected cram_impl.cpp/.h, cram_tree.cpp/.h, and cram_types.h)"
        )


def needs_rebuild(output_bin: Path, dependencies: list[Path]) -> bool:
    if not output_bin.exists():
        return True
    output_mtime = output_bin.stat().st_mtime
    return any(path.stat().st_mtime > output_mtime for path in dependencies)


def build_cpp_helper(root: Path, cpp_root: Path, build_dir: Path) -> Path:
    build_dir.mkdir(parents=True, exist_ok=True)
    output_bin = build_dir / "cram_cpp_page_metrics"
    dependencies = [
        root / "tools" / "cram_cpp_page_metrics.cpp",
        cpp_root / "cram_impl.cpp",
        cpp_root / "cram_impl.h",
        cpp_root / "cram_tree.cpp",
        cpp_root / "cram_tree.h",
        cpp_root / "cram_types.h",
    ]
    if needs_rebuild(output_bin, dependencies):
        cmd = [
            "c++",
            "-std=c++17",
            "-O2",
            "-I",
            str(cpp_root),
            str(root / "tools" / "cram_cpp_page_metrics.cpp"),
            str(cpp_root / "cram_tree.cpp"),
            str(cpp_root / "cram_impl.cpp"),
            "-o",
            str(output_bin),
        ]
        subprocess.run(cmd, check=True)
    return output_bin


def parse_cpp_output(stdout: str) -> tuple[list[dict], dict]:
    pages: list[dict] = []
    summary: dict | None = None
    for line in stdout.splitlines():
        stripped = line.strip()
        page_match = CPP_PAGE_RE.match(stripped)
        if page_match:
            info = page_match.groupdict()
            for key in ("page_idx", "page_total", "valid_bytes", "dict_count", "dict_bits", "encoded_bits"):
                info[key] = int(info[key])
            info["ratio"] = float(info["ratio"])
            info["raw_bits"] = info["valid_bytes"] * 8
            pages.append(info)
            continue

        summary_match = CPP_SUMMARY_RE.match(stripped)
        if summary_match:
            summary = summary_match.groupdict()
            for key in ("input_bytes", "pages", "dict_bits", "encoded_bits"):
                summary[key] = int(summary[key])
            summary["ratio"] = float(summary["ratio"])
            summary["raw_bits"] = summary["input_bytes"] * 8

    if summary is None:
        raise RuntimeError("failed to parse C++ reference summary output")
    return pages, summary


def run_cpp_model(
    cpp_bin: Path,
    input_file: Path,
    *,
    pages: int,
    chunk_size: int,
    memory_blocks: int,
    page_bytes: int = 4096,
    runtime_pad: bool = False,
) -> tuple[list[dict], dict]:
    cmd = [
        str(cpp_bin),
        "--input-file",
        str(input_file),
        "--pages",
        str(max(pages, 0)),
        "--page-bytes",
        str(page_bytes),
        "--chunk-size",
        str(chunk_size),
        "--memory-blocks",
        str(memory_blocks),
    ]
    if runtime_pad:
        cmd.append("--runtime-pad")
    completed = subprocess.run(cmd, check=True, text=True, capture_output=True)
    return parse_cpp_output(completed.stdout)
