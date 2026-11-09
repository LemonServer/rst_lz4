#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  run_small_signoff_closeout.sh --batch-label <label> [options]

Rebuild the reviewer-facing small closeout bundle from an existing parser-smoke batch.
This wrapper:
  1. refreshes inventory/batch summaries with a modern Python interpreter
  2. optionally regenerates small runtime metrics JSON
  3. optionally captures page-top power (activity/clock_only/zero_toggle)
  4. rebuilds the signoff markdown/json bundle with perf + power attached

Options:
  --batch-label <label>     Existing parser_smoke batch label (required)
  --output-dir <dir>        Bundle output dir (default: build/reviewer_small/<label>_closeout)
  --input-file <path>       Runtime/power workload (default: data/dacapo_avrora_rand1k)
  --pages <n>               Runtime/power pages (default: 16)
  --python <path>           Python interpreter for repo scripts
  --verilator-bin <path>    Optional Verilator path for runtime metrics
  --build-jobs <n>          Verilator build jobs for runtime metrics (default: 4)
  --vcs <path>              VCS binary (default: vcs)
  --vcd2saif <path>         vcd2saif binary (default: vcd2saif)
  --slack-tolerance-ps <n>  Optional reporting-only slack floor (default: 0.0)
  --skip-runtime-metrics    Skip rebuilding small runtime perf JSON
  --skip-power              Skip power capture / SAIF / power bundle wiring
EOF
}

batch_label=""
output_dir=""
input_file=""
pages="16"
python_bin=""
verilator_bin=""
build_jobs="4"
vcs_bin="${VCS_BIN:-vcs}"
vcd2saif_bin="${VCD2SAIF_BIN:-vcd2saif}"
slack_tolerance_ps="0.0"
skip_runtime_metrics=0
skip_power=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --batch-label)
            batch_label="${2:-}"
            shift 2
            ;;
        --output-dir)
            output_dir="${2:-}"
            shift 2
            ;;
        --input-file)
            input_file="${2:-}"
            shift 2
            ;;
        --pages)
            pages="${2:-}"
            shift 2
            ;;
        --python)
            python_bin="${2:-}"
            shift 2
            ;;
        --verilator-bin)
            verilator_bin="${2:-}"
            shift 2
            ;;
        --build-jobs)
            build_jobs="${2:-}"
            shift 2
            ;;
        --vcs)
            vcs_bin="${2:-}"
            shift 2
            ;;
        --vcd2saif)
            vcd2saif_bin="${2:-}"
            shift 2
            ;;
        --slack-tolerance-ps)
            slack_tolerance_ps="${2:-}"
            shift 2
            ;;
        --skip-runtime-metrics)
            skip_runtime_metrics=1
            shift
            ;;
        --skip-power)
            skip_power=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$batch_label" ]]; then
    echo "--batch-label is required" >&2
    usage >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
batch_root="${repo_root}/synthesis/results/parser_smoke_batches/${batch_label}"
manifest="${batch_root}/jobs.tsv"

if [[ ! -f "$manifest" ]]; then
    echo "batch manifest not found: $manifest" >&2
    exit 1
fi

if [[ -z "$python_bin" ]]; then
    if [[ -x "$HOME/miniforge3/envs/rst-build/bin/python" ]]; then
        python_bin="$HOME/miniforge3/envs/rst-build/bin/python"
    else
        python_bin="$(command -v python3)"
    fi
fi

if [[ -z "$input_file" ]]; then
    input_file="${repo_root}/data/dacapo_avrora_rand1k"
fi

if [[ -z "$output_dir" ]]; then
    output_dir="${repo_root}/build/reviewer_small/${batch_label}_closeout"
fi

runtime_root="${output_dir}/runtime"
power_root="${output_dir}/power"
runtime_json="${runtime_root}/small_runtime_metrics_${pages}pages.json"
runtime_log="${runtime_root}/small_runtime_metrics_${pages}pages.log"
python_bindir="$(cd "$(dirname "$python_bin")" && pwd)"

pc_dir="${batch_root}/results/pagecompressortop_tiny/02_pagecompressortop_compile"
pd_dir="${batch_root}/results/pagedecompressortop_tiny/03_pagedecompressortop_compile"

clean_toolchain_env() {
    env \
        -u CC -u CXX -u CPP -u LD -u AR -u AS -u NM -u RANLIB -u STRIP -u OBJCOPY -u OBJDUMP \
        -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u LIBRARY_PATH \
        -u CPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH -u PKG_CONFIG_PATH \
        "$@"
}

mkdir -p "$output_dir" "$runtime_root"

echo "Using Python: $python_bin"
"$python_bin" --version

