#!/usr/bin/env python3
"""Build a compact synthesis-evidence bundle from synthesis artifacts and optional perf summaries."""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from dataclasses import asdict
from pathlib import Path
from typing import Any

import inventory_dc_batch as inv


DEFAULT_TOP_ORDER = [
    "PageCompressorTop",
    "PageDecompressorTop",
    "CompressorTop",
    "DecompressorTop",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a compact synthesis-evidence bundle from a DC batch and optional perf JSON."
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--batch-label", help="Batch label under synthesis/results/parser_smoke_batches/")
    group.add_argument("--batch-root", type=Path, help="Absolute path to a DC batch directory")
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Directory where signoff_summary.json and signoff_summary.md should be written",
    )
    parser.add_argument(
        "--top",
        action="append",
        dest="tops",
        help="Top name to include (repeatable). Defaults to closed-out compressor/decompressor tops.",
    )
    parser.add_argument(
        "--perf-json",
        action="append",
        default=[],
        help="Optional perf JSON summary to embed in the bundle (repeatable).",
    )
    parser.add_argument(
        "--power-rpt",
        action="append",
        default=[],
        help="Power report file or directory to scan for *_summary.rpt files (repeatable).",
    )
    parser.add_argument(
        "--slack-tolerance-ps",
        type=float,
        default=0.0,
        help="Optional reporting-only slack floor: raw negative slack within this tolerance is rendered as 0.00 ps in the markdown summary.",
    )
    return parser.parse_args()


def resolve_batch_root(args: argparse.Namespace) -> Path:
    if args.batch_root is not None:
        return args.batch_root.resolve()
    return (inv.BATCHES_ROOT / args.batch_label).resolve()


def report_path(job: inv.JobSummary, suffix: str) -> Path:
    design_name = f"{job.top}_{job.artifact_tier}".lower()
    return Path(job.output_dir) / f"{design_name}_{suffix}"


def read_report(path: Path) -> str:
    return inv.read_text(path)


def extract_embedded_report(summary_path: Path, report_path_hint: Path) -> str:
    text = inv.read_text(summary_path)
    if not text:
        return ""

    current_path: str | None = None
    capture: list[str] = []
    target = str(report_path_hint)
    sections: dict[str, list[str]] = {}
    for line in text.splitlines():
        if line.startswith("=== "):
            if current_path is not None:
                sections[current_path] = capture
            current_path = line[4:].strip()
            capture = []
            continue
        if current_path is not None:
            capture.append(line)
    if current_path is not None:
        sections[current_path] = capture

    for key, lines in sections.items():
        if key == target or key.endswith(str(report_path_hint.name)):
            return "\n".join(lines).strip()
    return ""


def load_report(job: inv.JobSummary, batch_root: Path, suffix: str, summary_name: str) -> tuple[str, str]:
    direct_path = report_path(job, suffix)
    text = read_report(direct_path)
    if text:
        return text, str(direct_path)

    summary_path = batch_root / summary_name
    embedded = extract_embedded_report(summary_path, direct_path)
    if embedded:
        return embedded, f"{summary_path}::{direct_path.name}"
    return "", str(direct_path)


def parse_timing_point_line(line: str) -> tuple[str, float] | None:
    stripped = line.rstrip()
    if not stripped or stripped.startswith("---"):
        return None
    if "/" not in stripped and "(in)" not in stripped and "(out)" not in stripped:
        return None

    match = re.search(r"(?P<incr>-?\d+\.\d+)\s+(?P<path>-?\d+\.\d+)\s+[fr](?:\s|$)", stripped)
    if not match:
        return None
    point = stripped[: match.start()].strip()
    if not point:
        return None
    return point, float(match.group("incr"))


def hierarchy_bucket(point: str) -> str | None:
    point = point.split(" (", 1)[0].strip()
    if point.startswith(("clock ", "input external delay", "output external delay")):
        return None
    if point.endswith("(in)") or point.endswith("(out)"):
        return "<io>"
    if "/" not in point:
        return "<top>"
    bucket = point.split("/", 1)[0]
    if re.fullmatch(r"U\d+", bucket):
        return "<top_logic>"
    return bucket


