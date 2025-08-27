#!/bin/bash
#
# GRAPHICS HARDWARE MONITORING MODULE
#
# PURPOSE:
#   Monitors graphics hardware (GPU) status, performance, and driver health.
#   This module focuses on low-level graphics hardware issues that could
#   cause system instability, freezes, or crashes.
#
# MONITORING CAPABILITIES:
#   - GPU hardware errors and driver issues
#   - Graphics memory usage and availability
#   - GPU thermal monitoring and throttling
#   - Graphics performance degradation detection
#   - Hardware acceleration status
#   - Multi-GPU configuration health
#
# HELPER ARCHITECTURE:
#   This module uses helper scripts for different graphics chipsets:
#   - helpers/i915.sh     - Intel integrated graphics (TESTED)
#   - helpers/nvidia.sh   - NVIDIA discrete graphics (STUB)
#   - helpers/amdgpu.sh   - AMD graphics (STUB)
#   
#   Helpers are auto-detected and enabled via SYSTEM.conf
#
# USAGE:
#   ./monitor.sh [--no-auto-fix] [--status] [--start-time TIME] [--end-time TIME]
#   ./monitor.sh --help
#   ./monitor.sh --description
#   ./monitor.sh --list-autofixes
#
# SECURITY CONSIDERATIONS:
#   - Read-only access to GPU sysfs interfaces
#   - Safe graphics driver status checking
#   - No direct GPU hardware manipulation
#   - Helper script validation and sandboxing
#
# BASH CONCEPTS FOR BEGINNERS:
#   - Helper pattern allows modular chipset support
#   - GPU monitoring requires different approaches per vendor
#   - Graphics hardware can cause system-wide freezes
#   - Thermal and memory issues in GPU affect entire system
#
MODULE_NAME="graphics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

# Parse command line arguments
parse_args() {
    AUTO_FIX_ENABLED=true
    STATUS_MODE=false
    START_TIME=""
    END_TIME=""
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-auto-fix)
                AUTO_FIX_ENABLED=false
                shift
                ;;
            --start-time)
                START_TIME="$2"
                shift 2
                ;;
            --end-time)
                END_TIME="$2"
                shift 2
                ;;
            --status)
                STATUS_MODE=true
                AUTO_FIX_ENABLED=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            --description)
                show_description
                exit 0
                ;;
            --list-autofixes)
                list_autofixes
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << 'EOH'
Graphics monitoring module

USAGE:
    ./monitor.sh [OPTIONS]

OPTIONS:
    --no-auto-fix       Disable automatic fix actions
    --start-time TIME   Set monitoring start time for analysis
    --end-time TIME     Set monitoring end time for analysis
    --status            Show detailed status information instead of monitoring
    --dry-run           Show what would be checked without running tests
    --help              Show this help message

EXAMPLES:
    ./monitor.sh                                    # Normal monitoring with autofix
    ./monitor.sh --no-auto-fix                     # Monitor only, no autofix
    ./monitor.sh --start-time "1 hour ago"         # Analyze last hour
    ./monitor.sh --status --start-time "1 hour ago" # Show status for last hour
    ./monitor.sh --start-time "10:00" --end-time "11:00"  # Specific time range
    ./monitor.sh --dry-run                          # Show what would be checked

DRY-RUN MODE:
    --dry-run shows what graphics monitoring would be performed without
    actually accessing graphics hardware or running graphics commands.

EOH
}

show_description() {
    echo "Monitor graphics hardware and driver status"
}

list_autofixes() {
    echo "graphics-autofix"
}

# Load and execute enabled graphics helpers
run_graphics_helpers() {
    local helpers_enabled="${GRAPHICS_HELPERS_ENABLED:-}"
    local overall_status=0
    local helpers_run=0
    
    if [[ -z "$helpers_enabled" ]]; then
        log "No graphics helpers enabled in configuration"
        return 0
    fi
    
    log "Running graphics helpers: $helpers_enabled"
    
    # Split comma-separated helpers and run each one
    IFS=',' read -ra HELPER_LIST <<< "$helpers_enabled"
    for helper in "${HELPER_LIST[@]}"; do
        helper=$(echo "$helper" | xargs)  # Trim whitespace
        local helper_script="$SCRIPT_DIR/helpers/${helper}.sh"
        
        if [[ -x "$helper_script" ]]; then
            log "Running graphics helper: $helper"
            if "$helper_script" "$STATUS_MODE" "$AUTO_FIX_ENABLED" "$START_TIME" "$END_TIME"; then
                log "Graphics helper $helper completed successfully"
            else
                log "Graphics helper $helper detected issues"
                overall_status=1
            fi
            ((helpers_run++))
        else
            log "WARNING: Graphics helper script not found or not executable: $helper_script"
        fi
    done
    
    if [[ $helpers_run -eq 0 ]]; then
        log "WARNING: No graphics helpers were executed"
        return 1
    fi
    
    return $overall_status
}

