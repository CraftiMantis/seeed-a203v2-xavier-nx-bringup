# Findings: A203 / A203-V2 + Xavier NX bring-up

Every non-obvious thing that cost real bench time, with the symptom you'll actually
see, the cause, and the fix. Validated on JetPack 5.1.x / L4T r35.6.x.

---

## Flashing

### F1 — A203-V2 force-recovery is a *different* jumper than V1
**Symptom:** board never shows up as `0955:7e19` (NVIDIA APX) no matter how you jumper it.
**Cause:** the V2 carrier moved the force-recovery pin. V1 used one pin; **V2 uses J12
pin 3 (FC_REC) ↔ GND**.
**Fix:** read the silkscreen, jumper **pin 3 ↔ GND**, USB-C to host, then power on.
Confirm with `lsusb | grep 0955:7e19`.

### F2 — `flash.sh` creates `rootfs/etc` as a *file*, then dies at signing
**Symptom:** flash aborts around the tegraflash sign step; every retry dies the same place.
**Cause:** `flash.sh` runs `cp -f nv_boot_control.conf rootfs/etc`. If `rootfs/etc/`
doesn't exist, `cp` creates **`etc` as a regular file**, and the later
`sed -i rootfs/etc/nv_boot_control.conf` fails with `ENOTDIR`, killing BCT generation
before `bootloader/signed/` is created.
**Fix:** before flashing, ensure `rootfs/etc` is a directory (the pinmux script does this
in stage 1): `[[ -e rootfs/etc && ! -d rootfs/etc ]] && rm rootfs/etc; mkdir -p rootfs/etc`.

### F3 — Setting `BOARDID/BOARDSKU/FAB/BOARDREV` triggers a secure-boot hang
**Symptom:** flash hangs forever; log shows the secure/`--securedev` path being taken.
**Cause:** exporting those env vars makes `flash.sh` pick the SecureBoot binary path. On a
consumer (non-fused) module the applet can't decrypt → infinite hang.
**Fix:** don't set them. Let `flash.sh` auto-detect the module from its EEPROM.

### F4 — `flash.sh` "succeeds" but the board fell out of recovery
**Symptom:** `Error: probing the target board failed`, `ECID is ` (empty).
**Cause:** the board dropped out of RCM mid-flow (cable, power, or a prior failed attempt).
**Fix:** power-cycle the carrier **with the FC_REC jumper in** to cleanly reset the BootROM,
re-confirm `lsusb`, then re-flash.

### F5 — prefer plain `flash.sh` over `l4t_initrd_flash.sh --massflash`
**Symptom:** initrd massflash hangs at `BootRom is not running` / tegrarcm applet probe.
**Fix:** for this carrier, the plain `flash.sh <board> mmcblk0p1` path is reliable; the
initrd massflash path is fragile on r35.x and unnecessary here.

---

## Device tree

### D1 — building the kernel from Seeed's GitHub gives you the *stock NVIDIA* DTB
**Symptom:** after a from-source kernel build, `cat /proc/device-tree/compatible` shows
`nvidia,p3509-...` with none of the carrier mods; CAN transceiver / GPIO expander missing.
**Cause:** Seeed's public kernel branch doesn't carry the A203-V2 carrier DTS changes —
those live **only in Seeed's downloadable driver package** (per carrier × module × JetPack).
**Fix:** use the DTB/overlay from Seeed's driver package; don't expect a GitHub kernel build
to produce the carrier DTB.

### D2 — `/boot/*.dtb` is not what boots; `/boot/dtb/*.dtb` is
**Symptom:** you patch a DTB in `/boot/`, reboot, nothing changes.
**Cause:** `extlinux.conf`'s `FDT` line points at `/boot/dtb/kernel_<base>.dtb`. Files
directly under `/boot/` are alternates only used if SKU auto-detect fails.
**Fix:** patch/verify the one under `/boot/dtb/`; `md5sum /boot/dtb/kernel_*.dtb` to confirm
which is live.

