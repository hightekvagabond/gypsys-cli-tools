#!/bin/bash
# Network monitoring module

MODULE_NAME="network"
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
Network monitoring module

USAGE:
    ./monitor.sh [OPTIONS]

OPTIONS:
    --no-auto-fix       Disable automatic fix actions
    --start-time TIME   Set monitoring start time for analysis
    --end-time TIME     Set monitoring end time for analysis
    --status            Show detailed status information instead of monitoring
    --help              Show this help message

EXAMPLES:
    ./monitor.sh                                    # Normal monitoring with autofix
    ./monitor.sh --no-auto-fix                     # Monitor only, no autofix
    ./monitor.sh --start-time "1 hour ago"         # Analyze last hour
    ./monitor.sh --status --start-time "1 hour ago" # Show status for last hour
    ./monitor.sh --start-time "10:00" --end-time "11:00"  # Specific time range

EOH
}


check_status() {
    log "Checking network status..."
    
    # Check if we have network interfaces
    if ! command -v ip >/dev/null 2>&1; then
        log "Warning: ip command not available"
        return 0
    fi
    
    local active_interfaces
    active_interfaces=$(ip link show | grep -c "state UP" || echo "0")
    
    if [[ $active_interfaces -eq 0 ]]; then
        send_alert "warning" "🌐 Warning: No active network interfaces found"
        return 1
    fi
    
    # Check for network errors in logs
    local time_filter="--since '${DEFAULT_ANALYSIS_TIMESPAN:-1 hour ago}'"
    if [[ -n "$START_TIME" ]]; then
        time_filter="--since '$START_TIME'"
        if [[ -n "$END_TIME" ]]; then
            time_filter="$time_filter --until '$END_TIME'"
        fi
    fi
    
    local network_errors
    network_errors=$(eval "journalctl -k $time_filter --no-pager 2>/dev/null" | grep -c -i "network.*error\|ethernet.*timeout\|wifi.*failed" || echo "0")
    
    if [[ $network_errors -ge ${NETWORK_ERROR_CRITICAL:-15} ]]; then
        send_alert "critical" "🌐 CRITICAL: $network_errors network errors detected"
        return 1
    elif [[ $network_errors -ge ${NETWORK_ERROR_WARNING:-5} ]]; then
        send_alert "warning" "🌐 Warning: $network_errors network errors detected" 
        return 1
    fi
    
    log "Network status normal: $active_interfaces active interfaces, $network_errors errors"
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
