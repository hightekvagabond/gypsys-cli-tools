#!/bin/bash
# Quick start script for VM recovery
# This is a wrapper around the main recovery script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== VirtualBox VM Recovery ==="
echo ""
echo "This will recover VMs from the backup disk to ./tmp/"
echo "Only essential files will be copied (no corrupted logs)"
echo ""
echo "Estimated recovery:"
echo "  - CentOS 6 VM: ~18GB"
echo "  - Destination: ./tmp/"
echo ""

# Check if we have sudo
if [ "$EUID" -ne 0 ]; then
    echo "This script needs sudo to access the backup files."
    echo "Relaunching with sudo..."
    echo ""
    exec sudo bash "$0" "$@"
fi

# Run the main recovery script
exec "${SCRIPT_DIR}/recover-from-backup.sh"
