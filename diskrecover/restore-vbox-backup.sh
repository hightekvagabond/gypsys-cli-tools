#!/bin/bash
# Restore the .vbox file from backup
# Run with: sudo ./restore-vbox-backup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VBOX_FILE="${SCRIPT_DIR}/tmp/CentOS 6/CentOS 6.vbox"
BACKUP_FILE="${SCRIPT_DIR}/tmp/CentOS 6/CentOS 6.vbox.backup-20251105-210004"

# Detect the real user
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$USER"
fi

echo "=== Restore VirtualBox Configuration from Backup ==="
echo ""

# Check if we have root
if [ "$EUID" -ne 0 ]; then
    echo "This script needs sudo to restore the backup."
    echo "Relaunching with sudo..."
    echo ""
    exec sudo bash "$0" "$@"
fi

# Check if backup exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found at $BACKUP_FILE" >&2
    exit 1
fi

echo "Restoring from: $BACKUP_FILE"
echo "Restoring to: $VBOX_FILE"
echo ""

# Restore the backup
cp "$BACKUP_FILE" "$VBOX_FILE"
chown "$REAL_USER:$REAL_USER" "$VBOX_FILE"
chmod 644 "$VBOX_FILE"

echo "✓ Backup restored successfully"
echo ""
echo "The .vbox file has been restored to its original state."
echo "You can now try to import it into VirtualBox."
echo ""


