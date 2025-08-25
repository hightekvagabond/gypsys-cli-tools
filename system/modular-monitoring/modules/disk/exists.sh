#!/bin/bash
# Hardware existence check for disk monitoring module

MODULE_NAME="disk"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

check_hardware() {
    # Check if we can read disk information
    if command -v df >/dev/null 2>&1; then
        df / 2>/dev/null | grep -q "/" && return 0
    fi
    
    # Check for mounted filesystems
    if [[ -r "/proc/mounts" ]]; then
        grep -q "^/" /proc/mounts 2>/dev/null && return 0
    fi
    
    return 1
}

# When run directly, check hardware and exit with appropriate code
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if check_hardware; then
        echo "✅ Disk monitoring available"
        exit 0
    else
        echo "❌ Disk monitoring not available"
        exit 1
    fi
fi
