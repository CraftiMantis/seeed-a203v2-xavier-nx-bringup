#!/usr/bin/env bash
# Bring up native Tegra MTTCAN on a Seeed A203 / A203-V2 + Xavier NX.
#
# On the A203-V2, the routed channel is can0 (mttcan@c310000, W7 / J12 pins
# 11+13 = CAN_L/CAN_H). can1 (mttcan@c320000) has a driver but no physical
# pins on this carrier (loopback-only).
#
# NOTE: L4T r35 ships the mttcan module but does NOT autoload it — so a plain
# `ip link` will say the interface doesn't exist until you modprobe it.
#
# Usage:  sudo BITRATE=1000000 IFACES="can0" bash can/can-up.sh
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "run as root (sudo)"; exit 2; }

IFACES="${IFACES:-can0}"
BITRATE="${BITRATE:-1000000}"   # 1 Mbps is the common motor-bus rate (e.g. CubeMARS AK series)

modprobe mttcan; modprobe can_raw; modprobe can_dev
sleep 0.3

for iface in $IFACES; do
  [[ -e "/sys/class/net/${iface}" ]] || { echo "ERROR: ${iface} absent (DT status=okay? mttcan loaded?)"; exit 1; }
  state=$(ip -br link show "${iface}" | awk '{print $2}')
  cur=$(ip -d link show "${iface}" 2>/dev/null | grep -oP 'bitrate \K[0-9]+' | head -1 || echo "")
  if [[ "${state}" == "UP" && "${cur}" == "${BITRATE}" ]]; then
    echo "[can-up] ${iface} already UP @ ${BITRATE} bps"; continue
  fi
  echo "[can-up] ${iface}: down -> bitrate ${BITRATE} -> up"
  ip link set "${iface}" down 2>/dev/null || true
  ip link set "${iface}" type can bitrate "${BITRATE}"
  ip link set "${iface}" up
done

echo "[can-up] status:"
for iface in $IFACES; do ip -br link show "${iface}"; ip -d link show "${iface}" 2>/dev/null | grep -E 'bitrate|state' || true; done
