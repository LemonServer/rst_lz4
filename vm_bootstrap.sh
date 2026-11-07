#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${ROOT_DIR}/.venv"
export DEBIAN_FRONTEND=noninteractive

echo "[1/4] Installing VM packages..."
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  python3-pip \
  python3-venv \
  poppler-utils

echo "[2/4] Preparing Python virtual environment..."
if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  python3 -m venv "${VENV_DIR}"
else
  echo "Venv already exists at ${VENV_DIR}; reusing it."
fi

echo "[3/4] Installing Python dependencies..."
"${VENV_DIR}/bin/pip" install --upgrade pip
"${VENV_DIR}/bin/pip" install matplotlib numpy SciencePlots

echo "[4/4] VM bootstrap complete."
echo "Venv: ${VENV_DIR}"
echo "Next:"
echo "  bash regenerate_figures.sh --quick"
echo "  bash regenerate_figures.sh"
