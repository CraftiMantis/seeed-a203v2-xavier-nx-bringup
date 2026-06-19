#!/usr/bin/env bash
# Step 2 — populate the rootfs, apply NVIDIA binaries, and flash the Xavier NX
# to eMMC. Needs sudo AND the board in force-recovery mode.
#
# Run step 1 (flash/01-get-bsp.sh) first to assemble LDK_DIR.
#
# Usage:
#   export LDK_DIR=~/nvidia/a203-xavier-r35.6.1/Linux_for_Tegra
#   sudo -E bash flash/02-flash-board.sh
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "run as root (sudo -E, so LDK_DIR is preserved)"; exit 2; }

LDK_DIR="${LDK_DIR:-}"
[[ -n "$LDK_DIR" && -f "$LDK_DIR/flash.sh" ]] || { echo "Set LDK_DIR to the assembled Linux_for_Tegra (run flash/01-get-bsp.sh first)."; exit 2; }
ROOTFS_TBZ="${ROOTFS_TBZ:-$(dirname "$LDK_DIR")/rootfs.tbz2}"
BOARD="${BOARD:-jetson-xavier-nx-devkit-emmc}"   # the validated target for this carrier
ROOTDEV="${ROOTDEV:-mmcblk0p1}"
RCM="0955:7e19"

if [[ ! -e "$LDK_DIR/rootfs/etc/passwd" ]]; then
  [[ -f "$ROOTFS_TBZ" ]] || { echo "sample rootfs not found at $ROOTFS_TBZ (set ROOTFS_TBZ=...)"; exit 2; }
  echo "[1/3] unpack sample rootfs"
  tar -xpf "$ROOTFS_TBZ" -C "$LDK_DIR/rootfs/"
else
  echo "[1/3] rootfs already populated"
fi

echo "[2/3] apply_binaries.sh (merges NVIDIA + Seeed userspace into the rootfs)"
( cd "$LDK_DIR" && ./apply_binaries.sh )

echo "[3/3] flash"
if ! lsusb | grep -qi "$RCM"; then
  cat <<EOF
Board is not in force-recovery mode (lsusb $RCM not found).
  A203-V2: power off -> jumper J12 pin 3 (FC_REC) <-> GND -> USB-C to host -> power on
  (A203 V1 uses a different pin; check the silkscreen.)
Then re-run this script.
EOF
  exit 4
fi
echo "  recovery OK: $(lsusb | grep -i $RCM)"
echo "  flashing $BOARD $ROOTDEV — this rewrites the board, ~10-15 min"
( cd "$LDK_DIR" && ./flash.sh "$BOARD" "$ROOTDEV" )

echo "DONE. Remove the FC_REC jumper, power-cycle. The board boots to first-boot setup."
echo "Next: claim the header pins -> flash/03-claim-hdr40-pins.sh"
