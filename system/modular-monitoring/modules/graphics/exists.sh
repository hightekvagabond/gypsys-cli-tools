#!/bin/bash
# Hardware existence check for graphics monitoring module

MODULE_NAME="graphics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

check_hardware() {
    # Check for any graphics hardware
    # Look for graphics cards in PCI bus
    if lspci | grep -qi "vga\|display\|3d\|graphics"; then
        return 0  # Graphics hardware found
    fi
    
    # Check for graphics drivers loaded
    if lsmod | grep -qi "i915\|nvidia\|amdgpu\|radeon\|nouveau"; then
        return 0  # Graphics drivers loaded
    fi
    
    # Check for graphics devices in /dev
    if ls /dev/dri/card* >/dev/null 2>&1; then
        return 0  # Graphics devices present
    fi
    
    # Check for graphics info in /sys
    if [[ -d "/sys/class/drm" ]] && [[ -n "$(ls /sys/class/drm/ 2>/dev/null)" ]]; then
        return 0  # DRM graphics subsystem active
    fi
    
    return 1  # No graphics hardware detected
}

show_help() {
    cat << 'EOF'
GRAPHICS MODULE HARDWARE EXISTENCE CHECK

PURPOSE:
    Check if graphics monitoring is available on this system.

USAGE:
    ./exists.sh                    # Check hardware and exit with status code
    ./exists.sh --help            # Show this help information

EXIT CODES:
    0 - Graphics monitoring available
    1 - Graphics monitoring not available

HARDWARE DETECTION:
    • Graphics hardware (via 'lspci' command)
    • GPU drivers (/proc/modules)
    • Graphics devices (/dev/dri)
    • DRM subsystem (/sys/class/drm)
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
        echo "✅ Graphics hardware detected"
        exit 0
    else
        echo "❌ No graphics hardware found"
        exit 1
    fi
fi
