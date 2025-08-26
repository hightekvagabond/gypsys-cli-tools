#!/bin/bash
# =============================================================================
# KERNEL MODULE HARDWARE SCAN SCRIPT
# =============================================================================
#
# PURPOSE:
#   Detect kernel and system information for the kernel monitoring module.
#
# CAPABILITIES:
#   - Kernel version detection
#   - Architecture identification
#   - Boot parameters analysis
#   - System information gathering
#
# USAGE:
#   ./scan.sh                    # Human-readable scan results
#   ./scan.sh --config          # Machine-readable config format
#   ./scan.sh --help            # Show help information
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="kernel"

show_help() {
    cat << 'EOF'
KERNEL HARDWARE SCAN SCRIPT

PURPOSE:
    Detect kernel and system information for the kernel monitoring module.

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
    0 - Kernel information detected and configuration generated
    1 - No kernel information detected or scan failed
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

detect_kernel_info() {
    local config_mode=false
    if [[ "${1:-}" == "--config" ]]; then
        config_mode=true
    fi
    
    local kernel_version=""
    local kernel_arch=""
    local system_uptime=""
    local boot_params=""
    local distro=""
    
    # Get kernel version
    kernel_version=$(uname -r 2>/dev/null || echo "unknown")
    
    # Get architecture
    kernel_arch=$(uname -m 2>/dev/null || echo "unknown")
    
    # Get system uptime
    if [[ -r "/proc/uptime" ]]; then
        local uptime_seconds
        uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")
        local days=$((uptime_seconds / 86400))
        local hours=$(((uptime_seconds % 86400) / 3600))
        system_uptime="${days}d ${hours}h"
    fi
    
    # Get boot parameters
    if [[ -r "/proc/cmdline" ]]; then
        boot_params=$(cat /proc/cmdline 2>/dev/null | head -c 200 || echo "")
    fi
    
    # Get distribution info
    if [[ -r "/etc/os-release" ]]; then
        distro=$(grep "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "unknown")
    elif command -v lsb_release >/dev/null 2>&1; then
        distro=$(lsb_release -d 2>/dev/null | cut -f2 || echo "unknown")
    fi
    
    if [[ "$config_mode" == "true" ]]; then
        # Machine-readable config format
        if [[ "$kernel_version" != "unknown" ]]; then
            echo "KERNEL_VERSION=\"$kernel_version\""
            echo "KERNEL_ARCHITECTURE=\"$kernel_arch\""
            if [[ -n "$system_uptime" ]]; then
                echo "SYSTEM_UPTIME=\"$system_uptime\""
            fi
            if [[ -n "$distro" && "$distro" != "unknown" ]]; then
                echo "SYSTEM_DISTRO=\"$distro\""
            fi
            exit 0
        else
            exit 1
        fi
    else
        # Human-readable format
        if [[ "$kernel_version" == "unknown" ]]; then
            echo "❌ No kernel information detected"
            exit 1
        fi
        
        echo "✅ Kernel information detected:"
        echo ""
        echo "🔧 System Details:"
        echo "  Kernel version: $kernel_version"
        echo "  Architecture: $kernel_arch"
        
        if [[ -n "$distro" && "$distro" != "unknown" ]]; then
            echo "  Distribution: $distro"
        fi
        
        if [[ -n "$system_uptime" ]]; then
            echo "  System uptime: $system_uptime"
        fi
        
        # Show CPU info
        if [[ -r "/proc/cpuinfo" ]]; then
            local cpu_model
            cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^ *//' 2>/dev/null || echo "unknown")
            if [[ "$cpu_model" != "unknown" ]]; then
                echo "  CPU: $cpu_model"
            fi
        fi
        
        # Show memory info
        if [[ -r "/proc/meminfo" ]]; then
            local total_ram
            total_ram=$(grep "MemTotal:" /proc/meminfo | awk '{printf "%.1fGB", $2/1024/1024}' 2>/dev/null || echo "unknown")
            if [[ "$total_ram" != "unknown" ]]; then
                echo "  Memory: $total_ram"
            fi
        fi
        
        # Show boot parameters (truncated)
        if [[ -n "$boot_params" ]]; then
            echo ""
            echo "🚀 Boot Parameters:"
            echo "  $(echo "$boot_params" | cut -c1-80)..."
        fi
        
        echo ""
        echo "⚙️  Configuration Recommendations:"
        echo "  KERNEL_VERSION=\"$kernel_version\""
        echo "  KERNEL_ARCHITECTURE=\"$kernel_arch\""
        
        exit 0
    fi
}

# Execute detection
detect_kernel_info "$@"
