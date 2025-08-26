#!/bin/bash
# =============================================================================
# THERMAL MODULE HARDWARE SCAN SCRIPT
# =============================================================================
#
# PURPOSE:
#   Detect thermal monitoring hardware and generate appropriate configuration
#   for the thermal monitoring module.
#
# CAPABILITIES:
#   - CPU temperature sensor detection
#   - Thermal management tool detection  
#   - Hardware thermal zone identification
#   - Thermal monitoring configuration generation
#
# USAGE:
#   ./scan.sh                    # Human-readable scan results
#   ./scan.sh --config          # Machine-readable config format
#   ./scan.sh --help            # Show help information
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="thermal"

show_help() {
    cat << 'EOF'
THERMAL HARDWARE SCAN SCRIPT

PURPOSE:
    Detect thermal monitoring hardware and generate configuration for the
    thermal monitoring module.

USAGE:
    ./scan.sh                    # Human-readable scan results
    ./scan.sh --config          # Machine-readable config format for SYSTEM.conf
    ./scan.sh --help            # Show this help information

OUTPUT MODES:
    Default Mode:
        Human-readable hardware detection results with explanations
        
    Config Mode (--config):
        Shell variable assignments suitable for SYSTEM.conf

EXIT CODES:
    0 - Thermal hardware detected and configuration generated
    1 - No thermal hardware detected or scan failed
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

detect_thermal_hardware() {
    local config_mode=false
    if [[ "${1:-}" == "--config" ]]; then
        config_mode=true
    fi
    
    local thermal_zones=0
    local sensors_available=false
    local hwmon_available=false
    local cpu_thermal=false
    
    # Check for thermal zones
    if [[ -d "/sys/class/thermal" ]]; then
        thermal_zones=$(find /sys/class/thermal -name "thermal_zone*" -type d 2>/dev/null | wc -l)
    fi
    
    # Check for sensors command
    if command -v sensors >/dev/null 2>&1; then
        sensors_available=true
    fi
    
    # Check for hwmon interfaces
    if [[ -d "/sys/class/hwmon" ]]; then
        local hwmon_count
        hwmon_count=$(find /sys/class/hwmon -name "hwmon*" -type d 2>/dev/null | wc -l)
        if [[ $hwmon_count -gt 0 ]]; then
            hwmon_available=true
        fi
    fi
    
    # Check for CPU thermal support
    if [[ -r "/sys/class/thermal/thermal_zone0/type" ]]; then
        local zone_type
        zone_type=$(cat /sys/class/thermal/thermal_zone0/type 2>/dev/null || echo "")
        if [[ "$zone_type" =~ cpu|acpi|x86_pkg_temp ]]; then
            cpu_thermal=true
        fi
    fi
    
    if [[ "$config_mode" == "true" ]]; then
        # Machine-readable config format
        if [[ $thermal_zones -gt 0 || "$sensors_available" == "true" ]]; then
            echo "THERMAL_ZONES_COUNT=\"$thermal_zones\""
            echo "THERMAL_SENSORS_AVAILABLE=\"$sensors_available\""
            echo "THERMAL_HWMON_AVAILABLE=\"$hwmon_available\""
            echo "THERMAL_CPU_SUPPORT=\"$cpu_thermal\""
            exit 0
        else
            exit 1
        fi
    else
        # Human-readable format
        if [[ $thermal_zones -eq 0 && "$sensors_available" == "false" ]]; then
            echo "❌ No thermal monitoring hardware detected"
            echo ""
            echo "Recommendations:"
            echo "  • Install lm-sensors package: apt install lm-sensors"
            echo "  • Run sensors-detect to configure hardware sensors"
            echo "  • Check if thermal kernel modules are loaded"
            exit 1
        fi
        
        echo "✅ Thermal monitoring hardware detected:"
        echo ""
        echo "🔧 Hardware Details:"
        echo "  Thermal zones: $thermal_zones"
        echo "  Sensors command available: $sensors_available"
        echo "  Hardware monitoring (hwmon): $hwmon_available"
        echo "  CPU thermal support: $cpu_thermal"
        
        if [[ "$sensors_available" == "true" ]]; then
            echo ""
            echo "🌡️  Available sensors:"
            sensors 2>/dev/null | head -10 | sed 's/^/  /'
        fi
        
        echo ""
        echo "⚙️  Configuration Recommendations:"
        echo "  THERMAL_ZONES_COUNT=\"$thermal_zones\""
        echo "  THERMAL_SENSORS_AVAILABLE=\"$sensors_available\""
        echo "  THERMAL_HWMON_AVAILABLE=\"$hwmon_available\""
        
        exit 0
    fi
}

# Execute detection
detect_thermal_hardware "$@"
