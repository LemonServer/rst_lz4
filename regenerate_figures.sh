#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${ROOT_DIR}/.venv"
DUMPS_DIR="${ROOT_DIR}/5kcorrectdumps"
OUT_DIR="${ROOT_DIR}/generated"
FIG_DIR="${OUT_DIR}/figures"
DATA_DIR="${OUT_DIR}/data"
WORK_DUMPS_DIR="${OUT_DIR}/working_dumps"
LOG_DIR="${OUT_DIR}/logs"
RST_HW_ROOT="${RST_HW_ROOT:-}"

RUN_MAIN=1
RUN_ABLATION=1
QUICK_MODE=0
RERUN_STAGE_V=0
SCRIPT_START_TS="$(date +%s)"

phase_start() {
  PHASE_NAME="$1"
  PHASE_TS="$(date +%s)"
  echo
  echo "=== ${PHASE_NAME} ==="
  date -u '+UTC start: %Y-%m-%d %H:%M:%S'
}

phase_end() {
  local end_ts elapsed
  end_ts="$(date +%s)"
  elapsed="$((end_ts - PHASE_TS))"
  echo "[done] ${PHASE_NAME} (${elapsed}s)"
}

run_logged() {
  local label="$1"
  local logfile="$2"
  shift 2

  echo "[run] ${label}"
  if "$@" >"${logfile}" 2>&1; then
    echo "[ok] ${label}"
  else
    echo "[fail] ${label}. See ${logfile}" >&2
    tail -n 40 "${logfile}" >&2 || true
    return 1
  fi
}

script_end() {
  local end_ts elapsed
  end_ts="$(date +%s)"
  elapsed="$((end_ts - SCRIPT_START_TS))"
  echo
  echo "Done."
  echo "Total elapsed: ${elapsed}s"
  date -u '+UTC end: %Y-%m-%d %H:%M:%S'
}

usage() {
  cat <<'EOF'
Usage:
  bash regenerate_figures.sh [--dumps DIR] [--main-only] [--ablation-only] [--quick] [--rerun-stage-v]

Options:
  --dumps DIR       Directory containing dump files. Default: ./5kcorrectdumps
                    In --quick mode, dumps are grouped by the basename prefix before
                    the first underscore. Files without an underscore are treated as
                    their own suite.
  --main-only       Generate only the main compression figure pipeline
  --ablation-only   Generate only the ablation figure pipeline
  --quick           Run a reviewer-friendly smoke test on a small dump subset
  --rerun-stage-v   Recompute the expensive full-RST stage-V ablation sweep instead of
                    using the bundled measured checkpoint
  --help            Show this message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dumps)
      DUMPS_DIR="$2"
      shift 2
      ;;
    --main-only)
      RUN_MAIN=1
      RUN_ABLATION=0
      shift
      ;;
    --ablation-only)
      RUN_MAIN=0
      RUN_ABLATION=1
      shift
      ;;
    --quick)
      QUICK_MODE=1
      shift
      ;;
    --rerun-stage-v|--full-stage-v)
      RERUN_STAGE_V=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${QUICK_MODE}" -eq 1 && "${RERUN_STAGE_V}" -eq 1 ]]; then
  echo "--quick cannot be combined with --rerun-stage-v" >&2
  exit 1
fi

if [[ ! -d "${DUMPS_DIR}" ]]; then
  echo "Dump directory not found: ${DUMPS_DIR}" >&2
  exit 1
fi

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_cmd make
require_cmd g++
require_cmd find
require_cmd sort

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  echo "Missing virtual environment at ${VENV_DIR}" >&2
  echo "Run: bash vm_bootstrap.sh" >&2
  exit 1
fi

mkdir -p "${FIG_DIR}" "${DATA_DIR}" "${WORK_DUMPS_DIR}" "${LOG_DIR}"

