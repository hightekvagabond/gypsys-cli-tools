#!/bin/bash
# Common functions shared across all monitoring modules

set -euo pipefail

# Load configuration
MODULAR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$MODULAR_DIR/config"
FRAMEWORK_DIR="$MODULAR_DIR/framework"
STATE_DIR="/var/tmp/modular-monitor-state"
LOG_DIR="$MODULAR_DIR/logs"

# Ensure directories exist
mkdir -p "$STATE_DIR" "$LOG_DIR"

# Load configuration files in order (framework config first, then module-specific)
if [[ -f "$FRAMEWORK_DIR/monitor-config.sh" ]]; then
    MONITOR_ROOT="$MODULAR_DIR"
    source "$FRAMEWORK_DIR/monitor-config.sh"
fi

# Legacy config support
if [[ -f "$CONFIG_DIR/thresholds.conf" ]]; then
    source "$CONFIG_DIR/thresholds.conf"
fi

# Logging functions
log() {
    local module="${MODULE_NAME:-monitor}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$module] $*" | logger -t "modular-monitor" || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$module] $*"
}

error() {
    log "ERROR: $*" >&2
}

# Alert functions
send_alert() {
    local level="$1"
    local message="$2"
    local module="${MODULE_NAME:-monitor}"
    
    if ! should_alert "$level" "$module"; then
        return 0
    fi
    
    # Desktop notification
    if command -v notify-send >/dev/null 2>&1; then
        local urgency="normal"
        local icon="dialog-information"
        case "$level" in
            critical|emergency)
                urgency="critical"
                icon="dialog-error"
                ;;
            warning)
                urgency="normal"
                icon="dialog-warning"
                ;;
        esac
        
        DISPLAY=:0 notify-send -u "$urgency" -i "$icon" -t 10000 \
            "🛡️ Modular Monitor: $module" "$message" 2>/dev/null &
    fi
    
    # Log alert
    log "ALERT[$level]: $message"
    
    # Record alert timestamp
    record_alert "$level" "$module"
}

# Alert cooldown management
should_alert() {
    local level="$1"
    local module="$2"
    local cooldown_file="$STATE_DIR/${module}_${level}_last_alert"
    local current_time=$(date +%s)
    
    # Default cooldowns (in seconds)
    local cooldown=300  # 5 minutes default
    case "$level" in
        critical|emergency) cooldown=180 ;;  # 3 minutes
        warning) cooldown=600 ;;             # 10 minutes
    esac
    
    if [[ -f "$cooldown_file" ]]; then
        local last_alert
        last_alert=$(cat "$cooldown_file" 2>/dev/null || echo "0")
        local time_diff=$((current_time - last_alert))
        if [[ $time_diff -lt $cooldown ]]; then
            return 1  # Still in cooldown
        fi
    fi
    
    return 0  # Can alert
}

record_alert() {
    local level="$1"
    local module="$2"
    local cooldown_file="$STATE_DIR/${module}_${level}_last_alert"
    date +%s > "$cooldown_file"
}

# Process utilities
get_top_cpu_processes() {
    ps -eo pid,pcpu,cmd --sort=-pcpu --no-headers | head -10
}

get_top_memory_processes() {
    ps -eo pid,pmem,cmd --sort=-pmem --no-headers | head -10
}

is_system_critical_process() {
    local pid="$1"
    local cmd="$2"
    
    # System critical patterns
    local critical_patterns=(
        "^\[.*\]$"                    # Kernel threads
        "^(systemd|kthreadd|ksoftirqd|migration|rcu_|watchdog)"
        "^(dbus|networkd|resolved|login)"
        "^(Xorg|gdm|lightdm|sddm)"
        "^(pipewire|pulseaudio|alsa)"
        "^ssh"
    )
    
    for pattern in "${critical_patterns[@]}"; do
        if [[ "$cmd" =~ $pattern ]]; then
            return 0  # Is critical
        fi
    done
    
    return 1  # Not critical
}

# Temperature utilities
get_cpu_package_temp() {
    # Try sensors first (most reliable)
    if command -v sensors >/dev/null 2>&1; then
        local temp
        temp=$(sensors 2>/dev/null | grep -E "Package id 0|Tctl" | head -1 | grep -oE '[0-9]+\.[0-9]+°C' | head -1 | sed 's/°C//')
        if [[ -n "$temp" ]]; then
            echo "$temp"
            return 0
        fi
    fi
    
    # Fallback to thermal zones
    local max_temp=0
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        if [[ -f "$zone" ]]; then
            local temp_millic
            temp_millic=$(cat "$zone" 2>/dev/null || echo "0")
            local temp_c=$((temp_millic / 1000))
            if [[ $temp_c -gt $max_temp && $temp_c -lt 200 ]]; then
                max_temp=$temp_c
            fi
        fi
    done
    
    if [[ $max_temp -gt 0 ]]; then
        echo "$max_temp"
        return 0
    fi
    
    echo "unknown"
    return 1
}

# Module validation
validate_module() {
    local module_name="$1"
    
    # Check required variables
    if [[ -z "${MODULE_NAME:-}" ]]; then
        error "Module must set MODULE_NAME variable"
        return 1
    fi
    
    # Check required functions
    if ! declare -f check_status >/dev/null 2>&1; then
        error "Module must implement check_status() function"
        return 1
    fi
    
    return 0
}

# System utilities
get_uptime_seconds() {
    awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 3600
}

# Framework initialization  
init_framework() {
    local module_name="$1"
    MODULE_NAME="$module_name"
    LOG_TAG="$module_name"
    mkdir -p "$STATE_DIR/$module_name"
    log "Framework initialized for module: $module_name"
}

# Export functions for modules
export -f log error send_alert should_alert record_alert
export -f get_top_cpu_processes get_top_memory_processes is_system_critical_process
export -f get_cpu_package_temp get_uptime_seconds init_framework validate_module
