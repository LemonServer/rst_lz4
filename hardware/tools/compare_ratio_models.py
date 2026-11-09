#!/usr/bin/env python3
"""Compare baseline Python, ratio-aligned Python, and cram_cpp on real pages."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
HELPFUL_DIR = ROOT / "helpful_files"
sys.path.insert(0, str(HELPFUL_DIR))
sys.path.insert(0, str(ROOT / "tools"))

import rst_compressor_experimental as ratio_aligned_model
import rst_compressor_golden as baseline_model
from cram_cpp_vendor import vendored_cram_cpp_root
from gen_m4_file_pages import page_bytes
from rst_cpp_reference import build_cpp_helper, resolve_cpp_root, run_cpp_model


BASELINE_CONFIG = {
    "memory_blocks": 2,
    "chunk_size": 256,
    "apply_free_substitutions": False,
    "static_tree_codes_per_cycle": 0,
    "min_cycles_per_iteration": 16,
    "seq_len_2": {"banks": 6, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
    "seq_len_3": {"banks": 7, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
    "seq_len_4": {"banks": 9, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
    "seq_len_5": {"banks": 10, "sets_per_bank": 16, "ways": 4, "fifo_size": 64},
}

EXPERIMENTAL_CONFIG = {
    "memory_blocks": 2,
    "chunk_size": 256,
    "static_tree_codes_per_cycle": 0,
    "min_cycles_per_iteration": 16,
}

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare the baseline Python model, the ratio-aligned Python model, and cram_cpp."
    )
    parser.add_argument(
        "input_files",
        nargs="*",
        type=Path,
        help="Input files to compare. Defaults to data/dacapo_avrora_rand1k",
    )
    parser.add_argument(
        "--pages",
        type=int,
        default=16,
        help="Pages per input file to compare (0 = all pages)",
    )
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=256,
        help="Chunk size for both Python and cram_cpp runs",
    )
    parser.add_argument(
        "--memory-blocks",
        type=int,
        default=2,
        help="Dictionary memory blocks for all models",
    )
    parser.add_argument(
        "--cpp-root",
        type=Path,
        default=vendored_cram_cpp_root(),
        help="Path to the vendored cram_cpp helper sources",
    )
    parser.add_argument(
        "--cpp-build-dir",
        type=Path,
        default=ROOT / "build" / "ratio_alignment",
        help="Directory used to build the local cram_cpp helper",
    )
    parser.add_argument(
        "--write-json",
        type=Path,
        help="Optional path to write the full comparison result as JSON",
    )
    parser.add_argument(
        "--show-pages",
        action="store_true",
        help="Print per-page deltas in addition to per-file summaries",
    )
    return parser.parse_args()


def default_inputs() -> list[Path]:
    return [ROOT / "data" / "dacapo_avrora_rand1k"]


def normalize_inputs(args: argparse.Namespace) -> list[Path]:
    inputs = args.input_files or default_inputs()
    return [path.resolve() for path in inputs]


def load_pages_from_file(input_file: Path, max_pages: int) -> list[bytes]:
    pages = page_bytes(input_file.read_bytes())
    if max_pages > 0:
        pages = pages[:max_pages]
    if not pages:
        raise RuntimeError(f"no pages produced from {input_file}")
    return pages


def summarize_pages(pages: list[dict]) -> dict:
    raw_bits = sum(page["raw_bits"] for page in pages)
    encoded_bits = sum(page["encoded_bits"] for page in pages)
    dict_bits = sum(page["dict_bits"] for page in pages)
    return {
        "pages": len(pages),
        "raw_bits": raw_bits,
        "encoded_bits": encoded_bits,
        "dict_bits": dict_bits,
        "ratio": (raw_bits / encoded_bits) if encoded_bits else 0.0,
    }


def run_python_model(module, pages: list[bytes], config: dict) -> tuple[list[dict], dict]:
    page_results = []
    for page_idx, page in enumerate(pages, start=1):
        _result, cycles, details = module.cram_encode(page, config, return_details=True)
        page_results.append(
            {
                "page_idx": page_idx,
                "valid_bytes": len(page),
                "raw_bits": len(page) * 8,
                "dict_count": details.dict_count,
                "dict_bits": details.dict_bits,
                "encoded_bits": details.encoded_bits,
                "ratio": (len(page) * 8) / details.encoded_bits if details.encoded_bits else 0.0,
                "cycles": cycles,
                "details": asdict(details),
            }
        )
    return page_results, summarize_pages(page_results)


def model_delta_pct(model_encoded_bits: int, cpp_encoded_bits: int) -> float:
    return ((model_encoded_bits - cpp_encoded_bits) / cpp_encoded_bits * 100.0) if cpp_encoded_bits else 0.0


def main() -> int:
    args = parse_args()
    input_files = normalize_inputs(args)
    cpp_root = resolve_cpp_root(ROOT, args.cpp_root)
    cpp_bin = build_cpp_helper(ROOT, cpp_root, args.cpp_build_dir.resolve())

    baseline_config = dict(BASELINE_CONFIG)
    baseline_config["chunk_size"] = args.chunk_size
    baseline_config["memory_blocks"] = args.memory_blocks

    experimental_config = dict(EXPERIMENTAL_CONFIG)
    experimental_config["chunk_size"] = args.chunk_size
    experimental_config["memory_blocks"] = args.memory_blocks

    file_results = []
    overall = {
        "baseline": {"raw_bits": 0, "encoded_bits": 0, "dict_bits": 0},
        "experimental": {"raw_bits": 0, "encoded_bits": 0, "dict_bits": 0},
        "cpp": {"raw_bits": 0, "encoded_bits": 0, "dict_bits": 0},
    }

    for input_file in input_files:
        pages = load_pages_from_file(input_file, args.pages)
        baseline_pages, baseline_summary = run_python_model(baseline_model, pages, baseline_config)
        experimental_pages, experimental_summary = run_python_model(
            ratio_aligned_model,
            pages,
            experimental_config,
        )
        cpp_pages, cpp_summary = run_cpp_model(
            cpp_bin,
            input_file,
            pages=args.pages,
            chunk_size=args.chunk_size,
            memory_blocks=args.memory_blocks,
        )

        if len(cpp_pages) != len(pages):
            raise RuntimeError(
                f"cram_cpp processed {len(cpp_pages)} pages for {input_file}, expected {len(pages)}"
            )

        for model_name, summary in (
            ("baseline", baseline_summary),
            ("experimental", experimental_summary),
            ("cpp", cpp_summary),
        ):
            overall[model_name]["raw_bits"] += summary["raw_bits"] if "raw_bits" in summary else summary["input_bytes"] * 8
            overall[model_name]["encoded_bits"] += summary["encoded_bits"]
            overall[model_name]["dict_bits"] += summary["dict_bits"]

        per_page = []
        for baseline_page, experimental_page, cpp_page in zip(baseline_pages, experimental_pages, cpp_pages):
            per_page.append(
                {
                    "page_idx": baseline_page["page_idx"],
                    "baseline_encoded_bits": baseline_page["encoded_bits"],
                    "experimental_encoded_bits": experimental_page["encoded_bits"],
                    "cpp_encoded_bits": cpp_page["encoded_bits"],
                    "baseline_delta_pct_vs_cpp": model_delta_pct(
                        baseline_page["encoded_bits"], cpp_page["encoded_bits"]
                    ),
                    "experimental_delta_pct_vs_cpp": model_delta_pct(
                        experimental_page["encoded_bits"], cpp_page["encoded_bits"]
                    ),
                }
            )

        result = {
            "input_file": str(input_file),
            "pages": len(pages),
            "baseline": baseline_summary,
            "experimental": experimental_summary,
            "cpp": {
                "pages": cpp_summary["pages"],
                "raw_bits": cpp_summary["input_bytes"] * 8,
                "encoded_bits": cpp_summary["encoded_bits"],
                "dict_bits": cpp_summary["dict_bits"],
                "ratio": cpp_summary["ratio"],
            },
            "baseline_delta_pct_vs_cpp": model_delta_pct(
                baseline_summary["encoded_bits"], cpp_summary["encoded_bits"]
            ),
            "experimental_delta_pct_vs_cpp": model_delta_pct(
                experimental_summary["encoded_bits"], cpp_summary["encoded_bits"]
            ),
            "per_page": per_page,
        }
        file_results.append(result)

    overall_summary = {}
    for model_name, metrics in overall.items():
        raw_bits = metrics["raw_bits"]
        encoded_bits = metrics["encoded_bits"]
        overall_summary[model_name] = {
            **metrics,
            "ratio": (raw_bits / encoded_bits) if encoded_bits else 0.0,
        }
    overall_summary["baseline_delta_pct_vs_cpp"] = model_delta_pct(
        overall_summary["baseline"]["encoded_bits"],
        overall_summary["cpp"]["encoded_bits"],
    )
    overall_summary["experimental_delta_pct_vs_cpp"] = model_delta_pct(
        overall_summary["experimental"]["encoded_bits"],
        overall_summary["cpp"]["encoded_bits"],
    )

    output = {
        "chunk_size": args.chunk_size,
        "memory_blocks": args.memory_blocks,
        "pages_per_file": args.pages,
        "cpp_root": str(cpp_root),
        "cpp_bin": str(cpp_bin),
        "files": file_results,
        "overall": overall_summary,
    }

    if args.write_json is not None:
        args.write_json.write_text(json.dumps(output, indent=2), encoding="utf-8")

    print(
        f"Compared {len(file_results)} file(s), chunk_size={args.chunk_size}, "
        f"memory_blocks={args.memory_blocks}, pages_per_file={args.pages}"
    )
    for result in file_results:
        print(f"\n{Path(result['input_file']).name}")
        print(
            f"  baseline      ratio={result['baseline']['ratio']:.4f} "
            f"encoded_bits={result['baseline']['encoded_bits']} "
            f"delta_vs_cpp={result['baseline_delta_pct_vs_cpp']:+.2f}%"
        )
        print(
            f"  experimental  ratio={result['experimental']['ratio']:.4f} "
            f"encoded_bits={result['experimental']['encoded_bits']} "
            f"delta_vs_cpp={result['experimental_delta_pct_vs_cpp']:+.2f}%"
        )
        print(
            f"  cram_cpp      ratio={result['cpp']['ratio']:.4f} "
            f"encoded_bits={result['cpp']['encoded_bits']}"
        )
        if args.show_pages:
            for page in result["per_page"]:
                print(
                    f"    page {page['page_idx']:>2}: "
                    f"baseline={page['baseline_delta_pct_vs_cpp']:+.2f}% "
                    f"experimental={page['experimental_delta_pct_vs_cpp']:+.2f}%"
                )

    print("\nOverall")
    print(
        f"  baseline      ratio={overall_summary['baseline']['ratio']:.4f} "
        f"encoded_bits={overall_summary['baseline']['encoded_bits']} "
        f"delta_vs_cpp={overall_summary['baseline_delta_pct_vs_cpp']:+.2f}%"
    )
    print(
        f"  experimental  ratio={overall_summary['experimental']['ratio']:.4f} "
        f"encoded_bits={overall_summary['experimental']['encoded_bits']} "
        f"delta_vs_cpp={overall_summary['experimental_delta_pct_vs_cpp']:+.2f}%"
    )
    print(
        f"  cram_cpp      ratio={overall_summary['cpp']['ratio']:.4f} "
        f"encoded_bits={overall_summary['cpp']['encoded_bits']}"
    )
    if args.write_json is not None:
        print(f"\nJSON summary: {args.write_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
