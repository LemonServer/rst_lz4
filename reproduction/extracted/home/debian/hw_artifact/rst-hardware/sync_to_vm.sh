#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_USER="${VM_USER:-debian}"
VM_HOST="${VM_HOST:-localhost}"
SSH_PORT="${SSH_PORT:-2222}"
VM_DEST="${VM_DEST:-/home/debian/hw_artifact/rst-hardware}"
SSH_KEY="${SSH_KEY:-}"

usage() {
  cat <<'EOF'
Usage:
  bash sync_to_vm.sh

Environment overrides:
  SSH_PORT   SSH port for the VM (default: 2222)
  VM_USER    SSH username (default: debian)
  VM_HOST    SSH hostname (default: localhost)
  VM_DEST    Destination directory in the guest (default: /home/debian/hw_artifact/rst-hardware)
  SSH_KEY    Optional SSH private key path
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

ssh_opts=(
  -p "${SSH_PORT}"
  -o StrictHostKeyChecking=no
)

if [[ -n "${SSH_KEY}" ]]; then
  ssh_opts+=(-i "${SSH_KEY}")
fi

remote="${VM_USER}@${VM_HOST}"

tar -C "${ROOT_DIR}" \
  --exclude='./build' \
  --exclude='./dist' \
  --exclude='./__pycache__' \
  --exclude='./evidence/__pycache__' \
  -cf - \
  README.md \
  sync_to_vm.sh \
  compressor \
  data \
  decompressor \
  docs \
  evidence \
  experimental \
  helpful_files \
  notes_internal \
  synthesis \
  third_party \
  tools \
  m0_filelist.f \
  m4_filelist.f \
  rst_pkg.sv \
  dict_packed_codec.sv \
  m2_page_compressor_experimental_bits_tb.sv \
  m2_page_compressor_free_prefix_tb.sv \
  m3_file_roundtrip_tb.sv \
  m3_roundtrip_tb.sv \
  m4_file_roundtrip_tb.sv \
  m4_page_roundtrip_tb.sv \
  m4_runtime_file_experimental_tb.sv \
  m4_runtime_file_roundtrip_tb.sv \
  m6_dict_serialization_tb.sv \
| ssh "${ssh_opts[@]}" "${remote}" "mkdir -p '${VM_DEST}' && find '${VM_DEST}' -mindepth 1 -maxdepth 1 ! -name build -exec rm -rf {} + && tar -C '${VM_DEST}' -xf -"

echo "Synced host checkout to ${remote}:${VM_DEST}"
