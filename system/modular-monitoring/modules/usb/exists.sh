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

show_help() {
    cat << 'EOF'
USB MODULE HARDWARE EXISTENCE CHECK

PURPOSE:
    Check if USB monitoring is available on this system.

USAGE:
    ./exists.sh                    # Check hardware and exit with status code
    ./exists.sh --help            # Show this help information

EXIT CODES:
    0 - USB monitoring available
    1 - USB monitoring not available

HARDWARE DETECTION:
    • USB device information (via 'lsusb' command)
    • USB devices in sysfs (/sys/bus/usb/devices)
EOF
}

# When run directly, check hardware and exit with appropriate code
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check for help request
    if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
        show_help
        exit 0
    fi
    
    if check_hardware; then
        echo "✅ USB subsystem detected"
        exit 0
    else
        echo "❌ No USB subsystem found"
        exit 1
    fi
fi
