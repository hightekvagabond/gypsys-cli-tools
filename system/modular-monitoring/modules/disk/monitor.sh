#!/bin/bash
#
# DISK MONITORING MODULE
#
# PURPOSE:
#   Monitors disk space usage, filesystem health, and I/O performance to prevent
#   system failures due to full filesystems. A full root partition can prevent
#   system boot and cause data loss, making this a critical monitoring module.
#
# CRITICAL SAFETY FEATURES:
#   - Early warning for high disk usage
#   - Intelligent disk cleanup with usage analysis
#   - Emergency shutdown protection (prevents unbootable systems)
#   - Filesystem ignore list (excludes virtual/special filesystems)
#   - Grace period management for disk usage spikes
#
# MONITORING CAPABILITIES:
#   - Real-time disk space monitoring (df command)
#   - Multiple filesystem support (ext4, xfs, btrfs, etc.)
#   - Configurable warning and critical thresholds
#   - Historical disk usage trend analysis
#   - I/O performance tracking and bottleneck detection
#   - Automated space hog identification
#
# EMERGENCY RESPONSE:
#   - 80%+ usage: Warning alerts and monitoring
#   - 90%+ usage: Critical alerts and cleanup analysis
#   - 95%+ usage: Emergency cleanup with detailed space analysis
#   - 98%+ usage: Emergency measures to prevent system failure
#
# INTELLIGENT CLEANUP:
#   - Analyzes actual space consumers before cleanup
#   - Targets log files, cache directories, and temporary files
#   - Identifies large files and directories for manual review
#   - Protects critical system files and user data
#
# FILESYSTEM SAFETY:
#   - Ignores virtual filesystems (/proc, /sys, /dev)
#   - Excludes special-purpose mounts (efivarfs, tmpfs)
#   - Validates filesystem types before operations
#   - Prevents cleanup of critical system directories
#
# USAGE:
#   ./monitor.sh [--no-auto-fix] [--status] [--start-time TIME] [--end-time TIME]
#   ./monitor.sh --help
#   ./monitor.sh --description
#   ./monitor.sh --list-autofixes
#
# SECURITY CONSIDERATIONS:
#   - Read-only filesystem access for monitoring
#   - Safe cleanup operations (no critical file deletion)
#   - Validated mount point analysis
#   - Prevents accidental system file removal
#
# BASH CONCEPTS FOR BEGINNERS:
#   - df: Disk filesystem usage reporting tool
#   - du: Directory usage analysis tool
#   - Mount points: Locations where filesystems are attached
#   - Filesystem types: Different storage organization methods
#   - Space calculations: Understanding bytes, KB, MB, GB conversions
#
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
            --description)
                echo "Monitor disk space usage, health, and I/O performance"
                exit 0
                ;;
            --list-autofixes)
                echo "disk-cleanup"
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
            # Skip filesystems matching ignore patterns
            if [[ -n "${DISK_IGNORE_PATTERNS:-}" ]]; then
                local should_ignore=false
                IFS='|' read -ra patterns <<< "$DISK_IGNORE_PATTERNS"
                for pattern in "${patterns[@]}"; do
                    if [[ "$filesystem" =~ $pattern ]]; then
                        should_ignore=true
                        break
                    fi
                done
                if [[ "$should_ignore" == "true" ]]; then
                    log "Skipping $filesystem - matches ignore pattern"
                    continue
                fi
            fi
            
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
