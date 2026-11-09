#!/usr/bin/env python3
"""Summarize a parser_smoke batch run from its manifest, logs, and reports."""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[2]
BATCHES_ROOT = REPO_ROOT / "synthesis" / "results" / "parser_smoke_batches"


@dataclass
class JobSummary:
    job_id: str
    top: str
    tier: str
    artifact_tier: str
    mode: str
    status: str
    phase: str
    pid: str
    elab_wall_s: float | None
    elab_mem_mb: float | None
    ports: int | None
    regs: int | None
    compile_wall_s: float | None
    design_area: float | None
    comb_area: float | None
    noncomb_area: float | None
    leaf_cells: int | None
    seq_cells: int | None
    crit_path_len: float | None
    crit_slack: float | None
    tns: float | None
    violating_paths: int | None
    dw_blocks: str
    log: str
    output_dir: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize a synthesis/parser-smoke batch run."
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--batch-label",
        help="Batch label under synthesis/results/parser_smoke_batches/",
    )
    group.add_argument(
        "--batch-root",
        type=Path,
        help="Absolute path to a parser_smoke_batches/<label> directory.",
    )
    parser.add_argument(
        "--format",
        choices=("table", "tsv", "json", "summary"),
        default="table",
        help="Output format.",
    )
    parser.add_argument(
        "--running-only",
        action="store_true",
        help="Show only jobs that are still running.",
    )
    parser.add_argument(
        "--write-json",
        type=Path,
        help="Optional path to also write the parsed summary as JSON.",
    )
    return parser.parse_args()


def resolve_batch_root(args: argparse.Namespace) -> Path:
    if args.batch_root is not None:
        return args.batch_root.resolve()
    return (BATCHES_ROOT / args.batch_label).resolve()


def read_batch_metadata(batch_root: Path) -> dict[str, str]:
    metadata_path = batch_root / "batch_metadata.tsv"
    if not metadata_path.exists():
        return {}

    metadata: dict[str, str] = {}
    with metadata_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            key = (row.get("key") or "").strip()
            value = (row.get("value") or "").strip()
            if key:
                metadata[key] = value
    return metadata


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def parse_float(text: str) -> float | None:
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def parse_int(text: str) -> int | None:
    try:
        return int(float(text))
    except (TypeError, ValueError):
        return None


def parse_hms_to_seconds(text: str) -> float | None:
    if not text:
        return None
    match = re.fullmatch(r"(\d+):(\d+):(\d+)", text.strip())
    if not match:
        return None
    hours, minutes, seconds = (int(part) for part in match.groups())
    return float(hours * 3600 + minutes * 60 + seconds)


def pid_is_running(pid_text: str) -> bool:
    pid = parse_int(pid_text)
    if pid is None or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def compact_spaces(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip())


def last_phase_line(log_text: str) -> str:
    interesting_prefixes = (
        "Beginning ",
        "Processing ",
        "Compiling ",
        "Parser smoke complete",
        "Analyze failed",
        "Elaboration failed",
        "Link failed",
        "Error:",
        "Warning:",
        "Current design is",
        "Module:",
        "Loading db file",
    )
    lines = [line.rstrip() for line in log_text.splitlines() if line.strip()]
    for line in reversed(lines):
        stripped = line.strip()
        if stripped.startswith(interesting_prefixes):
            return compact_spaces(stripped)
    return compact_spaces(lines[-1]) if lines else ""


