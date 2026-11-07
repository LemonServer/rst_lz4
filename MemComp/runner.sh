set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run.sh --compression "lz4 zstd ..." [--output report.csv] [--list files.txt]

Options:
  --compression  Space- or comma-separated list of compression targets to build (required)
  --output       Output CSV file to write results to (default: report.csv)
  --list         Text file containing file paths, one per line. Lines starting with '#' are comments.
                 If omitted, defaults to: ../5kcorrectdumps/*
  --help         Show this message
EOF
}

OUTPUT="report.csv"
COMP_LIST=""
LIST_FILE=""
INPUTS=()

# Parse long options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { echo "ERROR: --output needs a value"; usage; exit 1; }
      OUTPUT="$2"; shift 2;;
    --output=*)   OUTPUT="${1#*=}"; shift;;
    --compression)
      [[ $# -ge 2 ]] || { echo "ERROR: --compression needs a value"; usage; exit 1; }
      COMP_LIST="$2"; shift 2;;
    --compression=*) COMP_LIST="${1#*=}"; shift;;
    --list)
      [[ $# -ge 2 ]] || { echo "ERROR: --list needs a file path"; usage; exit 1; }
      LIST_FILE="$2"; shift 2;;
    --list=*)     LIST_FILE="${1#*=}"; shift;;
    --help|-h)    usage; exit 0;;
    *)            echo "ERROR: Unknown argument: $1"; usage; exit 1;;
  esac
done

if [[ -z "${COMP_LIST}" ]]; then
  echo "ERROR: --compression is required."
  usage
  exit 1
fi

# Normalize compression list: allow commas or spaces
# shellcheck disable=SC2206
COMPRESSIONS=(${COMP_LIST//,/ })

# --- Build phase (runs on the allocated node) ---
echo "[memcomp] building baseline binaries..."
make -s clean
make -s bootstrap driver
for comp in "${COMPRESSIONS[@]}"; do
  make -s "$comp"
done

# Start fresh output file
: > "${OUTPUT}"

# Helper: trim leading/trailing whitespace
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"  # leading
  s="${s%"${s##*[![:space:]]}"}"  # trailing
  printf '%s' "$s"
}

process_file() {
  local fp="$1"
  local idx="$2"
  local total="$3"
  if [[ -z "$fp" ]]; then
    return
  fi
  if [[ ! -e "$fp" ]]; then
    echo "WARN: File not found: $fp" >&2
    return
  fi
  echo "[memcomp ${idx}/${total}] $(basename "$fp")"
  # Ensure the task does NOT read from the list file's stdin:
  # - --input=none prevents srun from attaching stdin
  # - </dev/null is a belt-and-suspenders to stop ./bin/driver from reading the loop's stdin
  if ! ./bin/driver -v -f "$fp" >> "${OUTPUT}" </dev/null; then
    echo "WARN: driver failed for $fp (continuing)" >&2
  fi
}

if [[ -n "${LIST_FILE}" ]]; then
  if [[ ! -r "${LIST_FILE}" ]]; then
    echo "ERROR: Cannot read --list file: ${LIST_FILE}"
    exit 1
  fi
  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line="$(trim "$raw_line")"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    INPUTS+=("$line")
  done < "${LIST_FILE}"
else
  shopt -s nullglob
  for filename in ../5kcorrectdumps/*; do
    INPUTS+=("$filename")
  done
fi

if [[ "${#INPUTS[@]}" -eq 0 ]]; then
  echo "ERROR: No input dumps found."
  exit 1
fi

echo "[memcomp] built targets: ${COMPRESSIONS[*]}"
echo "[memcomp] processing ${#INPUTS[@]} dump(s)..."

for idx in "${!INPUTS[@]}"; do
  process_file "${INPUTS[$idx]}" "$((idx + 1))" "${#INPUTS[@]}"
done
