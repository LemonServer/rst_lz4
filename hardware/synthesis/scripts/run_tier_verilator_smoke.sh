#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <small|medium|large> <lint_m0|lint_m4|hash_table_tb|m3_roundtrip|m4_page_roundtrip>" >&2
    exit 1
fi

public_tier="$1"
target="$2"

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

if [[ -n "${VLT:-}" ]]; then
    verilator_bin="${VLT}"
elif [[ -n "${VERILATOR_BIN:-}" ]]; then
    verilator_bin="${VERILATOR_BIN}"
elif command -v verilator >/dev/null 2>&1; then
    verilator_bin="$(command -v verilator)"
else
    verilator_bin="/opt/homebrew/bin/verilator"
fi
macro="RST_TIER_${internal_tier^^}"
common_flags=(
    --timing
    -Wno-WIDTH
    -Wno-LATCH
    -Wno-UNOPTFLAT
    -Wno-IMPLICITSTATIC
    "-D${macro}"
)
timeout_flags=()

if [[ "$internal_tier" == "tiny" ]]; then
    case "$target" in
        m3_roundtrip)
            timeout_flags+=(-DM3_COMP_TIMEOUT_CYCLES=50000 -DM3_DECOMP_TIMEOUT_CYCLES=50000)
            ;;
        m4_page_roundtrip)
            timeout_flags+=(-DM4_PAGE_COMP_TIMEOUT_CYCLES=200000 -DM4_PAGE_DECOMP_TIMEOUT_CYCLES=200000)
            ;;
    esac
fi

case "$target" in
    lint_m0)
        cmd=(
            "$verilator_bin"
            --lint-only
            "${common_flags[@]}"
            --top-module CompressorTop
            -f m0_filelist.f
        )
        run_bin=""
        ;;
    lint_m4)
        cmd=(
            "$verilator_bin"
            --lint-only
            "${common_flags[@]}"
            --top-module PageCompressorTop
            -f m4_filelist.f
        )
        run_bin=""
        ;;
    hash_table_tb)
        mdir="obj_dir_hash_table_${public_tier}"
        cmd=(
            "$verilator_bin"
            -sv
            --binary
            "${common_flags[@]}"
            "${timeout_flags[@]}"
            --top-module tb_SeqUtilHashTable
            -Mdir "$mdir"
            -f compressor/tb_common.f
            compressor/seq_util_hash_table_tb.sv
        )
        run_bin="./${mdir}/Vtb_SeqUtilHashTable"
        ;;
    m3_roundtrip)
        mdir="obj_dir_m3_roundtrip_${public_tier}"
        cmd=(
            "$verilator_bin"
            -sv
            --binary
            "${common_flags[@]}"
            "${timeout_flags[@]}"
            --top-module tb_RoundTripTop
            -Mdir "$mdir"
            -f m0_filelist.f
            m3_roundtrip_tb.sv
        )
        run_bin="./${mdir}/Vtb_RoundTripTop"
        ;;
    m4_page_roundtrip)
        mdir="obj_dir_m4_page_roundtrip_${public_tier}"
        cmd=(
            "$verilator_bin"
            -sv
            --binary
            "${common_flags[@]}"
            "${timeout_flags[@]}"
            --top-module tb_M4PageRoundTripTop
            -Mdir "$mdir"
            -f m4_filelist.f
            m4_page_roundtrip_tb.sv
        )
        run_bin="./${mdir}/Vtb_M4PageRoundTripTop"
        ;;
    *)
        echo "Unknown target '$target'" >&2
        exit 1
        ;;
esac

printf 'Running:'
for arg in "${cmd[@]}"; do
    printf ' %q' "$arg"
done
printf '\n'

"${cmd[@]}"

if [[ -n "$run_bin" ]]; then
    "$run_bin"
fi