def parse_elab_metrics(log_text: str, top: str) -> dict[str, float | int | None]:
    metrics: dict[str, float | int | None] = {
        "ports": None,
        "regs": None,
        "elab_wall_s": None,
        "elab_mem_mb": None,
    }

    ports_match = re.search(
        rf"Module:\s+{re.escape(top)}\s*,\s*Ports:\s+(\d+)",
        log_text,
    )
    if ports_match:
        metrics["ports"] = int(ports_match.group(1))

    regs_match = re.search(
        rf"Module:\s+{re.escape(top)}\s*,\s*Registers:\s+([\d.]+)",
        log_text,
    )
    if regs_match:
        metrics["regs"] = int(float(regs_match.group(1)))

    elapsed_match = re.search(
        rf"Module:\s+{re.escape(top)}\s*,\s*Elapsed Time:\s+(\d+:\d+:\d+).*?Total Mem:\s+([\d.]+)\s+MB",
        log_text,
    )
    if elapsed_match:
        metrics["elab_wall_s"] = parse_hms_to_seconds(elapsed_match.group(1))
        metrics["elab_mem_mb"] = float(elapsed_match.group(2))

    return metrics


def parse_qor_metrics(qor_path: Path) -> dict[str, float | int | None]:
    metrics: dict[str, float | int | None] = {
        "compile_wall_s": None,
        "design_area": None,
        "comb_area": None,
        "noncomb_area": None,
        "leaf_cells": None,
        "seq_cells": None,
        "crit_path_len": None,
        "crit_slack": None,
        "tns": None,
        "violating_paths": None,
    }
    text = read_text(qor_path)
    if not text:
        return metrics

    patterns: list[tuple[str, str, callable]] = [
        ("compile_wall_s", r"Overall Compile Wall Clock Time:\s+([-\d.]+)", float),
        ("design_area", r"Design Area:\s+([-\d.]+)", float),
        ("comb_area", r"Combinational Area:\s+([-\d.]+)", float),
        ("noncomb_area", r"Noncombinational Area:\s+([-\d.]+)", float),
        ("leaf_cells", r"Leaf Cell Count:\s+([-\d.]+)", parse_int),
        ("seq_cells", r"Sequential Cell Count:\s+([-\d.]+)", parse_int),
        ("crit_path_len", r"Critical Path Length:\s+([-\d.]+)", float),
        ("crit_slack", r"Critical Path Slack:\s+([-\d.]+)", float),
        ("tns", r"Total Negative Slack:\s+([-\d.]+)", float),
        ("violating_paths", r"No\. of Violating Paths:\s+([-\d.]+)", parse_int),
    ]
    for key, pattern, caster in patterns:
        match = re.search(pattern, text)
        if match:
            metrics[key] = caster(match.group(1))
    return metrics


def parse_area_fallback(area_path: Path) -> dict[str, float | int | None]:
    metrics: dict[str, float | int | None] = {
        "design_area": None,
        "comb_area": None,
        "noncomb_area": None,
        "leaf_cells": None,
        "seq_cells": None,
    }
    text = read_text(area_path)
    if not text:
        return metrics

    patterns: list[tuple[str, str, callable]] = [
        ("design_area", r"Total cell area:\s+([-\d.]+)", float),
        ("comb_area", r"Combinational area:\s+([-\d.]+)", float),
        ("noncomb_area", r"Noncombinational area:\s+([-\d.]+)", float),
        ("leaf_cells", r"Number of cells:\s+(\d+)", int),
        ("seq_cells", r"Number of sequential cells:\s+(\d+)", int),
    ]
    for key, pattern, caster in patterns:
        match = re.search(pattern, text)
        if match:
            metrics[key] = caster(match.group(1))
    return metrics


def collect_dw_blocks(log_text: str) -> str:
    matches = sorted(set(re.findall(r"DW[A-Za-z0-9_]+", log_text)))
    if not matches:
        return ""
    preview = matches[:4]
    suffix = ""
    if len(matches) > len(preview):
        suffix = f" +{len(matches) - len(preview)}"
    return ",".join(preview) + suffix


