#!/usr/bin/env python3
"""Shared helpers for the M4 runtime-harness simulation flows."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


DEFAULT_VERILATOR_BIN = shutil.which("verilator") or "/opt/homebrew/bin/verilator"
DEFAULT_DATASET_NAME = "dacapo_avrora_rand1k"
DEFAULT_LOG_DIR = Path("build/hardware_sim/logs")
IGNORED_DATA_SUFFIXES = frozenset({".json", ".md", ".txt"})
RUNTIME_TIER_ALIASES = {
    "tiny": "tiny",
    "small": "tiny",
    "medium": "medium",
    "large": "large",
}

RE_PAGE = re.compile(
    r"^\[page (?P<page_idx>\d+)(?:/(?P<page_total>\d+))?\] "
    r"valid_bytes=(?P<valid_bytes>\d+) "
    r"comp_syms=(?P<comp_syms>\d+) "
    r"dict_count=(?P<dict_count>\d+) "
    r"dict_bits=(?P<dict_bits>\d+) "
    r"raw_bits=(?P<raw_bits>\d+) "
    r"encoded_bits=(?P<encoded_bits>\d+) "
    r"ratio=(?P<ratio>[0-9.]+) "
    r"comp_cycles=(?P<comp_cycles>\d+) "
    r"decomp_cycles=(?P<decomp_cycles>\d+) "
    r"comp_Bpc=(?P<comp_bpc>[0-9.]+) "
    r"decomp_Bpc=(?P<decomp_bpc>[0-9.]+)$"
)

RE_SUMMARY = re.compile(
    r"^\[file summary\] "
    r"input_bytes=(?P<input_bytes>\d+) "
    r"padded_bytes=(?P<padded_bytes>\d+) "
    r"pages=(?P<pages>\d+) "
    r"raw_bits=(?P<raw_bits>\d+) "
    r"encoded_bits=(?P<encoded_bits>\d+) "
    r"ratio=(?P<ratio>[0-9.]+) "
    r"comp_cycles=(?P<comp_cycles>\d+) "
    r"decomp_cycles=(?P<decomp_cycles>\d+) "
    r"total_cycles=(?P<total_cycles>\d+) "
    r"comp_Bpc=(?P<comp_bpc>[0-9.]+) "
    r"decomp_Bpc=(?P<decomp_bpc>[0-9.]+)$"
)


@dataclass(frozen=True)
class LoadedPageInput:
    input_file: Path
    page_width: int
    pages: list[bytes]
    file_bytes: int
    file_pages: int
    selected_bytes: int
    ignored_tail_bytes: int
    file_trailing_bytes: int

    def accounting(self, pages_requested: int) -> dict:
        selected_trailing_bytes = 0
        if self.pages and self.ignored_tail_bytes == 0:
            last_page_bytes = len(self.pages[-1])
            if last_page_bytes < self.page_width:
                selected_trailing_bytes = last_page_bytes

        return {
            "page_width": self.page_width,
            "pages_requested": pages_requested,
            "file_bytes": self.file_bytes,
            "file_pages": self.file_pages,
            "selected_pages": len(self.pages),
            "selected_bytes": self.selected_bytes,
            "ignored_tail_bytes": self.ignored_tail_bytes,
            "file_trailing_bytes": self.file_trailing_bytes,
            "selected_trailing_bytes": selected_trailing_bytes,
            "truncated_by_page_limit": self.ignored_tail_bytes > 0,
        }


@dataclass(frozen=True)
class PageShard:
    shard_idx: int
    shard_count: int
    start_page: int
    pages: list[bytes]

    @property
    def page_count(self) -> int:
        return len(self.pages)

    @property
    def end_page(self) -> int:
        return self.start_page + len(self.pages)


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def resolve_repo_path(root: Path, path: Path) -> Path:
    return path.resolve() if path.is_absolute() else (root / path).resolve()


def relative_repo_path(root: Path, path: Path) -> str:
    resolved_root = root.resolve()
    resolved_path = path.resolve()
    try:
        return resolved_path.relative_to(resolved_root).as_posix() or "."
    except ValueError as exc:
        raise RuntimeError(f"path must stay within the repo root: {resolved_path}") from exc


def resolve_repo_member(root: Path, path: Path, *, label: str) -> Path:
    resolved = resolve_repo_path(root, path)
    try:
        relative_repo_path(root, resolved)
    except RuntimeError as exc:
        raise RuntimeError(f"{label} must stay within the repo root: {resolved}") from exc
    return resolved


def default_data_dir(root: Path | None = None) -> Path:
    base = root or repo_root()
    return (base / "data").resolve()


def default_input_file(root: Path | None = None) -> Path:
    return default_data_dir(root) / DEFAULT_DATASET_NAME


def ensure_parent(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def safe_stem(path: Path) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", path.stem)


def import_page_helpers() -> tuple[int, Callable[[bytes], list[bytes]]]:
    from gen_m4_file_pages import PAGE_WIDTH, page_bytes

    return PAGE_WIDTH, page_bytes


def load_paged_input(root: Path, input_file: Path, pages_requested: int) -> LoadedPageInput:
    if pages_requested < 0:
        raise RuntimeError("--pages must be >= 0")

    resolved_input = resolve_repo_path(root, input_file)
    if not resolved_input.is_file():
        try:
            display_input = relative_repo_path(root, resolved_input)
        except RuntimeError:
            display_input = str(resolved_input)
        raise RuntimeError(f"input file not found: {display_input}")
    page_width, page_bytes_fn = import_page_helpers()
    data = resolved_input.read_bytes()
    all_pages = page_bytes_fn(data)
    pages = all_pages[:pages_requested] if pages_requested > 0 else all_pages
    selected_bytes = sum(len(page) for page in pages)

    return LoadedPageInput(
        input_file=resolved_input,
        page_width=page_width,
        pages=pages,
        file_bytes=len(data),
        file_pages=len(all_pages),
        selected_bytes=selected_bytes,
        ignored_tail_bytes=max(len(data) - selected_bytes, 0),
        file_trailing_bytes=len(data) % page_width,
    )


def shard_page_inputs(raw_pages: list[bytes], shard_count: int) -> list[PageShard]:
    if shard_count < 1:
        raise RuntimeError("shard_count must be >= 1")
    if not raw_pages:
        return []

    actual_shards = min(shard_count, len(raw_pages))
    base_pages, remainder = divmod(len(raw_pages), actual_shards)

    shards: list[PageShard] = []
    start_page = 0
    for shard_idx in range(actual_shards):
        page_count = base_pages + (1 if shard_idx < remainder else 0)
        shard_pages = raw_pages[start_page:start_page + page_count]
        shards.append(
            PageShard(
                shard_idx=shard_idx,
                shard_count=actual_shards,
                start_page=start_page,
                pages=shard_pages,
            )
        )
        start_page += page_count
    return shards


def discover_data_inputs(root: Path, data_dir: Path) -> list[Path]:
    resolved_dir = resolve_repo_path(root, data_dir)
    if not resolved_dir.is_dir():
        try:
            display_dir = relative_repo_path(root, resolved_dir)
        except RuntimeError:
            display_dir = str(resolved_dir)
        raise RuntimeError(f"data directory not found: {display_dir}")

    inputs = [
        path
        for path in sorted(resolved_dir.rglob("*"))
        if path.is_file()
        and not path.name.startswith(".")
        and path.suffix.lower() not in IGNORED_DATA_SUFFIXES
    ]
    if not inputs:
        try:
            display_dir = relative_repo_path(root, resolved_dir)
        except RuntimeError:
            display_dir = str(resolved_dir)
        raise RuntimeError(f"no dump files found in {display_dir}")
    return inputs


def runtime_log_path(log_dir: Path, input_file: Path, tier: str, pages: int, root: Path | None = None) -> Path:
    base = resolve_repo_path(root or repo_root(), log_dir)
    page_suffix = f"{pages}pages" if pages > 0 else "allpages"
    return ensure_parent(base / f"{safe_stem(input_file)}_{page_suffix}_{tier}_m4_runtime.log")


def resolve_runtime_tier(tier: str) -> str:
    try:
        return RUNTIME_TIER_ALIASES[tier]
    except KeyError as exc:
        expected = ", ".join(sorted(RUNTIME_TIER_ALIASES))
        raise RuntimeError(f"unknown runtime tier '{tier}' (expected one of: {expected})") from exc


def run_cmd(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    env.pop("VERILATOR_BIN", None)
    return subprocess.run(
        cmd,
        cwd=cwd,
        check=True,
        text=True,
        capture_output=True,
        env={**env, "LC_ALL": "C", "LANG": "C"},
    )


def run_cmd_streaming(
    cmd: list[str],
    cwd: Path,
    *,
    log_path: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    env.pop("VERILATOR_BIN", None)
    env.update({"LC_ALL": "C", "LANG": "C"})
    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
        env=env,
    )

    output_chunks: list[str] = []
    log_file = ensure_parent(log_path).open("w", encoding="utf-8") if log_path is not None else None
    try:
        assert proc.stdout is not None
        for line in proc.stdout:
            output_chunks.append(line)
            if log_file is not None:
                log_file.write(line)
                log_file.flush()
            print(line, end="", flush=True)
        return_code = proc.wait()
    finally:
        if log_file is not None:
            log_file.close()

    stdout = "".join(output_chunks)
    result = subprocess.CompletedProcess(cmd, return_code, stdout=stdout, stderr="")
    if return_code != 0:
        raise subprocess.CalledProcessError(return_code, cmd, output=stdout, stderr="")
    return result


def is_stale_verilator_cache(exc: subprocess.CalledProcessError) -> bool:
    combined = (exc.stdout or "") + (exc.stderr or "")
    return "precompiled header" in combined and "has been modified since" in combined


def verilator_supports_flag(verilator_bin: str, flag: str) -> bool:
    try:
        help_text = run_cmd([verilator_bin, "--help"], repo_root()).stdout
    except subprocess.CalledProcessError:
        return False
    return flag in help_text


def parse_hardware_log(log_text: str) -> tuple[list[dict], dict]:
    pages: list[dict] = []
    summary: dict | None = None

    for raw_line in log_text.splitlines():
        line = raw_line.strip()
        page_match = RE_PAGE.match(line)
        if page_match:
            page_info = page_match.groupdict()
            for key in (
                "page_idx",
                "valid_bytes",
                "comp_syms",
                "dict_count",
                "dict_bits",
                "raw_bits",
                "encoded_bits",
                "comp_cycles",
                "decomp_cycles",
            ):
                page_info[key] = int(page_info[key])
            if page_info["page_total"] is not None:
                page_info["page_total"] = int(page_info["page_total"])
            for key in ("ratio", "comp_bpc", "decomp_bpc"):
                page_info[key] = float(page_info[key])
            pages.append(page_info)
            continue

        summary_match = RE_SUMMARY.match(line)
        if summary_match:
            summary = summary_match.groupdict()
            for key in (
                "input_bytes",
                "padded_bytes",
                "pages",
                "raw_bits",
                "encoded_bits",
                "comp_cycles",
                "decomp_cycles",
                "total_cycles",
            ):
                summary[key] = int(summary[key])
            for key in ("ratio", "comp_bpc", "decomp_bpc"):
                summary[key] = float(summary[key])

    if summary is None:
        if not pages:
            raise RuntimeError("Did not find any [page ...] or [file summary] lines in hardware output")
        summary = derive_summary_from_pages(pages)

    return pages, summary


def derive_summary_from_pages(pages: list[dict]) -> dict:
    if not pages:
        raise RuntimeError("Runtime harness emitted no [page ...] metrics")

    input_bytes = sum(page["valid_bytes"] for page in pages)
    raw_bits = sum(page["raw_bits"] for page in pages)
    encoded_bits = sum(page["encoded_bits"] for page in pages)
    comp_cycles = sum(page["comp_cycles"] for page in pages)
    decomp_cycles = sum(page["decomp_cycles"] for page in pages)
    page_width_bytes = max(page["raw_bits"] // 8 for page in pages)

    return {
        "input_bytes": input_bytes,
        "padded_bytes": len(pages) * page_width_bytes,
        "pages": len(pages),
        "raw_bits": raw_bits,
        "encoded_bits": encoded_bits,
        "ratio": (raw_bits / encoded_bits) if encoded_bits else 0.0,
        "comp_cycles": comp_cycles,
        "decomp_cycles": decomp_cycles,
        "total_cycles": comp_cycles + decomp_cycles,
        "comp_bpc": (input_bytes / comp_cycles) if comp_cycles else 0.0,
        "decomp_bpc": (input_bytes / decomp_cycles) if decomp_cycles else 0.0,
    }


def build_runtime_harness(
    root: Path,
    *,
    verilator_bin: str = DEFAULT_VERILATOR_BIN,
    build_dir: Path,
    tier: str,
    build_jobs: int,
) -> Path:
    build_dir_path = resolve_repo_path(root, build_dir)
    build_dir_path.mkdir(parents=True, exist_ok=True)
    internal_tier = resolve_runtime_tier(tier)
    macro = f"RST_TIER_{internal_tier.upper()}"
    if internal_tier == "tiny":
        filelist = "tools/runtime_configs/m4_runtime_tiny_filelist.f"
    elif internal_tier == "medium":
        filelist = "tools/runtime_configs/m4_runtime_medium_filelist.f"
    else:
        filelist = "m4_filelist.f"
    verilator_cmd = [
        verilator_bin,
        "-sv",
        "--binary",
        "--build-jobs",
        str(max(build_jobs, 0)),
        "--timing",
        "-Wno-WIDTH",
        "-Wno-LATCH",
        "-Wno-UNOPTFLAT",
        "-Wno-IMPLICITSTATIC",
        f"-D{macro}",
        "--top-module",
        "tb_M4RuntimeFileRoundTripTop",
        "-Mdir",
        str(build_dir_path),
        "-f",
        filelist,
        "m4_runtime_file_roundtrip_tb.sv",
    ]
    if verilator_supports_flag(verilator_bin, "--quiet-build"):
        verilator_cmd.insert(3, "--quiet-build")

    try:
        run_cmd(verilator_cmd, root)
    except subprocess.CalledProcessError as exc:
        if not is_stale_verilator_cache(exc):
            raise
        shutil.rmtree(build_dir_path, ignore_errors=True)
        run_cmd(verilator_cmd, root)

    return build_dir_path / "Vtb_M4RuntimeFileRoundTripTop"


def run_runtime_harness(
    root: Path,
    *,
    run_bin: Path,
    input_file: Path,
    pages: int,
    log_path: Path | None = None,
    expect_pages: bool = True,
    vcd_out: Path | None = None,
) -> str:
    input_path = input_file.resolve()
    run_cmdline = [
        str(run_bin.resolve()),
        f"+INPUT_FILE={input_path}",
    ]
    if pages >= 0:
        run_cmdline.append(f"+MAX_PAGES={pages}")
        if expect_pages and pages > 0:
            run_cmdline.append(f"+EXPECT_PAGES={pages}")
    if vcd_out is not None:
        run_cmdline.append(f"+VCD_FILE={vcd_out.resolve()}")

    try:
        run = run_cmd(run_cmdline, root)
    except subprocess.CalledProcessError as exc:
        if log_path is not None and exc.stdout:
            ensure_parent(log_path).write_text(exc.stdout, encoding="utf-8")
        raise

    if log_path is not None:
        ensure_parent(log_path).write_text(run.stdout, encoding="utf-8")
    return run.stdout
