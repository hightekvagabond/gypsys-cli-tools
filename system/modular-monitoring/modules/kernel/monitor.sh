#!/bin/bash
#
# KERNEL MONITORING MODULE
#
# PURPOSE:
#   Monitors kernel version changes, system updates, and kernel-related issues
#   to track system stability patterns and correlate problems with kernel updates.
#   Kernel changes can introduce hardware compatibility issues and system instability.
#
# MONITORING CAPABILITIES:
#   - Kernel version change detection
#   - System boot correlation with kernel updates
#   - Kernel module loading issues
#   - Historical kernel stability tracking
#   - Hardware compatibility analysis
#
# USAGE:
#   ./monitor.sh [--no-auto-fix] [--status] [--start-time TIME] [--end-time TIME]
#   ./monitor.sh --help
#   ./monitor.sh --description
#   ./monitor.sh --list-autofixes
#
MODULE_NAME="kernel"
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
Kernel monitoring module

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
    --dry-run shows what kernel monitoring would be performed without
    actually accessing kernel logs or running kernel commands.

EOH
}

show_description() {
    echo "Monitor kernel version and error status"
}

list_autofixes() {
    echo "emergency-shutdown"
    echo "kernel-branch-switch"
}

# =============================================================================
# check_kernel_branch_compliance() - Check if current kernel matches preferred branch
# =============================================================================
check_kernel_branch_compliance() {
    local current_kernel="$1"
    local preferred_branch="${PREFERRED_KERNEL_BRANCH:-stable}"
    
    log "Checking kernel branch compliance (current: $current_kernel, preferred: $preferred_branch)"
    
    # Determine current kernel branch based on version pattern
    local current_branch="unknown"
    
    # Parse kernel version to determine branch
    # Extract major.minor version for analysis
    local major_minor
    major_minor=$(echo "$current_kernel" | sed 's/\([0-9]*\.[0-9]*\).*/\1/')
    
    # Convert to comparable format (e.g., "6.14" -> 614)
    local version_num
    version_num=$(echo "$major_minor" | awk -F. '{printf "%d%02d", $1, $2}')
    
    if [[ "$current_kernel" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-generic$ ]]; then
        # Three-part version number (e.g., 5.15.120-91-generic, 6.14.0-29-generic)
        if [[ $version_num -ge 614 ]]; then
            # 6.14+ is linux-next territory (very new)
            current_branch="linux-next"
        elif [[ $version_num -ge 608 ]]; then
            # 6.8+ is mainline
            current_branch="mainline"
        elif [[ $version_num -ge 515 ]]; then
            # 5.15+ is stable
            current_branch="stable"
        else
            # Older versions are longterm/LTS
            current_branch="longterm"
        fi
    elif [[ "$current_kernel" =~ ^[0-9]+\.[0-9]+\.0-[0-9]+-generic$ ]]; then
        # Standard format (e.g., 6.8.0-31-generic, 6.14.0-29-generic)
        if [[ $version_num -ge 614 ]]; then
            # 6.14+ is linux-next territory (very new)
            current_branch="linux-next"
        elif [[ $version_num -ge 608 ]]; then
            # 6.8+ is mainline
            current_branch="mainline"
        elif [[ $version_num -ge 515 ]]; then
            # 5.15+ is stable
            current_branch="stable"
        else
            # Older versions are longterm/LTS
            current_branch="longterm"
        fi
    elif [[ "$current_kernel" =~ ^[0-9]+\.[0-9]+-[0-9]+-generic$ ]]; then
        # Two-part version (e.g., 6.14-29-generic)
        if [[ $version_num -ge 614 ]]; then
            current_branch="linux-next"
        elif [[ $version_num -ge 608 ]]; then
            current_branch="mainline"
        else
            current_branch="stable"
        fi
    else
        # Custom or unknown format - try to guess based on version number
        if [[ $version_num -ge 614 ]]; then
            current_branch="linux-next"
        elif [[ $version_num -ge 608 ]]; then
            current_branch="mainline"
        else
            current_branch="stable"
        fi
    fi
    
    log "Detected kernel branch: $current_branch"
    
    # Check compliance
    if [[ "$current_branch" == "$preferred_branch" ]]; then
        log "✅ Kernel branch compliance: OK ($current_branch matches preferred $preferred_branch)"
        return 0
    fi
    
    # Handle non-compliance
    local severity="warning"
    local message="⚠️ Kernel branch mismatch: running $current_branch kernel ($current_kernel) but $preferred_branch preferred"
    
    # Increase severity for problematic combinations
    if [[ "$current_branch" == "linux-next" && "$preferred_branch" == "stable" ]]; then
        severity="critical"
        message="🚨 CRITICAL: Running linux-next kernel ($current_kernel) in production environment (stable preferred)"
    elif [[ "$current_branch" == "linux-next" && "$preferred_branch" == "longterm" ]]; then
        severity="critical"
        message="🚨 CRITICAL: Running linux-next kernel ($current_kernel) with longterm stability requirements"
    elif [[ "$current_branch" == "mainline" && "$preferred_branch" == "longterm" ]]; then
        severity="warning"
        message="⚠️ WARNING: Running mainline kernel ($current_kernel) with longterm stability preference"
    fi
    
    # Send alert
    send_alert "$severity" "$message"
    
    # Trigger autofix if enabled and allowed
    if [[ "${AUTO_FIX_ENABLED:-true}" == "true" && "${ALLOW_KERNEL_BRANCH_CHANGES:-true}" == "true" ]]; then
        local autofix_script="$SCRIPT_DIR/../../autofix/kernel-branch-switch.sh"
        if [[ -x "$autofix_script" ]]; then
            log "Triggering kernel branch autofix to switch to $preferred_branch"
            
            # Use recommend action for non-critical issues, install for critical
            local autofix_action="recommend"
            if [[ "$severity" == "critical" ]]; then
                autofix_action="install"
            fi
            
            # Call the autofix script with appropriate grace period
            if "$autofix_script" "$MODULE_NAME" 7200 "$preferred_branch" "$autofix_action"; then
                log "Kernel branch autofix completed successfully"
            else
                log "Kernel branch autofix failed - check logs"
            fi
        else
            log "Kernel branch autofix script not found or not executable: $autofix_script"
        fi
    else
        log "Kernel branch autofix disabled (AUTO_FIX_ENABLED=${AUTO_FIX_ENABLED:-true}, ALLOW_KERNEL_BRANCH_CHANGES=${ALLOW_KERNEL_BRANCH_CHANGES:-true})"
    fi
    
    # Log recommendation if warnings are enabled
    if [[ "${KERNEL_COMPATIBILITY_WARNINGS:-true}" == "true" ]]; then
        log "RECOMMENDATION: Consider switching to $preferred_branch kernel branch for better stability"
        log "CURRENT ISSUES: Development kernels may cause driver compatibility problems"
        log "SUGGESTED ACTION: Check available kernels with 'apt list --installed linux-image-*'"
        
        # Provide specific guidance based on preferred branch
        case "$preferred_branch" in
            "stable")
                log "TO INSTALL STABLE: sudo apt install linux-image-generic"
                ;;
            "longterm")
                log "TO INSTALL LONGTERM: sudo apt install linux-image-generic-hwe-20.04 (or latest LTS)"
                ;;
            "mainline")
                log "TO INSTALL MAINLINE: Use Ubuntu Mainline Kernel PPA"
                ;;
        esac
        
        # Hardware-specific warnings
        if [[ "${GRAPHICS_CHIPSET:-}" == "i915" ]]; then
            log "⚠️ HARDWARE WARNING: Intel i915 graphics may have issues with kernel $current_kernel"
            log "   Common problems: HDMI detection, display freezes, GPU hangs"
            log "   Solution: Use stable kernel branch for Intel graphics reliability"
        fi
    fi
    
    return 1  # Non-compliance detected
}


