#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#  debug-watch.sh – Proactive system health monitoring watchdog
#
#  DEVELOPER NOTES
#  ---------------
#  Comprehensive system monitoring that complements i915-watch.sh.
#  Focuses on broader system health: performance, hardware errors,
#  network issues, service failures, and resource exhaustion.
#
#  ARCHITECTURE
#  ------------
#  - Multi-tier monitoring: performance, hardware, services, resources
#  - Escalation levels with automatic fixes for common issues
#  - Cooldown periods prevent fix loops
#  - State tracking in /var/tmp/debug-watch-state
#  - Integration with debug-fix-all.sh for repairs
#
#  MONITORING AREAS
#  ----------------
#  - System performance degradation
#  - Hardware errors (PCIe, NVMe, USB, network)
#  - Service failures and network connectivity
#  - Resource exhaustion (disk, memory, CPU)
#  - Post-crash indicators and system instability
#
#  DEPLOYMENT
#  ----------
#  Designed for cron execution (every 15-30 minutes recommended).
#  Use debug-install.sh for automated deployment.
#
# -----------------------------------------------------------------------------

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX_SCRIPT="$SCRIPT_DIR/debug-fix-all.sh"
STATE_FILE="/var/tmp/debug-watch-state"

# Thresholds for escalation
DISK_USAGE_WARN=80      # Warn when disk usage exceeds this percentage
DISK_USAGE_CRITICAL=90  # Critical alert for disk usage
MEMORY_AVAILABLE_WARN=20 # Warn when available memory below this percentage
MEMORY_AVAILABLE_CRITICAL=10 # Critical when available memory below this
FAILED_SERVICES_WARN=1   # Warn when this many services are failed
CPU_LOAD_WARN=80        # Warn when 1-minute load average exceeds this percentage of CPU count

# Cooldown periods (in hours) to prevent fix loops
NETWORK_FIX_COOLDOWN=1  # Wait 1 hour before trying network fix again
SERVICE_FIX_COOLDOWN=2  # Wait 2 hours before trying service fix again
CLEANUP_COOLDOWN=24     # Wait 24 hours before running cleanup again

