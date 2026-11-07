#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_USER="${VM_USER:-debian}"
VM_HOST="${VM_HOST:-localhost}"
SSH_PORT="${SSH_PORT:-2222}"
VM_DEST="${VM_DEST:-/home/debian/artifact}"
GUEST_README_DEST="${GUEST_README_DEST:-/home/debian/README.md}"
SSH_KEY="${SSH_KEY:-}"

usage() {
  cat <<'EOF'
Usage:
  bash sync_to_vm.sh

Environment overrides:
  SSH_PORT   SSH port for the VM (default: 2222)
  VM_USER    SSH username (default: debian)
  VM_HOST    SSH hostname (default: localhost)
  VM_DEST    Destination directory in the guest (default: /home/debian/artifact)
  GUEST_README_DEST  Guest landing-page README path (default: /home/debian/README.md)
  SSH_KEY    Optional SSH private key path

This script syncs the current host checkout into the guest artifact directory.
It intentionally excludes the QCOW2 image, generated outputs, Python venvs, and
archived reference bundles.
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
  --exclude='./debian-12-genericcloud-amd64.qcow2' \
  --exclude='./seed.img' \
  --exclude='./generated' \
  --exclude='./.venv' \
  --exclude='./reference' \
  -cf - \
  README.md \
  LICENSE \
  GUEST_HOME_README.md \
  install.sh \
  bootvm.sh \
  vm_bootstrap.sh \
  sync_to_vm.sh \
  regenerate_figures.sh \
  MemComp \
  ablation \
  rst_figures \
  5kcorrectdumps \
| ssh "${ssh_opts[@]}" "${remote}" "mkdir -p '${VM_DEST}' && find '${VM_DEST}' -mindepth 1 -maxdepth 1 ! -name .venv -exec rm -rf {} + && tar -C '${VM_DEST}' -xf -"

ssh "${ssh_opts[@]}" "${remote}" "cat > '${GUEST_README_DEST}'" < "${ROOT_DIR}/GUEST_HOME_README.md"

echo "Synced host checkout to ${remote}:${VM_DEST}"
echo "Updated guest landing page at ${remote}:${GUEST_README_DEST}"
