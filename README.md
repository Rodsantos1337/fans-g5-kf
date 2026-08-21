# g5-fan-control

Fan control for the **Gigabyte G5 KF** (Clevo NP50RND chassis) on Linux.

The laptop's ITE IT5570 EC is not exposed via standard `hwmon` pwm, and has no
nbfc profile. This tool drives the fans through the `tuxedo_io` kernel module
(`clevo_acpi` interface), the same ioctl path TUXEDO Control Center uses on
Clevo machines - no raw EC register writes.

Requires the `tuxedo_io` module (CachyOS ships it via `tuxedo-keyboard` /
`tuxedo-drivers`; check with `lsmod | grep tuxedo_io`).

## Install - final setup

This is everything. The `sudo ./install.sh` step is the **last password you
will ever type for fan control**:

```bash
git clone https://github.com/Rodsantos1337/fans-g5-kf.git
cd fans-g5-kf
sudo ./install.sh                          # builds + installs + sudoers rule
sudo systemctl enable --now fans-guard     # optional: thermal guard at boot
```

After this, every command and every i3 keybind is **fully passwordless** -
no sudo prompts, no polkit modals.

### Why there are no auth prompts

The design keeps privileged work in exactly one place:

```
you -> fans <cmd>            (unprivileged wrapper)
        └─ sudo -n fans-priv <cmd>    ONE silent call (NOPASSWD scoped rule)
             └─ root does all systemctl / systemd-run / g5fan work
```

The installer adds a single **scoped** sudoers rule:
`<user> ALL=(root) NOPASSWD: /usr/local/bin/fans-priv`
- `fans-priv` accepts only fixed subcommands (`max | pin N | auto | ec |
  status`), no arbitrary command execution. Nothing else runs passwordless.

> Got a password prompt after an update? Your installed `fans` wrapper
> prediates the `fans-priv` redesign - fix with `cd fans-g5-kf && git pull
> && sudo make install`.

## Commands

| Command | Effect |
|---|---|
| `fans max` | performance profile + both fans pinned at 100% ("turbine mode") |
| `fans 60` | pin both fans at 60% (any 0-100) |
| `fans auto` | thermal guard daemon: ≥85°C → 100%, ≥80° → 80%, ≥70° → 60%, else EC auto |
| `fans ec` | release fans to EC auto control, stop guard/manual modes |
| `fans status` | guard/manual state + per-fan duty % + temperature |

All commands are passwordless. Manual modes run detached (`systemd-run`) and
keep rewriting the duty every ~2s (the Clevo EC otherwise re-takes control
after a single write).

## i3 keybinds

Add to `~/.config/i3/config` - they work immediately after install with zero
auth prompts (`$mod+f` alone stays fullscreen toggle):

```
bindsym $mod+Shift+f exec --no-startup-id fans max && notify-send "Fans" "MAX - turbine mode"
bindsym $mod+Control+f exec --no-startup-id fans auto && notify-send "Fans" "auto (thermal guard)"
bindsym $mod+Mod1+f exec --no-startup-id notify-send "Fan status" "$(fans status 2>/dev/null | tr '\n' ' ')"
```

Reload i3 with `$mod+Shift+c`.

## Full setup guide

See [AGENTS.md](AGENTS.md) for the complete fresh-install guide: hardware
context, prerequisites, everything that does NOT work on this machine
(nbfc, it5570-fan-dkms, pwmconfig), protocol gotchas, troubleshooting and
machine-specific warnings.

## Notes / gotchas learned on this machine

*   The fan speed ioctl takes **duty as raw 0-255 packed for 3 fans in one
    argument** (`raw | raw<<8 | raw<<16`). Writing a bare percentage is
    interpreted as /255 - `100` means 39%.
*   `W_CL_FANAUTO` wants argument `0xF` to return all fans to EC control.
*   Performance profiles: `0`=quiet, `1`=power_saving, `2`=performance,
    `3`=entertainment (`g5fan perf N`).
*   Fan info decode: low byte = duty raw, bits 16-23 = associated temp (°C).
*   GPU fan temp reads ~20°C at idle (faninfo2 quirk) - harmless, duty is
    still valid.
*   fish shell does not support `<<<` herestrings - use `bash -c '...'` or
    `echo ... | sudo tee`.
*   Sudden power-off under GPU+CPU load on battery = voltage sag, not heat.
    Game plugged into the original charger.

## Files

*   `g5fan.c` - ioctl tool (status/on/hold/perf/off)
*   `fans` - unprivileged user-facing wrapper (silent `sudo -n fans-priv`)
*   `fans-priv` - privileged backend, fixed subcommands only (root via NOPASSWD)
*   `fans-guard` + `fans-guard.service` - temperature-driven daemon
*   thresholds live at the top of `fans-guard`
