# Seeed A203 / A203-V2 + Jetson Xavier NX — flashing, device tree, UART & CAN bring-up

The board-specific things you hit when you flash a **Seeed Studio A203 / A203-V2
carrier** with an **NVIDIA Jetson Xavier NX** module on **JetPack 5.x (L4T r35.x)**
— and that aren't written down clearly anywhere: the right `flash.sh` invocations,
the **UEFI-grabs-your-UART boot hang**, getting the **40-pin header pins actually
claimed**, and bringing up **native CAN**. Scripts here are generalized from a real,
bench-validated bring-up.

> Scope: A203 / A203-V2 carrier, Xavier NX (Tegra194), JetPack 5.x / L4T r35.6.x,
> flashed from an x86 Ubuntu host with the Seeed BSP (`Linux_for_Tegra`). This is
> the **last JetPack line that supports Xavier** — JP6/JP7 dropped it.

## The four things this repo solves

1. **Force-recovery on the A203-V2 is different from V1.** V2 = jumper **J12 pin 3
   (FC_REC) ↔ GND**, not the V1 pin. Get this wrong and the board never enters RCM.
2. **UEFI uses UART_A (J12 pin 8/10) as its boot console** — a JetPack 5.x Xavier-NX
   regression. Any device powered on that UART at boot hangs UEFI. Fixed with a
   **dual-DTB** split → [`flash/uart-boot-console-fix.sh`](flash/uart-boot-console-fix.sh).
3. **~19 of the 40-pin header pins ship "MUX UNCLAIMED."** UART_A, I2S5, SPI1, PWM,
   GPIOs are dead until you patch the **MB1_BCT pinmux** and reflash that partition →
   [`flash/mb1-bct-hdr40-pinmux.sh`](flash/mb1-bct-hdr40-pinmux.sh) ·
   [pinout map](docs/J12_PINOUT.md).
4. **CAN doesn't auto-start** — L4T r35 ships `mttcan` but doesn't autoload it, and the
   bitrate/up-state need persisting → [`can/`](can/).

The hard-won details behind each are in **[FINDINGS.md](FINDINGS.md)** — read it; it's
the part that saves you days.

## Flash sequence (reference)

Initial bring-up uses NVIDIA/Seeed's stock flow; the value-add scripts come after.

```bash
# Force-recovery (A203-V2): power off → jumper J12 pin 3 ↔ GND → USB-C to host → power on
lsusb | grep 0955:7e19           # NVIDIA APX = you're in recovery

cd <Seeed Linux_for_Tegra>       # the Seeed BSP, e.g. ~/nvidia/seeed-l4t-r35.6.1
sudo ./flash.sh jetson-xavier-nx-devkit-emmc mmcblk0p1     # initial flash to eMMC
```

The board target is **always `jetson-xavier-nx-devkit-emmc`** — not the hostname,
not "seeed-a203". `flash.sh` reads the board profile from the BSP, not from mDNS.

Then the partition-only reflashes from this repo (each preserves rootfs/kernel/NVMe):

```bash
export LDK_DIR=<Seeed Linux_for_Tegra>

# claim the 40-pin header functions (board in recovery mode):
sudo -E bash flash/mb1-bct-hdr40-pinmux.sh        # -> flash.sh -k MB1_BCT

# stop UEFI from owning UART_A (build step; then flash bootloader-dtb in recovery):
sudo -E bash flash/uart-boot-console-fix.sh       # -> prints the flash.sh -k bootloader-dtb command
```

## CAN (on the Xavier, after boot)

```bash
sudo BITRATE=1000000 bash can/can-up.sh           # bring can0 up now
sudo BITRATE=1000000 bash can/can-persist.sh      # autoload mttcan + bring up @ boot
sudo bash can/can-loopback-test.sh                # driver smoke test (no bus needed)
```

## Files

```
flash/uart-boot-console-fix.sh   dual-DTB: UEFI stops using UART_A as console (Linux keeps /dev/ttyTHS0)
flash/mb1-bct-hdr40-pinmux.sh    patch MB1_BCT pinmux + reflash → claim all J12 hdr40 functions
can/can-up.sh                    bring up can0 at a bitrate (modprobe mttcan + ip link)
can/can-persist.sh               autoload mttcan + systemd-networkd bitrate at boot
can/can-loopback-test.sh         controller/driver loopback smoke test
docs/J12_PINOUT.md               40-pin header pinmux register map
FINDINGS.md                      every gotcha, with symptoms + fixes
```

## Caveats

- You need Seeed's `Linux_for_Tegra` BSP for the A203 + Xavier NX (r35.6.x). The
  A203-V2 carrier mods live in Seeed's driver package, not in NVIDIA's stock tree.
- The partition reflashes need the board in **force-recovery mode**; they rewrite only
  their target partition.
- Built/validated on L4T r35.6.x (JetPack 5.1.x). Other r35 point releases are likely
  fine but verify the DTB/conf filenames.
- The pinmux register values target the **Xavier NX (Tegra194) p3668** module.
