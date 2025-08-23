#!/bin/bash

# Monitor Framework - Extracted from working debug-watchdogs scripts
# Common functions used across all monitoring modules

set -euo pipefail

# Framework version
FRAMEWORK_VERSION="1.0.0"

# Get the monitoring suite root directory
MONITOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load configuration if available
if [[ -f "$MONITOR_ROOT/framework/monitor-config.sh" ]]; then
    source "$MONITOR_ROOT/framework/monitor-config.sh"
fi

# Default directories and settings (from critical-monitor.sh)
STATE_DIR="${STATE_DIR:-/var/tmp/modular-monitor-state}"
LOG_TAG="${LOG_TAG:-modular-monitor}"

# Temperature thresholds (from critical-monitor.sh - these WORK!)
TEMP_WARNING=${TEMP_WARNING:-85}
TEMP_CRITICAL=${TEMP_CRITICAL:-90}
TEMP_EMERGENCY=${TEMP_EMERGENCY:-95}

# USB thresholds (from critical-monitor.sh)
USB_RESET_WARNING=${USB_RESET_WARNING:-10}
USB_RESET_CRITICAL=${USB_RESET_CRITICAL:-20}

# Memory thresholds (from critical-monitor.sh)
MEMORY_WARNING=${MEMORY_WARNING:-90}
MEMORY_CRITICAL=${MEMORY_CRITICAL:-95}

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# ========================================
# LOGGING FUNCTIONS (from critical-monitor.sh - PROVEN)
# ========================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LOG_TAG] $*" | logger -t "$LOG_TAG" || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LOG_TAG] $*"
}

error() {
    log "ERROR: $*" >&2
}

# ========================================
# ALERTING FUNCTIONS (from critical-monitor.sh - PROVEN)
# ========================================

send_alert() {
    local level="$1"
    local message="$2"
    
    log "ALERT ($level): $message"
    
    # Send desktop notification (PROVEN TO WORK)
    notify-send -u "$level" "Monitor Alert: $message" 2>/dev/null || true
    
    # Log to syslog with appropriate priority
    case $level in
        critical)
            logger -p user.crit -t "$LOG_TAG" "CRITICAL: $message" || true
            ;;
        normal)
            logger -p user.notice -t "$LOG_TAG" "WARNING: $message" || true
            ;;
    esac
}

# ========================================
# STATE MANAGEMENT (from critical-monitor.sh - PROVEN)
# ========================================

should_alert() {
    local alert_type="$1"
    local cooldown_minutes="$2"
    local state_file="$STATE_DIR/last_${alert_type}_alert"
    
    if [[ ! -f "$state_file" ]]; then
        return 0  # First time, send alert
    fi
    
    local last_alert
    last_alert=$(cat "$state_file" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    local cooldown_seconds=$((cooldown_minutes * 60))
    
    if [[ $((now - last_alert)) -gt $cooldown_seconds ]]; then
        return 0  # Cooldown expired, send alert
    fi
    
    return 1  # Still in cooldown
}

record_alert() {
    local alert_type="$1"
    local state_file="$STATE_DIR/last_${alert_type}_alert"
    date +%s > "$state_file"
}

# ========================================
# SYSTEM UTILITIES (from critical-monitor.sh - PROVEN)
# ========================================

is_system_critical_process() {
    local pid="$1"
    local cmd="$2"
    
    # Check if it's a kernel thread
    if [[ "$cmd" =~ ^\[.*\]$ ]]; then
        return 0  # Critical (kernel thread)
    fi
    
    # Check for essential system processes
    if [[ "$cmd" =~ (systemd|init|kthread|migration|rcu_|watchdog|ksoftirq|systemd-|dbus|NetworkManager|sddm|plasmashell|kwin) ]]; then
        return 0  # Critical
    fi
    
    # Check if it's PID 1 or very low PID (likely system process)
    if [[ "$pid" -le 10 ]]; then
        return 0  # Critical
    fi
    
    return 1  # Not critical, can be killed
}

get_uptime_seconds() {
    awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 3600
}

# ========================================
# MODULE INITIALIZATION
# ========================================

init_framework() {
    local module_name="$1"
    LOG_TAG="$module_name"
    mkdir -p "$STATE_DIR/$module_name"
    log "Framework initialized for module: $module_name"
}

# Export functions for modules to use
export -f log error send_alert should_alert record_alert is_system_critical_process get_uptime_seconds
