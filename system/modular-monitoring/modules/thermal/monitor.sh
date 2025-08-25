#!/bin/bash
# Thermal monitoring module - restructured version

MODULE_NAME="thermal"
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
                echo "Monitor CPU temperature, thermal throttling, and overheating conditions"
                exit 0
                ;;
            --list-autofixes)
                list_autofix_scripts
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
    cat << 'EOF'
Thermal Monitor Module

USAGE:
    ./monitor.sh [OPTIONS]

OPTIONS:
    --no-auto-fix       Disable automatic fix actions
    --start-time TIME   Set monitoring start time for analysis
    --end-time TIME     Set monitoring end time for analysis
    --status            Show detailed status information instead of monitoring
    --list-autofixes    List available autofix scripts and their triggers
    --help              Show this help message

EXAMPLES:
    ./monitor.sh                                    # Normal monitoring with autofix
    ./monitor.sh --no-auto-fix                     # Monitor only, no autofix
    ./monitor.sh --start-time "1 hour ago"         # Analyze last hour
    ./monitor.sh --status --start-time "1 hour ago" # Show status for last hour
    ./monitor.sh --start-time "10:00" --end-time "11:00"  # Specific time range

EOF
}

# Thermal-specific functions
check_status() {
    local temp
    temp=$(get_cpu_package_temp)
    
    if [[ "$temp" == "unknown" ]]; then
        log "Warning: Cannot read CPU temperature"
        return 1
    fi
    
    local temp_int
    temp_int=$(echo "$temp" | cut -d. -f1)
    
    # Check thresholds
    if [[ $temp_int -ge ${TEMP_EMERGENCY:-95} ]]; then
        if [[ "${AUTO_FIX_ENABLED:-true}" == "true" && "${ENABLE_THERMAL_AUTOFIX:-true}" == "true" ]]; then
            handle_emergency_thermal "$temp"
        else
            send_alert "emergency" "🔥 Emergency CPU temperature: ${temp}°C (autofix disabled)"
        fi
        return 1
    elif [[ $temp_int -ge ${TEMP_CRITICAL:-90} ]]; then
        send_alert "critical" "🔥 Critical CPU temperature: ${temp}°C (threshold: ${TEMP_CRITICAL}°C)"
        return 1
    elif [[ $temp_int -ge ${TEMP_WARNING:-85} ]]; then
        send_alert "warning" "🌡️ High CPU temperature: ${temp}°C (threshold: ${TEMP_WARNING}°C)"
        return 1
    fi
    
    log "Temperature normal: ${temp}°C"
    return 0
}

handle_emergency_thermal() {
    local temp="$1"
    log "EMERGENCY: Thermal protection activated at ${temp}°C"
    
    # Try emergency process kill first (using global autofix with grace period)
    local global_autofix_dir="$(dirname "$SCRIPT_DIR/../..")/autofix"
    if [[ -x "$global_autofix_dir/emergency-process-kill.sh" ]]; then
        # Pass grace period to autofix script
        local grace_seconds=${THERMAL_SPIKE_GRACE_SECONDS:-45}
        if "$global_autofix_dir/emergency-process-kill.sh" "thermal" "$temp" "$grace_seconds"; then
            log "EMERGENCY: Process kill request submitted (grace period: ${grace_seconds}s)"
            return 0
        fi
    fi
    
    # If process kill failed or not available, try shutdown (using global autofix with grace period)
    if [[ -x "$global_autofix_dir/emergency-shutdown.sh" ]] && [[ "${ENABLE_EMERGENCY_SHUTDOWN:-true}" == "true" ]]; then
        local shutdown_grace_seconds=${THERMAL_SHUTDOWN_GRACE_SECONDS:-120}
        log "EMERGENCY: No suitable processes - requesting shutdown (grace period: ${shutdown_grace_seconds}s)"
        "$global_autofix_dir/emergency-shutdown.sh" "thermal" "$temp" "$shutdown_grace_seconds"
        return 1
    else
        log "EMERGENCY: System-level thermal issue - no autofix available"
        return 1
    fi
}

