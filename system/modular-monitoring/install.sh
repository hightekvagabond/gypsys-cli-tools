#!/bin/bash
# Modular Monitor Installer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="modular-monitor"

if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

echo "🛡️ Installing Modular Monitor System"
echo "===================================="

# Create service
cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOFSVC
[Unit]
Description=Modular System Monitor
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_DIR/orchestrator.sh
User=root
WorkingDirectory=$SCRIPT_DIR
StandardOutput=journal
StandardError=journal
SyslogIdentifier=modular-monitor

[Install]
WantedBy=multi-user.target
EOFSVC

# Create timer
cat > "/etc/systemd/system/${SERVICE_NAME}.timer" << EOFTIMER
[Unit]
Description=Modular System Monitor Timer
Requires=${SERVICE_NAME}.service

[Timer]
OnCalendar=*:0/2
Persistent=true

[Install]
WantedBy=timers.target
EOFTIMER

# Setup
mkdir -p "/var/tmp/modular-monitor-state"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.timer"
systemctl start "${SERVICE_NAME}.timer"

echo "✅ Installation complete!"
echo "Monitor logs: journalctl -t modular-monitor -f"
echo "Manual run: $SCRIPT_DIR/orchestrator.sh"
