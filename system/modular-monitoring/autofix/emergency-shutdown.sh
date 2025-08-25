#!/bin/bash
# Emergency Shutdown Autofix Script
# Usage: emergency-shutdown.sh <calling_module> <grace_period_seconds> [trigger_reason] [trigger_value]
# Handles shutdown requests from multiple monitors with intelligent grace period tracking

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Load modules common.sh for helper functions
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/modules/common.sh"

# Validate arguments
if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1
fi

CALLING_MODULE="$1"
GRACE_PERIOD="$2"
TRIGGER_REASON="${3:-emergency}"
TRIGGER_VALUE="${4:-unknown}"

# Load autofix configuration
AUTOFIX_CONFIG="$PROJECT_ROOT/config/autofix.conf"
if [[ -f "$AUTOFIX_CONFIG" ]]; then
    source "$AUTOFIX_CONFIG"
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
    
    autofix_log "INFO" "Initiating system shutdown - grace period completed"
    autofix_log "INFO" "Shutdown trigger: $trigger_reason ($trigger_value) from $CALLING_MODULE"
    
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