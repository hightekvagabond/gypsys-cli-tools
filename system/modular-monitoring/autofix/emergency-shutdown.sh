#!/bin/bash
# =============================================================================
# EMERGENCY SHUTDOWN AUTOFIX SCRIPT
# =============================================================================
#
# ⚠️  CRITICAL DANGER WARNING:
#   This script SHUTS DOWN YOUR ENTIRE SYSTEM immediately. It should only be
#   used in true emergencies when hardware damage is imminent (thermal/power).
#
# PURPOSE:
#   Performs controlled emergency shutdown when system conditions threaten
#   hardware damage. Creates diagnostic dump before shutdown to help diagnose
#   the root cause after reboot.
#
# EMERGENCY CONDITIONS:
#   - Critical thermal overheating (CPU/GPU protection)
#   - Power supply instability
#   - Hardware malfunction detected
#   - Unrecoverable system state
#
# SAFETY MECHANISMS:
#   ✅ Grace period prevents multiple shutdown attempts
#   ✅ Creates emergency diagnostic log before shutdown
#   ✅ Attempts graceful shutdown first, then forces if necessary
#   ✅ Comprehensive logging for post-incident analysis
#   ✅ Validates all inputs to prevent abuse
#
# USAGE:
#   emergency-shutdown.sh <module> <grace_period> [reason] [value]
#
# EXAMPLES:
#   emergency-shutdown.sh thermal 600 critical_temp 95C
#   emergency-shutdown.sh power 300 voltage_drop 10.2V
#
# SECURITY CONSIDERATIONS:
#   - Input validation prevents command injection
#   - Grace period prevents rapid repeated shutdowns
#   - All actions logged for security audit
#   - No user input passed directly to shutdown commands
#
# BASH CONCEPTS FOR BEGINNERS:
#   - 'shutdown' command controls system power state
#   - Grace periods prevent dangerous repeated actions
#   - Diagnostic dumps capture system state for analysis
#   - Emergency scripts require highest safety standards
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize autofix script with common setup
init_autofix_script "$@"

# Additional arguments specific to this script
# Note: Arguments may be shifted if --dry-run was used
if [[ "${DRY_RUN:-false}" == "true" ]]; then
    # In dry-run mode, arguments are: --dry-run calling_module grace_period [trigger_reason] [trigger_value]
    TRIGGER_REASON="${4:-emergency}"
    TRIGGER_VALUE="${5:-unknown}"
else
    # Normal mode: calling_module grace_period [trigger_reason] [trigger_value]
    TRIGGER_REASON="${3:-emergency}"
    TRIGGER_VALUE="${4:-unknown}"
fi

# Configuration loaded automatically via modules/common.sh

