#!/usr/bin/env bash
# Persist Tegra MTTCAN across reboots on a Seeed A203 / A203-V2 + Xavier NX,
# using systemd-networkd (already on L4T r35 — no extra packages).
#
# Two parts, both needed:
#   1. /etc/modules-load.d/  -> autoload mttcan at boot (L4T does NOT by default,
#      so can0/can1 won't enumerate at boot even with DT status=okay).
#   2. /etc/systemd/network/80-canX.network -> set the bitrate + bring up at boot.
#
# Usage:  sudo BITRATE=1000000 bash can/can-persist.sh
set -euo pipefail
[[ "${EUID}" -eq 0 ]] || { echo "run as root (sudo)"; exit 2; }
BITRATE="${BITRATE:-1000000}"

cat >/etc/modules-load.d/tegra-can.conf <<'EOF'
# L4T r35 ships mttcan but does not autoload it; without this, can0/can1
# do not enumerate at boot even though the device tree marks them okay.
mttcan
can_raw
can_dev
EOF
echo "[can-persist] wrote /etc/modules-load.d/tegra-can.conf"
modprobe mttcan can_raw can_dev 2>/dev/null || true

write_unit() {
  local iface="$1" path="/etc/systemd/network/80-${1}.network"
  cat >"${path}" <<EOF
[Match]
Name=${iface}

[CAN]
BitRate=${BITRATE}

[Link]
RequiredForOnline=no
EOF
  chmod 0644 "${path}"; echo "[can-persist] wrote ${path}"
}
for iface in can0 can1; do
  [[ -e "/sys/class/net/${iface}" ]] && write_unit "${iface}" || echo "[can-persist] ${iface} absent — skipping"
done

systemctl daemon-reload
systemctl enable --now systemd-networkd >/dev/null 2>&1 || true
networkctl reload
for iface in can0 can1; do networkctl reconfigure "${iface}" 2>/dev/null || true; done
sleep 0.5

echo "[can-persist] final state:"
for iface in can0 can1; do [[ -e "/sys/class/net/${iface}" ]] && ip -br link show "${iface}"; done
echo "[can-persist] DONE — CAN comes up @ ${BITRATE} bps on every boot."