# Make autofix scripts executable
make_autofix_executable() {
    if [[ -d "$SCRIPT_DIR/autofix" ]]; then
        chmod +x "$SCRIPT_DIR/autofix"/*.sh 2>/dev/null || true
    fi
}

# Initialize
init_framework "$MODULE_NAME"
make_autofix_executable

# Parse arguments
parse_args "$@"

# Module validation
validate_module "$MODULE_NAME"

# Check if required hardware exists
if ! check_hardware_exists "$MODULE_NAME"; then
    error "Required thermal monitoring hardware not detected on this system"
    log "Skipping thermal monitoring - no thermal sensors found"
    exit 0
fi

show_status() {
    local start_time="${START_TIME:-${DEFAULT_STATUS_START_TIME:-1 hour ago}}"
    local end_time="${END_TIME:-${DEFAULT_STATUS_END_TIME:-now}}"
    
    echo "=== THERMAL MODULE STATUS ==="
    echo "Time range: $start_time to $end_time"
    echo ""
    
    # Current temperature
    local current_temp
    current_temp=$(get_cpu_package_temp)
    if [[ "$current_temp" != "unknown" ]]; then
        local temp_int
        temp_int=$(echo "$current_temp" | cut -d. -f1)
        if [[ $temp_int -lt 70 ]]; then
            echo "🌡️  Current CPU Temperature: ${current_temp}°C (NORMAL)"
        elif [[ $temp_int -lt 85 ]]; then
            echo "🌡️  Current CPU Temperature: ${current_temp}°C (ELEVATED)"
        else
            echo "🌡️  Current CPU Temperature: ${current_temp}°C (HIGH)"
        fi
    else
        echo "🌡️  Current CPU Temperature: Unknown"
    fi
    echo ""
    
    # Check historical alerts if not real-time
    if [[ "$start_time" != "now" ]]; then
        local thermal_alerts
        thermal_alerts=$(journalctl -t modular-monitor --since "$start_time" --until "$end_time" --no-pager 2>/dev/null | grep -i "thermal.*alert\|temperature.*critical\|temperature.*emergency" || echo "")
        
        if [[ -n "$thermal_alerts" ]]; then
            echo "🚨 THERMAL ALERTS IN PERIOD:"
            echo "$thermal_alerts" | while IFS= read -r alert; do
                local timestamp=$(echo "$alert" | awk '{print $1, $2, $3}')
                local message=$(echo "$alert" | sed 's/^.*modular-monitor.*: //')
                echo "  [$timestamp] $message"
            done
        else
            echo "✅ No thermal alerts in specified period"
        fi
    fi
    echo ""
    
    # Show thermal configuration
    echo "📋 THERMAL CONFIGURATION:"
    echo "  Warning threshold: ${TEMP_WARNING:-85}°C"
    echo "  Critical threshold: ${TEMP_CRITICAL:-90}°C"
    echo "  Emergency threshold: ${TEMP_EMERGENCY:-95}°C"
    echo "  Autofix enabled: ${ENABLE_THERMAL_AUTOFIX:-true}"
    echo "  Emergency kill enabled: ${ENABLE_EMERGENCY_KILL:-true}"
    echo "  Emergency shutdown enabled: ${ENABLE_EMERGENCY_SHUTDOWN:-true}"
    echo ""
    
    # Show recent emergency actions
    local emergency_actions
    emergency_actions=$(journalctl -t modular-monitor --since "$start_time" --until "$end_time" --no-pager 2>/dev/null | grep -i "emergency.*killed\|emergency.*shutdown" || echo "")
    
    if [[ -n "$emergency_actions" ]]; then
        echo "🚨 EMERGENCY ACTIONS IN PERIOD:"
        echo "$emergency_actions" | while IFS= read -r action; do
            local timestamp=$(echo "$action" | awk '{print $1, $2, $3}')
            local message=$(echo "$action" | sed 's/^.*modular-monitor.*: //')
            echo "  [$timestamp] $message"
        done
    else
        echo "✅ No emergency actions taken in specified period"
    fi
}

# If script is run directly, run appropriate function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$STATUS_MODE" == "true" ]]; then
        show_status
    else
        check_status
    fi
fi