prepare_working_dumps() {
  echo "[prep] Preparing working dump set..."
  rm -rf "${WORK_DUMPS_DIR}"
  mkdir -p "${WORK_DUMPS_DIR}"

  shopt -s nullglob
  local dump
  for dump in "${DUMPS_DIR}"/*; do
    ln -s "${dump}" "${WORK_DUMPS_DIR}/$(basename "${dump}")"
  done
}

write_dump_list() {
  local output_path="$1"
  mapfile -t dumps < <(find -L "${WORK_DUMPS_DIR}" -maxdepth 1 -type f | sort)
  if [[ "${#dumps[@]}" -eq 0 ]]; then
    echo "No dump files found in ${WORK_DUMPS_DIR}" >&2
    exit 1
  fi

  if [[ "${QUICK_MODE}" -eq 0 ]]; then
    printf '%s\n' "${dumps[@]}" > "${output_path}"
    echo "[prep] Selected ${#dumps[@]} dump(s) for the full run."
    return
  fi

  declare -A seen_suites=()
  local suite_count=0
  local dump
  for dump in "${dumps[@]}"; do
    local base suite
    base="$(basename "${dump}")"
    suite="${base%%_*}"
    if [[ -z "${seen_suites[${suite}]+x}" ]]; then
      seen_suites["${suite}"]=1
      suite_count=$((suite_count + 1))
    fi
  done

  if [[ "${suite_count}" -le 1 ]]; then
    printf '%s\n' "${dumps[@]}" > "${output_path}"
    echo "[prep] Quick mode kept all ${#dumps[@]} dump(s) because only one suite is present."
    return
  fi

  declare -A selected_suites=()
  : > "${output_path}"
  for dump in "${dumps[@]}"; do
    local base suite
    base="$(basename "${dump}")"
    suite="${base%%_*}"
    if [[ -n "${selected_suites[${suite}]+x}" ]]; then
      continue
    fi
    selected_suites["${suite}"]=1
    printf '%s\n' "${dump}" >> "${output_path}"
  done

  echo "[prep] Quick mode selected $(wc -l < "${output_path}") representative dump(s) across ${suite_count} suites."
}

apply_quick_subset() {
  local list_path="$1"
  if [[ "${QUICK_MODE}" -eq 0 ]]; then
    return
  fi

  local selected_dir="${OUT_DIR}/quick_dumps"
  echo "[prep] Materializing quick-mode dump subset in ${selected_dir}"
  rm -rf "${selected_dir}"
  mkdir -p "${selected_dir}"

  while IFS= read -r dump_path || [[ -n "${dump_path}" ]]; do
    [[ -n "${dump_path}" ]] || continue
    ln -s "${dump_path}" "${selected_dir}/$(basename "${dump_path}")"
  done < "${list_path}"

  WORK_DUMPS_DIR="${selected_dir}"
}

write_figure_index() {
  cat > "${FIG_DIR}/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>RST Artifact Figures</title>
  <style>
    body { font-family: sans-serif; margin: 24px; }
    img { max-width: 100%; border: 1px solid #ccc; margin-bottom: 24px; }
    .figure { margin-bottom: 40px; }
  </style>
</head>
<body>
  <h1>RST Artifact Figures</h1>
  <div class="figure">
    <h2>Main Compression Figure</h2>
    <p><a href="rst_vs_lz4huff_suite_scatter.pdf">PDF</a></p>
    <img src="rst_vs_lz4huff_suite_scatter.png" alt="Main compression figure">
  </div>
  <div class="figure">
    <h2>Ablation Figure</h2>
    <p><a href="fig_cr_ablation_dictsize.pdf">PDF</a></p>
    <img src="fig_cr_ablation_dictsize.png" alt="Ablation figure">
  </div>
</body>
</html>
EOF
}

prepare_working_dumps
write_dump_list "${DATA_DIR}/working_dump_list.txt"
apply_quick_subset "${DATA_DIR}/working_dump_list.txt"

resolve_rst_hw_root() {
  local candidate
  if [[ -n "${RST_HW_ROOT}" && -d "${RST_HW_ROOT}" ]]; then
    printf '%s\n' "${RST_HW_ROOT}"
    return 0
  fi

  for candidate in \
    "${ROOT_DIR}/../../eval_hw/rst_artifact_deadline_integration_hardware_sim_artifact" \
    "/home/debian/hw_artifact/rst-hardware"
  do
    if [[ -d "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

if [[ "${RUN_MAIN}" -eq 1 ]]; then
  phase_start "Main Figure: MemComp Baselines"
  pushd "${ROOT_DIR}/MemComp" >/dev/null
  bash runner.sh \
    --compression "lz4_huffman deflate" \
    --output "${DATA_DIR}/memcomp_raw.csv" \
    --list "${DATA_DIR}/working_dump_list.txt"
  "${VENV_DIR}/bin/python" "${ROOT_DIR}/MemComp/MemComp_summarize_cr.py" \
    -i "${DATA_DIR}/memcomp_raw.csv" \
    -o "${DATA_DIR}/memcomp_summary.csv"
  popd >/dev/null
  phase_end

  if [[ "${QUICK_MODE}" -eq 1 ]]; then
    phase_start "Main Figure: Quick RST Approximation"
    g++ -O3 -std=c++17 -pthread "${ROOT_DIR}/ablation/rst_step_3.cpp" -o "${OUT_DIR}/rst_step_3"
    run_logged \
      "Quick RST approximation over representative dump subset" \
      "${LOG_DIR}/main_quick_rst.log" \
      "${OUT_DIR}/rst_step_3" -f "${WORK_DUMPS_DIR}" -o "${DATA_DIR}/rst_step_3_raw.csv"
    phase_end
  else
    hw_root="$(resolve_rst_hw_root)" || {
      echo "Full main-figure regeneration requires the hardware artifact checkout." >&2
      echo "Set RST_HW_ROOT or ensure /home/debian/hw_artifact/rst-hardware exists." >&2
      exit 1
    }
    phase_start "Main Figure: Full-RST Sweep"
    echo "[main] Using hardware tree: ${hw_root}"
    "${VENV_DIR}/bin/python" "${ROOT_DIR}/rst_figures/build_full_rst_main_csv.py" \
      --hw-root "${hw_root}" \
      --dumps-dir "${WORK_DUMPS_DIR}" \
      --pages 5000 \
      --memory-blocks 2 \
      --chunk-size 256 \
      --jobs "${CPUS:-4}" \
      --output "${DATA_DIR}/full_rst_main_mb2_5k.csv"
    phase_end
  fi

  phase_start "Main Figure: Merge And Render"
  if [[ "${QUICK_MODE}" -eq 1 ]]; then
    "${VENV_DIR}/bin/python" "${ROOT_DIR}/rst_figures/build_main_plot_data.py" \
      --memcomp-summary "${DATA_DIR}/memcomp_summary.csv" \
      --rst-raw "${DATA_DIR}/rst_step_3_raw.csv" \
      --rst-config "lz-bse:dict=128:util=utility:cd=1" \
      --output "${DATA_DIR}/main_plot_data.csv"
  else
    "${VENV_DIR}/bin/python" "${ROOT_DIR}/rst_figures/build_main_plot_data.py" \
      --memcomp-summary "${DATA_DIR}/memcomp_summary.csv" \
      --rst-full "${DATA_DIR}/full_rst_main_mb2_5k.csv" \
      --output "${DATA_DIR}/main_plot_data.csv"
  fi

  MPLBACKEND=Agg "${VENV_DIR}/bin/python" "${ROOT_DIR}/rst_figures/main_compression_tmcc_fig.py" \
    --input "${DATA_DIR}/main_plot_data.csv" \
    --output-prefix "${FIG_DIR}/rst_vs_lz4huff_suite_scatter"
  phase_end
fi

if [[ "${RUN_ABLATION}" -eq 1 ]]; then
  phase_start "Ablation: Compile"
  g++ -O3 -std=c++17 -pthread "${ROOT_DIR}/ablation/rst_step_1.cpp" -o "${OUT_DIR}/rst_step_1"
  g++ -O3 -std=c++17 -pthread "${ROOT_DIR}/ablation/rst_step_2.cpp" -o "${OUT_DIR}/rst_step_2"
  g++ -O3 -std=c++17 -pthread "${ROOT_DIR}/ablation/rst_step_3.cpp" -o "${OUT_DIR}/rst_step_3"
  phase_end

  phase_start "Ablation: Measure"
  run_logged \
    "Ablation stage IV.A measurement" \
    "${LOG_DIR}/ablation_step_1.log" \
    "${OUT_DIR}/rst_step_1" -f "${WORK_DUMPS_DIR}" -o "${DATA_DIR}/rst_step_1_raw.csv"
  run_logged \
    "Ablation stage IV.B measurement" \
    "${LOG_DIR}/ablation_step_2.log" \
    "${OUT_DIR}/rst_step_2" -f "${WORK_DUMPS_DIR}" -o "${DATA_DIR}/rst_step_2_raw.csv"
  run_logged \
    "Ablation stage IV.C measurement" \
    "${LOG_DIR}/ablation_step_3.log" \
    "${OUT_DIR}/rst_step_3" -f "${WORK_DUMPS_DIR}" -o "${DATA_DIR}/rst_step_3_raw.csv"
  phase_end

  phase_start "Ablation: Summarize And Render"
  "${VENV_DIR}/bin/python" "${ROOT_DIR}/ablation/rst_step_summarize_cr.py" \
    -i "${DATA_DIR}/rst_step_1_raw.csv" \
    -o "${DATA_DIR}/rst_step_1_summary.csv"
  "${VENV_DIR}/bin/python" "${ROOT_DIR}/ablation/rst_step_summarize_cr.py" \
    -i "${DATA_DIR}/rst_step_2_raw.csv" \
    -o "${DATA_DIR}/rst_step_2_summary.csv"
  "${VENV_DIR}/bin/python" "${ROOT_DIR}/ablation/rst_step_summarize_cr.py" \
    -i "${DATA_DIR}/rst_step_3_raw.csv" \
    -o "${DATA_DIR}/rst_step_3_summary.csv"

  if [[ "${RERUN_STAGE_V}" -eq 1 ]]; then
    hw_root="$(resolve_rst_hw_root)" || {
      echo "Full stage-V regeneration requires the hardware artifact checkout." >&2
      echo "Set RST_HW_ROOT or ensure /home/debian/hw_artifact/rst-hardware exists." >&2
      exit 1
    }
    echo "[ablation] Recomputing full-RST stage-V summary from scratch..."
    "${VENV_DIR}/bin/python" "${ROOT_DIR}/rst_figures/build_full_rst_stage4_summary.py" \
      --hw-root "${hw_root}" \
      --dumps-dir "${WORK_DUMPS_DIR}" \
      --pages 5000 \
      --memory-blocks 1,2,3,4 \
      --chunk-size 256 \
      --jobs "${CPUS:-4}" \
      --output "${DATA_DIR}/rst_stage_4_summary.csv"
  else
    echo "[ablation] Using bundled measured full-RST stage-V summary checkpoint."
    echo "[ablation] Pass --rerun-stage-v to recompute this stage from scratch."
    "${VENV_DIR}/bin/python" "${ROOT_DIR}/rst_figures/write_stage4_full_rst_summary.py" \
      --output "${DATA_DIR}/rst_stage_4_summary.csv"
  fi

  echo "[ablation] Building combined plotting data..."
  "${VENV_DIR}/bin/python" "${ROOT_DIR}/rst_figures/build_ablation_plot_data.py" \
    --stage "Util-aware sel. (IV.A)" "${DATA_DIR}/rst_step_1_summary.csv" \
    --stage "+8B Loc Dict (IV.B)" "${DATA_DIR}/rst_step_2_summary.csv" \
    --stage "+0B Sym Dict (IV.C)" "${DATA_DIR}/rst_step_3_summary.csv" \
    --stage "Top util. sel. (V)" "${DATA_DIR}/rst_stage_4_summary.csv" \
    --output "${DATA_DIR}/ablation_plot_data.csv"

  MPLBACKEND=Agg "${VENV_DIR}/bin/python" "${ROOT_DIR}/rst_figures/ablation_graph.py" \
    --input "${DATA_DIR}/ablation_plot_data.csv" \
    --output-prefix "${FIG_DIR}/fig_cr_ablation_dictsize"
  phase_end
fi

write_figure_index

script_end
echo "Data: ${DATA_DIR}"
echo "Figures: ${FIG_DIR}"
echo "View in a browser: ${FIG_DIR}/index.html"