def parse_timing_report(text: str) -> dict[str, Any]:
    if not text:
        return {
            "available": False,
            "startpoint": "",
            "endpoint": "",
            "path_group": "",
            "slack_ps": None,
            "ordered_hierarchy": [],
            "hierarchy_delay_ps": [],
        }

    startpoint = ""
    endpoint = ""
    path_group = ""
    slack_ps: float | None = None

    start_match = re.search(r"^\s*Startpoint:\s+(.+)$", text, re.MULTILINE)
    if start_match:
        startpoint = start_match.group(1).strip()
    end_match = re.search(r"^\s*Endpoint:\s+(.+)$", text, re.MULTILINE)
    if end_match:
        endpoint = end_match.group(1).strip()
    group_match = re.search(r"^\s*Path Group:\s+(.+)$", text, re.MULTILINE)
    if group_match:
        path_group = group_match.group(1).strip()

    slack_matches = re.findall(r"^\s*slack(?:\s+\([^)]+\))?\s+(-?\d+\.\d+)\s*$", text, re.MULTILINE)
    if slack_matches:
        # The generated timing report appends a second `report_timing -delay min`
        # section after the setup report, so the first slack corresponds to the
        # worst setup/max path and later matches can be hold/min slack.
        slack_ps = float(slack_matches[0])

    ordered_hierarchy: list[str] = []
    delay_by_hierarchy: defaultdict[str, float] = defaultdict(float)
    for raw_line in text.splitlines():
        parsed = parse_timing_point_line(raw_line)
        if parsed is None:
            continue
        point, incr = parsed
        bucket = hierarchy_bucket(point)
        if bucket is None:
            continue
        if bucket not in ordered_hierarchy:
            ordered_hierarchy.append(bucket)
        delay_by_hierarchy[bucket] += abs(incr)

    hierarchy_delay_ps = [
        {"instance": name, "delay_ps": round(delay, 2)}
        for name, delay in sorted(delay_by_hierarchy.items(), key=lambda item: (-item[1], item[0]))[:8]
    ]

    return {
        "available": True,
        "startpoint": startpoint,
        "endpoint": endpoint,
        "path_group": path_group,
        "slack_ps": slack_ps,
        "ordered_hierarchy": ordered_hierarchy[:12],
        "hierarchy_delay_ps": hierarchy_delay_ps,
    }


def parse_area_hierarchy(text: str) -> list[dict[str, Any]]:
    if not text:
        return []

    rows: list[dict[str, Any]] = []
    seen: set[tuple[str, float]] = set()
    for line in text.splitlines():
        if line.strip().startswith(("Hierarchical", "Instance", "Combinational", "Noncombinational", "Total")):
            continue
        parts = re.split(r"\s{2,}", line.strip())
        if len(parts) < 2:
            continue
        floats = []
        for field in parts[1:]:
            try:
                floats.append(float(field))
            except ValueError:
                continue
        if not floats:
            continue
        name = parts[0]
        total_area = floats[-1]
        key = (name, total_area)
        if key in seen:
            continue
        seen.add(key)
        rows.append({"instance": name, "total_area": total_area})

    if len(rows) <= 1:
        return []
    rows.sort(key=lambda row: (-row["total_area"], row["instance"]))
    return rows[:12]


def load_perf_json(path_text: str) -> dict[str, Any]:
    path = Path(path_text).resolve()
    return json.loads(path.read_text(encoding="utf-8"))


def sanitize_path_text(text: str, batch_root: Path, batch_label: str) -> str:
    batch_root_str = str(batch_root)
    if text == batch_root_str:
        return f"synthesis/results/parser_smoke_batches/{batch_label}"

    markers = (
        "/synthesis/results/parser_smoke_batches/",
        "/build/",
        "/data/",
        "/evidence/",
        "/docs/",
    )
    for marker in markers:
        idx = text.find(marker)
        if idx != -1:
            return text[idx + 1 :]
    return text


def sanitize_bundle_paths(value: Any, batch_root: Path, batch_label: str) -> Any:
    if isinstance(value, dict):
        return {key: sanitize_bundle_paths(subvalue, batch_root, batch_label) for key, subvalue in value.items()}
    if isinstance(value, list):
        return [sanitize_bundle_paths(item, batch_root, batch_label) for item in value]
    if isinstance(value, str):
        return sanitize_path_text(value, batch_root, batch_label)
    return value


def convert_to_mw(value: float, unit: str) -> float:
    unit = unit.strip()
    scale = {
        "W": 1000.0,
        "mW": 1.0,
        "uW": 1e-3,
        "nW": 1e-6,
        "pW": 1e-9,
    }.get(unit)
    if scale is None:
        raise ValueError(f"Unsupported power unit '{unit}'")
    return value * scale


def parse_scalar_power(text: str, label: str) -> float | None:
    match = re.search(rf"^\s*{re.escape(label)}\s*=\s*([0-9.eE+-]+)\s+([munp]?W|W)\b", text, re.MULTILINE)
    if not match:
        return None
    return convert_to_mw(float(match.group(1)), match.group(2))


