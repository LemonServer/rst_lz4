#!/usr/bin/env bash
set -e

IMAGE="${IMAGE:-debian-12-genericcloud-amd64.qcow2}"
SEED="${SEED:-}"
MEM="${MEM:-8192}"
CPUS="${CPUS:-8}"
SSH_PORT="${SSH_PORT:-2222}"
HOST_SHARE_DIR="${HOST_SHARE_DIR:-}"
HOST_SHARE_TAG="${HOST_SHARE_TAG:-hostshare}"

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO]  $*"; }

[ -f "$IMAGE" ] || die "Disk image not found: $IMAGE"

if [ "$(uname -s)" = "Linux" ] && [ -e /dev/kvm ]; then
    ACCEL_FLAGS="-accel kvm"
    CPU_FLAGS="-cpu host"
    info "KVM available — enabling."
else
    ACCEL_FLAGS="-accel tcg"
    CPU_FLAGS="-cpu max"
fi

QEMU_CMD="qemu-system-x86_64 \
    -m ${MEM} \
    -smp ${CPUS} \
    $ACCEL_FLAGS $CPU_FLAGS \
    -drive file=${IMAGE},format=qcow2,if=virtio \
    -net nic,model=virtio \
    -net user,hostfwd=tcp::${SSH_PORT}-:22 \
    -nographic"

if [ -n "$SEED" ]; then
    [ -f "$SEED" ] || die "Seed image not found: $SEED"
    QEMU_CMD="$QEMU_CMD -drive file=${SEED},format=raw,if=virtio"
fi

if [ -n "$HOST_SHARE_DIR" ]; then
    [ -d "$HOST_SHARE_DIR" ] || die "Host share directory not found: $HOST_SHARE_DIR"
    info "Host share: ${HOST_SHARE_DIR} (exported as FAT-backed virtio disk)"
    QEMU_CMD="$QEMU_CMD -drive file=fat:rw:${HOST_SHARE_DIR},format=raw,if=virtio"
fi

info "SSH: ssh -p ${SSH_PORT} debian@localhost"
info "Exit: sudo poweroff inside the VM"
info "user:debian"
info "pw:<empty> (press Enter if prompted)"
sleep 5
info "starting qemu..."
echo ""
eval $QEMU_CMD
