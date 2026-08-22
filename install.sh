#!/bin/bash
set -e

# fans - install script for Gigabyte G5 KF fan control
# usage: sudo ./install.sh
#
# Handles everything: tuxedo drivers (if missing), module loading + boot
# persistence, build, binaries, sudoers rule. One password, done.

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

USER_NAME="${SUDO_USER:-$USER}"

# --- prerequisite: tuxedo drivers ------------------------------------------
# clevo_acpi is what binds to the hardware - without it /dev/tuxedo_io exists
# but hwcheck reports 0 and every fan write silently no-ops

if ! modinfo -n clevo_acpi >/dev/null 2>&1; then
    HELPER="$(command -v yay || command -v paru || true)"
    if [ -z "$HELPER" ]; then
        echo "ERROR: clevo_acpi module missing and no AUR helper (yay/paru) found."
        echo "Install tuxedo-drivers-dkms manually, then re-run this script."
        exit 1
    fi
    if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
        echo "WARNING: kernel headers for $(uname -r) missing - DKMS build will fail."
        echo "Install them (e.g. linux-zen-headers), then re-run."
        exit 1
    fi
    echo "== tuxedo-drivers not found - installing tuxedo-drivers-dkms =="
    sudo -u "$USER_NAME" "$HELPER" -S --needed tuxedo-drivers-dkms
fi

# load now + persist across reboots
lsmod | grep -q '^clevo_acpi ' || modprobe clevo_acpi
cat > /etc/modules-load.d/tuxedo.conf <<EOF
clevo_acpi
tuxedo_io
tuxedo_keyboard
EOF

# --- fan control itself ------------------------------------------------------

make
make install

# passwordless sudo for the privileged backend ONLY (fixed subcommands,
# no arbitrary command execution) - keeps i3 keybinds fully silent
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
echo "enable thermal guard at boot with:"
echo "  sudo systemctl enable --now fans-guard"
echo "usage: fans max | fans <0-100> | fans auto | fans ec | fans status"
