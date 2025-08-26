#!/bin/bash
# =============================================================================
# GRAPHICS MODULE HARDWARE SCAN SCRIPT
# =============================================================================
#
# PURPOSE:
#   Detect graphics hardware and generate appropriate configuration for the
#   graphics monitoring module and autofix system.
#
# CAPABILITIES:
#   - Graphics chipset detection (Intel i915, NVIDIA, AMD)
#   - Graphics vendor identification
#   - Graphics memory detection
#   - Graphics driver status checking
#   - Autofix configuration generation
#
# USAGE:
#   ./scan.sh                    # Human-readable scan results
#   ./scan.sh --config          # Machine-readable config format
#   ./scan.sh --help            # Show help information
#
# OUTPUT MODES:
#   Default: Human-readable hardware information
#   --config: Shell variable assignments for SYSTEM.conf
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="graphics"

# =============================================================================
# show_help() - Display usage information
# =============================================================================
show_help() {
    cat << 'EOF'
GRAPHICS HARDWARE SCAN SCRIPT

PURPOSE:
    Detect graphics hardware and generate configuration for the graphics
    monitoring module and autofix system.

USAGE:
    ./scan.sh                    # Human-readable scan results
    ./scan.sh --config          # Machine-readable config format for SYSTEM.conf
    ./scan.sh --help            # Show this help information

OUTPUT MODES:
    Default Mode:
        Human-readable hardware detection results with explanations
        
    Config Mode (--config):
        Shell variable assignments suitable for SYSTEM.conf:
        GRAPHICS_CHIPSET="i915"
        GPU_VENDOR="intel" 
        GRAPHICS_HELPERS_ENABLED="i915"

DETECTED HARDWARE:
    ✅ Intel Graphics (i915)    - Fully supported and tested
    ⚠️  NVIDIA Graphics         - Autofix helpers need testing
    ⚠️  AMD Graphics (amdgpu)   - Autofix helpers need testing

EXIT CODES:
    0 - Graphics hardware detected and configuration generated
    1 - No graphics hardware detected or scan failed
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

# =============================================================================
# detect_graphics_chipset() - Identify primary graphics chipset
# =============================================================================
detect_graphics_chipset() {
    local chipset="unknown"
    local vendor="unknown"
    local driver=""
    local details=""
    
    # Check loaded kernel modules for graphics drivers
    local loaded_modules
    loaded_modules=$(lsmod 2>/dev/null || echo "")
    
    # Check PCI devices for graphics cards
    local pci_graphics
    pci_graphics=$(lspci 2>/dev/null | grep -i "vga\|3d\|graphics" || echo "")
    
    # Intel graphics detection
    if echo "$loaded_modules" | grep -q "^i915" || echo "$pci_graphics" | grep -qi "intel"; then
        chipset="i915"
        vendor="intel"
        driver="i915"
        
        # Get more details about Intel graphics
        if command -v lspci >/dev/null; then
            details=$(lspci | grep -i "intel.*graphics" | head -1 || echo "Intel integrated graphics")
        else
            details="Intel integrated graphics"
        fi
    
    # NVIDIA graphics detection
    elif echo "$loaded_modules" | grep -q "nvidia" || echo "$pci_graphics" | grep -qi "nvidia"; then
        chipset="nvidia"
        vendor="nvidia"
        driver="nvidia"
        
        # Get NVIDIA GPU details
        if command -v nvidia-smi >/dev/null 2>&1; then
            details=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -1 2>/dev/null || echo "NVIDIA GPU")
        elif command -v lspci >/dev/null; then
            details=$(lspci | grep -i "nvidia" | head -1 || echo "NVIDIA GPU")
        else
            details="NVIDIA GPU"
        fi
    
    # AMD graphics detection
    elif echo "$loaded_modules" | grep -q "amdgpu\|radeon" || echo "$pci_graphics" | grep -qi "amd\|ati"; then
        chipset="amdgpu"
        vendor="amd"
        
        # Determine if using amdgpu or legacy radeon driver
        if echo "$loaded_modules" | grep -q "^amdgpu"; then
            driver="amdgpu"
        elif echo "$loaded_modules" | grep -q "^radeon"; then
            driver="radeon"
        else
            driver="amdgpu"  # Default assumption
        fi
        
        # Get AMD GPU details
        if command -v lspci >/dev/null; then
            details=$(lspci | grep -i "amd\|ati" | grep -i "vga\|graphics" | head -1 || echo "AMD GPU")
        else
            details="AMD GPU"
        fi
    fi
    
    echo "$chipset|$vendor|$driver|$details"
}

# =============================================================================
# get_graphics_memory() - Estimate graphics memory information
# =============================================================================
get_graphics_memory() {
    local mem_info="unknown"
    
    # Try to get graphics memory information
    if command -v nvidia-smi >/dev/null 2>&1; then
        # NVIDIA: Use nvidia-smi
        local nvidia_mem
        nvidia_mem=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "")
        if [[ -n "$nvidia_mem" ]]; then
            mem_info="${nvidia_mem}MB (dedicated)"
        fi
    elif [[ -d "/sys/class/drm" ]]; then
        # Intel/AMD: Check DRM interfaces
        local total_mem=0
        for card in /sys/class/drm/card*/device/mem_info_vram_total; do
            if [[ -r "$card" ]]; then
                local card_mem
                card_mem=$(cat "$card" 2>/dev/null || echo "0")
                ((total_mem += card_mem))
            fi
        done
        
        if [[ $total_mem -gt 0 ]]; then
            mem_info="$((total_mem / 1024 / 1024))MB"
        else
            # Fallback: Check system memory for integrated graphics
            if [[ -r "/proc/meminfo" ]]; then
                local sys_mem
                sys_mem=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}' 2>/dev/null || echo "0")
                if [[ $sys_mem -gt 0 ]]; then
                    # Estimate integrated graphics share (typically 1/8 to 1/4 of system RAM)
                    local estimated_gfx_mem=$((sys_mem / 8 / 1024))
                    mem_info="${estimated_gfx_mem}MB (shared/integrated)"
                fi
            fi
        fi
    fi
    
    echo "$mem_info"
}

