#!/usr/bin/env bash
# Stop UEFI from using UART_A (J12 pin 8/10) as its boot console on a
# Seeed A203 / A203-V2 + Jetson Xavier NX (JetPack 5.x / L4T r35.x).
#
# THE PROBLEM (a JetPack 5.x Xavier-NX regression):
#   The UEFI bootloader uses serial@3100000 (= /dev/ttyTHS0 = J12 pin 8/10)
#   as its console. If any peripheral (MCU, FTDI, sensor) is powered on that
#   UART when the Xavier boots, UEFI reads the incoming bytes as console
#   input and hangs / aborts the boot. You only find this out when "the board
#   won't boot with my serial device plugged in."
#
# THE FIX (dual-DTB — NVIDIA-endorsed, forum topic 273815):
#   Point the bootloader DTB (TBCDTB_FILE) at a copy with serial@3100000
#   DISABLED, while leaving the kernel DTB (DTB_FILE) ENABLED. Result: UEFI
#   no longer listens on UART_A, but Linux still exposes /dev/ttyTHS0 fully.
#   The Seeed BSP already has a separate `bootloader-dtb` partition, so this
#   is a partial reflash — kernel, rootfs, and everything else are untouched.
#
# This script only does the BUILD-TIME edits (decompile, patch, recompile,
# update the conf). It then prints the exact flash command for you to run
# with the board in force-recovery mode. Idempotent and reversible.
#
# Usage:
#   LDK_DIR=/path/to/Linux_for_Tegra sudo -E bash flash/04-fix-uart-boot-hang.sh
set -euo pipefail

LDK_DIR="${LDK_DIR:-}"
[[ -n "$LDK_DIR" && -d "$LDK_DIR" ]] || {
  echo "Set LDK_DIR to your Linux_for_Tegra (Seeed BSP) directory, e.g.:"
  echo "  LDK_DIR=~/nvidia/seeed-l4t-r35.6.1 sudo -E bash flash/04-fix-uart-boot-hang.sh"
  exit 2; }

DTB_DIR="${LDK_DIR}/kernel/dtb"
CONF="${LDK_DIR}/p3668.conf.common"
STOCK_DTB_NAME="${STOCK_DTB_NAME:-tegra194-p3668-all-p3509-0000.dtb}"
PATCHED_DTB_NAME="${STOCK_DTB_NAME%.dtb}-noUART1-uefi.dtb"
STOCK_DTB="${DTB_DIR}/${STOCK_DTB_NAME}"
PATCHED_DTB="${DTB_DIR}/${PATCHED_DTB_NAME}"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DTB="/tmp/uefi-dtb-stock-${TS}.dtb.bak"
BACKUP_CONF="/tmp/p3668.conf.common-pre-noUART1-${TS}.bak"

banner() { printf '\n=== %s ===\n' "$*"; }

banner "0. preflight"
command -v dtc >/dev/null || { echo "FATAL: dtc missing (apt install device-tree-compiler)"; exit 2; }
[[ -f "${STOCK_DTB}" ]] || { echo "FATAL: stock DTB not found: ${STOCK_DTB}"; exit 2; }
[[ -f "${CONF}"      ]] || { echo "FATAL: ${CONF} not found"; exit 2; }
echo "  BSP:       ${LDK_DIR}"
echo "  stock DTB: ${STOCK_DTB} (md5 $(md5sum "${STOCK_DTB}" | cut -d' ' -f1))"

banner "1. backup stock DTB + conf"
cp -n "${STOCK_DTB}" "${BACKUP_DTB}" || true
cp -n "${CONF}"      "${BACKUP_CONF}" || true
echo "  ${BACKUP_DTB}"; echo "  ${BACKUP_CONF}"

