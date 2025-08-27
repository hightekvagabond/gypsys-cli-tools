#!/bin/bash
# Hardware existence check for network monitoring module

MODULE_NAME="network"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

check_hardware() {
    # Check if we have network interfaces
    if command -v ip >/dev/null 2>&1; then
        ip link show 2>/dev/null | grep -q ":" && return 0
    fi
    
    # Check /proc/net/dev
    if [[ -r "/proc/net/dev" ]]; then
        tail -n +3 /proc/net/dev 2>/dev/null | grep -q ":" && return 0
    fi
    
    # Check sysfs
    if [[ -d "/sys/class/net" ]]; then
        find /sys/class/net -mindepth 1 -maxdepth 1 -not -name "lo" 2>/dev/null | head -1 | grep -q . && return 0
    fi
    
    return 1
}

show_help() {
    cat << 'EOF'
NETWORK MODULE HARDWARE EXISTENCE CHECK

PURPOSE:
    Check if network monitoring is available on this system.

USAGE:
    ./exists.sh                    # Check hardware and exit with status code
    ./exists.sh --help            # Show this help information

EXIT CODES:
    0 - Network monitoring available
    1 - Network monitoring not available

HARDWARE DETECTION:
    • Network interfaces (via 'ip link' command)
    • Network device files (/proc/net/dev)
    • Network sysfs (/sys/class/net)
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
        echo "✅ Network interfaces detected"
        exit 0
    else
        echo "❌ No network interfaces found"
        exit 1
    fi
fi