def parse_power_group_total(text: str, group_name: str) -> float | None:
    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped.startswith(group_name):
            continue
        parts = re.split(r"\s+", stripped)
        if len(parts) < 5:
            continue
        try:
            return float(parts[4])
        except ValueError:
            continue
    return None


def parse_power_report(path: Path) -> dict[str, Any] | None:
    text = path.read_text(encoding="utf-8")
    design_match = re.search(r"^\s*Design\s*:\s*(.+)$", text, re.MULTILINE)
    if not design_match:
        return None

    mode_match = re.search(r"_(activity|clock_only|zero_toggle)_summary\.rpt$", path.name)
    mode = mode_match.group(1) if mode_match else path.stem
    design = design_match.group(1).strip()
    total_dynamic_mw = parse_scalar_power(text, "Total Dynamic Power")
    leakage_mw = parse_scalar_power(text, "Cell Leakage Power")
    internal_mw = parse_scalar_power(text, "Cell Internal Power")
    switching_mw = parse_scalar_power(text, "Net Switching Power")
    if total_dynamic_mw is None:
        return None

    return {
        "path": str(path),
        "mode": mode,
        "design": design,
        "internal_mw": internal_mw,
        "switching_mw": switching_mw,
        "total_dynamic_mw": total_dynamic_mw,
        "leakage_mw": leakage_mw,
        "clock_network_mw": parse_power_group_total(text, "clock_network"),
        "register_mw": parse_power_group_total(text, "register"),
        "combinational_mw": parse_power_group_total(text, "combinational"),
    }


def collect_power_reports(inputs: list[str]) -> dict[str, dict[str, Any]]:
    by_top: dict[str, dict[str, Any]] = defaultdict(dict)
    seen: set[Path] = set()

    for raw_input in inputs:
        path = Path(raw_input).resolve()
        candidates: list[Path] = []
        if path.is_dir():
            candidates.extend(sorted(path.rglob("*_summary.rpt")))
        elif path.is_file():
            candidates.append(path)

        for candidate in candidates:
            if candidate in seen:
                continue
            seen.add(candidate)
            parsed = parse_power_report(candidate)
            if parsed is None:
                continue
            by_top[parsed["design"]][parsed["mode"]] = parsed
    return by_top


def pick_jobs(jobs: list[inv.JobSummary], requested_tops: list[str]) -> list[inv.JobSummary]:
    by_top = {job.top: job for job in jobs if job.mode == "compile"}
    picked: list[inv.JobSummary] = []
    for top in requested_tops:
        job = by_top.get(top)
        if job is not None:
            picked.append(job)
    if picked:
        return picked
    return [job for job in jobs if job.mode == "compile"]


def format_float(value: float | None, digits: int = 2) -> str:
    if value is None:
        return "n/a"
    return f"{value:.{digits}f}"


def effective_slack_ps(value: float | None, tolerance_ps: float) -> float | None:
    if value is None:
        return None
    if tolerance_ps > 0.0 and value < 0.0 and abs(value) <= tolerance_ps:
        return 0.0
    return value


def slack_is_clipped(raw_value: float | None, tolerance_ps: float) -> bool:
    effective = effective_slack_ps(raw_value, tolerance_ps)
    return raw_value is not None and effective is not None and effective != raw_value


