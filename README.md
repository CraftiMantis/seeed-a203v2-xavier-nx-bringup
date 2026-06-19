# Seeed A203 / A203-V2 + Jetson Xavier NX — flash, UART & CAN bring-up

Flash a **Seeed A203 / A203-V2** carrier + **Jetson Xavier NX** on **JetPack 5.x**,
and get past the board-specific traps that aren't documented anywhere: the V2
recovery jumper, UEFI stealing your UART at boot, dead 40-pin-header pins, and CAN
that won't start. Scripts are generalized from a bench-validated bring-up.

> Xavier's last supported JetPack is **5.x (L4T r35.x)** — JetPack 6 and 7 dropped it.

## What you need

- Seeed **A203** or **A203-V2** carrier + **Jetson Xavier NX** (eMMC) module
- An **x86_64 Ubuntu host** to flash from, USB-C to the carrier
- ~30 GB free on the host

## Where the BSP comes from

| Piece | Source |
|---|---|
| NVIDIA L4T r35.6.1 BSP | [jetson_linux_r35.6.1_aarch64.tbz2](https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/release/jetson_linux_r35.6.1_aarch64.tbz2) |
| Sample root filesystem | [tegra_linux_sample-root-filesystem_r35.6.1_aarch64.tbz2](https://developer.nvidia.com/downloads/embedded/l4t/r35_release_v6.1/tegra_linux_sample-root-filesystem_r35.6.1_aarch64.tbz2) |
| Bootlin GCC-9.3 toolchain | [bootlin-toolchain-gcc-93](https://developer.nvidia.com/embedded/jetson-linux/bootlin-toolchain-gcc-93) |
| Seeed carrier BSP | [github.com/Seeed-Studio/Linux_for_Tegra](https://github.com/Seeed-Studio/Linux_for_Tegra) (branch `r35.6.1`) |
| Seeed's own flash guide | [wiki.seeedstudio.com/reComputer_A203_Flash_System](https://wiki.seeedstudio.com/reComputer_A203_Flash_System/) |

## Steps

```bash
# 1) on the HOST, as your user — download + assemble the BSP
STAGING=~/nvidia/a203-xavier bash flash/01-get-bsp.sh
export LDK_DIR=~/nvidia/a203-xavier/Linux_for_Tegra

# enter force-recovery (A203-V2): power off → jumper J12 pin 3 (FC_REC) ↔ GND
#   → USB-C to host → power on.   check:  lsusb | grep 0955:7e19

# 2) flash the board to eMMC (host, root, board in recovery)
sudo -E bash flash/02-flash-board.sh

# 3) claim the 40-pin header functions — UART_A, I2S5, SPI1, GPIO, PWM (recovery)
sudo -E bash flash/03-claim-hdr40-pins.sh

# 4) stop UEFI hanging when a device is powered on UART_A (recovery)
sudo -E bash flash/04-fix-uart-boot-hang.sh
```

Each step prints exactly what to do next. Steps 3–4 reflash a single partition
(rootfs/kernel preserved) and need the board in recovery mode.

### CAN — on the Xavier, after it boots

```bash
sudo BITRATE=1000000 bash can/can-up.sh        # bring up can0 now
sudo bash can/can-persist.sh                   # autoload mttcan + bitrate at boot
sudo bash can/can-loopback-test.sh             # driver smoke test (no bus needed)
```

## Why steps 3–4 and CAN exist

They each work around a specific board trap. The full list — **symptom → cause → fix**
— is in **[FINDINGS.md](FINDINGS.md)** (the part that saves you days). The header pin
map is in **[docs/J12_PINOUT.md](docs/J12_PINOUT.md)**.

## Notes

- Validated on **L4T r35.6.x** (JetPack 5.1.x). For other r35 point releases, re-check
  the DTB/conf filenames.
- The board target is `jetson-xavier-nx-devkit-emmc` (the carrier bits come from the
  Seeed overlay applied in step 1) — override with `BOARD=` if yours differs.
- Scripts are generalized from a bench-validated bring-up; the flash steps haven't been
  re-run from this cleaned copy — read each before running, and keep the backups they make.
