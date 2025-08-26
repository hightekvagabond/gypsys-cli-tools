#!/bin/bash
# =============================================================================
# MEMORY MODULE HARDWARE SCAN SCRIPT
# =============================================================================
#
# PURPOSE:
#   Detect memory hardware and generate appropriate configuration for the
#   memory monitoring module.
#
# CAPABILITIES:
#   - RAM capacity detection
#   - Memory type identification
#   - Swap configuration analysis
#   - Memory performance characteristics
#
# USAGE:
#   ./scan.sh                    # Human-readable scan results
#   ./scan.sh --config          # Machine-readable config format
#   ./scan.sh --help            # Show help information
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="memory"

show_help() {
    cat << 'EOF'
MEMORY HARDWARE SCAN SCRIPT

PURPOSE:
    Detect memory hardware and generate configuration for the memory
    monitoring module.

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
    0 - Memory hardware detected and configuration generated
    1 - No memory hardware detected or scan failed
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

detect_memory_hardware() {
    local config_mode=false
    if [[ "${1:-}" == "--config" ]]; then
        config_mode=true
    fi
    
    local total_ram_mb=0
    local available_ram_mb=0
    local swap_total_mb=0
    local memory_type="unknown"
    local dimm_count=0
    
    # Get memory information from /proc/meminfo
    if [[ -r "/proc/meminfo" ]]; then
        total_ram_mb=$(grep "MemTotal:" /proc/meminfo | awk '{print int($2/1024)}')
        available_ram_mb=$(grep "MemAvailable:" /proc/meminfo | awk '{print int($2/1024)}' 2>/dev/null || echo "$total_ram_mb")
        swap_total_mb=$(grep "SwapTotal:" /proc/meminfo | awk '{print int($2/1024)}')
    fi
    
    # Try to get memory type from dmidecode (requires root)
    if command -v dmidecode >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
        memory_type=$(dmidecode -t memory 2>/dev/null | grep "Type:" | grep -v "Unknown\|Other" | head -1 | awk '{print $2}' || echo "unknown")
        dimm_count=$(dmidecode -t memory 2>/dev/null | grep -c "Size.*MB\|Size.*GB" || echo "0")
    elif command -v lshw >/dev/null 2>&1; then
        # Alternative method using lshw
        memory_type=$(lshw -c memory 2>/dev/null | grep "description" | grep -i "ram\|ddr" | head -1 | sed 's/.*description: //' || echo "unknown")
    fi
    
    if [[ "$config_mode" == "true" ]]; then
        # Machine-readable config format
        if [[ $total_ram_mb -gt 0 ]]; then
            echo "MEMORY_TOTAL_MB=\"$total_ram_mb\""
            echo "MEMORY_AVAILABLE_MB=\"$available_ram_mb\""
            echo "MEMORY_SWAP_MB=\"$swap_total_mb\""
            if [[ "$memory_type" != "unknown" ]]; then
                echo "MEMORY_TYPE=\"$memory_type\""
            fi
            if [[ $dimm_count -gt 0 ]]; then
                echo "MEMORY_DIMM_COUNT=\"$dimm_count\""
            fi
            exit 0
        else
            exit 1
        fi
    else
        # Human-readable format
        if [[ $total_ram_mb -eq 0 ]]; then
            echo "❌ No memory hardware detected"
            exit 1
        fi
        
        echo "✅ Memory hardware detected:"
        echo ""
        echo "🔧 Hardware Details:"
        echo "  Total RAM: ${total_ram_mb}MB ($(echo "scale=1; $total_ram_mb/1024" | bc 2>/dev/null || echo "$((total_ram_mb/1024))")GB)"
        echo "  Available RAM: ${available_ram_mb}MB"
        echo "  Swap space: ${swap_total_mb}MB"
        
        if [[ "$memory_type" != "unknown" ]]; then
            echo "  Memory type: $memory_type"
        fi
        
        if [[ $dimm_count -gt 0 ]]; then
            echo "  DIMM modules: $dimm_count"
        fi
        
        # Show current memory usage
        if command -v free >/dev/null 2>&1; then
            echo ""
            echo "💾 Current Memory Usage:"
            free -h | sed 's/^/  /'
        fi
        
        echo ""
        echo "⚙️  Configuration Recommendations:"
        echo "  MEMORY_TOTAL_MB=\"$total_ram_mb\""
        echo "  MEMORY_SWAP_MB=\"$swap_total_mb\""
        
        # Suggest thresholds based on available memory
        local warning_threshold=$((total_ram_mb * 80 / 100))
        local critical_threshold=$((total_ram_mb * 90 / 100))
        echo "  Suggested monitoring thresholds:"
        echo "    Warning: ${warning_threshold}MB (80%)"
        echo "    Critical: ${critical_threshold}MB (90%)"
        
        exit 0
    fi
}

# Execute detection
detect_memory_hardware "$@"
