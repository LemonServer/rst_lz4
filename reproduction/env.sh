# Source this file from the existing SSH shell; no extra login is created.
RST_ARTIFACT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RST_ARTIFACT_ROOT
export RST_HW_ROOT="$RST_ARTIFACT_ROOT/reproduction/extracted/home/debian/hw_artifact/rst-hardware"
export VERILATOR_ROOT="$RST_ARTIFACT_ROOT/reproduction/extracted/home/debian/verilator-5.046/share/verilator"
export RST_VERILATOR_BIN="$RST_ARTIFACT_ROOT/reproduction/extracted/home/debian/verilator-5.046/bin/verilator_bin"
export MPLBACKEND=Agg
export CPUS=8
