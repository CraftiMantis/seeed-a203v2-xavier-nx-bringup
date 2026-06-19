#!/usr/bin/env bash
# Step 1 — download + assemble the Seeed A203 / A203-V2 BSP for Jetson Xavier NX
# (L4T r35.6.1 = JetPack 5.1.4). No sudo. Idempotent.
#
# Follows Seeed's documented flow:
#   https://wiki.seeedstudio.com/reComputer_A203_Flash_System/
#
# Sources pulled (all public, no NGC / Dev-Zone login):
#   NVIDIA L4T r35.6.1 BSP + sample rootfs   (developer.nvidia.com)
#   Bootlin GCC-9.3 aarch64 toolchain        (developer.nvidia.com)
#   Seeed carrier BSP                        (github.com/Seeed-Studio/Linux_for_Tegra, branch r35.6.1)
#
# Result: $STAGING/Linux_for_Tegra (the carrier-aware BSP) + $STAGING/rootfs.tbz2.
# Then run step 2.
#
# Usage:  STAGING=~/nvidia/a203-xavier bash flash/01-get-bsp.sh
set -euo pipefail
[[ "${EUID}" -ne 0 ]] || { echo "run as your normal user (NO sudo)"; exit 2; }
command -v git  >/dev/null || { echo "install git";  exit 2; }
command -v wget >/dev/null || { echo "install wget"; exit 2; }

STAGING="${STAGING:-$HOME/nvidia/a203-xavier-r35.6.1}"
mkdir -p "$STAGING"; cd "$STAGING"

# --- Verified references (NVIDIA L4T r35.6.1; Seeed branch r35.6.1) -----------
BSP_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/release/jetson_linux_r35.6.1_aarch64.tbz2"
RFS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/tegra_linux_sample-root-filesystem_r35.6.1_aarch64.tbz2"
TC_URL="https://developer.nvidia.com/embedded/jetson-linux/bootlin-toolchain-gcc-93"
SEEED_GIT="https://github.com/Seeed-Studio/Linux_for_Tegra.git"   # branch r35.6.1
# -----------------------------------------------------------------------------

echo "[1/5] download NVIDIA L4T r35.6.1 BSP + rootfs + toolchain (~1.5 GB total)"
wget -c -nv --show-progress -O jetson_linux.tbz2  "$BSP_URL"
wget -c -nv --show-progress -O rootfs.tbz2        "$RFS_URL"
wget -c -nv --show-progress -O bootlin-gcc93.tar.gz "$TC_URL"

echo "[2/5] extract NVIDIA BSP -> Linux_for_Tegra/"
[[ -d Linux_for_Tegra ]] || tar -xjf jetson_linux.tbz2

echo "[3/5] clone Seeed Linux_for_Tegra (branch r35.6.1)"
[[ -d seeed_lft/.git ]] || git clone --depth 1 --branch r35.6.1 "$SEEED_GIT" seeed_lft

echo "[4/5] overlay Seeed carrier BSP onto Linux_for_Tegra/"
cp -rf seeed_lft/. Linux_for_Tegra/

echo "[5/5] unpack the Bootlin toolchain into Linux_for_Tegra/l4t-gcc/"
mkdir -p Linux_for_Tegra/l4t-gcc
[[ -x Linux_for_Tegra/l4t-gcc/bin/aarch64-buildroot-linux-gnu-gcc ]] || tar xf bootlin-gcc93.tar.gz -C Linux_for_Tegra/l4t-gcc

cat <<EOF

DONE. BSP assembled:
  LDK_DIR=$STAGING/Linux_for_Tegra
  rootfs tarball still at $STAGING/rootfs.tbz2 (step 2 unpacks it as root)

Next:
  export LDK_DIR=$STAGING/Linux_for_Tegra
  sudo -E bash flash/02-flash-board.sh     # with the board in recovery mode
EOF