echo "Refreshing batch inventory..."
"$python_bin" synthesis/scripts/inventory_dc_batch.py --batch-root "$batch_root" --format table > "${batch_root}/inventory_table.txt"
"$python_bin" synthesis/scripts/inventory_dc_batch.py --batch-root "$batch_root" --format summary > "${batch_root}/batch_summary.txt"

perf_args=()
if [[ "$skip_runtime_metrics" != "1" ]]; then
    echo "Rebuilding small runtime metrics..."
    runtime_cmd=(
        "$python_bin"
        tools/run_m4_runtime_file_metrics.py
        "$input_file"
        --tier
        small
        --pages
        "$pages"
        --write-json
        "$runtime_json"
        --write-log
        "$runtime_log"
        --build-jobs
        "$build_jobs"
    )
    if [[ -n "$verilator_bin" ]]; then
        runtime_cmd+=(--verilator-bin "$verilator_bin")
    fi
    (cd "$repo_root" && env PATH="${python_bindir}:$PATH" "${runtime_cmd[@]}")
    perf_args+=(--perf-json "$runtime_json")
fi

power_args=()
if [[ "$skip_power" != "1" ]]; then
    echo "Capturing page-top power..."
    command -v "$vcs_bin" >/dev/null
    command -v "$vcd2saif_bin" >/dev/null
    command -v dc_shell >/dev/null
    mkdir -p "$power_root"

    clean_toolchain_env bash synthesis/scripts/run_runtime_file_power_capture.sh \
        --tier small \
        --input-file "$input_file" \
        --pages "$pages" \
        --vcs "$vcs_bin" \
        --frozen-baseline \
        --out-dir "${power_root}/runtime_capture"

    "$vcd2saif_bin" \
        -input "${power_root}/runtime_capture/runtime_capture.vcd" \
        -instance tb_M4RuntimeFileRoundTripTop/compressor_dut \
        -output "${power_root}/runtime_capture/pagecompressortop_activity.saif"

    "$vcd2saif_bin" \
        -input "${power_root}/runtime_capture/runtime_capture.vcd" \
        -instance tb_M4RuntimeFileRoundTripTop/decompressor_dut \
        -output "${power_root}/runtime_capture/pagedecompressortop_activity.saif"

    for mode in activity clock_only zero_toggle; do
        out="${power_root}/pagecompressortop/${mode}"
        mkdir -p "$out"
        xcmd="set TOP PageCompressorTop; set DDC_FILE {$pc_dir/pagecompressortop_tiny.ddc}; set SDC_FILE {$pc_dir/pagecompressortop_tiny.sdc}; set OUTPUT_DIR {$out}; set POWER_MODE $mode; set OUTPUT_TAG {pagecompressortop_tiny_${mode}}"
        if [[ "$mode" == "activity" ]]; then
            xcmd="${xcmd}; set SAIF_FILE {${power_root}/runtime_capture/pagecompressortop_activity.saif}; set SAIF_INSTANCE_NAME {tb_M4RuntimeFileRoundTripTop/compressor_dut}; set SAIF_STRIP_PATH {compressor_dut}"
        fi
        dc_shell -x "$xcmd" -f synthesis/scripts/power_from_saif.tcl | tee "${out}/dc_shell.log"
    done

    for mode in activity clock_only zero_toggle; do
        out="${power_root}/pagedecompressortop/${mode}"
        mkdir -p "$out"
        xcmd="set TOP PageDecompressorTop; set DDC_FILE {$pd_dir/pagedecompressortop_tiny.ddc}; set SDC_FILE {$pd_dir/pagedecompressortop_tiny.sdc}; set OUTPUT_DIR {$out}; set POWER_MODE $mode; set OUTPUT_TAG {pagedecompressortop_tiny_${mode}}"
        if [[ "$mode" == "activity" ]]; then
            xcmd="${xcmd}; set SAIF_FILE {${power_root}/runtime_capture/pagedecompressortop_activity.saif}; set SAIF_INSTANCE_NAME {tb_M4RuntimeFileRoundTripTop/decompressor_dut}; set SAIF_STRIP_PATH {decompressor_dut}"
        fi
        dc_shell -x "$xcmd" -f synthesis/scripts/power_from_saif.tcl | tee "${out}/dc_shell.log"
    done

    power_args+=(
        --power-rpt "${power_root}/pagecompressortop"
        --power-rpt "${power_root}/pagedecompressortop"
    )
fi

echo "Building signoff bundle..."
"$python_bin" synthesis/scripts/build_signoff_bundle.py \
    --batch-label "$batch_label" \
    --output-dir "$output_dir" \
    --slack-tolerance-ps "$slack_tolerance_ps" \
    "${perf_args[@]}" \
    "${power_args[@]}"

echo "Wrote:"
echo "  ${output_dir}/signoff_summary.json"
echo "  ${output_dir}/signoff_summary.md"