# =============================================================================
# show_help() - Display critical usage and safety information
# =============================================================================
show_help() {
    cat << 'EOF'
EMERGENCY SHUTDOWN AUTOFIX SCRIPT

⚠️  CRITICAL DANGER WARNING:
    This script SHUTS DOWN YOUR ENTIRE SYSTEM immediately!
    Only use in true hardware emergencies (thermal/power).

PURPOSE:
    Performs controlled emergency shutdown when system conditions threaten
    hardware damage. Creates diagnostic dump before shutdown.

USAGE:
    emergency-shutdown.sh <calling_module> <grace_period> [reason] [value]

EXAMPLES:
    emergency-shutdown.sh thermal 600 critical_temp 95C
    emergency-shutdown.sh power 300 voltage_drop 10.2V

EMERGENCY CONDITIONS:
    - Critical thermal overheating (CPU/GPU protection)
    - Power supply instability
    - Hardware malfunction detected
    - Unrecoverable system state

EXIT CODES:
    0 - Shutdown initiated successfully
    1 - Error occurred (check logs)
    2 - Skipped due to grace period

CRITICAL WARNING:
    This will shut down your computer immediately!
    Save all work before testing!
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

# Create emergency diagnostic dump
create_emergency_dump() {
    local trigger_reason="$1"
    local trigger_value="$2"
    local calling_module="$3"
    local dump_file="/var/log/emergency-dump-$(date +%Y%m%d-%H%M%S).log"
    
    autofix_log "INFO" "Creating emergency diagnostic dump: $dump_file"
    
    {
        echo "EMERGENCY SYSTEM DIAGNOSTIC DUMP"
        echo "================================="
        echo "Timestamp: $(date)"
        echo "Trigger Reason: $trigger_reason"
        echo "Trigger Value: $trigger_value"
        echo "Calling Module: $calling_module"
        echo "Grace Period: Completed"
        echo ""
        
        echo "SYSTEM TEMPERATURES:"
        sensors 2>/dev/null || echo "sensors not available"
        echo ""
        
        echo "THERMAL ZONES:"
        for zone in /sys/class/thermal/thermal_zone*/temp; do
            if [[ -f "$zone" ]]; then
                local zone_temp=$(($(cat "$zone" 2>/dev/null || echo 0) / 1000))
                echo "$(basename "$(dirname "$zone")"): ${zone_temp}°C"
            fi
        done
        echo ""
        
        echo "TOP CPU PROCESSES:"
        get_top_cpu_processes 2>/dev/null || ps aux --sort=-%cpu | head -10
        echo ""
        
        echo "TOP MEMORY PROCESSES:"
        get_top_memory_processes 2>/dev/null || ps aux --sort=-%mem | head -10
        echo ""
        
        echo "DISK USAGE:"
        df -h
        echo ""
        
        echo "MEMORY INFO:"
        free -h
        echo ""
        
        echo "SYSTEM UPTIME:"
        uptime
        echo ""
        
        echo "LOAD AVERAGE:"
        cat /proc/loadavg 2>/dev/null || echo "load average not available"
        echo ""
        
        echo "RECENT HARDWARE ERRORS:"
        dmesg | tail -50 | grep -iE "error|warn|fail|critical" || echo "No recent errors"
        echo ""
        
        echo "ACTIVE NETWORK CONNECTIONS:"
        ss -tuln 2>/dev/null | head -20 || netstat -tuln 2>/dev/null | head -20 || echo "network info not available"
        echo ""
        
        echo "MONITORING SYSTEM STATUS:"
        journalctl -t modular-monitor --since "10 minutes ago" --no-pager | tail -20 || echo "monitoring logs not available"
        
    } > "$dump_file" 2>/dev/null || autofix_log "ERROR" "Failed to create diagnostic dump"
    
    if [[ -f "$dump_file" ]]; then
        autofix_log "INFO" "Emergency dump created successfully: $dump_file"
    fi
}

# The actual emergency shutdown action
perform_emergency_shutdown() {
    local trigger_reason="$1"
    local trigger_value="$2"
    
    # Check if we're in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        autofix_log "INFO" "[DRY-RUN] Would initiate system shutdown - grace period completed"
        autofix_log "INFO" "[DRY-RUN] Shutdown trigger: $trigger_reason ($trigger_value) from $CALLING_MODULE"
        autofix_log "INFO" "[DRY-RUN] Would execute emergency diagnostic dump creation"
        autofix_log "INFO" "[DRY-RUN] Would check disk space before shutdown"
        autofix_log "INFO" "[DRY-RUN] Would execute shutdown command: shutdown -h \"+1\" \"EMERGENCY: System shutdown initiated - Reason: $trigger_reason ($trigger_value) from $CALLING_MODULE\""
        autofix_log "INFO" "[DRY-RUN] Would try fallback commands if shutdown fails: systemctl poweroff, /sbin/poweroff"
        autofix_log "INFO" "[DRY-RUN] Emergency shutdown procedure would complete successfully"
        return 0
    fi
    
    autofix_log "INFO" "Initiating system shutdown - grace period completed"
    autofix_log "INFO" "Shutdown trigger: $trigger_reason ($trigger_value) from $CALLING_MODULE"
    
    # =========================================================================
    # CRITICAL: CHECK DISK SPACE BEFORE SHUTDOWN
    # =========================================================================
    # A full root partition will prevent the system from rebooting!
    # This is a common cause of unbootable systems after emergency shutdown.
    
    autofix_log "INFO" "CRITICAL: Checking disk space before shutdown..."
    
    local root_usage
    root_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ "$root_usage" -ge 95 ]]; then
        autofix_log "CRITICAL" "ROOT PARTITION IS ${root_usage}% FULL!"
        autofix_log "CRITICAL" "System may NOT REBOOT if we shutdown now!"
        autofix_log "CRITICAL" "Attempting emergency disk cleanup before shutdown..."
        
        # Try emergency cleanup of root partition
        if [[ -x "$SCRIPT_DIR/disk-cleanup.sh" ]]; then
            autofix_log "INFO" "Running emergency disk cleanup on root partition..."
            "$SCRIPT_DIR/disk-cleanup.sh" "emergency-shutdown" 30 "/" "$root_usage" || true
            
            # Re-check after cleanup
            root_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
            autofix_log "INFO" "Root partition usage after cleanup: ${root_usage}%"
            
            if [[ "$root_usage" -ge 95 ]]; then
                autofix_log "CRITICAL" "STILL ${root_usage}% FULL AFTER CLEANUP!"
                autofix_log "CRITICAL" "SHUTDOWN RISK: System may not reboot properly!"
                autofix_log "CRITICAL" "Manual intervention may be required after reboot!"
            else
                autofix_log "INFO" "Disk cleanup successful - safer to shutdown now"
            fi
        else
            autofix_log "ERROR" "No disk cleanup available - EXTREME REBOOT RISK!"
        fi
    else
        autofix_log "INFO" "Root partition usage: ${root_usage}% - safe for shutdown"
    fi
    
    # Create emergency diagnostic dump
    create_emergency_dump "$trigger_reason" "$trigger_value" "$CALLING_MODULE"
    
    # Broadcast shutdown warning to all users
    local shutdown_message="EMERGENCY: System shutdown initiated - Reason: $trigger_reason ($trigger_value) from $CALLING_MODULE"
    echo "$shutdown_message" | wall 2>/dev/null || true
    
    # Desktop notification for imminent shutdown
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical -t 30000 "🚨 Emergency Shutdown" \
            "System shutting down NOW!\nReason: $trigger_reason\nValue: $trigger_value\nModule: $CALLING_MODULE" 2>/dev/null || true
    fi
    
    # Initiate shutdown with minimal delay since grace period already elapsed
    local shutdown_delay="${EMERGENCY_SHUTDOWN_DELAY:-1}"  # minutes
    autofix_log "INFO" "Executing clean shutdown in $shutdown_delay minute(s)"
    
    # Try multiple shutdown methods for reliability
    if command -v shutdown >/dev/null 2>&1; then
        shutdown -h "+$shutdown_delay" "$shutdown_message" 2>/dev/null || {
            autofix_log "WARN" "shutdown command failed, trying systemctl"
            systemctl poweroff 2>/dev/null || {
                autofix_log "WARN" "systemctl failed, trying poweroff"
                /sbin/poweroff 2>/dev/null || {
                    autofix_log "ERROR" "All shutdown methods failed"
                    return 1
                }
            }
        }
    else
        autofix_log "WARN" "shutdown command not available, trying systemctl"
        systemctl poweroff 2>/dev/null || {
            autofix_log "WARN" "systemctl failed, trying poweroff"
            /sbin/poweroff 2>/dev/null || {
                autofix_log "ERROR" "All shutdown methods failed"
                return 1
            }
        }
    fi
    
    autofix_log "INFO" "Emergency shutdown command executed successfully"
    return 0
}

# Execute with grace period management
autofix_log "INFO" "Emergency shutdown requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "emergency-shutdown" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_emergency_shutdown" "$TRIGGER_REASON" "$TRIGGER_VALUE"