# Comprehensive pre-shutdown diagnostic dump for future investigation
create_emergency_diagnostic_dump() {
    local temp="$1"
    local source_script="${2:-debug-watch}"
    local dump_file="/var/log/emergency-thermal-dump-${source_script}-$(date +%Y%m%d-%H%M%S).log"
    
    log "EMERGENCY: Creating diagnostic dump at $dump_file"
    
    {
        echo "=== EMERGENCY THERMAL DIAGNOSTIC DUMP ==="
        echo "Source: $source_script"
        echo "Timestamp: $(date)"
        echo "Trigger Temperature: ${temp}°C"
        echo "Emergency Threshold: 80°C"
        echo ""
        
        echo "=== CURRENT TEMPERATURE READINGS ==="
        sensors 2>/dev/null || echo "sensors command failed"
        echo ""
        
        echo "=== CPU FREQUENCY AND THROTTLING ==="
        cat /proc/cpuinfo | grep "cpu MHz" | head -6 2>/dev/null || echo "CPU freq check failed"
        echo ""
        if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
            echo "CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'unknown')"
        fi
        echo ""
        
        echo "=== TOP CPU PROCESSES (DETAILED) ==="
        ps aux --sort=-%cpu --no-headers | head -15 2>/dev/null || echo "Process list failed"
        echo ""
        
        echo "=== TOP MEMORY PROCESSES ==="
        ps aux --sort=-%mem --no-headers | head -10 2>/dev/null || echo "Memory process list failed"
        echo ""
        
        echo "=== SYSTEM LOAD ==="
        uptime 2>/dev/null || echo "uptime failed"
        echo ""
        
        echo "=== MEMORY USAGE ==="
        free -h 2>/dev/null || echo "free command failed"
        echo ""
        
        echo "=== DISK USAGE ==="
        df -h 2>/dev/null || echo "df command failed"
        echo ""
        
        echo "=== RECENT THERMAL EVENTS (Last 3 hours) ==="
        journalctl --since "3 hours ago" --no-pager 2>/dev/null | grep -E "(thermal|temperature|100.*°C|95.*°C|90.*°C|80.*°C|emergency|critical-monitor|debug-watch)" | tail -25 || echo "Journal thermal check failed"
        echo ""
        
        echo "=== RECENT HARDWARE ERRORS (Last 3 hours) ==="
        journalctl -k --since "3 hours ago" --no-pager 2>/dev/null | grep -E "(error|fail|critical|thermal|USB.*disconnect|PCIe|NVMe)" | tail -20 || echo "Hardware error check failed"
        echo ""
        
        echo "=== USB RESETS AND HARDWARE ISSUES ==="
        journalctl -b --no-pager 2>/dev/null | grep -E "(USB.*reset|uas_eh|PCIe.*error|nvme.*error)" | tail -15 || echo "USB/Hardware reset check failed"
        echo ""
        
        echo "=== SYSTEMD FAILED SERVICES ==="
        systemctl --failed --no-pager 2>/dev/null || echo "Failed services check failed"
        echo ""
        
        echo "=== NETWORK STATUS ==="
        ip link show 2>/dev/null | grep -E "(state|mtu)" || echo "Network status check failed"
        nmcli device status 2>/dev/null || echo "nmcli device status failed"
        echo ""
        
        echo "=== DMESG RECENT ERRORS ==="
        dmesg -T --level=err,crit,alert,emerg 2>/dev/null | tail -15 || echo "dmesg check failed"
        echo ""
        
        echo "=== LSCPU OUTPUT ==="
        lscpu 2>/dev/null | grep -E "(Model name|CPU MHz|Thread|Core|Socket)" || echo "lscpu failed"
        echo ""
        
        echo "=== ACPI THERMAL INFO ==="
        if [[ -d /sys/class/thermal ]]; then
            for zone in /sys/class/thermal/thermal_zone*; do
                if [[ -f "$zone/type" && -f "$zone/temp" ]]; then
                    local zone_type=$(cat "$zone/type" 2>/dev/null || echo "unknown")
                    local zone_temp=$(cat "$zone/temp" 2>/dev/null || echo "unknown")
                    if [[ "$zone_temp" != "unknown" && "$zone_temp" =~ ^[0-9]+$ ]]; then
                        zone_temp=$((zone_temp / 1000))°C
                    fi
                    echo "Thermal Zone: $zone_type = $zone_temp"
                fi
            done
        else
            echo "No thermal zones found"
        fi
        echo ""
        
        echo "=== RECENT REBOOT COUNT ==="
        local boot_count=$(journalctl --list-boots --no-pager 2>/dev/null | wc -l || echo "unknown")
        echo "Boot sessions in journal: $boot_count"
        echo ""
        
        echo "=== SUMMARY ==="
        echo "This diagnostic dump was created automatically by $source_script"
        echo "before emergency thermal shutdown at ${temp}°C (threshold: 80°C)"
        echo "Use this information to investigate the root cause of thermal issues."
        echo "Check /var/log/emergency-thermal-dump-*.log for all dumps."
        echo ""
        echo "=== END DIAGNOSTIC DUMP ==="
        
    } > "$dump_file" 2>&1
    
    # Make sure the file is readable
    chmod 644 "$dump_file" 2>/dev/null || true
    
    log "EMERGENCY: Diagnostic dump completed: $dump_file"
    
    # Also log a summary to syslog for easy reference
    log "DIAGNOSTIC SUMMARY: Source=$source_script, Temp=${temp}°C, CPU Load=$(uptime | grep -oE 'load average: [0-9]+\.[0-9]+' | awk '{print $3}' || echo 'unknown'), Top Process=$(ps aux --sort=-%cpu --no-headers | head -1 | awk '{print $11}' || echo 'unknown')"
}

# Logging function
log() {
    echo "[debug-watch] $*"
    logger -t "debug-watch" "$*"
}

