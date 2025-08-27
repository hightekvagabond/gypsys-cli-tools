#!/bin/bash
# Hardware existence check for thermal monitoring module

MODULE_NAME="thermal"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

# Load common functions (but don't initialize framework)
source "$SCRIPT_DIR/../common.sh" 2>/dev/null || exit 1

check_hardware() {
    # Check if we can read CPU temperature
    if command -v sensors >/dev/null 2>&1; then
        sensors 2>/dev/null | grep -q "°C" && return 0
    fi
    
    # Check thermal zones
    if [[ -d "/sys/class/thermal" ]]; then
        find /sys/class/thermal -name "temp" -readable 2>/dev/null | head -1 | grep -q . && return 0
    fi
    
    # Check for CPU package temp
    if [[ -r "/sys/class/thermal/thermal_zone0/temp" ]]; then
        return 0
    fi
    
    return 1
}

show_help() {
    cat << 'EOF'
THERMAL MODULE HARDWARE EXISTENCE CHECK

PURPOSE:
    Check if thermal monitoring hardware is available on this system.

USAGE:
    ./exists.sh                    # Check hardware and exit with status code
    ./exists.sh --help            # Show this help information

EXIT CODES:
    0 - Thermal monitoring hardware detected
    1 - No thermal monitoring hardware found

HARDWARE DETECTION:
    • CPU temperature sensors (via 'sensors' command)
    • Thermal zones (/sys/class/thermal)
    • CPU package temperature files
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
        echo "✅ Thermal monitoring hardware detected"
        exit 0
    else
        echo "❌ No thermal monitoring hardware found"
        exit 1
    fi
fi
