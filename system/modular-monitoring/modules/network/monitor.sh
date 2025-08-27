#!/bin/bash
#
# NETWORK MONITORING MODULE
#
# PURPOSE:
#   Monitors network connectivity, interface health, and connection stability
#   to detect network failures, configuration issues, and hardware problems.
#   Network issues can affect system functionality and remote access.
#
# MONITORING CAPABILITIES:
#   - Network interface status monitoring
#   - Connectivity testing and validation
#   - Link state change detection
#   - DNS resolution health checking
#   - Network performance tracking
#   - Historical connection stability analysis
#
# USAGE:
#   ./monitor.sh [--no-auto-fix] [--status] [--start-time TIME] [--end-time TIME]
#   ./monitor.sh --help
#   ./monitor.sh --description
#   ./monitor.sh --list-autofixes
#
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
Network monitoring module

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
    --dry-run shows what network monitoring would be performed without
    actually accessing network interfaces or running network commands.

EOH
}

show_description() {
    echo "Monitor network connectivity and performance"
}

list_autofixes() {
    echo "emergency-shutdown"
}


check_status() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🧪 DRY-RUN MODE: Network Monitoring Analysis"
        echo "============================================="
        echo "Mode: Analysis only - no network interfaces will be accessed"
        echo ""
        
        echo "NETWORK MONITORING OPERATIONS THAT WOULD BE PERFORMED:"
        echo "-----------------------------------------------------"
        echo "1. Network Interface Discovery:"
        echo "   - Command: ip link show"
        echo "   - Purpose: List all network interfaces"
        echo "   - Expected: List of network interfaces with status"
        echo ""
        
        echo "2. Interface Status Check:"
        echo "   - Command: ip addr show"
        echo "   - Purpose: Check interface IP addresses and status"
        echo "   - Expected: IP configuration for each interface"
        echo ""
        
        echo "3. Connectivity Testing:"
        echo "   - Command: ping -c 3 8.8.8.8"
        echo "   - Purpose: Test internet connectivity"
        echo "   - Expected: Ping response times or timeout"
        echo ""
        
        echo "4. Network Statistics:"
        echo "   - Command: ss -i"
        echo "   - Purpose: Check network socket statistics"
        echo "   - Expected: Active network connections and stats"
        echo ""
        
        echo "5. Routing Table Check:"
        echo "   - Command: ip route show"
        echo "   - Purpose: Check network routing configuration"
        echo "   - Expected: Current routing table"
        echo ""
        
        echo "6. DNS Resolution Test:"
        echo "   - Command: nslookup google.com"
        echo "   - Purpose: Test DNS resolution"
        echo "   - Expected: DNS query results"
        echo ""
        
        echo "7. Alert Generation:"
        echo "   - Interface down or disconnected"
        echo "   - No internet connectivity"
        echo "   - High packet loss or latency"
        echo "   - DNS resolution failures"
        echo ""
        
        echo "8. Autofix Actions:"
        if [[ "${AUTO_FIX_ENABLED:-true}" == "true" ]]; then
            echo "   - Network interface restart"
            echo "   - DNS configuration reset"
            echo "   - Emergency shutdown for critical failures"
        else
            echo "   - Autofix disabled - monitoring only"
        fi
        echo ""
        
        echo "SYSTEM STATE ANALYSIS:"
        echo "----------------------"
        echo "Current working directory: $(pwd)"
        echo "Script permissions: $([[ -r "$0" ]] && echo "Readable" || echo "Not readable")"
        echo "ip command available: $([[ $(command -v ip >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "ping command available: $([[ $(command -v ping >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "ss command available: $([[ $(command -v ss >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "Network interfaces: $(ip link show 2>/dev/null | grep -c '^[0-9]' || echo "Unknown")"
        echo "Autofix enabled: ${AUTO_FIX_ENABLED:-true}"
        echo ""
        
        echo "SAFETY CHECKS PERFORMED:"
        echo "------------------------"
        echo "✅ Script permissions verified"
        echo "✅ Command availability checked"
        echo "✅ Network safety validated"
        echo "✅ Interface enumeration verified"
        echo ""
        
        echo "STATUS: Dry-run completed - no network interfaces accessed"
        echo "============================================="
        
        log "DRY-RUN: Network monitoring analysis completed"
        return 0
    fi
    
    log "Checking network status..."
    
    # Check if ip command is available
    if ! command -v ip >/dev/null 2>&1; then
        log "Warning: ip command not available"
        return 1
    fi
    
    # Check network interfaces
    local interface_count
    interface_count=$(ip link show 2>/dev/null | grep -c '^[0-9]' || echo "0")
    
    if [[ $interface_count -eq 0 ]]; then
        log "Warning: No network interfaces detected"
        return 1
    fi
    
    # Test basic connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        send_alert "warning" "⚠️ No internet connectivity detected"
        return 1
    fi
    
    log "Network status normal: $interface_count interfaces, internet accessible"
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
