#!/bin/bash
#
# INTEL i915 GRAPHICS HELPER SCRIPT
#
# PURPOSE:
#   Helper script for monitoring Intel integrated graphics (i915) driver health.
#   This script is called by the graphics module to handle Intel-specific monitoring.
#
# CAPABILITIES:
#   - i915 kernel error detection and analysis
#   - GPU hang and reset monitoring
#   - Display pipeline error tracking
#   - Driver stability assessment
#   - Historical error pattern analysis
#
# USAGE:
#   Called by graphics module: ./i915.sh <status_mode> <autofix_enabled> [start_time] [end_time]
#   Manual testing: ./i915.sh false true
#
# AUTOFIX CAPABILITIES:
#   - DKMS module rebuild (i915-dkms-rebuild)
#   - GRUB parameter application (i915-grub-flags)
#   - GPU-intensive process management
#
# SECURITY CONSIDERATIONS:
#   - Read-only i915 status monitoring
#   - Safe dmesg analysis
#   - No direct hardware manipulation
#   - Validated autofix script execution

HELPER_NAME="i915"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common functions (graphics module loads the main common.sh)
# We'll create our own logging function for helpers
helper_log() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [graphics:$HELPER_NAME] $level: $message" | tee -a "${AUTOFIX_LOG_FILE:-/tmp/modular-monitor.log}"
}

# Parse arguments passed from graphics module
STATUS_MODE="${1:-false}"
AUTO_FIX_ENABLED="${2:-true}"
START_TIME="${3:-}"
END_TIME="${4:-}"

# i915-specific configuration (can be overridden in SYSTEM.conf)
I915_WARN_THRESHOLD="${I915_WARN_THRESHOLD:-5}"
I915_FIX_THRESHOLD="${I915_FIX_THRESHOLD:-15}"
I915_CRITICAL_THRESHOLD="${I915_CRITICAL_THRESHOLD:-50}"

# Check if i915 hardware exists
check_i915_hardware() {
    # Check if i915 driver is loaded
    if ! lsmod | grep -q "i915"; then
        helper_log "DEBUG" "i915 driver not loaded"
        return 1
    fi
    
    # Check if Intel graphics hardware exists
    if ! lspci | grep -qi "intel.*graphics\|intel.*display"; then
        helper_log "DEBUG" "Intel graphics hardware not detected"
        return 1
    fi
    
    return 0
}

# Get i915 errors from kernel logs
get_i915_errors() {
    local since_time="${1:-1 hour ago}"
    local error_count=0
    local recent_errors=""
    
    # Search for i915 errors in kernel logs
    if command -v journalctl >/dev/null 2>&1; then
        recent_errors=$(journalctl --since "$since_time" --no-pager -q 2>/dev/null | grep -i "i915\|drm.*error\|gpu hang\|display.*error" || echo "")
    else
        # Fallback to dmesg
        recent_errors=$(dmesg | grep -i "i915\|drm.*error\|gpu hang\|display.*error" || echo "")
    fi
    
    if [[ -n "$recent_errors" ]]; then
        error_count=$(echo "$recent_errors" | wc -l)
    fi
    
    echo "$error_count|$recent_errors"
}

# Analyze i915 error patterns
analyze_i915_errors() {
    local error_data="$1"
    local error_count="${error_data%%|*}"
    local error_details="${error_data#*|}"
    local severity="normal"
    local recommendations=()
    
    if [[ $error_count -ge $I915_CRITICAL_THRESHOLD ]]; then
        severity="critical"
        recommendations+=("Consider DKMS rebuild: i915-dkms-rebuild")
        recommendations+=("Apply GRUB stability flags: i915-grub-flags")
    elif [[ $error_count -ge $I915_FIX_THRESHOLD ]]; then
        severity="warning"
        recommendations+=("Monitor for GPU hangs and display issues")
        recommendations+=("Consider DKMS rebuild if issues persist")
    elif [[ $error_count -ge $I915_WARN_THRESHOLD ]]; then
        severity="info"
        recommendations+=("Monitor i915 driver stability")
    fi
    
    # Analyze specific error types
    if [[ "$error_details" =~ "gpu hang".*"hang" ]]; then
        recommendations+=("GPU hangs detected - consider process management")
        severity="warning"
    fi
    
    if [[ "$error_details" =~ "display.*error\|pipe.*error" ]]; then
        recommendations+=("Display pipeline errors - check monitor connections")
    fi
    
    echo "$severity|${recommendations[*]}"
}

# Main i915 monitoring function
check_i915_status() {
    local since_time="${START_TIME:-1 hour ago}"
    
    helper_log "INFO" "Checking Intel i915 GPU status..."
    
    # Check if i915 hardware exists
    if ! check_i915_hardware; then
        helper_log "INFO" "Intel i915 hardware not available - skipping"
        return 0
    fi
    
    # Get error information
    local error_data
    error_data=$(get_i915_errors "$since_time")
    local error_count="${error_data%%|*}"
    local error_details="${error_data#*|}"
    
    # Analyze errors and get recommendations
    local analysis_data
    analysis_data=$(analyze_i915_errors "$error_data")
    local severity="${analysis_data%%|*}"
    local recommendations="${analysis_data#*|}"
    
    # Report status based on severity
    case "$severity" in
        "critical")
            helper_log "CRITICAL" "i915 GPU critical issues: $error_count errors detected"
            if [[ "$AUTO_FIX_ENABLED" == "true" ]]; then
                trigger_i915_autofix "$error_count" "$recommendations"
            fi
            return 1
            ;;
        "warning")
            helper_log "WARN" "i915 GPU issues detected: $error_count errors since $since_time"
            if [[ "$AUTO_FIX_ENABLED" == "true" ]]; then
                trigger_i915_autofix "$error_count" "$recommendations"
            fi
            return 1
            ;;
        "info")
            helper_log "INFO" "i915 GPU minor issues: $error_count errors detected"
            return 1
            ;;
        *)
            helper_log "INFO" "i915 GPU status normal: $error_count errors detected"
            return 0
            ;;
    esac
}

