# AGENTS.md - G5 KF Fan Control

Guide for setting up this tooling on a fresh install of this laptop
(Gigabyte G5 KF, CachyOS or similar Arch-based system). Written after a full
working session on 2026-08-21 so nothing has to be rediscovered.

## Hardware context

*   **Laptop:** Gigabyte G5 KF (2023, bought second hand) = **Clevo NP50RND**
    chassis rebrand. Board: `6-77-NP50RNDY0D01-B`.
*   **CPU/GPU:** i7-13620H + RTX 4060 Laptop.
*   **EC:** ITE IT5570 (`sensors-detect`: "Found unknown chip with ID 0x5570").
*   Fans are controlled by the EC and are **NOT** exposed via `hwmon` pwm,
    `lm-sensors`, or nbfc. The working path is the `tuxedo_io` kernel module
    talking to the `clevo_acpi` interface (WMI GUID
    `F6CB5C3C-9CAE-4EBD-B577-931EA32A2CC0`).

## What does NOT work (do not retry)

| Approach | Result on this machine |
|---|---|
| `nbfc-linux` | No `Gigabyte G5 KF` profile; `p35w v3` / `Aero15x` maps are for 10-year-old ECs; service fails |
| `it5570-fan-dkms` (AUR) | Builds but `modprobe: No such device` - register layout is for mini-PCs, not this Clevo firmware |
| `lm-sensors` / `pwmconfig` / `fancontrol` | No pwm-capable sensor modules found |
| Raw `/sys/kernel/debug/ec/ec0/io` writes | Possible but unnecessary and risky - tuxedo_io path is safer |

## Prerequisites

```bash
# kernel module (CachyOS ships it; check):
lsmod | grep tuxedo_io          # want: tuxedo_io, clevo_acpi, clevo_wmi loaded
ls -l /dev/tuxedo_io            # must exist (root-only)

# if missing:
sudo pacman -S tuxedo-drivers   # or tuxedo-keyboard from AUR
sudo modprobe tuxedo_io

# build deps:
sudo pacman -S --needed base-devel git
```

dmesg should show `clevo_acpi: interface initialized`.

## Install

```bash
git clone https://github.com/Rodsantos1337/fans-g5-kf.git
cd fans-g5-kf
sudo ./install.sh                          # builds + installs + scoped sudoers rule
sudo systemctl enable --now fans-guard     # thermal guard at boot (recommended)
```

What install.sh does:

1. `make` (compiles g5fan)
2. installs to `/usr/local/bin/`: `g5fan`, `fans`, `fans-guard`
3. installs `fans-guard.service` to `/etc/systemd/system/`
4. adds `/etc/sudoers.d/fans-nopasswd`:
   `<user> ALL=(root) NOPASSWD: /usr/local/bin/g5fan` — scoped to this binary
   ONLY, then validates with `visudo -c`

## Commands

| Command | Effect |
|---|---|
| `fans max` | perf profile "performance" + both fans pinned 100% (turbine mode), detached via systemd-run |
| `fans <N>` (e.g. `fans 60`) | pin both fans at N%, continuously rewritten |
| `fans auto` | stop manual modes, run thermal guard daemon |
| `fans ec` | release everything, pure EC auto control |
| `fans status` | guard/manual state + per-fan duty % + temp |

Direct binary: `g5fan status | on [0-100] | hold [0-100] | perf [0-3] | off`

Services:

*   `fans-guard.service` - thermal daemon (enable at boot)
*   `fans-manual.service` - transient unit created by `systemd-run` while
    pinning speeds; removed automatically when it stops

### Thermal guard thresholds

Top of `/usr/local/bin/fans-guard`:

```bash
T_MAX=85; S_MAX=100    # >=85°C -> 100%
T_HIGH=80; S_HIGH=80   # >=80°C -> 80%
T_MED=70;  S_MED=60    # >=70°C -> 60%
# below -> released to EC auto
```

Guard reads CPU package temp from
`/sys/class/hwmon/hwmon4/temp1_input` (coretemp). **This hwmon index can shift
after kernel updates** - find it again with:

```bash
grep -l coretemp /sys/class/hwmon/hwmon*/name
cat /sys/class/hwmon/hwmon*/temp1_input   # pick the coretemp one
```

## i3 keybinds (already in ~/.config/i3/config)

```
bindsym $mod+Shift+f   fans max    (+ notification)
bindsym $mod+Control+f fans auto   (+ notification)
bindsym $mod+Mod1+f    fans status (notification)
```

(`$mod+f` alone stays fullscreen toggle.)

## Technical gotchas (hard-won)

These are the bugs that cost hours - do not "fix" them back:

1.  **Fan duty ioctl takes RAW 0-255 packed for 3 fans in ONE argument:**
    ```c
    raw = round(percent * 255.0 / 100.0);
    arg = (raw & 0xff) | ((raw & 0xff) << 8) | ((raw & 0xff) << 16);
    ioctl(fd, W_CL_FANSPEED, &arg);
    ```
    Writing a bare `100` means 39% duty (100/255). This was the reason the
    first attempt "ramped a bit but not crazy".
2.  **Single writes don't stick.** The Clevo EC re-takes control after a
    while; TUXEDO Control Center rewrites every poll. Manual modes therefore
    rewrite every ~2 s (`hold` loop).
3.  **Auto restore needs argument `0xF`** (all fan bits set), matching TCC's
    `SetFansAuto()`. Passing 0 is wrong.
4.  **Faninfo decode:** `R_CL_FANINFO{1,2,3}` per fan:
    low byte = duty raw (÷255 = %), bits 16-23 = associated temp °C.
    Example: `0x353247` = duty 71/255 (~28%), temp 53°C.
5.  **Performance profiles** via `W_CL_PERF_PROFILE`
    (`CLEVO_CMD_OPT 0x79`, sub `0x19`): `0`=quiet, `1`=power_saving,
    `2`=performance, `3`=entertainment.
6.  **Ioctl numbers** come from tuxedo_io_ioctl.h: magic `0xEC`,
    `MAGIC_READ_CL = 0xED`, `MAGIC_WRITE_CL = 0xEE`; e.g.
    `W_CL_FANSPEED = _IOW(0xEE, 0x10, int32_t*)`.
7.  `g5fan` needs a ~200 ms sleep after a speed write before reading back,
    otherwise you read the old value.

## Troubleshooting

*   `open /dev/tuxedo_io: No such file or directory` → module not loaded:
    `sudo modprobe tuxedo_io`
*   `hwcheck_cl: 0` → clevo_acpi didn't bind; check `journalctl -k | grep clevo`
*   Guard not acting → `journalctl -t fans-guard`; verify hwmon path (above)
*   Fans stuck manual after crash → they reset on reboot (EC default is auto)
*   Verify temps: `sensors` (coretemp Package id 0) and `fans status`

## Machine-specific warnings

*   **Sudden power-off under heavy load on battery** (happened with CS2,
    2× on 2026-08-21): battery voltage sag, NOT heat - no log entry, instant
    cut. Game plugged into the original ~150 W+ charger until battery/
    charging hardware is checked.
*   Second-hand unit with likely dried paste: idle was hitting 89-90 °C under
    disk-heavy load before fan control was in place. Repaste + dust cleaning
    recommended; guard daemon is the stopgap.
