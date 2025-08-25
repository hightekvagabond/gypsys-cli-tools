#!/bin/bash
# Disk space and health monitoring module

MODULE_NAME="disk"
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
Disk space and health monitoring module

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
    local issues_found=0
    
    log "Checking disk space and health..."
    
    # Check disk space for all mounted filesystems
    while read -r filesystem; do
        if [[ -n "$filesystem" && "$filesystem" != "tmpfs" && "$filesystem" != "devtmpfs" ]]; then
            local disk_usage
            disk_usage=$(df "$filesystem" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
            
            if [[ $disk_usage -ge ${DISK_CRITICAL_THRESHOLD:-90} ]]; then
                send_alert "critical" "💾 CRITICAL: Disk usage ${disk_usage}% on $filesystem exceeds critical threshold"
                issues_found=1
            elif [[ $disk_usage -ge ${DISK_WARNING_THRESHOLD:-80} ]]; then
                send_alert "warning" "💾 Warning: Disk usage ${disk_usage}% on $filesystem exceeds warning threshold"
                issues_found=1
            fi
        fi
    done < <(df -h | awk 'NR>1 {print $6}' | grep -E '^/' | sort -u)
    
    if [[ $issues_found -eq 0 ]]; then
        log "Disk status normal"
    fi
    
    return $issues_found
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
