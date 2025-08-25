#!/bin/bash
# Hardware existence check for Intel i915 GPU monitoring module

MODULE_NAME="i915"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

check_hardware() {
    # Check if Intel GPU is present
    if command -v lspci >/dev/null 2>&1; then
        lspci 2>/dev/null | grep -qi "intel.*graphics\|intel.*display" && return 0
    fi
    
    # Check for i915 module
    if lsmod 2>/dev/null | grep -q "^i915"; then
        return 0
    fi
    
    # Check for Intel GPU in sysfs
    if [[ -d "/sys/class/drm" ]]; then
        find /sys/class/drm -name "*i915*" 2>/dev/null | head -1 | grep -q . && return 0
    fi
    
    return 1
}

# When run directly, check hardware and exit with appropriate code
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if check_hardware; then
        echo "✅ Intel i915 GPU detected"
        exit 0
    else
        echo "❌ No Intel i915 GPU found"
        exit 1
    fi
fi