### D3 — the `xavier-nx-seeed-industry.dtbo` name is misleading — it's the right one
**Symptom:** you skip the "industry" overlay assuming it's for a different product; CAN
transceiver enable / WiFi control / GPIO expander then don't work.
**Fix:** on the A203-V2, `xavier-nx-seeed-industry.dtbo` (and the matching `…-industry.conf`)
**is** the correct overlay — not the `devkit` conf. It carries the CAN standby enable and
the PCA9535 GPIO expander.

### D4 — `CONFIG_VIDEO_ECAM=m` aborts the kernel build (missing firmware blob)
**Symptom:** kernel build fails in `drivers/media` on a missing `e-CAM130A_*_mcu_fw.bin`.
**Cause:** Seeed's r35.6.1 defconfig enables the e-con camera driver but doesn't ship its
firmware blob.
**Fix:** set `CONFIG_VIDEO_ECAM=n` in `tegra_defconfig` before building (unless you actually
have that camera + its firmware).

---

## UART (the big one)

### U1 — UEFI uses UART_A as its boot console → board hangs if a device is on it
**Symptom:** the board boots fine bare, but **hangs at boot** whenever your serial
peripheral (MCU, FTDI, sensor) is powered on J12 pin 8/10.
**Cause:** JetPack 5.x Xavier-NX regression — UEFI uses `serial@3100000` (`/dev/ttyTHS0`,
J12 pin 8/10) as its console and reads incoming bytes as user input.
**Fix (NVIDIA-endorsed, forum topic 273815): dual-DTB.** Point `TBCDTB_FILE` (bootloader
DTB) at a copy with `serial@3100000` **disabled**, leave `DTB_FILE` (kernel) **enabled**.
UEFI stops listening; Linux keeps full `/dev/ttyTHS0`. → [`flash/04-fix-uart-boot-hang.sh`](flash/04-fix-uart-boot-hang.sh).
Verify by booting with the peripheral already powered — it should boot clean.

### U2 — UART_A pins are dead until the MB1_BCT pinmux is flashed
**Symptom:** `/dev/ttyTHS0` exists but no data; the pad shows `MUX UNCLAIMED`.
**Cause:** pad control is set at boot by MB1_BCT; the stock pinmux leaves UART_A (and ~18
other header pins) unclaimed.
**Fix:** [`flash/03-claim-hdr40-pins.sh`](flash/03-claim-hdr40-pins.sh) → `flash.sh -k MB1_BCT`.
Both U1 and U2 must be done for a usable, boot-safe UART_A.

---

## CAN

### C1 — `mttcan` isn't autoloaded by L4T
**Symptom:** `can0` doesn't exist at boot even with the device tree marking it `okay`.
**Cause:** L4T r35 ships the `mttcan` module but doesn't autoload it.
**Fix:** `/etc/modules-load.d/*.conf` with `mttcan`, `can_raw`, `can_dev` (see
[`can/can-persist.sh`](can/can-persist.sh)).

### C2 — `can0` is UP but no frames go out (TX stuck at 0)
**Symptom:** `ip link show can0` says UP, but `cansend` frames never reach the wire.
**Cause:** the CAN transceiver is in standby — the stock NVIDIA p3509 DTB has no CAN_STBY
GPIO config; the A203-V2 needs the standby line released.
**Fix:** use Seeed's carrier overlay (`xavier-nx-seeed-industry.dtbo`), which drives the
transceiver enable via the PCA9535 expander.

### C3 — `can1` shows up and even passes loopback, but has no pins
**Symptom:** you bring `can1` up, loopback passes, but no motor/peer ever responds.
**Cause:** on the A203-V2 only `mttcan@c310000` (**can0**) is routed to a physical
connector. `mttcan@c320000` (`can1`) has a working driver but **no pins**.
**Fix:** wire to `can0`. Treat `can1` as software/loopback-only on this carrier.

---

## One-line summary

> On the A203-V2 + Xavier NX, the device boots easily but the *carrier* is full of traps:
> a different recovery jumper, a `flash.sh` filesystem bug, UEFI stealing your UART, an
> unclaimed pinmux, and a CAN stack that needs autoloading + a transceiver enable. Each is
> a quick fix once you know it exists — this repo is the "knowing it exists."