# =============================================================================
# check_graphics_helpers_available() - Check which helpers are available
# =============================================================================
check_graphics_helpers_available() {
    local graphics_dir="$(dirname "$SCRIPT_DIR")/graphics"
    local helpers_available=""
    
    if [[ -d "$graphics_dir/helpers" ]]; then
        for helper in "$graphics_dir/helpers"/*.sh; do
            if [[ -x "$helper" ]]; then
                local helper_name
                helper_name=$(basename "$helper" .sh)
                if [[ -z "$helpers_available" ]]; then
                    helpers_available="$helper_name"
                else
                    helpers_available="$helpers_available,$helper_name"
                fi
            fi
        done
    fi
    
    echo "$helpers_available"
}

# =============================================================================
# main_scan() - Main scanning logic
# =============================================================================
main_scan() {
    local config_mode=false
    if [[ "${1:-}" == "--config" ]]; then
        config_mode=true
    fi
    
    # Detect graphics hardware
    local detection_result
    detection_result=$(detect_graphics_chipset)
    
    local chipset="${detection_result%%|*}"
    local vendor="${detection_result#*|}"
    vendor="${vendor%%|*}"
    local driver="${detection_result#*|*|}"
    driver="${driver%%|*}"
    local details="${detection_result##*|}"
    
    # Get additional information
    local memory_info
    memory_info=$(get_graphics_memory)
    
    local available_helpers
    available_helpers=$(check_graphics_helpers_available)
    
    # Determine which helper to enable
    local enabled_helper=""
    case "$chipset" in
        "i915"|"nvidia"|"amdgpu")
            enabled_helper="$chipset"
            ;;
    esac
    
    if [[ "$config_mode" == "true" ]]; then
        # Machine-readable config format
        if [[ "$chipset" != "unknown" ]]; then
            echo "GRAPHICS_CHIPSET=\"$chipset\""
            echo "GPU_VENDOR=\"$vendor\""
            if [[ -n "$enabled_helper" ]]; then
                echo "GRAPHICS_HELPERS_ENABLED=\"$enabled_helper\""
            fi
            if [[ -n "$driver" && "$driver" != "unknown" ]]; then
                echo "GRAPHICS_DRIVER=\"$driver\""
            fi
            exit 0
        else
            exit 1
        fi
    else
        # Human-readable format
        if [[ "$chipset" == "unknown" ]]; then
            echo "❌ No graphics hardware detected"
            echo ""
            echo "This could mean:"
            echo "  • No dedicated graphics card installed"
            echo "  • Graphics drivers not loaded"
            echo "  • Unsupported graphics hardware"
            echo ""
            echo "Install appropriate graphics drivers and try again."
            exit 1
        fi
        
        echo "✅ Graphics hardware detected:"
        echo ""
        echo "🔧 Hardware Details:"
        echo "  Chipset: $chipset"
        echo "  Vendor: $vendor"
        echo "  Driver: $driver"
        echo "  Details: $details"
        
        if [[ "$memory_info" != "unknown" ]]; then
            echo "  Memory: $memory_info"
        fi
        
        echo ""
        echo "⚙️  Configuration Recommendations:"
        echo "  GRAPHICS_CHIPSET=\"$chipset\""
        echo "  GPU_VENDOR=\"$vendor\""
        
        if [[ -n "$enabled_helper" ]]; then
            echo "  GRAPHICS_HELPERS_ENABLED=\"$enabled_helper\""
            
            echo ""
            echo "🛠️  Autofix Support:"
            case "$chipset" in
                "i915")
                    echo "  ✅ Intel i915: Fully supported and tested"
                    echo "     - DKMS module rebuild capability"
                    echo "     - GRUB stability parameter application"
                    echo "     - GPU hang detection and recovery"
                    ;;
                "nvidia")
                    echo "  ⚠️  NVIDIA: Helper available but needs testing"
                    echo "     - GPU reset and recovery (nvidia-smi)"
                    echo "     - CUDA application management"
                    echo "     - Thermal and power management"
                    ;;
                "amdgpu")
                    echo "  ⚠️  AMD GPU: Helper available but needs testing"
                    echo "     - sysfs-based GPU control"
                    echo "     - ROCm application management"
                    echo "     - Multi-GPU configuration recovery"
                    ;;
            esac
        else
            echo ""
            echo "⚠️  No autofix helper available for chipset: $chipset"
        fi
        
        if [[ -n "$available_helpers" ]]; then
            echo ""
            echo "📋 Available helpers: $available_helpers"
        fi
        
        exit 0
    fi
}

# Execute main scan function
main_scan "$@"
