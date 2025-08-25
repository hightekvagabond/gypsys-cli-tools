#!/bin/bash
# Hardware existence check for memory monitoring module

MODULE_NAME="memory"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

check_hardware() {
    # Check if we can read memory information
    if command -v free >/dev/null 2>&1; then
        free -b 2>/dev/null | grep -q "Mem:" && return 0
    fi
    
    # Check /proc/meminfo
    if [[ -r "/proc/meminfo" ]]; then
        grep -q "MemTotal:" /proc/meminfo 2>/dev/null && return 0
    fi
    
    return 1
}

# When run directly, check hardware and exit with appropriate code
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if check_hardware; then
        echo "✅ Memory monitoring available"
        exit 0
    else
        echo "❌ Memory monitoring not available"
        exit 1
    fi
fi
