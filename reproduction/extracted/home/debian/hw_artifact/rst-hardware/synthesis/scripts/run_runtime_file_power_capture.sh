#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  run_runtime_file_power_capture.sh --tier <small|medium|large> --input-file <path> --out-dir <dir> [--pages <n>] [--vcs <binary>] [--frozen-baseline]

Build the M4 runtime file harness with VCS, run it on a real input file, and emit:
  - simv binary
  - runtime_capture.log
  - runtime_capture.vcd

Example:
  bash synthesis/scripts/run_runtime_file_power_capture.sh \
    --tier small \
    --input-file /path/to/workload.bin \
    --pages 16 \
    --out-dir /tmp/pagecompressor_power_small
EOF
}

public_tier=""
internal_tier=""
input_file=""
out_dir=""
pages="16"
vcs_bin="${VCS_BIN:-vcs}"
frozen_baseline=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier)
            public_tier="${2:-}"
            shift 2
            ;;
        --input-file)
            input_file="${2:-}"
            shift 2
            ;;
        --out-dir)
            out_dir="${2:-}"
            shift 2
            ;;
        --pages)
            pages="${2:-}"
            shift 2
            ;;
        --vcs)
            vcs_bin="${2:-}"
            shift 2
            ;;
        --frozen-baseline)
            frozen_baseline=1
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

if [[ -z "$public_tier" || -z "$input_file" || -z "$out_dir" ]]; then
    usage >&2
    exit 1
fi

case "$public_tier" in
    small)
        internal_tier="tiny"
        ;;
    medium|large)
        internal_tier="$public_tier"
        ;;
    *)
        echo "Unknown tier '$public_tier'" >&2
        exit 1
        ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$out_dir"

simv_path="${out_dir}/simv_m4_runtime_${public_tier}"
vcd_path="${out_dir}/runtime_capture.vcd"
log_path="${out_dir}/runtime_capture.log"
macro="RST_TIER_${internal_tier^^}"
filelist="m4_filelist.f"
if [[ "$internal_tier" == "tiny" && "$frozen_baseline" != "1" ]]; then
    filelist="tools/runtime_configs/m4_runtime_tiny_filelist.f"
elif [[ "$internal_tier" == "medium" ]]; then
    filelist="tools/runtime_configs/m4_runtime_medium_filelist.f"
fi

compile_cmd=(
    "$vcs_bin"
    -full64
    -sverilog
    -timescale=1ps/1ps
    "+define+${macro}"
    -top tb_M4RuntimeFileRoundTripTop
    -f "$filelist"
    m4_runtime_file_roundtrip_tb.sv
    -o "$simv_path"
)

echo "Compiling runtime harness:"
printf '  %q' "${compile_cmd[@]}"
printf '\n'
(cd "$repo_root" && "${compile_cmd[@]}")

run_cmd=(
    "$simv_path"
    "+INPUT_FILE=${input_file}"
    "+MAX_PAGES=${pages}"
    "+EXPECT_PAGES=${pages}"
    "+VCD_FILE=${vcd_path}"
)

echo "Running runtime harness:"
printf '  %q' "${run_cmd[@]}"
printf '\n'
(cd "$repo_root" && "${run_cmd[@]}") | tee "$log_path"

echo "Wrote:"
echo "  $simv_path"
echo "  $log_path"
echo "  $vcd_path"
