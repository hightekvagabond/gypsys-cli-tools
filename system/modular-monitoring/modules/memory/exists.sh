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

show_help() {
    cat << 'EOF'
MEMORY MODULE HARDWARE EXISTENCE CHECK

PURPOSE:
    Check if memory monitoring is available on this system.

USAGE:
    ./exists.sh                    # Check hardware and exit with status code
    ./exists.sh --help            # Show this help information

EXIT CODES:
    0 - Memory monitoring available
    1 - Memory monitoring not available

HARDWARE DETECTION:
    • Memory information (/proc/meminfo)
    • Memory statistics access
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
        echo "✅ Memory monitoring available"
        exit 0
    else
        echo "❌ Memory monitoring not available"
        exit 1
    fi
fi
