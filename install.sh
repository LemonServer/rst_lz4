#!/usr/bin/env bash
set -e

info() { echo "[INFO]  $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

case "$(uname -s)" in
    Darwin)
        if ! command -v brew &>/dev/null; then
            die "Homebrew not found. Install it from https://brew.sh then re-run."
        fi
        info "Installing qemu via Homebrew..."
        brew install qemu
        ;;
    Linux)
        if command -v apt-get &>/dev/null; then
            info "Installing qemu via apt..."
            sudo apt-get update -y
            sudo apt-get install -y qemu-system-x86 qemu-utils
        elif command -v dnf &>/dev/null; then
            info "Installing qemu via dnf..."
            sudo dnf install -y qemu-kvm qemu-img
        elif command -v pacman &>/dev/null; then
            info "Installing qemu via pacman..."
            sudo pacman -Sy --noconfirm qemu-system-x86
        else
            die "No supported package manager found (apt/dnf/pacman). Install QEMU manually."
        fi
        ;;
    *)
        die "Unsupported OS: $(uname -s)"
        ;;
esac

info "Done! QEMU installed successfully."