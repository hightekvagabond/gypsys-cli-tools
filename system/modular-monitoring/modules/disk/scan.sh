#!/bin/bash
# =============================================================================
# DISK MODULE HARDWARE SCAN SCRIPT
# =============================================================================
#
# PURPOSE:
#   Detect disk hardware and generate appropriate configuration for the
#   disk monitoring module.
#
# CAPABILITIES:
#   - Disk device detection and identification
#   - Storage capacity analysis
#   - File system type detection
#   - Mount point configuration
#
# USAGE:
#   ./scan.sh                    # Human-readable scan results
#   ./scan.sh --config          # Machine-readable config format
#   ./scan.sh --help            # Show help information
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="disk"

show_help() {
    cat << 'EOF'
DISK HARDWARE SCAN SCRIPT

PURPOSE:
    Detect disk hardware and generate configuration for the disk
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
    0 - Disk hardware detected and configuration generated
    1 - No disk hardware detected or scan failed
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

detect_disk_hardware() {
    local config_mode=false
    if [[ "${1:-}" == "--config" ]]; then
        config_mode=true
    fi
    
    local disk_count=0
    local ssd_count=0
    local hdd_count=0
    local total_capacity=0
    local root_fs=""
    
    # Count disk devices
    if command -v lsblk >/dev/null 2>&1; then
        disk_count=$(lsblk -d -n -o NAME,TYPE 2>/dev/null | grep -c "disk" || echo "0")
        
        # Detect SSD vs HDD
        for disk in $(lsblk -d -n -o NAME,TYPE 2>/dev/null | grep "disk" | awk '{print $1}'); do
            if [[ -r "/sys/block/$disk/queue/rotational" ]]; then
                local rotational
                rotational=$(cat "/sys/block/$disk/queue/rotational" 2>/dev/null || echo "1")
                if [[ "$rotational" == "0" ]]; then
                    ((ssd_count++))
                else
                    ((hdd_count++))
                fi
            fi
        done
    fi
    
    # Get root filesystem type
    root_fs=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")
    
    # Get total storage capacity (in GB)
    if command -v df >/dev/null 2>&1; then
        local total_kb
        total_kb=$(df --total -k 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")
        total_capacity=$((total_kb / 1024 / 1024))  # Convert to GB
    fi
    
    if [[ "$config_mode" == "true" ]]; then
        # Machine-readable config format
        if [[ $disk_count -gt 0 ]]; then
            echo "DISK_COUNT=\"$disk_count\""
            echo "DISK_SSD_COUNT=\"$ssd_count\""
            echo "DISK_HDD_COUNT=\"$hdd_count\""
            echo "DISK_TOTAL_CAPACITY_GB=\"$total_capacity\""
            echo "DISK_ROOT_FILESYSTEM=\"$root_fs\""
            exit 0
        else
            exit 1
        fi
    else
        # Human-readable format
        if [[ $disk_count -eq 0 ]]; then
            echo "❌ No disk hardware detected"
            exit 1
        fi
        
        echo "✅ Disk hardware detected:"
        echo ""
        echo "🔧 Hardware Details:"
        echo "  Total disks: $disk_count"
        echo "  SSDs: $ssd_count"
        echo "  HDDs: $hdd_count"
        echo "  Total capacity: ${total_capacity}GB"
        echo "  Root filesystem: $root_fs"
        
        if command -v lsblk >/dev/null 2>&1; then
            echo ""
            echo "💾 Disk Layout:"
            lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | head -10 | sed 's/^/  /'
        fi
        
        echo ""
        echo "⚙️  Configuration Recommendations:"
        echo "  DISK_COUNT=\"$disk_count\""
        echo "  DISK_ROOT_FILESYSTEM=\"$root_fs\""
        
        exit 0
    fi
}

# Execute detection
detect_disk_hardware "$@"
