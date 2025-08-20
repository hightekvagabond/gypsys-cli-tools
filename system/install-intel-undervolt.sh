#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# install-intel-undervolt.sh
#
# PURPOSE:
#   This script installs and configures the `intel-undervolt` utility on a Linux
#   system, enabling safe undervolting of Intel CPUs to reduce idle temperature,
#   improve thermal headroom, and extend fan lifespan — especially on laptops
#   like the Acer Predator series that run hot under light loads.
#
#   It ensures all dependencies are installed, loads the required MSR kernel
#   module, installs the utility, and creates a persistent systemd unit to
#   automatically apply the undervolt at every boot.
#
# FEATURES:
#   - Self-locating: does not rely on hardcoded paths
#   - Idempotent: can be safely run multiple times
#   - Customizable: change the UNDER_VOLT value below
#
# REQUIREMENTS:
#   - Intel CPU
#   - Root privileges for system-wide changes
# ──────────────────────────────────────────────────────────────────────────────

# Configurable parameters
INSTALL_DIR="/opt/intel-undervolt"
SERVICE_NAME="intel-undervolt"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
UNDER_VOLT="-80"  # Safe default undervolt value
MSR_MODULE="msr"

# Determine script location (for future self-reference, if needed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔍 Checking and installing required packages..."

# Required system packages
for pkg in git python3-pip msr-tools; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    echo "📦 Installing $pkg..."
    sudo apt update
    sudo apt install -y "$pkg"
  else
    echo "✅ $pkg already installed"
  fi
done

# Load msr module if not loaded
if ! lsmod | grep -q "^$MSR_MODULE"; then
  echo "📥 Loading $MSR_MODULE kernel module..."
  sudo modprobe $MSR_MODULE
else
  echo "✅ Kernel module '$MSR_MODULE' already loaded"
fi

# Install intel-undervolt if not already
if [[ ! -d "$INSTALL_DIR" ]]; then
  echo "📥 Cloning intel-undervolt to $INSTALL_DIR..."
  git clone git@github.com:georgewhewell/undervolt.git /tmp/intel-undervolt
  sudo mv /tmp/intel-undervolt "$INSTALL_DIR"
  sudo pip3 install --break-system-packages "$INSTALL_DIR"
else
  echo "✅ intel-undervolt already cloned at $INSTALL_DIR"
  if ! command -v intel-undervolt &>/dev/null; then
    echo "📦 Reinstalling intel-undervolt via pip..."
    sudo pip3 install --break-system-packages "$INSTALL_DIR"
  else
    echo "✅ intel-undervolt is already installed"
  fi
fi


# Try resolving the binary directly using sudo's PATH
UNDERVOLT_BIN=$(sudo which intel-undervolt 2>/dev/null || true)

# Fallback to find if which fails
if [[ -z "$UNDERVOLT_BIN" ]]; then
  UNDERVOLT_BIN=$(sudo find / -type f -name intel-undervolt -executable 2>/dev/null | head -n 1)
fi


if [[ -z "$UNDERVOLT_BIN" ]]; then
  echo "❌ Could not find the intel-undervolt binary after install!"
  echo "🔍 Tried searching under /usr/local. Is the install missing or incomplete?"
  exit 1
fi

echo "✅ Found intel-undervolt at: $UNDERVOLT_BIN"


# Apply undervolt immediately for testing
echo "🧪 Applying undervolt of ${UNDER_VOLT} mV now..."
sudo "$UNDERVOLT_BIN" write -c "$UNDER_VOLT"

DESIRED_EXEC="ExecStart=$UNDERVOLT_BIN write -c $UNDER_VOLT"

if [[ ! -f "$SERVICE_PATH" ]] || ! grep -qF "$DESIRED_EXEC" "$SERVICE_PATH"; then
  echo "🛠 Writing systemd unit to $SERVICE_PATH"
  sudo tee "$SERVICE_PATH" >/dev/null <<EOF
[Unit]
Description=Apply Intel undervolt settings at boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=$UNDERVOLT_BIN write -c $UNDER_VOLT
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
else
  echo "✅ Existing systemd service is already correctly configured"
fi

# 🚀 Enable and start the service
echo "🚀 Enabling and starting $SERVICE_NAME.service..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE_NAME.service"

echo "🎉 Undervolt of ${UNDER_VOLT} mV is now active and persistent across reboots."
