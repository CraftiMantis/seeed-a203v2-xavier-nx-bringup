#!/usr/bin/env bash
# Claim all 40-pin header (J12) functions on a Seeed A203 / A203-V2 + Jetson
# Xavier NX by patching the MB1_BCT pinmux and reflashing that partition.
#
# THE PROBLEM:
#   The stock Seeed A203 pinmux leaves ~19 J12 header pins in "MUX UNCLAIMED"
#   (UART_A, I2S5, AUD_MCLK, SPI1_CS1, PWM5/7, GPIO01/07/11/12/13). Those pins
#   are dead until the bootloader pinmux claims them — a kernel-side overlay
#   alone won't do it, because the pad control is set in MB1_BCT at boot.
#
# THE FIX:
#   Patch bootloader/t186ref/BCT/tegra19x-mb1-pinmux-p3668-a01.cfg with the 15
#   PADCTL register overrides below, then `flash.sh -k MB1_BCT`. This is a
#   partial reflash — rootfs/kernel/NVMe are out of reach of -k MB1_BCT.
#
# A subtle flash.sh bug is handled in stage 1 (see comment there) — it's the
# reason naive attempts die at the tegraflash sign step.
#
# Run with the board in force-recovery mode (lsusb shows 0955:7e19):
#   LDK_DIR=/path/to/Linux_for_Tegra sudo -E bash flash/mb1-bct-hdr40-pinmux.sh
set -uo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "must run as root (sudo -E)"; exit 2; }
LDK_DIR="${LDK_DIR:-}"
[[ -n "$LDK_DIR" && -d "$LDK_DIR" ]] || { echo "Set LDK_DIR to your Linux_for_Tegra (Seeed BSP) dir."; exit 2; }
BOARD="${BOARD:-jetson-xavier-nx-devkit-emmc}"
ROOTDEV="${ROOTDEV:-mmcblk0p1}"
CFG="${LDK_DIR}/bootloader/t186ref/BCT/tegra19x-mb1-pinmux-p3668-a01.cfg"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${LDK_DIR}/.bringup_backups/pinmux_${TS}"; mkdir -p "${BACKUP_DIR}"
RCM="0955:7e19"

# addr:value:comment  — Xavier NX (Tegra194) PADCTL registers for the J12 hdr40.
PINMUX_PATCHES=(
  "0x024300a8:0x00000400:uart1_tx_pr2  UART_A TX  (pin 8)"
  "0x024300a0:0x00000454:uart1_rx_pr3  UART_A RX  (pin 10) pull-down"
  "0x02430098:0x00000400:uart1_rts_pr4 UART_A RTS (pin 11)"
  "0x02430090:0x00000458:uart1_cts_pr5 UART_A CTS (pin 36) pull-up"
  "0x02431080:0x00000402:dap5_sclk_pt5 I2S5 SCLK  (pin 12)"
  "0x02431068:0x00000456:dap5_fs_pu0   I2S5 FS    (pin 35)"
  "0x02431070:0x00000456:dap5_din_pt7  I2S5 DIN   (pin 38) E_INPUT=1"
  "0x02431078:0x00000402:dap5_dout_pt6 I2S5 DOUT  (pin 40)"
  "0x02431020:0x00000400:aud_mclk_ps4  AUD_MCLK   (pin 7)"
  "0x0243d050:0x00000400:spi1_cs1_pz7  SPI1 CS1   (pin 26)"
  "0x0c302000:0x00000040:touch_clk_pcc4 GPIO12    (pin 15)"
  "0x02430028:0x00000040:soc_gpio41_pq5 GPIO01    (pin 29)"
  "0x02430030:0x00000040:soc_gpio42_pq6 GPIO11    (pin 31)"
  "0x02430040:0x00000040:soc_gpio44_pr0 GPIO07/PWM5 (pin 32)"
  "0x02440020:0x00000040:soc_gpio54_pn1 GPIO13/PWM7 (pin 33)"
)

banner(){ echo; echo "==== $* ===="; }
fail(){ echo "FAIL: $*" >&2; exit 3; }
have_rcm(){ lsusb | grep -qi "${RCM}"; }

