#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  run_dc_smoke_batch.sh [--dry-run] [--fast-poc] [--clock-period <ns>] [--compile-mode <mode>] [--reuse-manifest <path>] <small|medium|large> <profile> [batch_label]
  run_dc_smoke_batch.sh --summarize-only <batch_label>

Profiles:
  parser_next
  compile_leaves_safe
  compile_leaves_extended
  m7b0_travel
  m7b2_refresh
  m7b3_assembly
  tops_only
  list

Examples:
  ./run_dc_smoke_batch.sh small parser_next
  ./run_dc_smoke_batch.sh small compile_leaves_safe
  ./run_dc_smoke_batch.sh small m7b2_refresh
  ./run_dc_smoke_batch.sh small m7b3_assembly
  ./run_dc_smoke_batch.sh --compile-mode ultra_retime small tops_only
  ./run_dc_smoke_batch.sh small m7b0_travel 20260401_trip1
EOF
}

dry_run=0
summarize_only=0
fast_poc=0
clock_period="2.0"
compile_mode="compile"
reuse_manifest=""
batch_label=""
public_tier=""
internal_tier=""
profile=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            dry_run=1
            shift
            ;;
        --reuse-manifest)
            reuse_manifest="${2:-}"
            if [[ -z "$reuse_manifest" ]]; then
                echo "Missing value for --reuse-manifest" >&2
                usage >&2
                exit 1
            fi
            shift 2
            ;;
        --fast-poc)
            fast_poc=1
            shift
            ;;
        --clock-period)
            clock_period="${2:-}"
            if [[ -z "$clock_period" ]]; then
                echo "Missing value for --clock-period" >&2
                usage >&2
                exit 1
            fi
            shift 2
            ;;
        --compile-mode)
            compile_mode="${2:-}"
            if [[ -z "$compile_mode" ]]; then
                echo "Missing value for --compile-mode" >&2
                usage >&2
                exit 1
            fi
            shift 2
            ;;
        --summarize-only)
            summarize_only=1
            batch_label="${2:-}"
            if [[ -z "$batch_label" ]]; then
                echo "Missing batch label for --summarize-only" >&2
                usage >&2
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$public_tier" ]]; then
                public_tier="$1"
            elif [[ -z "$profile" ]]; then
                profile="$1"
            elif [[ -z "$batch_label" ]]; then
                batch_label="$1"
            else
                echo "Unexpected extra argument '$1'" >&2
                usage >&2
                exit 1
            fi
            shift
            ;;
    esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
smoke_tcl="${script_dir}/synth_parser_smoke.tcl"
inventory_py="${script_dir}/inventory_dc_batch.py"

if [[ "$summarize_only" == "1" ]]; then
    batch_root="${repo_root}/synthesis/results/parser_smoke_batches/${batch_label}"
    inventory_out="${batch_root}/inventory_table.txt"
    summary_out="${batch_root}/batch_summary.txt"

    mkdir -p "$batch_root"
    python3 "$inventory_py" --batch-root "$batch_root" --format table > "$inventory_out"
    python3 "$inventory_py" --batch-root "$batch_root" --format summary > "$summary_out"
    echo "Wrote:"
    echo "  $inventory_out"
    echo "  $summary_out"
    exit 0
fi

if [[ -z "$public_tier" || -z "$profile" ]]; then
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

if [[ "$profile" == "list" ]]; then
    usage
    exit 0
fi

if [[ -z "$batch_label" ]]; then
    batch_label="$(date +%Y%m%d_%H%M%S)_${public_tier}_${profile}"
fi

batch_root="${repo_root}/synthesis/results/parser_smoke_batches/${batch_label}"
results_root="${batch_root}/results"
launch_root="${batch_root}/launch"
manifest="${batch_root}/jobs.tsv"
metadata="${batch_root}/batch_metadata.tsv"
inventory_out="${batch_root}/inventory_table.txt"
summary_out="${batch_root}/batch_summary.txt"

if [[ "$dry_run" != "1" ]]; then
    mkdir -p "$results_root" "$launch_root"
    {
        printf 'key\tvalue\n'
        printf 'batch_label\t%s\n' "$batch_label"
        printf 'launcher\t%s\n' "$(basename "$0")"
        printf 'tier\t%s\n' "$public_tier"
        printf 'internal_tier\t%s\n' "$internal_tier"
        printf 'profile\t%s\n' "$profile"
        printf 'start_epoch_s\t%s\n' "$(date +%s)"
        printf 'clock_period_ns\t%s\n' "$clock_period"
        printf 'compile_mode\t%s\n' "$compile_mode"
        printf 'constraint_profile\t%s\n' "$([[ "$fast_poc" == "1" ]] && echo fast_poc || echo nominal)"
        if [[ -n "$reuse_manifest" ]]; then
            printf 'reuse_manifest\t%s\n' "$(cd "$(dirname "$reuse_manifest")" && pwd)/$(basename "$reuse_manifest")"
        fi
    } > "$metadata"
fi

declare -a jobs=()

add_job() {
    local top="$1"
    local run_compile="$2"
    jobs+=("${top}|${run_compile}")
}

