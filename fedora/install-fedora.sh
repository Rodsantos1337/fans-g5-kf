#!/bin/bash
set -e

# fans - Fedora install script for Gigabyte G5 KF fan control
# usage: sudo ./fedora/install-fedora.sh  (or sudo ./install-fedora.sh from inside fedora/)
#
# Fedora port of ../install.sh (Arch). Handles everything: official Tuxedo
# repo + drivers (if missing), module loading + boot persistence, build,
# binaries, Fedora-robust fans-guard, sudoers rule. One password, done.
#
# Idempotent: safe to re-run.

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

USER_NAME="${SUDO_USER:-$USER}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -f /etc/fedora-release ]]; then
    echo "warning: no /etc/fedora-release found - continuing anyway (expected Fedora)" >&2
fi

# --- 0. build toolchain ------------------------------------------------------
# kernel-devel must match the RUNNING kernel for DKMS; dnf pulls the latest
# which may lag behind a freshly updated kernel until reboot.
echo "== [0/4] build toolchain =="
dnf install -y gcc make dkms kernel-devel kernel-headers dnf-plugins-core curl

if [[ ! -d "/lib/modules/$(uname -r)/build" ]]; then
    echo "WARNING: kernel headers for $(uname -r) missing - DKMS build will fail." >&2
    echo "Reboot into the newest installed kernel (or: sudo dnf install kernel-devel-$(uname -r)), then re-run." >&2
fi

# --- 1. prerequisite: tuxedo drivers (official repo) -------------------------
# clevo_acpi is what binds to the hardware - without it /dev/tuxedo_io exists
# but hwcheck reports 0 and every fan write silently no-ops.
echo "== [1/4] tuxedo drivers =="
if ! modinfo -n clevo_acpi >/dev/null 2>&1; then
    if [[ ! -f /etc/yum.repos.d/tuxedo.repo ]]; then
        echo "adding official Tuxedo repo for Fedora"
        dnf config-manager addrepo --from-repofile="https://rpm.tuxedocomputers.com/fedora/tuxedo.repo"
    fi
    echo "installing tuxedo-drivers (official repo, DKMS)"
    dnf install -y tuxedo-drivers
fi

if ! modinfo -n clevo_acpi >/dev/null 2>&1; then
    echo "ERROR: clevo_acpi still missing after tuxedo-drivers install." >&2
    echo "DKMS may have built for a different kernel - reboot, then re-run this script." >&2
    exit 1
fi

# load now + persist across reboots (one module per modprobe call)
lsmod | grep -q '^clevo_acpi ' || modprobe clevo_acpi || {
    echo "WARNING: modprobe clevo_acpi failed - likely needs a reboot after DKMS build." >&2
}
cat > /etc/modules-load.d/tuxedo.conf <<EOF
clevo_acpi
tuxedo_io
tuxedo_keyboard
EOF

# --- 2. fan control itself ----------------------------------------------------
echo "== [2/4] build + install fan control =="
make -C "$REPO_ROOT"
make -C "$REPO_ROOT" install
# Fedora-robust guard (dynamic coretemp lookup instead of hardcoded hwmon4)
# overwrites the make-installed copy with this dir's variant.
install -Dm755 "$SCRIPT_DIR/fans-guard" /usr/local/bin/fans-guard

# passwordless sudo for the privileged backend ONLY (fixed subcommands,
# no arbitrary command execution) - keeps i3 keybinds fully silent
echo "== [3/4] sudoers + systemd =="
cat > /etc/sudoers.d/fans-nopasswd <<EOF
${USER_NAME} ALL=(root) NOPASSWD: $(command -v fans-priv)
EOF
chmod 440 /etc/sudoers.d/fans-nopasswd
visudo -c

systemctl daemon-reload
echo
if /usr/local/bin/g5fan status 2>/dev/null | grep -q 'hwcheck 1'; then
    echo "done. driver bound (clevo_acpi), fan control live."
else
    echo "installed, but clevo_acpi isn't bound yet (hwcheck 0) -"
    echo "the module was likely half-loaded before this install. Reboot once,"
    echo "then check with: fans status"
fi
echo "== [4/4] next steps =="
echo "enable thermal guard at boot with:"
echo "  sudo systemctl enable --now fans-guard"
echo "usage: fans max | fans <0-100> | fans auto | fans ec | fans status"
