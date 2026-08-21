#!/bin/bash
set -e

# fans - install script for Gigabyte G5 KF fan control
# usage: sudo ./install.sh

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

USER_NAME="${SUDO_USER:-$USER}"

make
make install

# passwordless sudo for the g5fan binary only (not general root)
cat > /etc/sudoers.d/fans-nopasswd <<EOF
${USER_NAME} ALL=(root) NOPASSWD: $(command -v g5fan)
EOF
chmod 440 /etc/sudoers.d/fans-nopasswd
visudo -c

systemctl daemon-reload
echo
echo "done. enable thermal guard at boot with:"
echo "  sudo systemctl enable --now fans-guard"
echo "usage: fans max | fans <0-100> | fans auto | fans ec | fans status"