def build_markdown(bundle: dict[str, Any]) -> str:
    lines: list[str] = []
    batch = bundle["batch"]
    summary = batch["summary"]
    slack_tolerance_ps = float(bundle.get("slack_tolerance_ps") or 0.0)
    raw_worst_slack = summary.get("worst_slack_ps")
    if raw_worst_slack not in (None, "", "n/a"):
        try:
            raw_worst_slack = float(raw_worst_slack)
        except (TypeError, ValueError):
            raw_worst_slack = None
    else:
        raw_worst_slack = None
    shown_worst_slack = effective_slack_ps(raw_worst_slack, slack_tolerance_ps)

    lines.append(f"# Small Synthesis Evidence Bundle: {batch['label']}")
    lines.append("")
    lines.append("## Batch Snapshot")
    lines.append("")
    lines.append(f"- Packaged batch directory: `{batch['root']}`")
    lines.append(f"- Profile: `{batch['metadata'].get('profile', '')}`")
    lines.append(f"- Tier: `{batch['metadata'].get('tier', '')}`")
    lines.append(f"- Jobs done: `{summary.get('job_done', '')}/{summary.get('job_total', '')}`")
    lines.append(f"- Compile jobs done: `{summary.get('compile_jobs_done', '')}`")
    if slack_is_clipped(raw_worst_slack, slack_tolerance_ps):
        lines.append(
            f"- Worst slack: `{format_float(shown_worst_slack, 2)} ps` "
            f"(raw `{format_float(raw_worst_slack, 2)} ps`, tolerance `{format_float(slack_tolerance_ps, 2)} ps`)"
        )
    else:
        lines.append(f"- Worst slack: `{summary.get('worst_slack_ps', 'n/a')} ps`")
    lines.append("")
    lines.append("## Units")
    lines.append("")
    lines.append("- Timing and slack are reported in `ps`.")
    lines.append("- Power is reported in `mW`.")
    lines.append(
        "- Area values are DC `Design Area` / `report_area` totals from the ASAP7 library setup, so treat them as relative synthesized cell-area figures rather than routed silicon area."
    )
    lines.append("")
    lines.append("## Top Metrics")
    lines.append("")
    if not bundle["tops"]:
        lines.append("- No compile-job metrics were found for the requested tops.")
    for top_entry in bundle["tops"]:
        qor = top_entry["qor"]
        timing = top_entry["timing"]
        lines.append(f"### {top_entry['top']}")
        lines.append(f"- Status: `{top_entry['status']}`")
        lines.append(
            f"- Area (ASAP7 DC Design Area): total `{format_float(qor.get('design_area'), 1)}`, comb `{format_float(qor.get('comb_area'), 1)}`, "
            f"noncomb `{format_float(qor.get('noncomb_area'), 1)}`, seq cells `{qor.get('seq_cells', 'n/a')}`"
        )
        raw_slack = timing.get("slack_ps")
        shown_slack = effective_slack_ps(raw_slack, slack_tolerance_ps)
        if slack_is_clipped(raw_slack, slack_tolerance_ps):
            lines.append(
                f"- Timing: slack `{format_float(shown_slack, 2)} ps` "
                f"(raw `{format_float(raw_slack, 2)} ps`, tolerance `{format_float(slack_tolerance_ps, 2)} ps`), "
                f"start `{timing.get('startpoint', '')}`, end `{timing.get('endpoint', '')}`"
            )
        else:
            lines.append(
                f"- Timing: slack `{format_float(shown_slack, 2)} ps`, start `{timing.get('startpoint', '')}`, "
                f"end `{timing.get('endpoint', '')}`"
            )
        ordered = timing.get("ordered_hierarchy", [])
        if ordered:
            lines.append(f"- Path hierarchy trace: `{', '.join(ordered)}`")
        delay_rows = timing.get("hierarchy_delay_ps", [])
        if delay_rows:
            delay_text = ", ".join(
                f"{row['instance']}={row['delay_ps']:.2f} ps" for row in delay_rows
            )
            lines.append(f"- Hier delay attribution: `{delay_text}`")
        area_rows = top_entry.get("area_hierarchy", [])
        if area_rows:
            area_text = ", ".join(
                f"{row['instance']}={row['total_area']:.1f}" for row in area_rows[:6]
            )
            lines.append(f"- Area hierarchy preview: `{area_text}`")
        power = top_entry.get("power", {})
        if power:
            power_bits: list[str] = []
            for mode in ("activity", "clock_only", "zero_toggle"):
                report = power.get(mode)
                if report is None:
                    continue
                power_bits.append(f"{mode}={format_float(report.get('total_dynamic_mw'), 3)} mW")
            activity = power.get("activity")
            clock_only = power.get("clock_only")
            if activity is not None and clock_only is not None:
                data_delta = activity.get("total_dynamic_mw")
                base = clock_only.get("total_dynamic_mw")
                if data_delta is not None and base is not None:
                    power_bits.append(f"activity-minus-clock-only={data_delta - base:.3f} mW")
            if power_bits:
                lines.append(f"- Power: `{', '.join(power_bits)}`")
            if activity is not None:
                lines.append(
                    f"- Activity breakdown: `clock_network={format_float(activity.get('clock_network_mw'), 3)} mW, "
                    f"register={format_float(activity.get('register_mw'), 3)} mW, "
                    f"combinational={format_float(activity.get('combinational_mw'), 3)} mW, "
                    f"leakage={format_float(activity.get('leakage_mw'), 3)} mW`"
                )
        missing = top_entry.get("missing_artifacts", [])
        if missing:
            lines.append(f"- Missing artifacts: `{', '.join(missing)}`")
        lines.append("")

    if bundle["perf"]:
        lines.append("## Functional / Perf Context")
        lines.append("")
        for perf in bundle["perf"]:
            summary = perf.get("summary", {})
            lines.append(
                f"- `{perf.get('tier', '')}` runtime harness: pages `{summary.get('pages', '')}`, "
                f"ratio `{format_float(summary.get('ratio'), 4)}`, compressor throughput `{format_float(summary.get('comp_bpc'), 4)} B/cycle`, "
                f"decompressor throughput `{format_float(summary.get('decomp_bpc'), 4)} B/cycle`"
            )
        lines.append("")

    lines.append("## Gaps")
    lines.append("")
    gaps = bundle["gaps"]
    if not gaps:
        lines.append("- None.")
    else:
        for gap in gaps:
            lines.append(f"- {gap}")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    batch_root = resolve_batch_root(args)
    metadata = inv.read_batch_metadata(batch_root)
    jobs = [inv.summarize_job(row, batch_root, metadata) for row in inv.parse_manifest(batch_root / "jobs.tsv")]
    jobs.sort(key=inv.sort_key)
    requested_tops = args.tops or DEFAULT_TOP_ORDER
    top_jobs = pick_jobs(jobs, requested_tops)

    top_entries: list[dict[str, Any]] = []
    gaps: list[str] = []
    for job in top_jobs:
        timing_text, timing_source = load_report(job, batch_root, "timing.rpt", "timing_summary.txt")
        area_text, area_source = load_report(job, batch_root, "area.rpt", "area_summary.txt")
        qor_path = report_path(job, "qor.rpt")
        missing_artifacts = []
        if not timing_text:
            missing_artifacts.append("timing.rpt")
        if not inv.read_text(qor_path):
            missing_artifacts.append("qor.rpt")
        if not area_text:
            missing_artifacts.append("area.rpt")

        timing_summary = parse_timing_report(timing_text)
        if timing_summary["slack_ps"] is None and job.crit_slack is not None:
            timing_summary["slack_ps"] = job.crit_slack

        top_entries.append(
            {
                "top": job.top,
                "status": job.status,
                "job_id": job.job_id,
                "output_dir": job.output_dir,
                "qor": {
                    "design_area": job.design_area,
                    "comb_area": job.comb_area,
                    "noncomb_area": job.noncomb_area,
                    "leaf_cells": job.leaf_cells,
                    "seq_cells": job.seq_cells,
                    "crit_slack": job.crit_slack,
                    "tns": job.tns,
                    "violating_paths": job.violating_paths,
                    "compile_wall_s": job.compile_wall_s,
                },
                "timing": timing_summary,
                "area_hierarchy": parse_area_hierarchy(area_text),
                "artifacts": {
                    "qor_rpt": str(qor_path),
                    "timing_source": timing_source,
                    "area_source": area_source,
                },
                "missing_artifacts": missing_artifacts,
            }
        )
        if missing_artifacts:
            gaps.append(f"{job.top} is missing {', '.join(missing_artifacts)} in the local bundle.")

    perf_entries = [load_perf_json(path_text) for path_text in args.perf_json]
    if not perf_entries:
        gaps.append("No embedded perf JSON was provided.")
    power_by_top = collect_power_reports(args.power_rpt)

    top_names = {entry["top"] for entry in top_entries}
    for top_entry in top_entries:
        top_entry["power"] = power_by_top.get(top_entry["top"], {})
    if args.power_rpt and not power_by_top:
        gaps.append("No power summary reports were parsed from the provided --power-rpt inputs.")
    elif not args.power_rpt:
        gaps.append("No power reports were provided.")
    for power_top in sorted(power_by_top):
        if power_top not in top_names:
            gaps.append(f"Power reports were parsed for {power_top}, but that top is not in the requested bundle set.")

    summary_pairs = inv.compute_summary(jobs, metadata)
    bundle = {
        "batch": {
            "label": metadata.get("batch_label", batch_root.name),
            "root": str(batch_root),
            "metadata": metadata,
            "summary": {key: value for key, value in summary_pairs},
            "jobs": [asdict(job) for job in jobs],
        },
        "tops": top_entries,
        "perf": perf_entries,
        "gaps": sorted(set(gaps)),
        "slack_tolerance_ps": args.slack_tolerance_ps,
    }
    bundle = sanitize_bundle_paths(bundle, batch_root, metadata.get("batch_label", batch_root.name))

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    json_path = output_dir / "signoff_summary.json"
    md_path = output_dir / "signoff_summary.md"
    json_path.write_text(json.dumps(bundle, indent=2), encoding="utf-8")
    md_path.write_text(build_markdown(bundle), encoding="utf-8")

    print(f"Wrote {json_path}")
    print(f"Wrote {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
