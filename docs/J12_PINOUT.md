# J12 40-pin header — pinmux map (A203-V2 + Xavier NX)

These are the functions the [`mb1-bct-hdr40-pinmux.sh`](../flash/03-claim-hdr40-pins.sh)
script claims. Each row is one PADCTL register override in
`tegra19x-mb1-pinmux-p3668-a01.cfg`. Pin numbers are the J12 40-pin header.

| J12 pin | Function | Tegra pad | PADCTL reg | Value |
|--------:|----------|-----------|------------|-------|
| 7  | AUD_MCLK      | `aud_mclk_ps4`  | `0x02431020` | `0x00000400` |
| 8  | **UART_A TX**  | `uart1_tx_pr2`  | `0x024300a8` | `0x00000400` |
| 10 | **UART_A RX**  | `uart1_rx_pr3`  | `0x024300a0` | `0x00000454` (pull-down) |
| 11 | UART_A RTS    | `uart1_rts_pr4` | `0x02430098` | `0x00000400` |
| 12 | I2S5 SCLK     | `dap5_sclk_pt5` | `0x02431080` | `0x00000402` |
| 15 | GPIO12        | `touch_clk_pcc4`| `0x0c302000` | `0x00000040` |
| 26 | SPI1 CS1      | `spi1_cs1_pz7`  | `0x0243d050` | `0x00000400` |
| 29 | GPIO01        | `soc_gpio41_pq5`| `0x02430028` | `0x00000040` |
| 31 | GPIO11        | `soc_gpio42_pq6`| `0x02430030` | `0x00000040` |
| 32 | GPIO07 / PWM5 | `soc_gpio44_pr0`| `0x02430040` | `0x00000040` |
| 33 | GPIO13 / PWM7 | `soc_gpio54_pn1`| `0x02440020` | `0x00000040` |
| 35 | I2S5 FS       | `dap5_fs_pu0`   | `0x02431068` | `0x00000456` |
| 36 | UART_A CTS    | `uart1_cts_pr5` | `0x02430090` | `0x00000458` (pull-up) |
| 38 | I2S5 DIN      | `dap5_din_pt7`  | `0x02431070` | `0x00000456` (E_INPUT=1) |
| 40 | I2S5 DOUT     | `dap5_dout_pt6` | `0x02431078` | `0x00000402` |

**UART_A** (`/dev/ttyTHS0`, controller `serial@3100000`) is the headline use:
pins 8/10 (+ 11/36 for HW flow control). Two gotchas apply to it — the pins are
dead until this pinmux flash, **and** UEFI grabs the same UART as its boot
console (see [FINDINGS.md](../FINDINGS.md) and
[`uart-boot-console-fix.sh`](../flash/04-fix-uart-boot-hang.sh)).

Verify on the board after the pinmux flash:
```bash
sudo cat /sys/kernel/debug/pinctrl/2430000.pinmux/pinmux-pins \
  | grep -iE 'uart1|dap5|spi1_cs1|soc_gpio4|touch_clk' | grep -i unclaimed
# empty output = all target pins claimed
```

## CAN

CAN is **not on the 40-pin header** — it's on the carrier's dedicated CAN
port. The controller is `mttcan@c310000` → **`can0`**. The second controller
`mttcan@c320000` → `can1` has a driver but no pins routed on this carrier
(loopback-only). For the exact CAN connector/pinout, see the Seeed A203-V2
hardware documentation; for bring-up see [`can/`](../can/).
