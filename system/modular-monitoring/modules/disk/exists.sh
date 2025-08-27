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

show_help() {
    cat << 'EOF'
DISK MODULE HARDWARE EXISTENCE CHECK

PURPOSE:
    Check if disk monitoring is available on this system.

USAGE:
    ./exists.sh                    # Check hardware and exit with status code
    ./exists.sh --help            # Show this help information

EXIT CODES:
    0 - Disk monitoring available
    1 - Disk monitoring not available

HARDWARE DETECTION:
    • Disk information access (via 'df' command)
    • Mounted filesystems (/proc/mounts)
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
        echo "✅ Disk monitoring available"
        exit 0
    else
        echo "❌ Disk monitoring not available"
        exit 1
    fi
fi
