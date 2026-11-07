#!/usr/bin/env python3
"""Create a clean tarball or zip for the reviewer-facing hardware artifact."""

from __future__ import annotations

import argparse
import fnmatch
import tarfile
import zipfile
from pathlib import Path

from m4_hardware_sim_common import relative_repo_path, repo_root, resolve_repo_member


DEFAULT_SYNTHESIS_RERUN_INCLUDE_ROOTS = (
    "synthesis/SMALL_SIGNOFF_FLOW.md",
    "synthesis/configs/rst_pkg_tiny.sv",
    "synthesis/libs/asap7_db",
    "synthesis/results/parser_smoke_batches/20260402_tiny_m7b2_refresh",
    "synthesis/results/parser_smoke_batches/20260402_tiny_m7b3_assembly",
    "synthesis/scripts/build_signoff_bundle.py",
    "synthesis/scripts/common_setup.tcl",
    "synthesis/scripts/filter_saif.py",
    "synthesis/scripts/inventory_dc_batch.py",
    "synthesis/scripts/power_from_saif.tcl",
    "synthesis/scripts/run_dc_smoke_batch.sh",
    "synthesis/scripts/run_small_signoff_closeout.sh",
    "synthesis/scripts/run_runtime_file_power_capture.sh",
    "synthesis/scripts/synth_parser_smoke.tcl",
)

DEFAULT_INCLUDE_ROOTS = (
    "README.md",
    "compressor",
    "data/README.md",
    "data/dacapo_avrora_rand1k",
    "decompressor",
    "docs/HARDWARE_SIMULATION.md",
    "docs/rst_status_memo_2026-04-04.md",
    "evidence",
    "experimental",
    "helpful_files/cram_cpp_vendor.py",
    "helpful_files/new_hardware_sim_compressor.py",
    "helpful_files/rst_compressor_experimental.py",
    "helpful_files/rst_decompressor_experimental.py",
    "helpful_files/rst_decompressor_golden.py",
    "helpful_files/rst_experimental_format.py",
    *DEFAULT_SYNTHESIS_RERUN_INCLUDE_ROOTS,
    "third_party/cram_cpp",
    "tools",
)

DEFAULT_TOP_LEVEL_GLOBS = (
    "*.f",
    "*.sv",
)

EXCLUDED_TOP_LEVEL = frozenset(
    {
        ".git",
        "build",
        "dist",
    }
)

EXCLUDED_NAMES = frozenset(
    {
        ".DS_Store",
    }
)

EXCLUDED_GLOBS = (
    "obj_dir*",
    "simv*",
    "*.pyc",
    "*.vcd",
    "*.fst",
    "*.vpd",
    "*.swp",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a clean reviewer-facing artifact tarball or zip from repo root."
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("dist"),
        help="Directory for the generated archive",
    )
    parser.add_argument(
        "--name",
        default=None,
        help="Archive base name (default: <repo>_hardware_sim_artifact)",
    )
    parser.add_argument(
        "--format",
        choices=("tar.gz", "zip"),
        default="tar.gz",
        help="Archive format",
    )
    parser.add_argument(
        "--include-root",
        action="append",
        default=[],
        help=(
            "Additional repo-relative file or directory to include. "
            "Use this to opt in extra data or synced evidence."
        ),
    )
    parser.add_argument(
        "--exclude-path",
        action="append",
        default=[],
        help="Repo-relative path prefix to exclude after includes are collected (repeatable).",
    )
    parser.add_argument(
        "--exclude-glob",
        action="append",
        default=[],
        help="Additional glob pattern to exclude after includes are collected (repeatable).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the bundle summary without writing an archive.",
    )
    return parser.parse_args()


def should_skip(relative: Path, excluded_prefixes: tuple[str, ...], excluded_globs: tuple[str, ...]) -> bool:
    relative_text = relative.as_posix()
    if relative.parts and relative.parts[0] in EXCLUDED_TOP_LEVEL:
        return True
    if any(relative_text == prefix or relative_text.startswith(f"{prefix}/") for prefix in excluded_prefixes):
        return True
    if any(part == "__pycache__" for part in relative.parts):
        return True
    if relative.name in EXCLUDED_NAMES:
        return True
    return any(
        fnmatch.fnmatch(relative.name, pattern) or fnmatch.fnmatch(relative_text, pattern)
        for pattern in excluded_globs
    )


