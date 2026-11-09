# Source from the repository root; no login or VM is created.
RST_ARTIFACT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RST_ARTIFACT_ROOT
export RST_HW_ROOT="${RST_HW_ROOT:-$RST_ARTIFACT_ROOT/hardware}"
_rst_tools="$RST_ARTIFACT_ROOT/reproduction/extracted/home/debian/verilator-5.046"
if [[ -x "$_rst_tools/bin/verilator_bin" ]]; then
  export VERILATOR_ROOT="${VERILATOR_ROOT:-$_rst_tools/share/verilator}"
  export RST_VERILATOR_BIN="${RST_VERILATOR_BIN:-$_rst_tools/bin/verilator_bin}"
else
  export RST_VERILATOR_BIN="${RST_VERILATOR_BIN:-$(command -v verilator || true)}"
fi
unset _rst_tools
export MPLBACKEND=Agg
export CPUS="${CPUS:-8}"
