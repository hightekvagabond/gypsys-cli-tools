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
    START_TIME=""
    END_TIME=""
    STATUS_MODE=false
    
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
            --help)
                show_help
                exit 0
                ;;
            --description)
                echo "Monitor graphics hardware status, drivers, and GPU performance"
                exit 0
                ;;
            --list-autofixes)
                echo "graphics-autofix"
                echo "emergency-process-kill"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << 'EOH'
Graphics Hardware Monitor Module

USAGE:
    ./monitor.sh [OPTIONS]

OPTIONS:
    --no-auto-fix       Disable automatic fix actions
    --start-time TIME   Set monitoring start time for analysis
    --end-time TIME     Set monitoring end time for analysis
    --status            Show detailed status information instead of monitoring
    --description       Show a short description of what this module monitors
    --list-autofixes    List autofix scripts that this module uses
    --help              Show this help message

EXAMPLES:
    ./monitor.sh                                    # Normal monitoring with autofix
    ./monitor.sh --no-auto-fix                     # Monitor only, no autofix
    ./monitor.sh --start-time "1 hour ago"         # Analyze last hour
    ./monitor.sh --status --start-time "1 hour ago" # Show status for last hour

GRAPHICS HELPERS:
    This module automatically detects and uses appropriate graphics helpers:
    - i915 (Intel integrated graphics) - TESTED
    - nvidia (NVIDIA discrete graphics) - STUB - needs testing
    - amdgpu (AMD graphics) - STUB - needs testing

WHAT THIS MODULE MONITORS:
    - GPU hardware errors and driver crashes
    - Graphics memory usage and VRAM pressure  
    - GPU thermal throttling and overheating
    - Graphics performance degradation
    - Hardware acceleration availability
    - Multi-GPU configuration issues

EOH
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
    log "Checking graphics hardware status..."
    
    # Run enabled graphics helpers
    local helpers_status=0
    if ! run_graphics_helpers; then
        helpers_status=1
    fi
    
    # Overall graphics status assessment
    if [[ $helpers_status -eq 0 ]]; then
        log "Graphics hardware status normal"
        return 0
    else
        log "Graphics hardware issues detected"
        return 1
    fi
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