def detect_status(
    *,
    run_compile: bool,
    log_text: str,
    pid_text: str,
    output_dir: Path,
    design_name: str,
) -> str:
    done_markers = [
        "Parser smoke complete for",
        "Thank you...",
    ]
    fail_markers = [
        "Analyze failed for",
        "Elaboration failed for",
        "Link failed for",
        "Compile failed for",
        "Report generation failed for",
        "Write-out failed for",
        "terminated with 1 errors",
        "terminated with 2 errors",
        "terminated with 3 errors",
        "*** Presto compilation terminated",
    ]

    if run_compile:
        if (output_dir / f"{design_name}_qor.rpt").exists():
            return "done"
    elif (output_dir / f"{design_name}_check_design.rpt").exists():
        if any(marker in log_text for marker in done_markers):
            return "done"

    if any(marker in log_text for marker in done_markers):
        return "done"
    if pid_is_running(pid_text):
        return "running"
    if any(marker in log_text for marker in fail_markers):
        return "failed"
    if log_text.strip():
        return "stopped"
    return "missing"


def parse_manifest(manifest_path: Path) -> list[dict[str, str]]:
    with manifest_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return [dict(row) for row in reader]


def rebase_batch_path(batch_root: Path, raw_path: str) -> Path:
    candidate = Path(raw_path)
    if candidate.exists():
        return candidate

    marker = f"/parser_smoke_batches/{batch_root.name}/"
    if marker in raw_path:
        suffix = raw_path.split(marker, 1)[1]
        rebased = batch_root / suffix
        if rebased.exists():
            return rebased

    return candidate


def resolve_artifact_tier(row_tier: str, metadata: dict[str, str] | None = None) -> str:
    if not metadata:
        return row_tier
    public_tier = metadata.get("tier", "").strip()
    internal_tier = metadata.get("internal_tier", "").strip()
    if row_tier == public_tier and internal_tier:
        return internal_tier
    return row_tier


def resolve_output_dir(
    *,
    row: dict[str, str],
    batch_root: Path | None,
    artifact_tier: str,
) -> Path:
    if batch_root is None:
        return Path(row["output_dir"])

    rebased = rebase_batch_path(batch_root, row["output_dir"])
    if rebased.exists():
        return rebased

    # Older "small" manifests recorded the public tier path even though dc_shell
    # wrote artifacts under the internal "tiny" tier directory.
    return batch_root / "results" / f"{row['top']}_{artifact_tier}".lower() / row["job_id"]


def summarize_job(
    row: dict[str, str],
    batch_root: Path | None = None,
    metadata: dict[str, str] | None = None,
) -> JobSummary:
    top = row["top"]
    tier = row["tier"]
    artifact_tier = resolve_artifact_tier(tier, metadata)
    run_compile = row["run_compile"] == "1"
    mode = "compile" if run_compile else "elab"
    if batch_root is None:
        log_path = Path(row["log"])
    else:
        log_path = rebase_batch_path(batch_root, row["log"])
    output_dir = resolve_output_dir(row=row, batch_root=batch_root, artifact_tier=artifact_tier)
    design_name = f"{top}_{artifact_tier}".lower()
    log_text = read_text(log_path)

    status = detect_status(
        run_compile=run_compile,
        log_text=log_text,
        pid_text=row["pid"],
        output_dir=output_dir,
        design_name=design_name,
    )
    phase = last_phase_line(log_text)

    elab = parse_elab_metrics(log_text, top)
    qor = parse_qor_metrics(output_dir / f"{design_name}_qor.rpt")
    if qor["design_area"] is None:
        fallback = parse_area_fallback(output_dir / f"{design_name}_area.rpt")
        for key, value in fallback.items():
            if qor.get(key) is None:
                qor[key] = value

    return JobSummary(
        job_id=row["job_id"],
        top=top,
        tier=tier,
        artifact_tier=artifact_tier,
        mode=mode,
        status=status,
        phase=phase,
        pid=row["pid"],
        elab_wall_s=elab["elab_wall_s"],
        elab_mem_mb=elab["elab_mem_mb"],
        ports=elab["ports"],
        regs=elab["regs"],
        compile_wall_s=qor["compile_wall_s"],
        design_area=qor["design_area"],
        comb_area=qor["comb_area"],
        noncomb_area=qor["noncomb_area"],
        leaf_cells=qor["leaf_cells"],
        seq_cells=qor["seq_cells"],
        crit_path_len=qor["crit_path_len"],
        crit_slack=qor["crit_slack"],
        tns=qor["tns"],
        violating_paths=qor["violating_paths"],
        dw_blocks=collect_dw_blocks(log_text),
        log=str(log_path),
        output_dir=str(output_dir),
    )


