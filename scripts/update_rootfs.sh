#!/usr/bin/env bash
# scripts/update_rootfs.sh
# Rsyncs the sysroot into the rootfs partition of an existing boot.img.
# Use after rebuilding VesperaApps to get fresh binaries into the image
# without recreating the full disk.
#
# Usage: update_rootfs.sh <boot.img> <sysroot_dir> <vesperaos_src_dir>

set -euo pipefail

IMG_FILE="$1"
SYSROOT_DIR="$2"
SRC_DIR="$3"

if [[ ! -f "$IMG_FILE" ]]; then
    echo "[update-rootfs] ERROR: $IMG_FILE not found." >&2
    echo "  Run 'make pack' or 'make disk_image' to create the initial image." >&2
    exit 1
fi

if [[ ! -d "$SYSROOT_DIR/bin" || ! -d "$SYSROOT_DIR/usr/lib" ]]; then
    echo "[update-rootfs] ERROR: sysroot looks empty or incomplete: $SYSROOT_DIR" >&2
    echo "  Run 'make build-libs' (VesperaOS) and 'make build-apps' (VesperaApps) first." >&2
    exit 1
fi

# rsync is much faster than cp -r for incremental updates; require it.
if ! command -v rsync &>/dev/null; then
    echo "[update-rootfs] ERROR: rsync not found. Install it (e.g. pacman -S rsync)." >&2
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
echo "[update-rootfs] Loop device: $LOOPDEV"

sudo mount "${LOOPDEV}p2" "$MNT_DIR"

# Sync all standard FHS directories from the sysroot.
for dir in bin lib etc tmp mnt var root home; do
    if [[ -d "$SYSROOT_DIR/$dir" ]]; then
        sudo mkdir -p "$MNT_DIR/$dir"
        sudo rsync -a --delete "$SYSROOT_DIR/$dir/" "$MNT_DIR/$dir/"
    fi
done

# VesperaOS-side assets (fonts, test images, etc.)
if [[ -f "$SRC_DIR/assets/test.jpg" ]]; then
    sudo cp "$SRC_DIR/assets/test.jpg" "$MNT_DIR/"
fi
if [[ -f "$SRC_DIR/assets/CaskaydiaCoveNerdFontMono.ttf" ]]; then
    sudo mkdir -p "$MNT_DIR/etc/fonts"
    sudo cp "$SRC_DIR/assets/CaskaydiaCoveNerdFontMono.ttf" "$MNT_DIR/etc/fonts/"
fi

# su needs the setuid bit after every rsync (rsync strips it)
if [[ -f "$MNT_DIR/bin/su" ]]; then
    sudo chown root:root "$MNT_DIR/bin/su"
    sudo chmod 4755      "$MNT_DIR/bin/su"
fi

sudo umount "$MNT_DIR"
sudo losetup -d "$LOOPDEV"
LOOPDEV=""

echo "[update-rootfs] Done — rootfs updated from sysroot."