case "$profile" in
    parser_next)
        add_job DictSerializer 0
        add_job CompressorTop 0
        add_job PageCompressorTop 0
        ;;
    compile_leaves_safe)
        add_job PriorityEncoder 1
        add_job Matcher 1
        add_job Filter 1
        add_job Replacer 1
        add_job MatchFilterReplace 1
        add_job DictSerializer 1
        add_job DictDeserializer 1
        add_job FIFO 1
        add_job LifoExpander 1
        ;;
    compile_leaves_extended)
        add_job PriorityEncoder 1
        add_job Matcher 1
        add_job Filter 1
        add_job Replacer 1
        add_job MatchFilterReplace 1
        add_job DictSerializer 1
        add_job DictDeserializer 1
        add_job SeqHasher 1
        add_job SeqSorter 1
        add_job SeqAggregator 1
        add_job BankGrouper 1
        add_job FIFO 1
        add_job InitSeqCountGen 1
        add_job SeqUpdateGen 1
        add_job HashTableBank 1
        add_job HashTableSubTable 1
        add_job HashTableTop 1
        add_job UpdatePipelineN 1
        add_job LifoExpander 1
        ;;
    m7b0_travel)
        add_job CompressorTop 0
        add_job PageCompressorTop 0
        add_job DictSerializer 1
        add_job DictDeserializer 1
        add_job PriorityEncoder 1
        add_job MatchFilterReplace 1
        add_job FIFO 1
        add_job HashTableSubTable 1
        add_job HashTableTop 1
        add_job LifoExpander 1
        add_job PageDecompressorTop 1
        ;;
    m7b2_refresh)
        add_job CompressorTop 0
        add_job PageCompressorTop 0
        add_job DictSerializer 1
        add_job MatchFilterReplace 1
        add_job HashTableTop 1
        add_job LifoExpander 1
        add_job PageDecompressorTop 1
        ;;
    m7b3_assembly)
        add_job CompressorTop 1
        add_job DecompressorTop 1
        add_job PageCompressorTop 1
        ;;
    tops_only)
        add_job CompressorTop 1
        add_job DecompressorTop 1
        add_job PageCompressorTop 1
        add_job PageDecompressorTop 1
        ;;
    *)
        echo "Unknown profile '$profile'" >&2
        exit 1
        ;;
esac

if [[ "$dry_run" != "1" ]]; then
    printf "job_id\tpid\ttier\ttop\trun_compile\tlog\toutput_dir\n" > "$manifest"
fi

job_index=0
for job in "${jobs[@]}"; do
    IFS='|' read -r top run_compile <<<"$job"

    mode="elab"
    if [[ "$run_compile" == "1" ]]; then
        mode="compile"
    fi

    job_id="$(printf '%02d_%s_%s' "$job_index" "$top" "$mode" | tr '[:upper:]' '[:lower:]')"
    run_cwd="${launch_root}/${job_id}"
    log_file="${run_cwd}/dc_shell.log"
    output_dir="${results_root}/$(printf '%s_%s' "$top" "$internal_tier" | tr '[:upper:]' '[:lower:]')/${job_id}"
    xcmd="set RST_TIER ${internal_tier}; set TOP ${top}; set RUN_COMPILE ${run_compile}; set RUN_LABEL {${job_id}}; set OUTPUT_ROOT {${results_root}}; set CLK_PERIOD_NS ${clock_period}; set FAST_POC ${fast_poc}; set COMPILE_MODE ${compile_mode}"
    if [[ -n "$reuse_manifest" ]]; then
        xcmd="${xcmd}; set REUSE_MANIFEST {$(cd "$(dirname "$reuse_manifest")" && pwd)/$(basename "$reuse_manifest")}"
    fi

    if [[ "$dry_run" == "1" ]]; then
        printf '[dry-run] (%s) cd %q && nohup dc_shell -x %q -f %q > %q 2>&1 < /dev/null &\n' \
            "$job_id" "$run_cwd" "$xcmd" "$smoke_tcl" "$log_file"
        pid="DRY_RUN"
    else
        mkdir -p "$run_cwd"
        (
            cd "$run_cwd"
            nohup dc_shell -x "$xcmd" -f "$smoke_tcl" > "$log_file" 2>&1 < /dev/null &
            echo $! > pid.txt
        )
        pid="$(cat "${run_cwd}/pid.txt")"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$job_id" "$pid" "$public_tier" "$top" "$run_compile" "$log_file" "$output_dir" >> "$manifest"
    fi
    job_index=$((job_index + 1))
done

echo "Launched ${#jobs[@]} jobs for profile '${profile}'"
echo "Batch root: ${batch_root}"
echo "Manifest:   ${manifest}"

if [[ "$dry_run" != "1" ]]; then
    echo
    echo "Follow progress with:"
    echo "  column -t -s \$'\\t' ${manifest}"
    echo "  tail -f ${launch_root}"'/*/dc_shell.log'
    echo
    echo "Summarize when done with:"
    echo "  $0 --summarize-only ${batch_label}"
    echo "  sed -n '1,200p' ${summary_out}"
fi
