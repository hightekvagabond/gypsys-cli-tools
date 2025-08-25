#!/bin/bash
# Emergency Shutdown Autofix with Centralized Grace Period Management
# Handles shutdown requests from multiple monitors with intelligent grace period tracking
# Usage: emergency-shutdown.sh <trigger_reason> <trigger_value> <grace_seconds>

# Get the project root directory
AUTOFIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$AUTOFIX_DIR")"
source "$PROJECT_ROOT/modules/common.sh"

# Grace period tracking directory
GRACE_DIR="/tmp/modular-monitor-grace"
mkdir -p "$GRACE_DIR"
SHUTDOWN_GRACE_FILE="$GRACE_DIR/shutdown_request"

emergency_shutdown() {
    local trigger_reason="${1:-emergency}"
    local trigger_value="${2:-unknown}"
    local grace_seconds="${3:-120}"
    local calling_module="${4:-unknown}"
    
    log "AUTOFIX: Emergency shutdown request - Trigger: $trigger_reason ($trigger_value) from $calling_module module (grace: ${grace_seconds}s)"
    
    # Load global autofix configuration
    local autofix_config="$PROJECT_ROOT/config/autofix.conf"
    if [[ -f "$autofix_config" ]]; then
        source "$autofix_config"
    fi
    
    local current_time=$(date +%s)
    
    # Check if we already have a shutdown grace period active
    if [[ -f "$SHUTDOWN_GRACE_FILE" ]]; then
        local grace_start=$(cat "$SHUTDOWN_GRACE_FILE" 2>/dev/null || echo "0")
        local elapsed=$((current_time - grace_start))
        
        if [[ $elapsed -lt $grace_seconds ]]; then
            local remaining=$((grace_seconds - elapsed))
            log "AUTOFIX: System still in shutdown grace period (${remaining}s remaining)"
            log "AUTOFIX: Shutdown request from $calling_module noted but grace period active"
            
            # Log the additional shutdown request
            echo "$(date '+%Y-%m-%d %H:%M:%S') $calling_module requested shutdown due to $trigger_reason ($trigger_value)" >> "${SHUTDOWN_GRACE_FILE}.requests"
            
            send_alert "warning" "⏳ Shutdown grace period active: ${remaining}s remaining (${calling_module}: $trigger_reason)"
            
            return 0  # Don't shutdown yet, grace period active
        else
            log "AUTOFIX: Shutdown grace period expired after ${elapsed}s"
        fi
    else
        # First shutdown request - start grace period
        echo "$current_time" > "$SHUTDOWN_GRACE_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') $calling_module initiated shutdown grace period due to $trigger_reason ($trigger_value)" > "${SHUTDOWN_GRACE_FILE}.requests"
        
        log "AUTOFIX: Starting ${grace_seconds}s shutdown grace period"
        log "AUTOFIX: Shutdown trigger: $trigger_reason ($trigger_value) from $calling_module"
        
        send_alert "warning" "⏳ Shutdown grace period started: ${grace_seconds}s for system to stabilize"
        
        # Desktop notification for grace period start
        if command -v notify-send >/dev/null 2>&1; then
            DISPLAY=:0 notify-send -u critical -t 15000 "⚠️ Shutdown Grace Period" \
                "System may shutdown soon!\nReason: $trigger_reason\nModule: $calling_module\nGrace: ${grace_seconds}s" 2>/dev/null &
        fi
        
        return 0  # Don't shutdown yet, just started grace period
    fi
    
    # Grace period has expired - proceed with shutdown
    log "AUTOFIX: Initiating system shutdown - grace period expired"
    
    # Show all the shutdown requests that led to this
    if [[ -f "${SHUTDOWN_GRACE_FILE}.requests" ]]; then
        log "AUTOFIX: Shutdown requests during grace period:"
        while IFS= read -r request_line; do
            log "AUTOFIX:   $request_line"
        done < "${SHUTDOWN_GRACE_FILE}.requests"
    fi
    
    send_alert "emergency" "🚨 SYSTEM SHUTDOWN: Grace period expired - multiple emergency requests"
    
    # Create emergency diagnostic dump
    create_emergency_dump "$trigger_reason" "$trigger_value" "$calling_module"
    
    # Broadcast shutdown warning to all users
    local shutdown_message="EMERGENCY: System shutdown initiated after grace period - Final trigger: $trigger_reason ($trigger_value) from $calling_module"
    echo "$shutdown_message" | wall 2>/dev/null || true
    
    # Desktop notification for imminent shutdown
    if command -v notify-send >/dev/null 2>&1; then
        DISPLAY=:0 notify-send -u critical -t 30000 "🚨 Emergency Shutdown" \
            "System shutting down NOW!\nReason: $trigger_reason\nValue: $trigger_value\nModule: $calling_module\nGrace Period: Expired" 2>/dev/null &
    fi
    
    # Clean up grace tracking files
    rm -f "$SHUTDOWN_GRACE_FILE" "${SHUTDOWN_GRACE_FILE}.requests"
    
    # Initiate shutdown with minimal delay since grace period already elapsed
    local shutdown_delay="${EMERGENCY_SHUTDOWN_DELAY:-1}"  # minutes
    log "AUTOFIX: Executing clean shutdown in $shutdown_delay minute(s)"
    
    /sbin/shutdown -h "+$shutdown_delay" "$shutdown_message" 2>/dev/null || \
    systemctl poweroff 2>/dev/null || \
    /sbin/poweroff 2>/dev/null || true
}

create_emergency_dump() {
    local trigger_reason="$1"
    local trigger_value="$2"
    local calling_module="$3"
    local dump_file="/var/log/emergency-dump-$(date +%Y%m%d-%H%M%S).log"
    
    log "Creating emergency diagnostic dump: $dump_file"
    
    {
        echo "EMERGENCY SYSTEM DIAGNOSTIC DUMP"
        echo "================================="
        echo "Timestamp: $(date)"
        echo "Trigger Reason: $trigger_reason"
        echo "Trigger Value: $trigger_value"
        echo "Calling Module: $calling_module"
        echo "Grace Period: Expired"
        echo ""
        
        # Show grace period history if available
        if [[ -f "${SHUTDOWN_GRACE_FILE}.requests" ]]; then
            echo "SHUTDOWN REQUESTS DURING GRACE PERIOD:"
            cat "${SHUTDOWN_GRACE_FILE}.requests"
            echo ""
        fi
        
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
        get_top_cpu_processes
        echo ""
        
        echo "TOP MEMORY PROCESSES:"
        get_top_memory_processes
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
        
    } > "$dump_file" 2>/dev/null || log "Failed to create diagnostic dump"
}

# Cleanup function for old grace files
cleanup_old_grace_files() {
    find "$GRACE_DIR" -name "shutdown_*" -mtime +1 -delete 2>/dev/null || true
}

# Clean up old files on startup
cleanup_old_grace_files

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trigger_reason="${1:-emergency}"
    trigger_value="${2:-unknown}"
    grace_seconds="${3:-120}"
    calling_module="${4:-direct}"
    emergency_shutdown "$trigger_reason" "$trigger_value" "$grace_seconds" "$calling_module"
fi