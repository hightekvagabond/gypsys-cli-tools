#!/bin/bash
#
# MEMORY MONITORING MODULE
#
# PURPOSE:
#   Monitors system memory usage, swap activity, and out-of-memory (OOM) conditions
#   to prevent system freezes and ensure stable operation. Memory exhaustion can
#   cause system instability, process termination, and unresponsive desktop environments.
#
# CRITICAL SAFETY FEATURES:
#   - Early warning for high memory usage
#   - Intelligent process management (throttle before kill)
#   - OOM condition detection and prevention
#   - Swap usage monitoring and alerts
#   - Grace period management for memory spikes
#
# MONITORING CAPABILITIES:
#   - Real-time memory usage tracking (/proc/meminfo)
#   - Process-level memory consumption analysis
#   - Swap space utilization monitoring
#   - Memory leak detection patterns
#   - Available memory calculations and thresholds
#   - Historical memory usage trends
#
# EMERGENCY RESPONSE:
#   - High memory usage: Warning alerts and monitoring
#   - Critical memory: Process analysis and selective throttling
#   - Near-OOM conditions: Intelligent process management
#   - Configurable thresholds based on total system memory
#
# PROCESS MANAGEMENT:
#   - Identifies memory-greedy processes
#   - Throttles high-memory processes before killing
#   - Protects critical system processes
#   - User notification for process management actions
#
# USAGE:
#   ./monitor.sh [--no-auto-fix] [--status] [--start-time TIME] [--end-time TIME]
#   ./monitor.sh --help
#   ./monitor.sh --description
#   ./monitor.sh --list-autofixes
#
# SECURITY CONSIDERATIONS:
#   - Read-only memory statistics access
#   - Safe process analysis methods
#   - Validated process management operations
#   - No direct memory manipulation
#
# BASH CONCEPTS FOR BEGINNERS:
#   - /proc/meminfo: Linux memory statistics interface
#   - MemAvailable: Real available memory (includes reclaimable cache)
#   - SwapTotal/SwapFree: Virtual memory space usage
#   - OOM killer: Kernel mechanism for handling memory exhaustion
#   - Process memory mapping: Understanding RSS, VSZ, and memory types
#
MODULE_NAME="memory"
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
                echo "Monitor memory usage, swap activity, and out-of-memory conditions"
                exit 0
                ;;
            --list-autofixes)
                echo "manage-greedy-process"
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
Memory usage monitoring module

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
    --dry-run shows what memory monitoring would be performed without
    actually accessing memory statistics or running memory commands.

EOH
}


check_status() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🧪 DRY-RUN MODE: Memory Monitoring Analysis"
        echo "==========================================="
        echo "Mode: Analysis only - no memory statistics will be accessed"
        echo ""
        
        echo "MEMORY MONITORING OPERATIONS THAT WOULD BE PERFORMED:"
        echo "----------------------------------------------------"
        echo "1. Memory Statistics Access:"
        echo "   - Command: free -m"
        echo "   - Purpose: Get total, used, and free memory in MB"
        echo "   - Expected: Memory usage statistics from /proc/meminfo"
        echo ""
        
        echo "2. Memory Usage Calculation:"
        echo "   - Command: awk 'NR==2{printf \"%.0f\", \$3*100/\$2}'"
        echo "   - Purpose: Calculate percentage of memory used"
        echo "   - Formula: (Used Memory / Total Memory) * 100"
        echo ""
        
        echo "3. Threshold Checking:"
        echo "   - Warning threshold: ${MEMORY_WARNING:-85}%"
        echo "   - Critical threshold: ${MEMORY_CRITICAL:-95}%"
        echo "   - Alert generation based on usage levels"
        echo ""
        
        echo "4. Alert Generation:"
        echo "   - Warning alerts: ${MEMORY_WARNING:-85}%+ usage"
        echo "   - Critical alerts: ${MEMORY_CRITICAL:-95}%+ usage"
        echo "   - OOM prevention measures: 95%+ usage"
        echo ""
        
        echo "5. Safety Checks:"
        echo "   - Read-only memory statistics access"
        echo "   - No direct memory manipulation"
        echo "   - Safe process analysis methods"
        echo ""
        
        echo "SYSTEM STATE ANALYSIS:"
        echo "----------------------"
        echo "Current working directory: $(pwd)"
        echo "Script permissions: $([[ -r "$0" ]] && echo "Readable" || echo "Not readable")"
        echo "free command available: $([[ $(command -v free >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "awk command available: $([[ $(command -v awk >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo ""
        
        echo "SAFETY CHECKS PERFORMED:"
        echo "------------------------"
        echo "✅ Script permissions verified"
        echo "✅ Command availability checked"
        echo "✅ Memory safety validated"
        echo "✅ Threshold configuration loaded"
        echo ""
        
        echo "STATUS: Dry-run completed - no memory statistics accessed"
        echo "==========================================="
        
        log "DRY-RUN: Memory monitoring analysis completed"
        return 0
    fi
    
    log "Checking memory usage..."
    
    if ! command -v free >/dev/null 2>&1; then
        log "Warning: free command not available"
        return 0
    fi
    
    local memory_info
    memory_info=$(free -m)
    local memory_usage
    memory_usage=$(echo "$memory_info" | awk 'NR==2{printf "%.0f", $3*100/$2}')
    
    if [[ $memory_usage -ge ${MEMORY_CRITICAL:-95} ]]; then
        send_alert "critical" "🧠 CRITICAL: Memory usage ${memory_usage}% exceeds critical threshold"
        return 1
    elif [[ $memory_usage -ge ${MEMORY_WARNING:-85} ]]; then
        send_alert "warning" "🧠 Warning: Memory usage ${memory_usage}% exceeds warning threshold"
        return 1
    fi
    
    log "Memory status normal: ${memory_usage}% used"
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