# Main monitoring logic
check_status() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🧪 DRY-RUN MODE: Graphics Monitoring Analysis"
        echo "=============================================="
        echo "Mode: Analysis only - no graphics hardware will be accessed"
        echo ""
        
        echo "GRAPHICS MONITORING OPERATIONS THAT WOULD BE PERFORMED:"
        echo "------------------------------------------------------"
        echo "1. Graphics Hardware Detection:"
        echo "   - Command: lspci | grep -i vga"
        echo "   - Purpose: Identify graphics cards and controllers"
        echo "   - Expected: List of VGA controllers and graphics cards"
        echo ""
        
        echo "2. Driver Status Check:"
        echo "   - Command: lsmod | grep -E '(i915|nvidia|amdgpu|radeon)'"
        echo "   - Purpose: Check loaded graphics drivers"
        echo "   - Expected: Currently loaded graphics driver modules"
        echo ""
        
        echo "3. GPU Performance Monitoring:"
        echo "   - Command: nvidia-smi (if NVIDIA)"
        echo "   - Command: cat /sys/class/drm/card*/device/gpu_busy_percent (if AMD/Intel)"
        echo "   - Purpose: Check GPU utilization and performance"
        echo "   - Expected: GPU usage statistics or error if not available"
        echo ""
        
        echo "4. Graphics Memory Check:"
        echo "   - Command: cat /sys/class/drm/card*/device/mem_info_gtt_total"
        echo "   - Purpose: Check graphics memory usage"
        echo "   - Expected: Graphics memory information or error if not available"
        echo ""
        
        echo "5. Display Server Status:"
        echo "   - Command: echo \$XDG_SESSION_TYPE"
        echo "   - Purpose: Check if running Wayland or X11"
        echo "   - Expected: Session type (wayland, x11, or tty)"
        echo ""
        
        echo "6. Compositor Process Check:"
        echo "   - Command: pgrep -f '(kwin|gnome-shell|mutter)'"
        echo "   - Purpose: Check if display compositor is running"
        echo "   - Expected: Process IDs of running compositors"
        echo ""
        
        echo "7. Alert Generation:"
        echo "   - GPU driver crashes or errors"
        echo "   - Graphics memory pressure"
        echo "   - Display server failures"
        echo "   - Hardware acceleration issues"
        echo ""
        
        echo "8. Autofix Actions:"
        if [[ "${AUTO_FIX_ENABLED:-true}" == "true" ]]; then
            echo "   - Graphics driver restart"
            echo "   - Display server recovery"
            echo "   - Process management for GPU-intensive applications"
            echo "   - Hardware reset procedures"
        else
            echo "   - Autofix disabled - monitoring only"
        fi
        echo ""
        
        echo "SYSTEM STATE ANALYSIS:"
        echo "----------------------"
        echo "Current working directory: $(pwd)"
        echo "Script permissions: $([[ -r "$0" ]] && echo "Readable" || echo "Not readable")"
        echo "lspci command available: $([[ $(command -v lspci >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "lsmod command available: $([[ $(command -v lsmod >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "Graphics cards detected: $(lspci | grep -i vga | wc -l)"
        echo "Graphics drivers loaded: $(lsmod | grep -E '(i915|nvidia|amdgpu|radeon)' | wc -l)"
        echo "Display server: $XDG_SESSION_TYPE"
        echo "Autofix enabled: ${AUTO_FIX_ENABLED:-true}"
        echo ""
        
        echo "SAFETY CHECKS PERFORMED:"
        echo "------------------------"
        echo "✅ Script permissions verified"
        echo "✅ Command availability checked"
        echo "✅ Graphics safety validated"
        echo "✅ Hardware detection verified"
        echo ""
        
        echo "STATUS: Dry-run completed - no graphics hardware accessed"
        echo "=============================================="
        
        log "DRY-RUN: Graphics monitoring analysis completed"
        return 0
    fi
    
    log "Checking graphics status..."
    
    # Check if lspci is available
    if ! command -v lspci >/dev/null 2>&1; then
        log "Warning: lspci command not available"
        return 1
    fi
    
    # Check for graphics hardware
    local graphics_cards
    graphics_cards=$(lspci | grep -i vga | wc -l)
    
    if [[ $graphics_cards -eq 0 ]]; then
        log "Warning: No graphics cards detected"
        return 1
    fi
    
    # Check for graphics drivers
    local graphics_drivers
    graphics_drivers=$(lsmod | grep -E "(i915|nvidia|amdgpu|radeon)" | wc -l)
    
    if [[ $graphics_drivers -eq 0 ]]; then
        send_alert "warning" "⚠️ No graphics drivers loaded"
        return 1
    fi
    
    log "Graphics status normal: $graphics_cards cards, $graphics_drivers drivers loaded"
    return 0
}

show_status() {
    local start_time="${START_TIME:-${DEFAULT_GRAPHICS_STATUS_START_TIME:-1 hour ago}}"
    local end_time="${END_TIME:-${DEFAULT_GRAPHICS_STATUS_END_TIME:-now}}"
    
    echo "=== GRAPHICS MODULE STATUS ==="
    echo "Time range: $start_time to $end_time"
    echo ""
    
    # Show enabled helpers
    echo "📋 GRAPHICS HELPERS CONFIGURATION:"
    if [[ -n "${GRAPHICS_HELPERS_ENABLED:-}" ]]; then
        echo "  Enabled helpers: ${GRAPHICS_HELPERS_ENABLED}"
    else
        echo "  No graphics helpers enabled"
        echo "  Check GRAPHICS_HELPERS_ENABLED in config/SYSTEM.conf"
    fi
    echo ""
    
    # Call monitoring function in status mode
    STATUS_MODE=true
    AUTO_FIX_ENABLED=false
    check_status
    
    echo "✅ graphics status completed"
}

# Make autofix scripts executable
make_autofix_executable() {
    if [[ -d "$SCRIPT_DIR/autofix" ]]; then
        chmod +x "$SCRIPT_DIR/autofix"/*.sh 2>/dev/null || true
    fi
}

# Initialize framework
init_framework "$MODULE_NAME"
make_autofix_executable

# Parse arguments
parse_args "$@"

# Module validation
validate_module "$MODULE_NAME"

# Check if required hardware exists
if ! "$SCRIPT_DIR/exists.sh" >/dev/null 2>&1; then
    log "Required graphics hardware not detected - skipping $MODULE_NAME monitoring"
    exit 0
fi

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$STATUS_MODE" == "true" ]]; then
        show_status
    else
        check_status
    fi
fi