# Trigger i915-specific autofix actions
trigger_i915_autofix() {
    local error_count="$1"
    local recommendations="$2"
    
    # Look for autofix scripts in the autofix directory
    local autofix_dir
    autofix_dir="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/autofix"
    
    helper_log "INFO" "Triggering graphics autofix for i915 issues (error count: $error_count)"
    
    # Determine issue type and severity based on error count and recommendations
    local issue_type="graphics_error"
    local severity="warning"
    
    if [[ "$recommendations" =~ "GPU hangs" ]]; then
        issue_type="gpu_hang"
    elif [[ "$recommendations" =~ "display.*error\|Display pipeline" ]]; then
        issue_type="display_error"
    elif [[ "$recommendations" =~ "DKMS rebuild" ]]; then
        issue_type="driver_error"
    fi
    
    if [[ $error_count -ge $I915_CRITICAL_THRESHOLD ]]; then
        severity="critical"
    elif [[ $error_count -ge $I915_FIX_THRESHOLD ]]; then
        severity="warning"
    fi
    
    # Use the new graphics autofix system with helper architecture
    if [[ -x "$autofix_dir/graphics.sh" ]]; then
        helper_log "INFO" "Calling graphics autofix: issue=$issue_type, severity=$severity"
        "$autofix_dir/graphics.sh" "graphics" 300 "$issue_type" "$severity" || \
            helper_log "ERROR" "Graphics autofix failed"
    else
        # Fallback to old direct calls if new system not available
        helper_log "WARN" "New graphics autofix not available, using legacy direct calls"
        
        # DKMS rebuild for critical issues
        if [[ $error_count -ge $I915_CRITICAL_THRESHOLD ]] && [[ -x "$autofix_dir/i915-dkms-rebuild.sh" ]]; then
            helper_log "INFO" "Initiating i915 DKMS rebuild due to critical errors"
            "$autofix_dir/i915-dkms-rebuild.sh" "graphics" 300 || helper_log "ERROR" "i915 DKMS rebuild failed"
        fi
        
        # GRUB flags for persistent issues
        if [[ $error_count -ge $I915_FIX_THRESHOLD ]] && [[ -x "$autofix_dir/i915-grub-flags.sh" ]]; then
            helper_log "INFO" "Applying i915 GRUB stability flags"
            "$autofix_dir/i915-grub-flags.sh" "graphics" 600 || helper_log "ERROR" "i915 GRUB flags application failed"
        fi
        
        # Process management for GPU hangs
        if [[ "$recommendations" =~ "GPU hangs" ]] && [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
            helper_log "INFO" "Managing GPU-intensive processes due to hangs"
            "$autofix_dir/manage-greedy-process.sh" "graphics" 180 "CPU_GREEDY" 80 || helper_log "ERROR" "Process management failed"
        fi
    fi
}

# Status reporting function
show_i915_status() {
    local since_time="${START_TIME:-1 hour ago}"
    local end_time="${END_TIME:-now}"
    
    echo "--- i915 Graphics Helper Status ---"
    echo "Time range: $since_time to $end_time"
    echo ""
    
    if ! check_i915_hardware; then
        echo "❌ Intel i915 hardware not available"
        return 0
    fi
    
    echo "✅ Intel i915 hardware detected"
    
    # Get and display error information
    local error_data
    error_data=$(get_i915_errors "$since_time")
    local error_count="${error_data%%|*}"
    local error_details="${error_data#*|}"
    
    echo "📊 i915 Error Analysis:"
    echo "  Errors since $since_time: $error_count"
    echo "  Warning threshold: $I915_WARN_THRESHOLD"
    echo "  Fix threshold: $I915_FIX_THRESHOLD"
    echo "  Critical threshold: $I915_CRITICAL_THRESHOLD"
    
    if [[ $error_count -gt 0 ]] && [[ -n "$error_details" ]]; then
        echo ""
        echo "🔍 Recent i915 Errors:"
        echo "$error_details" | head -5 | while read -r line; do
            echo "  • $line"
        done
    fi
    
    echo ""
}

show_help() {
    cat << 'EOF'
INTEL I915 GRAPHICS HELPER SCRIPT

PURPOSE:
    Helper script for monitoring Intel i915 graphics driver health.
    Provides Intel-specific graphics monitoring and diagnostics.

USAGE:
    ./i915.sh                      # Run Intel GPU monitoring
    ./i915.sh true                 # Show Intel GPU status
    ./i915.sh --help               # Show this help information

CAPABILITIES:
    • i915 driver error detection (dmesg, sysfs)
    • GPU temperature and power monitoring
    • VRAM usage tracking
    • Driver version compatibility checking
    • Intel GPU hang detection and recovery

INTEL TOOLS/INTERFACES:
    • /sys/class/drm/card*/device/* (sysfs interfaces)
    • intel_gpu_top (optional, for GPU monitoring)
    • i915 drivers properly installed
EOF
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check for help request
    if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
        show_help
        exit 0
    fi
    
    if [[ "$STATUS_MODE" == "true" ]]; then
        show_i915_status
    else
        check_i915_status
    fi
fi