# Check if we're in a cooldown period for a specific fix type
is_in_cooldown() {
    local fix_type="$1"
    local cooldown_hours="$2"
    local state_key="last_${fix_type}_fix"
    
    if [[ ! -f "$STATE_FILE" ]]; then
        return 1  # No state file = no cooldown
    fi
    
    local last_fix_time
    last_fix_time=$(grep "^$state_key=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2 || echo "0")
    
    local current_time
    current_time=$(date +%s)
    
    local cooldown_seconds=$((cooldown_hours * 3600))
    local time_since_fix=$((current_time - last_fix_time))
    
    if [[ $time_since_fix -lt $cooldown_seconds ]]; then
        return 0  # Still in cooldown
    else
        return 1  # Cooldown expired
    fi
}

# Record that we performed a fix
record_fix() {
    local fix_type="$1"
    local state_key="last_${fix_type}_fix"
    local current_time
    current_time=$(date +%s)
    
    # Create state file if it doesn't exist
    touch "$STATE_FILE"
    
    # Update or add the fix timestamp
    if grep -q "^$state_key=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s/^$state_key=.*/$state_key=$current_time/" "$STATE_FILE"
    else
        echo "$state_key=$current_time" >> "$STATE_FILE"
    fi
}

# Check if fix script exists and is executable
check_fix_script() {
    if [[ ! -x "$FIX_SCRIPT" ]]; then
        log "WARNING: Fix script not found or not executable: $FIX_SCRIPT"
        return 1
    fi
    return 0
}

# Check system performance indicators
check_performance() {
    local issues=0
    
    # CPU load check
    local cpu_count
    cpu_count=$(nproc)
    local load_1min
    load_1min=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
    local load_percentage
    load_percentage=$(echo "$load_1min * 100 / $cpu_count" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
    
    if [[ $load_percentage -gt $CPU_LOAD_WARN ]]; then
        log "WARNING: High CPU load: ${load_percentage}% (${load_1min} load average)"
        issues=1
    fi
    
    # Memory pressure check
    local mem_available
    mem_available=$(free | awk 'NR==2 {printf "%.0f", $7/$2*100}')
    if [[ $mem_available -lt $MEMORY_AVAILABLE_CRITICAL ]]; then
        log "CRITICAL: Low memory: only ${mem_available}% available"
        issues=1
    elif [[ $mem_available -lt $MEMORY_AVAILABLE_WARN ]]; then
        log "WARNING: Low memory: only ${mem_available}% available"
        issues=1
    fi
    
    # Disk space check
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt $DISK_USAGE_CRITICAL ]]; then
        log "CRITICAL: Disk space: ${disk_usage}% used"
        issues=1
    elif [[ $disk_usage -gt $DISK_USAGE_WARN ]]; then
        log "WARNING: Disk space: ${disk_usage}% used"
        issues=1
    fi
    
    return $issues
}

