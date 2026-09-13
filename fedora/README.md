# fans-g5-kf — Fedora support (`fedora/`)

Fedora port of the Arch installer. Shared binaries (`g5fan.c`, `fans`,
`fans-priv`, `fans-guard.service`) live at the repo root and are identical
on both distros — everything Fedora-specific lives in this folder.

## Install (Fedora 44+, Gigabyte G5 KF / Clevo NP50RND)

```bash
git clone https://github.com/Rodsantos1337/fans-g5-kf.git
cd fans-g5-kf
sudo ./fedora/install-fedora.sh           # drivers + build + install + sudoers
sudo systemctl enable --now fans-guard    # optional: thermal guard at boot
```

What `install-fedora.sh` does (mirrors `../install.sh` for Arch):

1. Installs build toolchain: `gcc make dkms kernel-devel kernel-headers`.
2. Adds the **official Tuxedo repo** (`rpm.tuxedocomputers.com/fedora/tuxedo.repo`)
   if `clevo_acpi` is missing, then `dnf install -y tuxedo-drivers` (DKMS).
3. Loads `clevo_acpi` + persists `clevo_acpi/tuxedo_io/tuxedo_keyboard` in
   `/etc/modules-load.d/tuxedo.conf`.
4. `make && make install` from the repo root, then overwrites
   `/usr/local/bin/fans-guard` with this folder's `fans-guard`.
5. Writes scoped sudoers rule `<user> ALL=(root) NOPASSWD: /usr/local/bin/fans-priv`
   and validates with `visudo -c`.

Idempotent: safe to re-run. Re-run after every major kernel upgrade if
`fans status` shows `hwcheck 0`.

## Why `fedora/fans-guard` differs

Root `../fans-guard` hardcodes `hwmon4` (correct on the author's Arch
`linux-zen` but fragile — hwmon indices shift between Fedora kernels,
leaving the guard reading temp `0` forever). This variant resolves the
`coretemp` package sensor dynamically every loop, falling back to `hwmon4`.

Thresholds are identical: ≥85°C → 100%, ≥80°C → 80%, ≥70°C → 60%, else EC auto.

## Verify

```bash
fans status          # want: clevo_acpi (hwcheck 1) + real temps
systemctl status fans-guard
journalctl -t fans-guard
```

If `hwcheck 0` right after install, reboot once (DKMS module was built for
the new kernel but the old one is still running), then re-check.

## Secure Boot

DKMS modules require MOK enrollment when Secure Boot is on. This laptop runs
with Secure Boot disabled, so no extra step is needed. If you re-enable it,
enroll the DKMS key after the first `tuxedo-drivers` install or the modules
will refuse to load.

## Files here

* `install-fedora.sh` — Fedora installer (run with sudo)
* `fans-guard` — Fedora-robust guard daemon (dynamic coretemp lookup)
* `README.md` — this file