banner "stage 0 preflight"
[[ -f "${LDK_DIR}/flash.sh" ]] || fail "${LDK_DIR}/flash.sh missing"
[[ -f "${CFG}" ]] || fail "${CFG} missing"
have_rcm || fail "board not in recovery mode (lsusb ${RCM}). Jumper J12 pin3<->GND + USB + power on."
echo "  RCM: $(lsusb | grep -i ${RCM})"

# STAGE 1 — work around flash.sh creating rootfs/etc as a FILE.
# flash.sh does `cp -f nv_boot_control.conf rootfs/etc`; if rootfs/etc is
# missing, cp makes 'etc' a regular file, and the later `sed -i
# rootfs/etc/nv_boot_control.conf` fails with ENOTDIR, aborting BCT signing.
banner "stage 1 rootfs/etc directory guard"
ROOTFS="${LDK_DIR}/rootfs"
if [[ -e "${ROOTFS}/etc" && ! -d "${ROOTFS}/etc" ]]; then
  cp -v "${ROOTFS}/etc" "${BACKUP_DIR}/rootfs_etc.contents"; rm -f "${ROOTFS}/etc"; mkdir -p "${ROOTFS}/etc"
  echo "  converted rootfs/etc file -> directory"
else
  mkdir -p "${ROOTFS}/etc"; echo "  rootfs/etc ok"
fi
touch "${ROOTFS}/etc/nv_boot_control.conf"

banner "stage 2 patch pinmux cfg (idempotent)"
if grep -q 'HDR40' "${CFG}"; then
  echo "  cfg already patched — skipping"
else
  cp -v "${CFG}" "${BACKUP_DIR}/$(basename "${CFG}").orig"
  for e in "${PINMUX_PATCHES[@]}"; do
    addr="${e%%:*}"; rest="${e#*:}"; val="${rest%%:*}"; cmt="${rest#*:}"
    if grep -q "^pinmux\.${addr}\s*=" "${CFG}"; then
      sed -i -E "s|^(pinmux\.${addr}\s*=\s*)0x[0-9a-fA-F]+;.*|\1${val}; # HDR40 ${cmt}|" "${CFG}"
    else
      printf 'pinmux.%s = %s; # HDR40 %s\n' "${addr}" "${val}" "${cmt}" >> "${CFG}"
    fi
    echo "  ${addr} = ${val}  | ${cmt}"
  done
  for e in "${PINMUX_PATCHES[@]}"; do
    addr="${e%%:*}"; rest="${e#*:}"; val="${rest%%:*}"
    grep -qE "^pinmux\.${addr}\s*=\s*${val};" "${CFG}" || { cp "${BACKUP_DIR}/$(basename "${CFG}").orig" "${CFG}"; fail "patch ${addr} did not land (rolled back)"; }
  done
  echo "  ${#PINMUX_PATCHES[@]} registers asserted"
fi

banner "stage 3 flash MB1_BCT"
have_rcm || fail "board left recovery between stages"
LOG="${BACKUP_DIR}/flash_MB1_BCT.log"
( cd "${LDK_DIR}" && ./flash.sh -k MB1_BCT "${BOARD}" "${ROOTDEV}" ) 2>&1 | tee "${LOG}"
RC=${PIPESTATUS[0]}
if [[ ${RC} -eq 0 ]] && grep -qE '\[MB1_BCT\] has been updated successfully|Writing partition MB1_BCT.*100%' "${LOG}"; then
  echo "  MB1_BCT flashed OK"
else
  tail -30 "${LOG}" >&2
  echo "  diag: signed/ $(test -d "${LDK_DIR}/bootloader/signed" && echo yes||echo NO)  rootfs/etc dir $(test -d "${ROOTFS}/etc" && echo yes||echo NO)  RCM $(have_rcm && echo yes||echo NO)"
  fail "flash.sh -k MB1_BCT failed (rc=${RC})"
fi

cat <<EOF

==== DONE ====
  1) remove the FC_REC jumper, power-cycle the board
  2) verify on the Xavier that the pins left "MUX UNCLAIMED":
       sudo cat /sys/kernel/debug/pinctrl/2430000.pinmux/pinmux-pins | grep -iE 'uart1|dap5|gpio4|spi1_cs1' | grep -i unclaimed
     (empty output = all claimed)
  Backup + flash log: ${BACKUP_DIR}
  Rollback: cp ${BACKUP_DIR}/$(basename "${CFG}").orig ${CFG}; rm -rf ${LDK_DIR}/bootloader/signed; re-run in recovery mode
EOF