banner "2. decompile + disable serial@3100000 (line-scoped, node-only)"
TMP_DTS="/tmp/uefi-dtb-${TS}.dts"
dtc -q -I dtb -O dts -o "${TMP_DTS}" "${STOCK_DTB}" 2>/dev/null
NODE_START=$(grep -n '^[[:space:]]*serial@3100000 {' "${TMP_DTS}" | head -1 | cut -d: -f1)
[[ -n "${NODE_START}" ]] || { echo "FATAL: serial@3100000 node not found"; exit 3; }
NODE_END=$(awk -v s="${NODE_START}" 'NR>s && /^\t};/ {print NR; exit}' "${TMP_DTS}")
[[ -n "${NODE_END}" ]] || { echo "FATAL: no closing brace for serial@3100000"; exit 3; }
echo "  node spans DTS lines ${NODE_START}..${NODE_END}"
COUNT=$(awk -v a="${NODE_START}" -v b="${NODE_END}" 'NR>=a&&NR<=b&&/status[[:space:]]*=/' "${TMP_DTS}" | wc -l)
[[ "${COUNT}" -eq 1 ]] || { echo "FATAL: expected 1 status= line in node, found ${COUNT}"; exit 3; }
CUR=$(awk -v a="${NODE_START}" -v b="${NODE_END}" 'NR>=a&&NR<=b&&/status[[:space:]]*=/' "${TMP_DTS}" | sed -E 's/.*"([^"]*)".*/\1/')
if [[ "${CUR}" == "disabled" ]]; then echo "  already disabled — no-op";
else
  sed -i "${NODE_START},${NODE_END} s/status = \"okay\";/status = \"disabled\";/" "${TMP_DTS}"
  NEW=$(awk -v a="${NODE_START}" -v b="${NODE_END}" 'NR>=a&&NR<=b&&/status[[:space:]]*=/' "${TMP_DTS}" | sed -E 's/.*"([^"]*)".*/\1/')
  [[ "${NEW}" == "disabled" ]] || { echo "FATAL: patch failed (got \"${NEW}\")"; exit 3; }
  echo "  status okay -> disabled"
fi

banner "3. recompile patched DTB"
dtc -q -I dts -O dtb -o "${PATCHED_DTB}" "${TMP_DTS}" 2>/dev/null
chmod 0644 "${PATCHED_DTB}"
echo "  ${PATCHED_DTB} (md5 $(md5sum "${PATCHED_DTB}" | cut -d' ' -f1))"

banner "4. round-trip verify"
RT=$(dtc -q -I dtb -O dts "${PATCHED_DTB}" 2>/dev/null | awk '/serial@3100000 {/,/^\t};/' | grep -E 'status[[:space:]]*=' | head -1 | sed -E 's/.*"([^"]*)".*/\1/')
[[ "${RT}" == "disabled" ]] || { echo "FATAL: round-trip shows status=\"${RT}\""; exit 4; }
echo "  patched DTB round-trip: status=\"disabled\" OK"

banner "5. point TBCDTB_FILE at the patched DTB (kernel DTB_FILE unchanged)"
sed -i "s|^TBCDTB_FILE=.*|TBCDTB_FILE=${PATCHED_DTB_NAME};|" "${CONF}"
echo "  TBCDTB_FILE -> ${PATCHED_DTB_NAME}"
echo "  DTB_FILE (kernel) stays: $(grep -E '^DTB_FILE=' "${CONF}" | head -1 | sed -E 's/^DTB_FILE=([^;]*);?.*/\1/')"

banner "6. flash the bootloader-dtb partition (board in recovery mode)"
cat <<EOF

  Build-time changes done. Put the Xavier in force-recovery mode:
    A203-V2: jumper J12 pin 3 (FC_REC) <-> GND, USB-C to host, power on
    verify: lsusb | grep 0955:7e19   (NVIDIA APX)
  then:
    cd ${LDK_DIR}
    sudo ./flash.sh -k bootloader-dtb jetson-xavier-nx-devkit-emmc mmcblk0p1

  Partial flash: ONLY bootloader-dtb is rewritten; kernel/rootfs preserved.

  Verify after boot (with your serial device ALREADY powered on pin 8/10 —
  the board should now boot cleanly):
    cat /proc/device-tree/serial@3100000/status   # -> okay  (kernel side)
    ls /dev/ttyTHS0                                # -> present

  Rollback:
    sudo cp ${BACKUP_DTB} ${STOCK_DTB}
    sudo cp ${BACKUP_CONF} ${CONF}
    sudo rm -f ${PATCHED_DTB}
    # then re-flash bootloader-dtb with the restored stock DTB
EOF