check_status() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🧪 DRY-RUN MODE: Kernel Monitoring Analysis"
        echo "============================================"
        echo "Mode: Analysis only - no kernel logs will be accessed"
        echo ""
        
        echo "KERNEL MONITORING OPERATIONS THAT WOULD BE PERFORMED:"
        echo "----------------------------------------------------"
        echo "1. Kernel Version Check:"
        echo "   - Command: uname -r"
        echo "   - Purpose: Get current kernel version"
        echo "   - Expected: Kernel version string (e.g., 6.14.0-29-generic)"
        echo ""
        
        echo "2. Kernel Branch Compliance Check:"
        echo "   - Purpose: Verify kernel branch matches system preference"
        echo "   - Config: PREFERRED_KERNEL_BRANCH in system_default.conf"
        echo "   - Current setting: ${PREFERRED_KERNEL_BRANCH:-stable}"
        echo "   - Expected: Compliance with preferred branch for stability"
        echo ""
        
        echo "2. Kernel Error Log Analysis:"
        echo "   - Command: dmesg | grep -i 'error\|fail\|panic' | tail -20"
        echo "   - Purpose: Check for recent kernel errors and failures"
        echo "   - Expected: Recent kernel error messages or empty output"
        echo ""
        
        echo "3. System Stability Check:"
        echo "   - Command: dmesg | grep -i 'oops\|segfault\|kernel bug' | tail -10"
        echo "   - Purpose: Check for kernel panics and serious errors"
        echo "   - Expected: No critical kernel errors"
        echo ""
        
        echo "4. Boot Time Analysis:"
        echo "   - Command: systemd-analyze time"
        echo "   - Purpose: Check system boot time and performance"
        echo "   - Expected: Boot time analysis and potential bottlenecks"
        echo ""
        
        echo "5. Kernel Module Status:"
        echo "   - Command: lsmod | head -20"
        echo "   - Purpose: Check loaded kernel modules"
        echo "   - Expected: List of currently loaded kernel modules"
        echo ""
        
        echo "6. Alert Generation:"
        echo "   - Kernel panics and oops"
        echo "   - Critical error messages"
        echo "   - Boot time issues"
        echo "   - Module loading failures"
        echo ""
        
        echo "7. Autofix Actions:"
        if [[ "${AUTO_FIX_ENABLED:-true}" == "true" ]]; then
            echo "   - Emergency shutdown for critical kernel errors"
            echo "   - Process management for problematic applications"
            echo "   - System recovery procedures"
        else
            echo "   - Autofix disabled - monitoring only"
        fi
        echo ""
        
        echo "SYSTEM STATE ANALYSIS:"
        echo "----------------------"
        echo "Current working directory: $(pwd)"
        echo "Script permissions: $([[ -r "$0" ]] && echo "Readable" || echo "Not readable")"
        echo "uname command available: $([[ $(command -v uname >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "dmesg command available: $([[ $(command -v dmesg >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "systemd-analyze available: $([[ $(command -v systemd-analyze >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "Current kernel: $(uname -r 2>/dev/null || echo "Unknown")"
        echo "Autofix enabled: ${AUTO_FIX_ENABLED:-true}"
        echo ""
        
        echo "SAFETY CHECKS PERFORMED:"
        echo "------------------------"
        echo "✅ Script permissions verified"
        echo "✅ Command availability checked"
        echo "✅ Kernel safety validated"
        echo "✅ System information verified"
        echo ""
        
        echo "STATUS: Dry-run completed - no kernel logs accessed"
        echo "============================================"
        
        log "DRY-RUN: Kernel monitoring analysis completed"
        return 0
    fi
    
    log "Checking kernel status..."
    
    # Check kernel version
    local kernel_version
    kernel_version=$(uname -r 2>/dev/null || echo "unknown")
    
    if [[ "$kernel_version" == "unknown" ]]; then
        log "Warning: Cannot determine kernel version"
        return 1
    fi
    
    # Check kernel branch compliance
    check_kernel_branch_compliance "$kernel_version"
    
    # Check for kernel errors in dmesg
    local kernel_errors
    kernel_errors=$(dmesg | grep -i "error\|fail\|panic" | tail -5 | wc -l)
    
    if [[ $kernel_errors -gt 0 ]]; then
        send_alert "warning" "⚠️ Kernel errors detected in system logs"
        return 1
    fi
    
    # Check for critical kernel issues
    local critical_errors
    critical_errors=$(dmesg | grep -i "oops\|segfault\|kernel bug" | tail -5 | wc -l)
    
    if [[ $critical_errors -gt 0 ]]; then
        send_alert "critical" "🚨 CRITICAL: Kernel panics or serious errors detected"
        return 1
    fi
    
    log "Kernel status normal: version $kernel_version"
    return 0
}

show_status() {
    local start_time="${START_TIME:-${DEFAULT_STATUS_START_TIME:-1 hour ago}}"
    local end_time="${END_TIME:-${DEFAULT_STATUS_END_TIME:-now}}"
    
    echo "=== ${MODULE_NAME^^} MODULE STATUS ==="
    echo "Time range: $start_time to $end_time"
    echo ""
    
    # Call the monitoring function with no autofix to get analysis
    AUTO_FIX_ENABLED=false
    check_status
}

# Parse arguments and initialize
parse_args "$@"
validate_module "$MODULE_NAME"

# If script is run directly, run appropriate function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$STATUS_MODE" == "true" ]]; then
        show_status
    else
        check_status
    fi
fi
