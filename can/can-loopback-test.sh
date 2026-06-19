#!/usr/bin/env bash
# Driver-level loopback smoke test for Tegra MTTCAN — proves the controller +
# driver work without needing a powered CAN bus or a peer node.
#
# Usage:  sudo IFACE=can0 bash can/can-loopback-test.sh
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "run as root (sudo)"; exit 2; }
IFACE="${IFACE:-can0}"
command -v cansend >/dev/null || { echo "install can-utils: apt install can-utils"; exit 2; }

modprobe mttcan can_raw can_dev 2>/dev/null || true
[[ -e "/sys/class/net/${IFACE}" ]] || { echo "ERROR: ${IFACE} absent"; exit 1; }

echo "DT status: $(cat /sys/firmware/devicetree/base/mttcan@c310000/status 2>/dev/null | tr -d '\0' || echo '?') (can0)  /  $(cat /sys/firmware/devicetree/base/mttcan@c320000/status 2>/dev/null | tr -d '\0' || echo '?') (can1)"

ip link set "${IFACE}" down 2>/dev/null || true
ip link set "${IFACE}" type can bitrate 500000 loopback on
ip link set "${IFACE}" up

tx0=$(ip -s link show "${IFACE}" | awk '/TX:/{getline; print $1}')
for i in 1 2 3 4 5; do cansend "${IFACE}" "10${i}#0${i}"; done
sleep 0.3
tx1=$(ip -s link show "${IFACE}" | awk '/TX:/{getline; print $1}')

echo "TX packets: ${tx0} -> ${tx1}  (delta $((tx1 - tx0)))"
ip link set "${IFACE}" down; ip link set "${IFACE}" type can loopback off 2>/dev/null || true
if [[ $((tx1 - tx0)) -ge 5 ]]; then echo "PASS — driver + controller OK (loopback)"; else echo "FAIL — no TX (check mttcan / DT status)"; exit 1; fi
