#!/usr/bin/env python3
"""Validate the richer SV decompressor against reference-formatted Python pages."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from m4_hardware_sim_common import (
    DEFAULT_VERILATOR_BIN,
    PageShard,
    default_input_file,
    load_paged_input,
    repo_root,
    resolve_repo_path,
    shard_page_inputs,
    verilator_supports_flag,
)


EXPERIMENTAL_CONFIG = {
    "memory_blocks": 2,
    "chunk_size": 256,
    "static_tree_codes_per_cycle": 0,
    "min_cycles_per_iteration": 16,
}

TIER_MACROS = {
    "tiny": "RST_TIER_TINY",
    "small": "RST_TIER_SMALL",
    "medium": "RST_TIER_MEDIUM",
    "large": "RST_TIER_LARGE",
}

DICT_BITS_MAX = 1024
CHUNK_BITS_MAX = 2560
PAGE_WIDTH = 4096
PAGE_CHUNKS = 16


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the richer SV decompressor against reference-formatted Python pages."
    )
    parser.add_argument(
        "input_file",
        nargs="?",
        type=Path,
        help="Input file to page (default: data/dacapo_avrora_rand1k)",
    )
    parser.add_argument(
        "--pages",
        type=int,
        default=4,
        help="Number of pages to validate (0 = all pages from the file)",
    )
    parser.add_argument(
        "--tier",
        choices=sorted(TIER_MACROS),
        default="large",
        help="RST tier macro used for the SV build",
    )
    parser.add_argument(
        "--verilator-bin",
        default=DEFAULT_VERILATOR_BIN,
        help="Path to the Verilator binary",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=Path("build/verilator/rst_verify_decompressor"),
        help="Directory for the compiled simulation harness and generated stimuli",
    )
    parser.add_argument(
        "--write-json",
        type=Path,
        help="Optional JSON summary output path",
    )
    return parser.parse_args()


def import_helpers(root: Path):
    sys.path.insert(0, str(root / "helpful_files"))
    sys.path.insert(0, str(root / "tools"))

    import rst_compressor_experimental as experimental_compressor
    import rst_decompressor_experimental as experimental_decompressor
    import rst_decompressor_golden as golden
    from gen_m4_file_pages import page_bytes

    return experimental_compressor, experimental_decompressor, golden, page_bytes


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


def pack_bitstring(bitstring: str, width: int) -> str:
    if len(bitstring) > width:
        raise ValueError(f"bitstring width overflow: len={len(bitstring)} width={width}")
    if width % 4 != 0:
        raise ValueError(f"expected nibble-aligned width, got {width}")
    padded = bitstring.ljust(width, "0")
    return format(int(padded, 2) if padded else 0, f"0{width // 4}x")


def write_stimulus(
    path: Path,
    *,
    dict_bitstring: str,
    chunk_bitstrings: list[str],
) -> None:
    if len(chunk_bitstrings) != PAGE_CHUNKS:
        raise ValueError(f"expected {PAGE_CHUNKS} chunks, got {len(chunk_bitstrings)}")

    lines = [
        str(len(dict_bitstring)),
        pack_bitstring(dict_bitstring, DICT_BITS_MAX),
    ]
    for chunk_bits in chunk_bitstrings:
        lines.append(str(len(chunk_bits)))
        lines.append(pack_bitstring(chunk_bits, CHUNK_BITS_MAX))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_expected_page(path: Path, expected_page: list[int]) -> None:
    if len(expected_page) != PAGE_WIDTH:
        raise ValueError(f"expected {PAGE_WIDTH} page symbols, got {len(expected_page)}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(f"{sym & 0xff:02x}" for sym in expected_page) + "\n", encoding="utf-8")


def build_sim_binary(
    root: Path,
    build_dir: Path,
    tier: str,
    verilator_bin: str,
    build_jobs: int = 0,
    verilate_jobs: int = 0,
) -> Path:
    macro = TIER_MACROS[tier]
    build_dir.mkdir(parents=True, exist_ok=True)
    output_path = build_dir / "Vtb_ExperimentalPageDecompressorTop"
    cmd = [
        verilator_bin,
        "-sv",
        "--binary",
        "--timing",
        "--build-jobs",
        str(max(build_jobs, 0)),
        "--verilate-jobs",
        str(max(verilate_jobs, 0)),
        "-Wno-WIDTH",
        "-Wno-LATCH",
        "-Wno-UNOPTFLAT",
        "-Wno-IMPLICITSTATIC",
        "-Wno-WIDTHCONCAT",
        f"-D{macro}",
        "--top-module",
        "tb_ExperimentalPageDecompressorTop",
        "-Mdir",
        str(build_dir),
        "-f",
        "experimental/frozen_large/experimental_decompressor_filelist.f",
        "experimental/frozen_large/decompressor/experimental_page_decompressor_tb.sv",
    ]
    if verilator_supports_flag(verilator_bin, "--quiet-build"):
        cmd.insert(4, "--quiet-build")
    run_cmd(cmd, root)
    return output_path


def run_case(root: Path, sim_bin: Path, stim_path: Path, expected_path: Path) -> str:
    cmd = [
        str(sim_bin),
        f"+STIM_FILE={stim_path.resolve()}",
        f"+EXPECTED_FILE={expected_path.resolve()}",
    ]
    result = run_cmd(cmd, root)
    return result.stdout


def page_artifact_paths(build_dir: Path, page_idx: int, shard: PageShard) -> tuple[Path, Path]:
    if shard.shard_count > 1:
        shard_dir = build_dir / f"shard_{shard.shard_idx + 1:02d}_of_{shard.shard_count:02d}"
        stim_path = shard_dir / "stimuli" / f"page_{page_idx:04d}.txt"
        expected_path = shard_dir / "expected" / f"page_{page_idx:04d}.hex"
    else:
        stim_path = build_dir / "stimuli" / f"page_{page_idx:04d}.txt"
        expected_path = build_dir / "expected" / f"page_{page_idx:04d}.hex"
    return stim_path, expected_path


def _run_decompressor_shard(
    *,
    root: Path,
    sim_bin: Path,
    build_dir: Path,
    shard: PageShard,
    experimental_compressor,
    experimental_decompressor,
    golden,
) -> dict:
    page_results = []
    for local_page_idx, raw_page in enumerate(shard.pages):
        page_idx = shard.start_page + local_page_idx
        padded_page = golden.pad_runtime_page(raw_page, page_idx, golden.DEFAULT_LARGE_TIER)
        _encoded, _cycles, details = experimental_compressor.cram_encode(
            bytes(padded_page),
            EXPERIMENTAL_CONFIG,
            return_details=True,
        )
        python_decoded = experimental_decompressor.decompress_experimental_page(details.encoded_page)
        if python_decoded.page_symbols != padded_page:
            raise RuntimeError(f"python reference-format mismatch on page {page_idx}")

        stim_path, expected_path = page_artifact_paths(build_dir, page_idx, shard)
        write_stimulus(
            stim_path,
            dict_bitstring=details.dict_bitstring,
            chunk_bitstrings=details.compressed_chunk_bitstrings,
        )
        write_expected_page(expected_path, padded_page)
        sim_stdout = run_case(root, sim_bin, stim_path, expected_path)
        if "[sv-decompressor] PASS" not in sim_stdout:
            raise RuntimeError(
                f"SV simulator did not report pass for page {page_idx}:\n{sim_stdout}"
            )

        page_results.append(
            {
                "page_idx": page_idx,
                "raw_bytes": len(raw_page),
                "padded_bytes": len(padded_page),
                "dict_count": details.dict_total_entries,
                "added_dict_entries": details.dict_count,
                "dict_bits": len(details.dict_bitstring),
                "chunk_bit_lengths": [len(bits) for bits in details.compressed_chunk_bitstrings],
                "sv_stdout": sim_stdout.strip(),
            }
        )

    return {
        "shard_idx": shard.shard_idx,
        "page_start": shard.start_page,
        "page_end": shard.end_page,
        "page_count": shard.page_count,
        "pages": page_results,
    }


def run_sv_decompressor_check(
    *,
    input_file: Path,
    pages_requested: int,
    root: Path,
    tier: str,
    verilator_bin: str,
    build_dir: Path,
    raw_pages: list[bytes] | None = None,
    sim_bin: Path | None = None,
    page_shards: int = 1,
    verbose: bool = True,
) -> dict:
    experimental_compressor, experimental_decompressor, golden, _page_bytes = import_helpers(root)

    if tier != "large":
        raise RuntimeError("the richer SV decompressor check currently expects the large-tier contract")

    if raw_pages is None:
        loaded = load_paged_input(root, input_file, pages_requested)
        raw_pages = loaded.pages

    build_dir = resolve_repo_path(root, build_dir)
    if sim_bin is None:
        sim_bin = build_sim_binary(root, build_dir, tier, verilator_bin)

    actual_shards = min(max(page_shards, 1), max(len(raw_pages), 1))
    shard_inputs = shard_page_inputs(raw_pages, actual_shards) if raw_pages else []

    if actual_shards == 1 or len(raw_pages) <= 1:
        shard_results = [
            _run_decompressor_shard(
                root=root,
                sim_bin=sim_bin,
                build_dir=build_dir,
                shard=shard_inputs[0] if shard_inputs else PageShard(0, 1, 0, []),
                experimental_compressor=experimental_compressor,
                experimental_decompressor=experimental_decompressor,
                golden=golden,
            )
        ]
    else:
        if verbose:
            print(f"Running decompressor decode across {len(shard_inputs)} page shard(s)...")

        shard_results = []
        with ThreadPoolExecutor(max_workers=len(shard_inputs)) as executor:
            futures = {
                executor.submit(
                    _run_decompressor_shard,
                    root=root,
                    sim_bin=sim_bin,
                    build_dir=build_dir,
                    shard=shard,
                    experimental_compressor=experimental_compressor,
                    experimental_decompressor=experimental_decompressor,
                    golden=golden,
                ): shard
                for shard in shard_inputs
            }
            completed = 0
            for future in as_completed(futures):
                shard_result = future.result()
                completed += 1
                if verbose:
                    print(
                        f"  [decompressor shard {completed}/{len(shard_inputs)} complete] "
                        f"pages={shard_result['page_start'] + 1}-{shard_result['page_end']}"
                    )
                shard_results.append(shard_result)

    shard_results.sort(key=lambda item: item["page_start"])
    page_results = [page for shard_result in shard_results for page in shard_result["pages"]]
    if verbose and page_results:
        for page in page_results:
            print(
                f"[page {page['page_idx'] + 1}/{len(page_results)}] "
                f"dict_total={page['dict_count']} "
                f"dict_bits={page['dict_bits']} "
                f"status=PASS"
            )

    summary = {
        "status": "PASS",
        "input_file": str(input_file),
        "pages": page_results,
        "page_count": len(page_results),
        "sim_bin": str(sim_bin),
        "build_dir": str(build_dir),
        "shard_count": actual_shards,
        **(
            {
                "shards": [
                    {
                        "shard_idx": shard_result["shard_idx"],
                        "page_start": shard_result["page_start"] + 1,
                        "page_end": shard_result["page_end"],
                        "page_count": shard_result["page_count"],
                    }
                    for shard_result in shard_results
                ]
            }
            if actual_shards > 1
            else {}
        ),
    }
    return summary


def main() -> int:
    args = parse_args()
    root = repo_root()
    input_file = args.input_file.resolve() if args.input_file is not None else default_input_file(root)

    summary = run_sv_decompressor_check(
        input_file=input_file,
        pages_requested=args.pages,
        root=root,
        tier=args.tier,
        verilator_bin=args.verilator_bin,
        build_dir=args.build_dir,
        verbose=True,
    )
    if args.write_json is not None:
        args.write_json.parent.mkdir(parents=True, exist_ok=True)
        args.write_json.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(
        f"[summary] pages={summary['page_count']} sim_bin={summary['sim_bin']} "
        f"build_dir={summary['build_dir']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
