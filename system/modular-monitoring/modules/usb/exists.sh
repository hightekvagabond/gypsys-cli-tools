#!/bin/bash
# Hardware existence check for USB monitoring module

MODULE_NAME="usb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

check_hardware() {
    # Check if USB subsystem exists
    if command -v lsusb >/dev/null 2>&1; then
        lsusb 2>/dev/null | grep -q "Bus" && return 0
    fi
    
    # Check for USB devices in sysfs
    if [[ -d "/sys/bus/usb/devices" ]]; then
        find /sys/bus/usb/devices -mindepth 1 -maxdepth 1 2>/dev/null | head -1 | grep -q . && return 0
    fi
    
    return 1
}

# When run directly, check hardware and exit with appropriate code
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if check_hardware; then
        echo "✅ USB subsystem detected"
        exit 0
    else
        echo "❌ No USB subsystem found"
        exit 1
    fi
fi