def sort_key(job: JobSummary) -> tuple[int, float, float, str]:
    status_rank = {
        "running": 0,
        "failed": 1,
        "stopped": 2,
        "done": 3,
        "missing": 4,
    }.get(job.status, 9)
    wall = -(job.compile_wall_s or 0.0)
    mem = -(job.elab_mem_mb or 0.0)
    return (status_rank, wall, mem, job.job_id)


def fmt_float(value: float | None, digits: int = 1) -> str:
    if value is None or math.isnan(value):
        return ""
    return f"{value:.{digits}f}"


def iter_rows(jobs: Iterable[JobSummary]) -> list[list[str]]:
    rows: list[list[str]] = []
    for job in jobs:
        rows.append(
            [
                job.job_id,
                job.top,
                job.mode,
                job.status,
                fmt_float(job.elab_wall_s, 0),
                fmt_float(job.elab_mem_mb, 0),
                fmt_float(job.compile_wall_s, 0),
                fmt_float(job.design_area, 1),
                fmt_float(job.crit_slack, 1),
                str(job.violating_paths or ""),
                str(job.leaf_cells or ""),
                job.dw_blocks,
                job.phase,
            ]
        )
    return rows


def print_table(jobs: list[JobSummary]) -> None:
    headers = [
        "job_id",
        "top",
        "mode",
        "status",
        "elab_s",
        "elab_mb",
        "compile_s",
        "area",
        "slack",
        "viol",
        "leaf",
        "dw",
        "phase",
    ]
    rows = iter_rows(jobs)
    widths = [len(header) for header in headers]
    for row in rows:
        for idx, cell in enumerate(row):
            widths[idx] = max(widths[idx], len(cell))

    print("Batch inventory")
    print("---------------")
    print("  elab_s/elab_mb come from elaboration logs")
    print("  compile_s/area/slack/viol/leaf come from compiled jobs only")
    print()

    header_line = "  ".join(header.ljust(widths[idx]) for idx, header in enumerate(headers))
    print(header_line)
    print("  ".join("-" * width for width in widths))
    for row in rows:
        print("  ".join(cell.ljust(widths[idx]) for idx, cell in enumerate(row)))


def print_tsv(jobs: list[JobSummary]) -> None:
    writer = csv.writer(sys.stdout, delimiter="\t")
    writer.writerow(
        [
            "job_id",
            "top",
            "mode",
            "status",
            "elab_s",
            "elab_mb",
            "compile_s",
            "area",
            "comb_area",
            "noncomb_area",
            "slack",
            "tns",
            "violating_paths",
            "leaf_cells",
            "seq_cells",
            "ports",
            "regs",
            "dw_blocks",
            "phase",
            "log",
            "output_dir",
        ]
    )
    for job in jobs:
        writer.writerow(
            [
                job.job_id,
                job.top,
                job.mode,
                job.status,
                fmt_float(job.elab_wall_s, 0),
                fmt_float(job.elab_mem_mb, 1),
                fmt_float(job.compile_wall_s, 1),
                fmt_float(job.design_area, 6),
                fmt_float(job.comb_area, 6),
                fmt_float(job.noncomb_area, 6),
                fmt_float(job.crit_slack, 6),
                fmt_float(job.tns, 6),
                job.violating_paths or "",
                job.leaf_cells or "",
                job.seq_cells or "",
                job.ports or "",
                job.regs or "",
                job.dw_blocks,
                job.phase,
                job.log,
                job.output_dir,
            ]
        )