# Check for hardware errors (excluding i915 - handled by i915-watch)
check_hardware_errors() {
    local issues=0
    local error_count
    
    # PCIe/AER errors
    error_count=$(journalctl -b --since "1 hour ago" 2>/dev/null | grep -icE 'pcie.*error|aer.*error|BadTLP|BadDLLP' 2>/dev/null || echo "0")
    error_count=${error_count//[^0-9]/}  # Remove any non-numeric characters
    error_count=${error_count:-0}        # Default to 0 if empty
    if [[ $error_count -gt 0 ]]; then
        log "WARNING: $error_count PCIe/AER errors in last hour"
        issues=1
    fi
    
    # NVMe/storage errors
    error_count=$(journalctl -k -b --since "1 hour ago" 2>/dev/null | grep -icE 'nvme.*(error|timeout|reset)|ata.*error' 2>/dev/null || echo "0")
    error_count=${error_count//[^0-9]/}  # Remove any non-numeric characters
    error_count=${error_count:-0}        # Default to 0 if empty
    if [[ $error_count -gt 0 ]]; then
        log "WARNING: $error_count storage errors in last hour"
        issues=1
    fi
    
    # USB errors
    error_count=$(journalctl -k -b --since "1 hour ago" 2>/dev/null | grep -icE 'usb.*error|xhci.*error' 2>/dev/null || echo "0")
    error_count=${error_count//[^0-9]/}  # Remove any non-numeric characters
    error_count=${error_count:-0}        # Default to 0 if empty
    if [[ $error_count -gt 2 ]]; then  # USB errors are more common, higher threshold
        log "WARNING: $error_count USB errors in last hour"
        issues=1
    fi
    
    # Network hardware errors
    error_count=$(journalctl -k -b --since "1 hour ago" 2>/dev/null | grep -icE 'alx.*timeout|r8169.*error|network.*error' 2>/dev/null || echo "0")
    error_count=${error_count//[^0-9]/}  # Remove any non-numeric characters
    error_count=${error_count:-0}        # Default to 0 if empty
    if [[ $error_count -gt 0 ]]; then
        log "WARNING: $error_count network hardware errors in last hour"
        issues=1
    fi
    
    # USB storage device resets (CRITICAL freeze risk)
    error_count=$(dmesg 2>/dev/null | grep -cE 'uas_eh.*reset|USB device.*reset' 2>/dev/null || echo "0")
    error_count=${error_count//[^0-9]/}
    error_count=${error_count:-0}
    if [[ $error_count -gt 10 ]]; then
        log "CRITICAL: $error_count USB storage resets detected (HIGH FREEZE RISK)"
        issues=1
    elif [[ $error_count -gt 5 ]]; then
        log "WARNING: $error_count USB storage resets detected (freeze risk)"
        issues=1
    fi
    
    # Thermal monitoring (can cause freezes)
    if command -v sensors >/dev/null 2>&1; then
        local max_temp
        max_temp=$(sensors 2>/dev/null | grep -E "Core|Package" | grep -oE "\+[0-9]+\.[0-9]+°C" | sed 's/+//;s/°C//' | sort -n | tail -1)
        if [[ -n "$max_temp" ]] && (( $(echo "$max_temp > 80" | bc -l 2>/dev/null || echo 0) )); then
            log "EMERGENCY: CPU temperature ${max_temp}°C - TAKING IMMEDIATE ACTION"
            notify-send -u critical "THERMAL EMERGENCY" "CPU at ${max_temp}°C - Taking emergency action!" 2>/dev/null || true
            
            # Take immediate emergency action - kill high CPU processes
            log "EMERGENCY: Analyzing top CPU processes for termination"
            local top_processes
            top_processes=$(ps -eo pid,pcpu,cmd --sort=-pcpu --no-headers | head -5)
            local killed_any=0
            
            while IFS= read -r line; do
                local pid pcpu cmd
                read -r pid pcpu cmd <<< "$line"
                if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]]; then
                    local cpu_int=$(echo "$pcpu" | cut -d. -f1)
                    if [[ $cpu_int -lt 20 ]]; then continue; fi
                    
                    # Skip critical system processes
                    if [[ "$cmd" =~ (systemd|kthreadd|ksoftirqd|kernel|kworker|init) ]]; then
                        log "EMERGENCY: Skipping critical system process: PID $pid ($cmd)"
                        continue
                    fi
                    
                    log "EMERGENCY: Killing high CPU process: PID $pid (${pcpu}% CPU) - $cmd"
                    kill -TERM "$pid" 2>/dev/null || true
                    sleep 1
                    if kill -0 "$pid" 2>/dev/null; then
                        kill -KILL "$pid" 2>/dev/null || true
                        log "EMERGENCY: Force killed process PID: $pid"
                    fi
                    killed_any=1
                    sleep 2
                fi
            done <<< "$top_processes"
            
            if [[ $killed_any -eq 0 ]]; then
                log "EMERGENCY: No killable user processes - system-level thermal crisis"
                log "EMERGENCY: Initiating clean shutdown to prevent hardware damage"
                
                # Create diagnostic dump before shutdown
                create_emergency_diagnostic_dump "$max_temp" "debug-watch"
                
                notify-send -u critical "THERMAL CRISIS" "System shutdown in 2 minutes - CPU at ${max_temp}°C. Diagnostic dump created." 2>/dev/null || true
                /sbin/shutdown -h +2 "EMERGENCY: Thermal protection shutdown - CPU at ${max_temp}°C" 2>/dev/null || true
            fi
            
            issues=1
        elif [[ -n "$max_temp" ]] && (( $(echo "$max_temp > 85" | bc -l 2>/dev/null || echo 0) )); then
            log "CRITICAL: CPU temperature ${max_temp}°C exceeds safe threshold (freeze risk)"
            issues=1
        elif [[ -n "$max_temp" ]] && (( $(echo "$max_temp > 75" | bc -l 2>/dev/null || echo 0) )); then
            log "WARNING: CPU temperature ${max_temp}°C elevated"
            issues=1
        fi
    fi
    
    return $issues
}

# Check system services and network connectivity
check_services_and_network() {
    local issues=0
    
    # Failed services check
    local failed_services
    failed_services=$(systemctl --failed --no-pager --no-legend | wc -l)
    if [[ $failed_services -ge $FAILED_SERVICES_WARN ]]; then
        log "WARNING: $failed_services failed system services"
        issues=1
    fi
    
    # Network connectivity check
    if ! ping -c1 -W3 1.1.1.1 >/dev/null 2>&1; then
        log "WARNING: No internet connectivity"
        issues=1
    fi
    
    # DNS resolution check
    if command -v resolvectl >/dev/null 2>&1; then
        if ! resolvectl query example.com >/dev/null 2>&1; then
            log "WARNING: DNS resolution failing"
            issues=1
        fi
    fi
    
    return $issues
}

# Check for system instability indicators
check_system_stability() {
    local issues=0
    
    # Recent crashes or kernel panics
    if journalctl --since "6 hours ago" | grep -qi "kernel panic\|oops\|segfault\|core dumped"; then
        log "WARNING: Recent system crashes detected"
        issues=1
    fi
    
    # System hang indicators
    if journalctl --since "6 hours ago" | grep -qi "rcu.*stall\|soft.*lockup\|hard.*lockup\|hung.*task"; then
        log "WARNING: System hang indicators detected"
        issues=1
    fi
    
    # High number of recent reboots
    local boot_count
    boot_count=$(journalctl --list-boots | wc -l)
    if [[ $boot_count -gt 5 ]]; then
        # Check if multiple reboots in last 24 hours
        local recent_boots
        recent_boots=$(journalctl --list-boots --since "24 hours ago" | wc -l)
        if [[ $recent_boots -gt 3 ]]; then
            log "WARNING: $recent_boots reboots in last 24 hours (possible instability)"
            issues=1
        fi
    fi
    
    return $issues
}

# Attempt network fixes
attempt_network_fix() {
    if is_in_cooldown "network" "$NETWORK_FIX_COOLDOWN"; then
        log "Network fix in cooldown period, skipping"
        return 1
    fi
    
    # Test connectivity before fix
    local pre_fix_connectivity="FAILED"
    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        pre_fix_connectivity="OK"
    fi
    
    log "ATTEMPTING: Network connectivity fix (current connectivity: $pre_fix_connectivity)"
    
    local fix_output
    fix_output=$("$FIX_SCRIPT" --network-fix 2>&1)
    local fix_result=$?
    
    if [[ $fix_result -eq 0 ]]; then
        record_fix "network"
        
        # Test connectivity after fix
        sleep 3
        local post_fix_connectivity="FAILED"
        if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
            post_fix_connectivity="OK"
        fi
        
        log "NETWORK FIX SUCCESS: Connectivity after fix: $post_fix_connectivity"
        
        if [[ "$post_fix_connectivity" == "OK" ]]; then
            notify-send -u normal "debug-watch: Network connectivity restored" 2>/dev/null || true
        else
            log "WARNING: Network fix completed but connectivity still failing"
            notify-send -u normal "debug-watch: Network fix applied but connectivity still failing" \
                "May require manual intervention" 2>/dev/null || true
        fi
        return 0
    else
        log "NETWORK FIX FAILED: Network repair operations failed (exit code: $fix_result)"
        log "FIX OUTPUT: $fix_output"
        
        notify-send -u critical "debug-watch: Network fix failed" \
            "Check journalctl -t debug-watch for details" 2>/dev/null || true
        
        error "Network fix failed - manual network troubleshooting may be required"
        return 1
    fi
}

# Attempt service fixes
attempt_service_fix() {
    if is_in_cooldown "service" "$SERVICE_FIX_COOLDOWN"; then
        log "Service fix in cooldown period, skipping"
        return 1
    fi
    
    # Get list of failed services before attempting fix
    local failed_services
    failed_services=$(systemctl --failed --no-pager --no-legend --plain | awk '{print $1}' || echo "")
    
    if [[ -n "$failed_services" ]]; then
        log "ATTEMPTING: Service fix for failed services: $failed_services"
    else
        log "No failed services found to fix"
        return 0
    fi
    
    log "Executing service restart fix..."
    local fix_output
    fix_output=$("$FIX_SCRIPT" --service-fix 2>&1)
    local fix_result=$?
    
    if [[ $fix_result -eq 0 ]]; then
        record_fix "service"
        log "SERVICE FIX SUCCESS: Completed service restart operations"
        
        # Check which services are still failed after fix attempt
        local still_failed
        still_failed=$(systemctl --failed --no-pager --no-legend --plain | awk '{print $1}' || echo "")
        
        if [[ -z "$still_failed" ]]; then
            log "RESULT: All failed services successfully restarted"
            notify-send -u normal "debug-watch: All failed services restarted successfully" 2>/dev/null || true
        else
            log "RESULT: Some services still failed after restart: $still_failed"
            notify-send -u normal "debug-watch: Partial service fix success" \
                "Some services still failed: $still_failed" 2>/dev/null || true
        fi
        return 0
    else
        log "SERVICE FIX FAILED: Service restart operations failed (exit code: $fix_result)"
        log "FIX OUTPUT: $fix_output"
        
        # Log specific failure details for troubleshooting
        local current_failed
        current_failed=$(systemctl --failed --no-pager --no-legend --plain | awk '{print $1}' || echo "")
        log "FAILED SERVICES AFTER FIX ATTEMPT: $current_failed"
        
        # Send detailed notification to user
        notify-send -u critical "debug-watch: Service fix failed" \
            "Failed to restart services. Check journalctl -t debug-watch for details" 2>/dev/null || true
        
        error "Service fix failed - manual intervention may be required"
        return 1
    fi
}

# Attempt cleanup when disk space is critical
attempt_cleanup() {
    if is_in_cooldown "cleanup" "$CLEANUP_COOLDOWN"; then
        log "Cleanup in cooldown period, skipping"
        return 1
    fi
    
    log "Attempting system cleanup"
    if "$FIX_SCRIPT" --quiet --cleanup; then
        record_fix "cleanup"
        log "System cleanup completed successfully"
        notify-send -u normal "debug-watch: Performed system cleanup" 2>/dev/null || true
        return 0
    else
        log "System cleanup failed"
        return 1
    fi
}

# Send notification and log message
send_alert() {
    local urgency="$1"
    local message="$2"
    
    log "$message"
    notify-send -u "$urgency" "debug-watch: $message" 2>/dev/null || true
}

# Log a summary of the watchdog run for easy troubleshooting
log_run_summary() {
    local performance_issues="$1"
    local hardware_issues="$2" 
    local service_issues="$3"
    local stability_issues="$4"
    local fixes_attempted="$5"
    
    log "=== DEBUG WATCHDOG RUN SUMMARY ==="
    
    # Use if statements instead of command substitution to avoid variable expansion issues
    if [[ $performance_issues -eq 1 ]]; then
        log "Performance Issues: DETECTED"
    else
        log "Performance Issues: None"
    fi
    
    if [[ $hardware_issues -eq 1 ]]; then
        log "Hardware Issues: DETECTED"
    else
        log "Hardware Issues: None"
    fi
    
    if [[ $service_issues -eq 1 ]]; then
        log "Service Issues: DETECTED"
    else
        log "Service Issues: None"
    fi
    
    if [[ $stability_issues -eq 1 ]]; then
        log "Stability Issues: DETECTED"
    else
        log "Stability Issues: None"
    fi
    
    if [[ $fixes_attempted -eq 1 ]]; then
        log "Fixes Attempted: YES"
    else
        log "Fixes Attempted: No"
    fi
    
    # Add specific recommendations
    if [[ $performance_issues -eq 1 ]]; then
        log "PERFORMANCE: Check CPU/memory usage with 'debug-fix-all.sh --performance'"
    fi
    if [[ $hardware_issues -eq 1 ]]; then
        log "HARDWARE: Check logs with 'journalctl -k -b | grep -E \"pcie|nvme|usb.*error\"'"
    fi
    if [[ $service_issues -eq 1 ]]; then
        log "SERVICES: Check failed services with 'systemctl --failed'"
    fi
    if [[ $stability_issues -eq 1 ]]; then
        log "STABILITY: Run post-crash analysis with 'debug-fix-all.sh --post-crash'"
    fi
    
    log "=== END SUMMARY (search for this in logs: journalctl -t debug-watch) ==="
}

# Show help
show_help() {
    cat << 'EOF'
debug-watch.sh - Proactive system health monitoring watchdog

DESCRIPTION:
    Comprehensive system monitoring that complements i915-watch.sh.
    Monitors performance, hardware health, services, and resource usage,
    automatically applying fixes when issues are detected.

USAGE:
    ./debug-watch.sh [OPTIONS]

OPTIONS:
    --help, -h            Show this help message

OPERATION:
    This script runs automatically via cron (every 15-30 minutes recommended).
    It monitors multiple system health indicators:
    
    • Performance: CPU load, memory pressure, disk space
    • Hardware: PCIe errors, NVMe issues, USB problems, network hardware
    • Services: Failed systemd services, network connectivity, DNS resolution
    • Stability: Crashes, hangs, excessive reboots

    Automatic fixes applied:
    • Network connectivity restoration
    • Failed service restarts  
    • System cleanup when disk space critical
    • Cooldown periods prevent fix loops

INTEGRATION:
    Works alongside i915-watch.sh for complete system monitoring
    Uses debug-fix-all.sh for actual fix operations

INSTALLATION:
    Use debug-install.sh for proper system integration, or manually add to cron:
    @reboot /path/to/debug-watch.sh
    0 */6 * * * /path/to/debug-watch.sh

MONITORING:
    View watchdog activity: sudo journalctl -t debug-watch -f
    Check fix history: cat /var/tmp/debug-watch-state

EOF
}

# Main watchdog logic
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done
    
    # Run all checks
    local performance_issues=0
    local hardware_issues=0
    local service_issues=0
    local stability_issues=0
    
    check_performance || performance_issues=1
    check_hardware_errors || hardware_issues=1
    check_services_and_network || service_issues=1
    check_system_stability || stability_issues=1
    
    # Determine if fixes are needed
    local fixes_needed=0
    if [[ $performance_issues -eq 1 ]] || [[ $hardware_issues -eq 1 ]] || [[ $service_issues -eq 1 ]] || [[ $stability_issues -eq 1 ]]; then
        fixes_needed=1
    fi
    
    # Apply fixes if needed and script is available
    local fix_attempted=0
    if [[ $fixes_needed -eq 1 ]]; then
        if ! check_fix_script; then
            send_alert "critical" "System issues detected but fix script unavailable"
            # Still log summary even if fix script unavailable
            log_run_summary "$performance_issues" "$hardware_issues" "$service_issues" "$stability_issues" "$fix_attempted"
            exit 1
        fi
        
        # Try fixes based on issue types
        if [[ $service_issues -eq 1 ]]; then
            if attempt_service_fix; then
                fix_attempted=1
            fi
            if attempt_network_fix; then
                fix_attempted=1
            fi
        fi
        
        # Try cleanup if disk space is critical
        local disk_usage
        disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
        if [[ $disk_usage -gt $DISK_USAGE_CRITICAL ]]; then
            if attempt_cleanup; then
                fix_attempted=1
            fi
        fi
        
        # Send alerts for issues that couldn't be fixed
        if [[ $fix_attempted -eq 0 ]]; then
            if [[ $performance_issues -eq 1 ]]; then
                send_alert "normal" "Performance issues detected (high load/low memory/disk space)"
            fi
            if [[ $hardware_issues -eq 1 ]]; then
                send_alert "normal" "Hardware errors detected (check logs for PCIe/NVMe/USB issues)"
            fi
            if [[ $stability_issues -eq 1 ]]; then
                send_alert "critical" "System instability detected (crashes/hangs/frequent reboots)"
            fi
        fi
    fi
    
    # Always log a summary for easy troubleshooting
    log_run_summary "$performance_issues" "$hardware_issues" "$service_issues" "$stability_issues" "$fix_attempted"
    
    exit 0
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
