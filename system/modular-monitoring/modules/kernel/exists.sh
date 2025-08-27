#!/bin/bash
# Hardware existence check for kernel monitoring module

MODULE_NAME="kernel"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

check_hardware() {
    # Kernel monitoring should work on any Linux system
    if [[ -r "/proc/version" ]]; then
        return 0
    fi
    
    # Check if we can access kernel logs
    if command -v dmesg >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

show_help() {
    cat << 'EOF'
KERNEL MODULE HARDWARE EXISTENCE CHECK

PURPOSE:
    Check if kernel monitoring is available on this system.

USAGE:
    ./exists.sh                    # Check hardware and exit with status code
    ./exists.sh --help            # Show this help information

EXIT CODES:
    0 - Kernel monitoring available
    1 - Kernel monitoring not available

HARDWARE DETECTION:
    • Kernel information (/proc/version)
    • Kernel logs access (/var/log/kern.log)
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
        echo "✅ Kernel monitoring available"
        exit 0
    else
        echo "❌ Kernel monitoring not available"
        exit 1
    fi
fi
