#!/usr/bin/env bash
# scripts/update_kernel.sh
# Replaces kernel.elf in the EFI partition of an existing boot.img.
# Much faster than recreating the full disk image — use for kernel-only iterations.
#
# Usage: update_kernel.sh <boot.img> <kernel.elf>

set -euo pipefail

IMG_FILE="$1"
KERNEL_ELF="$2"

if [[ ! -f "$IMG_FILE" ]]; then
    echo "[update-kernel] ERROR: $IMG_FILE not found." >&2
    echo "  Run 'make pack' or 'make disk_image' to create the initial image." >&2
    exit 1
fi

if [[ ! -f "$KERNEL_ELF" ]]; then
    echo "[update-kernel] ERROR: kernel ELF not found: $KERNEL_ELF" >&2
    exit 1
fi

MNT_DIR=$(mktemp -d)
LOOPDEV=""

cleanup() {
    sudo umount "$MNT_DIR" 2>/dev/null || true
    [[ -n "$LOOPDEV" ]] && sudo losetup -d "$LOOPDEV" 2>/dev/null || true
    rm -rf "$MNT_DIR"
}
trap cleanup EXIT

LOOPDEV=$(sudo losetup -fP --show "$IMG_FILE")
echo "[update-kernel] Loop device: $LOOPDEV"

sudo mount "${LOOPDEV}p1" "$MNT_DIR"
sudo cp "$KERNEL_ELF" "$MNT_DIR/kernel.elf"
sudo umount "$MNT_DIR"

sudo losetup -d "$LOOPDEV"
LOOPDEV=""

echo "[update-kernel] Done — kernel updated in EFI partition."