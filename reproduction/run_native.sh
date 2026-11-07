#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$RST_ARTIFACT_ROOT"
mode="${1:-verify}"
if [[ $# -gt 0 ]]; then shift; fi
case "$mode" in
 verify)
  python3 "$RST_HW_ROOT/tools/run_rst_verify.py" --jobs 2 --build-jobs 2 --verilator-bin "$RST_VERILATOR_BIN" --roundtrip-build-dir build/native/roundtrip --decompressor-build-dir build/native/decompressor --latency-build-dir build/native/latency --cpp-build-dir build/native/cpp --log-dir build/native/logs --write-json build/native/latest-result.json "$@"
  ;;
 quick|full|full-stage-v)
  if [[ -d generated ]]; then
   mv generated "reproduction/generated-before-${mode}-$(date +%Y%m%d-%H%M%S)"
  fi
  opts=()
  [[ "$mode" != quick ]] || opts+=(--quick)
  [[ "$mode" != full-stage-v ]] || opts+=(--rerun-stage-v)
  bash regenerate_figures.sh "${opts[@]}" "$@"
  ;;
 *) echo 'Usage: bash reproduction/run_native.sh {verify|quick|full|full-stage-v} [extra options]' >&2; exit 2;;
esac