def compute_summary(jobs: list[JobSummary], metadata: dict[str, str]) -> list[tuple[str, str]]:
    total_jobs = len(jobs)
    compile_jobs = [job for job in jobs if job.mode == "compile"]
    done_jobs = [job for job in jobs if job.status == "done"]
    running_jobs = [job for job in jobs if job.status == "running"]
    failed_jobs = [job for job in jobs if job.status == "failed"]
    stopped_jobs = [job for job in jobs if job.status == "stopped"]
    missing_jobs = [job for job in jobs if job.status == "missing"]
    done_compile_jobs = [job for job in compile_jobs if job.status == "done"]

    total_compile_s = sum(job.compile_wall_s or 0.0 for job in done_compile_jobs)
    total_elab_s = sum(job.elab_wall_s or 0.0 for job in jobs)
    max_compile_s = max((job.compile_wall_s or 0.0 for job in done_compile_jobs), default=0.0)

    worst_slack_job = None
    worst_slack = None
    for job in done_compile_jobs:
        if job.crit_slack is None:
            continue
        if worst_slack is None or job.crit_slack < worst_slack:
            worst_slack = job.crit_slack
            worst_slack_job = job

    summary_rows = [
        ("batch_label", metadata.get("batch_label", "")),
        ("launcher", metadata.get("launcher", "")),
        ("profile", metadata.get("profile", "")),
        ("tier", metadata.get("tier", "")),
        ("job_total", str(total_jobs)),
        ("job_done", str(len(done_jobs))),
        ("job_running", str(len(running_jobs))),
        ("job_failed", str(len(failed_jobs))),
        ("job_stopped", str(len(stopped_jobs))),
        ("job_missing", str(len(missing_jobs))),
        ("compile_jobs_done", str(len(done_compile_jobs))),
        ("compile_wall_s_sum", fmt_float(total_compile_s, 1)),
        ("compile_wall_s_max", fmt_float(max_compile_s, 1)),
        ("elab_wall_s_sum", fmt_float(total_elab_s, 1)),
    ]

    if worst_slack_job is not None and worst_slack is not None:
        summary_rows.extend(
            [
                ("worst_slack_ps", fmt_float(worst_slack, 1)),
                ("worst_slack_job", worst_slack_job.job_id),
                ("worst_slack_top", worst_slack_job.top),
            ]
        )

    start_epoch = parse_float(metadata.get("start_epoch_s", ""))
    end_epoch = parse_float(metadata.get("summary_epoch_s", "")) or time.time()
    if start_epoch is not None:
        summary_rows.append(("batch_elapsed_wall_s", fmt_float(max(0.0, end_epoch - start_epoch), 1)))

    if metadata.get("reuse_manifest", ""):
        summary_rows.append(("reuse_manifest", metadata["reuse_manifest"]))

    return [(key, value) for key, value in summary_rows if value != ""]


def print_summary(jobs: list[JobSummary], metadata: dict[str, str]) -> None:
    rows = compute_summary(jobs, metadata)
    key_width = max((len(key) for key, _ in rows), default=0)

    print("Batch summary")
    print("-------------")
    for key, value in rows:
        print(f"{key.ljust(key_width)} : {value}")


def main() -> int:
    args = parse_args()
    batch_root = resolve_batch_root(args)
    manifest_path = batch_root / "jobs.tsv"
    if not manifest_path.exists():
        print(f"error: manifest not found: {manifest_path}", file=sys.stderr)
        return 2

    metadata = read_batch_metadata(batch_root)
    jobs = [summarize_job(row, batch_root, metadata) for row in parse_manifest(manifest_path)]
    jobs.sort(key=sort_key)
    if args.running_only:
        jobs = [job for job in jobs if job.status == "running"]

    if args.write_json is not None:
        args.write_json.write_text(
            json.dumps([asdict(job) for job in jobs], indent=2),
            encoding="utf-8",
        )

    if args.format == "json":
        print(json.dumps([asdict(job) for job in jobs], indent=2))
    elif args.format == "summary":
        print_summary(jobs, metadata)
    elif args.format == "tsv":
        print_tsv(jobs)
    else:
        print_table(jobs)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