def normalize_prefixes(prefixes: list[str]) -> tuple[str, ...]:
    normalized = []
    for prefix in prefixes:
        cleaned = prefix.strip().strip("/")
        if cleaned:
            normalized.append(cleaned)
    return tuple(sorted(set(normalized)))


def iter_root_files(path: Path) -> list[Path]:
    if path.is_symlink():
        return []
    if path.is_file():
        return [path]
    if not path.is_dir():
        return []
    return [candidate for candidate in sorted(path.rglob("*")) if candidate.is_file() and not candidate.is_symlink()]


def iter_bundle_files(
    root: Path,
    include_roots: tuple[str, ...],
    top_level_globs: tuple[str, ...],
    excluded_prefixes: tuple[str, ...],
    excluded_globs: tuple[str, ...],
) -> list[Path]:
    files_by_relative: dict[str, Path] = {}

    def add_path(path: Path) -> None:
        relative = Path(relative_repo_path(root, path))
        if should_skip(relative, excluded_prefixes, excluded_globs):
            return
        files_by_relative[relative.as_posix()] = path

    for include_root in include_roots:
        resolved = resolve_repo_member(root, Path(include_root), label="bundle include root")
        if not resolved.exists():
            raise RuntimeError(f"bundle include root not found: {include_root}")
        for candidate in iter_root_files(resolved):
            add_path(candidate)

    for pattern in top_level_globs:
        for candidate in sorted(root.glob(pattern)):
            if candidate.is_file() and not candidate.is_symlink():
                add_path(candidate)

    return [files_by_relative[key] for key in sorted(files_by_relative)]


def format_bytes(size_bytes: int) -> str:
    units = ("B", "KiB", "MiB", "GiB")
    size = float(size_bytes)
    for unit in units:
        if size < 1024.0 or unit == units[-1]:
            return f"{size:.1f} {unit}"
        size /= 1024.0
    raise AssertionError("unreachable")


def write_tarball(files: list[Path], root: Path, output_path: Path, bundle_root: str) -> None:
    with tarfile.open(output_path, "w:gz") as archive:
        for path in files:
            relative = path.relative_to(root)
            archive.add(path, arcname=Path(bundle_root) / relative)


def write_zipfile(files: list[Path], root: Path, output_path: Path, bundle_root: str) -> None:
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            relative = path.relative_to(root)
            archive.write(path, arcname=str(Path(bundle_root) / relative))


def main() -> int:
    args = parse_args()
    root = repo_root()
    bundle_root = args.name or f"{root.name}_hardware_sim_artifact"
    output_dir = (root / args.output_dir).resolve() if not args.output_dir.is_absolute() else args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    suffix = ".tar.gz" if args.format == "tar.gz" else ".zip"
    output_path = output_dir / f"{bundle_root}{suffix}"
    include_roots = tuple(dict.fromkeys((*DEFAULT_INCLUDE_ROOTS, *args.include_root)))
    excluded_prefixes = normalize_prefixes(args.exclude_path)
    excluded_globs = tuple((*EXCLUDED_GLOBS, *args.exclude_glob))
    files = iter_bundle_files(
        root,
        include_roots=include_roots,
        top_level_globs=DEFAULT_TOP_LEVEL_GLOBS,
        excluded_prefixes=excluded_prefixes,
        excluded_globs=excluded_globs,
    )
    total_size = sum(path.stat().st_size for path in files)

    if args.dry_run:
        print(f"Dry run: {len(files)} files, {format_bytes(total_size)}")
        print(f"Archive path: {output_path}")
        return 0

    if args.format == "tar.gz":
        write_tarball(files, root, output_path, bundle_root)
    else:
        write_zipfile(files, root, output_path, bundle_root)

    print(f"Wrote {output_path}")
    print(f"Included {len(files)} files")
    print(f"Input payload size {format_bytes(total_size)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
