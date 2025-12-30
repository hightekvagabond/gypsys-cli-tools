#!/bin/bash
# Quick start script for fixing VirtualBox configuration issues
# This is a wrapper around the snapshot fix script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== VirtualBox Configuration Fix ==="
echo ""
echo "This will fix broken snapshot references in the recovered VM."
echo "The VM will be configured to use the base disk directly."
echo "A backup of the original .vbox file will be created."
echo ""

# Check if recovery has been done
if [ ! -d "${SCRIPT_DIR}/tmp" ] || [ ! "$(ls -A "${SCRIPT_DIR}/tmp" 2>/dev/null)" ]; then
    echo "Error: No recovered VMs found in ./tmp/" >&2
    echo ""
    echo "Please run the recovery script first:" >&2
    echo "  ./1-recover-vms.sh" >&2
    echo ""
    exit 1
fi

# Check if we have sudo
if [ "$EUID" -ne 0 ]; then
    echo "This script needs sudo to modify the VM configuration."
    echo "Relaunching with sudo..."
    echo ""
    exec sudo bash "$0" "$@"
fi

# Run the CORRECT snapshot fix script
exec "${SCRIPT_DIR}/fix-vbox-use-base-disk.sh"

