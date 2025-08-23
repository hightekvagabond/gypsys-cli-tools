#!/bin/bash
#
#  critical-monitor.sh – Real-time critical system monitoring
#
#  DEVELOPER NOTES
#  ---------------
#  Lightweight monitoring for fast-developing critical issues:
#  - Thermal spikes (can cause instant freezes)
#  - USB storage resets (can cause system hangs)
#  - Memory pressure (OOM kills)
#  
#  Designed to run every 1-2 minutes via systemd service.
#  Focuses ONLY on conditions that can cause immediate system failure.
#
#  ARCHITECTURE
#  ------------
#  - Minimal resource usage
#  - Fast execution (< 5 seconds)
#  - Immediate alerts for critical conditions
#  - Automatic fixes for known issues
#  - State tracking to prevent spam alerts

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="/var/tmp/critical-monitor-state"
LOG_TAG="critical-monitor"

# Thresholds (lowered based on 100°C crisis events)
TEMP_WARNING=85     # °C - Start warning (CPU package temp - normal under load is ~75-80°C)
TEMP_CRITICAL=90    # °C - Critical action needed (approaching thermal throttling)
TEMP_EMERGENCY=95   # °C - Emergency action (thermal throttling zone - immediate danger)
USB_RESET_WARNING=10    # USB resets per boot (warning)
USB_RESET_CRITICAL=20   # USB resets per boot (critical)
MEMORY_WARNING=90   # % memory usage warning
MEMORY_CRITICAL=95  # % memory usage critical

# Create state directory
mkdir -p "$STATE_DIR"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [critical-monitor] $*" | logger -t "$LOG_TAG" || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [critical-monitor] $*"
}

# Error function
error() {
    log "ERROR: $*" >&2
}

# Alert function
send_alert() {
    local level="$1"
    local message="$2"
    
    log "ALERT ($level): $message"
    
    # Send desktop notification
    notify-send -u "$level" "Critical Monitor: $message" 2>/dev/null || true
    
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

# Check if we should send an alert (cooldown logic)
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

# Record that we sent an alert
record_alert() {
    local alert_type="$1"
    local state_file="$STATE_DIR/last_${alert_type}_alert"
    date +%s > "$state_file"
}

# Check if a process is a critical system process that shouldn't be killed
is_system_critical_process() {
    local pid="$1"
    local cmd="$2"
    
    # Critical system processes that should never be killed
    case "$cmd" in
        */kernel*|*kthreadd*|*ksoftirqd*|*migration*|*rcu_*|*watchdog*)
            return 0  # Is critical
            ;;
        *systemd*|*init*|*/sbin/init*|*dbus*|*NetworkManager*)
            return 0  # Is critical
            ;;
        *Xorg*|*kwin*|*plasmashell*|*gdm*|*lightdm*)
            return 0  # Is critical (display/window manager)
            ;;
    esac
    
    # Check if it's a kernel thread (usually in brackets)
    if [[ "$cmd" =~ ^\[.*\]$ ]]; then
        return 0  # Is critical kernel thread
    fi
    
    # Check if PID is very low (likely system process)
    if [[ $pid -lt 100 ]]; then
        return 0  # Is critical (low PID system process)
    fi
    
    return 1  # Not critical, can be killed
}

# Comprehensive pre-shutdown diagnostic dump for future investigation
emergency_diagnostic_dump() {
    local temp="$1"
    local dump_file="/var/log/emergency-thermal-dump-$(date +%Y%m%d-%H%M%S).log"
    
    log "EMERGENCY: Creating diagnostic dump at $dump_file"
    
    {
        echo "=== EMERGENCY THERMAL DIAGNOSTIC DUMP ==="
        echo "Timestamp: $(date)"
        echo "Trigger Temperature: ${temp}°C"
        echo "Emergency Threshold: ${TEMP_EMERGENCY}°C"
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
        
        echo "=== RECENT THERMAL EVENTS (Last 2 hours) ==="
        journalctl --since "2 hours ago" --no-pager 2>/dev/null | grep -E "(thermal|temperature|100.*°C|95.*°C|90.*°C|emergency|critical-monitor|debug-watch)" | tail -20 || echo "Journal thermal check failed"
        echo ""
        
        echo "=== RECENT HARDWARE ERRORS (Last 2 hours) ==="
        journalctl -k --since "2 hours ago" --no-pager 2>/dev/null | grep -E "(error|fail|critical|thermal|USB.*disconnect|PCIe|NVMe)" | tail -15 || echo "Hardware error check failed"
        echo ""
        
        echo "=== USB RESETS AND HARDWARE ISSUES ==="
        journalctl -b --no-pager 2>/dev/null | grep -E "(USB.*reset|uas_eh|PCIe.*error|nvme.*error)" | tail -10 || echo "USB/Hardware reset check failed"
        echo ""
        
        echo "=== SYSTEMD FAILED SERVICES ==="
        systemctl --failed --no-pager 2>/dev/null || echo "Failed services check failed"
        echo ""
        
        echo "=== NETWORK STATUS ==="
        ip link show 2>/dev/null | grep -E "(state|mtu)" || echo "Network status check failed"
        echo ""
        
        echo "=== DMESG RECENT ERRORS ==="
        dmesg -T --level=err,crit,alert,emerg 2>/dev/null | tail -10 || echo "dmesg check failed"
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
        
        echo "=== SUMMARY ==="
        echo "This diagnostic dump was created automatically by critical-monitor.sh"
        echo "before emergency thermal shutdown at ${temp}°C (threshold: ${TEMP_EMERGENCY}°C)"
        echo "Use this information to investigate the root cause of thermal issues."
        echo ""
        echo "=== END DIAGNOSTIC DUMP ==="
        
    } > "$dump_file" 2>&1
    
    # Make sure the file is readable
    chmod 644 "$dump_file" 2>/dev/null || true
    
    log "EMERGENCY: Diagnostic dump completed: $dump_file"
    
    # Also log a summary to syslog for easy reference
    log "DIAGNOSTIC SUMMARY: Temp=${temp}°C, CPU Load=$(uptime | grep -oE 'load average: [0-9]+\.[0-9]+' | awk '{print $3}' || echo 'unknown'), Top Process=$(ps aux --sort=-%cpu --no-headers | head -1 | awk '{print $11}' || echo 'unknown')"
}

# Emergency thermal protection - kill offending applications or shutdown if system-level
emergency_thermal_protection() {
    local temp="$1"
    
    log "EMERGENCY: Initiating thermal protection at ${temp}°C"
    
    # SMART TARGETING: Find the single highest CPU non-system process
    local target_pid target_pcpu target_cmd target_process_age
    local found_target=false
    
    # Get top 10 CPU consuming processes for analysis
    local top_processes
    top_processes=$(ps -eo pid,pcpu,cmd --sort=-pcpu --no-headers | head -10)
    
    log "EMERGENCY: Analyzing top CPU processes to find target:"
    
    # Find the first (highest CPU) non-system, non-grace-period process
    while IFS= read -r line; do
        local pid pcpu cmd
        read -r pid pcpu cmd <<< "$line"
        
        if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]]; then
            local cpu_int
            cpu_int=$(echo "$pcpu" | cut -d. -f1)
            
            log "EMERGENCY: Evaluating PID $pid (${pcpu}% CPU) - $cmd"
            
            # Skip if CPU usage is too low to be worth targeting (only kill if >10% CPU)
            if [[ $cpu_int -lt 10 ]]; then
                log "EMERGENCY: CPU too low (${pcpu}%) - not worth targeting"
                continue
            fi
            
            # Skip system critical processes
            if is_system_critical_process "$pid" "$cmd"; then
                log "EMERGENCY: Skipping critical system process: PID $pid ($cmd)"
                continue
            fi
            
            # CHECK GRACE PERIOD: Give processes 60 seconds after boot to settle
            local uptime_seconds
            uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 3600)
            if [[ $uptime_seconds -lt 60 ]]; then
                log "EMERGENCY: System just booted (${uptime_seconds}s) - giving process grace period: PID $pid ($cmd)"
                continue
            fi
            
            # CHECK PROCESS AGE: Give new processes 60 seconds to settle
            local process_age
            if [[ -f "/proc/$pid/stat" ]]; then
                local start_time
                start_time=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || echo 0)
                local boot_time
                boot_time=$(awk '/btime/ {print $2}' /proc/stat 2>/dev/null || echo 0)
                local current_time
                current_time=$(date +%s)
                process_age=$((current_time - boot_time - start_time/100))
                
                if [[ $process_age -lt 60 ]]; then
                    log "EMERGENCY: Process too new (${process_age}s) - giving startup grace period: PID $pid ($cmd)"
                    continue
                fi
            fi
            
            # FOUND OUR TARGET - the highest CPU non-system process
            target_pid="$pid"
            target_pcpu="$pcpu"
            target_cmd="$cmd"
            target_process_age="$process_age"
            found_target=true
            log "EMERGENCY: TARGET IDENTIFIED - PID $pid (${pcpu}% CPU, age: ${process_age:-unknown}s) - $cmd"
            break
        fi
    done <<< "$top_processes"
    
    local killed_any=false
    
    # Kill only the single target process (if found)
    if [[ "$found_target" == "true" ]]; then
        log "EMERGENCY: Killing target process: PID $target_pid (${target_pcpu}% CPU, age: ${target_process_age:-unknown}s) - $target_cmd"
        
        # Enhanced desktop notification with more details
        local app_name
        app_name=$(basename "$target_cmd" | cut -d' ' -f1)
        send_alert "critical" "🚨 EMERGENCY THERMAL PROTECTION: Killed TOP CPU process '$app_name' (${target_pcpu}% CPU) at ${temp}°C to prevent system freeze"
        
        # Additional desktop notification with wall message for all users
        if command -v notify-send >/dev/null 2>&1; then
            DISPLAY=:0 notify-send -u critical -t 15000 "🚨 Critical Monitor: Process Killed" \
                "Application: $app_name\nCPU Usage: ${target_pcpu}%\nTemperature: ${temp}°C\nReason: Emergency thermal protection (TOP CPU offender)\nProcess age: ${target_process_age:-unknown}s" 2>/dev/null &
        fi
        
        # Wall message to all logged-in users
        echo "🚨 EMERGENCY: Critical-monitor killed TOP CPU offender '$app_name' (${target_pcpu}% CPU) due to thermal emergency at ${temp}°C" | wall 2>/dev/null || true
        
        # Kill process gracefully first, then force if needed
        kill -TERM "$target_pid" 2>/dev/null || true
        sleep 2
        if kill -0 "$target_pid" 2>/dev/null; then
            kill -KILL "$target_pid" 2>/dev/null || true
            log "Force killed target process PID: $target_pid"
        fi
        
        killed_any=true
        log "EMERGENCY: Successfully terminated target process - thermal protection complete"
    else
        log "EMERGENCY: No suitable target process found (all high-CPU processes are system critical or in grace period)"
    fi
    
    # If we couldn't kill any user processes, or if system processes are the problem,
    # initiate clean shutdown to prevent hardware damage
    if [[ "$killed_any" != "true" ]]; then
        log "EMERGENCY: No killable user processes found - system-level thermal issue detected"
        log "EMERGENCY: Initiating clean shutdown to prevent hardware damage"
        send_alert "critical" "EMERGENCY: System-level thermal crisis at ${temp}°C - Initiating clean shutdown to prevent hardware damage"
        
        # Create comprehensive diagnostic dump before shutdown
        emergency_diagnostic_dump "$temp"
        
        # Give user a few seconds to see the alert and complete dump
        sleep 8
        
        # Initiate clean shutdown
        log "EMERGENCY: Executing clean shutdown now"
        /sbin/shutdown -h +1 "EMERGENCY: Thermal protection shutdown - CPU at ${temp}°C" 2>/dev/null || \
        systemctl poweroff 2>/dev/null || \
        /sbin/poweroff 2>/dev/null || true
    fi
    
    log "EMERGENCY: Thermal protection complete"
    return 0
}

# Get top CPU consuming processes
get_top_cpu_processes() {
    # Get top 5 CPU consuming processes with details
    ps -eo pid,ppid,cmd,pcpu,pmem --sort=-pcpu --no-headers | head -5 | while read -r line; do
        echo "    $line"
    done
}

# Check thermal conditions
check_thermal() {
    if ! command -v sensors >/dev/null 2>&1; then
        return 0  # No sensors available
    fi
    
    local max_temp package_temp
    # Get package temperature (most critical for thermal throttling)
    package_temp=$(sensors 2>/dev/null | grep "Package id 0:" | awk '{print $4}' | grep -oE "\+[0-9]+\.[0-9]+" | sed 's/+//' 2>/dev/null)
    # Get maximum core temperature as backup
    local core_temp
    core_temp=$(sensors 2>/dev/null | grep -E "Core [0-9]:" | awk '{print $3}' | grep -oE "\+[0-9]+\.[0-9]+" | sed 's/+//' | sort -n | tail -1 2>/dev/null)
    
    # Use package temp if available, otherwise use max core temp
    if [[ -n "$package_temp" ]]; then
        max_temp="$package_temp"
    else
        max_temp="$core_temp"
    fi
    
    if [[ -z "$max_temp" ]]; then
        return 0  # No temperature readings
    fi
    
    # Use integer comparison to avoid bc dependency
    local temp_int
    temp_int=$(echo "$max_temp" | cut -d. -f1)
    
    # Get current CPU load for context
    local cpu_load
    cpu_load=$(uptime | grep -oE 'load average: [0-9]+\.[0-9]+' | awk '{print $3}')
    
    # EMERGENCY ACTION - Kill processes to prevent lockup
    if [[ $temp_int -ge $TEMP_EMERGENCY ]]; then
        if should_alert "thermal_emergency" 1; then
            local top_processes
            top_processes=$(get_top_cpu_processes)
            send_alert "critical" "EMERGENCY: CPU temperature ${max_temp}°C exceeds emergency threshold (${TEMP_EMERGENCY}°C) - TAKING EMERGENCY ACTION. Load: ${cpu_load:-unknown}. Top CPU processes: $top_processes"
            record_alert "thermal_emergency"
        fi
        log "EMERGENCY: CPU temperature ${max_temp}°C (emergency threshold: ${TEMP_EMERGENCY}°C)"
        log "CPU Load: ${cpu_load:-unknown}"
        log "Top CPU consuming processes:"
        get_top_cpu_processes | while read -r process_line; do
            log "$process_line"
        done
        
        # Take emergency action
        emergency_thermal_protection "$max_temp"
        return 1
    elif [[ $temp_int -ge $TEMP_CRITICAL ]]; then
        if should_alert "thermal_critical" 5; then
            local top_processes
            top_processes=$(get_top_cpu_processes)
            send_alert "critical" "CPU temperature ${max_temp}°C exceeds critical threshold (${TEMP_CRITICAL}°C) - FREEZE RISK. Load: ${cpu_load:-unknown}. Top CPU processes: $top_processes"
            record_alert "thermal_critical"
        fi
        log "CRITICAL: CPU temperature ${max_temp}°C (threshold: ${TEMP_CRITICAL}°C)"
        log "CPU Load: ${cpu_load:-unknown}"
        log "Top CPU consuming processes:"
        get_top_cpu_processes | while read -r process_line; do
            log "$process_line"
        done
        return 1
    elif [[ $temp_int -ge $TEMP_WARNING ]]; then
        if should_alert "thermal_warning" 10; then
            local top_processes
            top_processes=$(get_top_cpu_processes | head -3)
            send_alert "normal" "CPU temperature ${max_temp}°C elevated (threshold: ${TEMP_WARNING}°C). Load: ${cpu_load:-unknown}. Top processes: $top_processes"
            record_alert "thermal_warning"
        fi
        log "WARNING: CPU temperature ${max_temp}°C (threshold: ${TEMP_WARNING}°C)"
        log "CPU Load: ${cpu_load:-unknown}"
        log "Top CPU consuming processes:"
        get_top_cpu_processes | while read -r process_line; do
            log "$process_line"
        done
        return 1
    fi
    
    return 0
}

# Check USB storage device issues
check_usb_storage() {
    local reset_count
    reset_count=$(dmesg 2>/dev/null | grep -cE 'uas_eh.*reset|USB device.*reset' 2>/dev/null || echo "0")
    reset_count=${reset_count//[^0-9]/}
    reset_count=${reset_count:-0}
    
    # Check for docking station ethernet failures (like enx00e04c68039a)
    local dock_failures
    dock_failures=$(journalctl -b --no-pager 2>/dev/null | grep -c "ip-config-unavailable.*enx" || echo "0")
    dock_failures=${dock_failures//[^0-9]/}
    dock_failures=${dock_failures:-0}
    
    # Check for USB disconnect events (docking station instability)
    local usb_disconnects
    usb_disconnects=$(journalctl -b --no-pager 2>/dev/null | grep -c "USB disconnect, device number" || echo "0") 
    usb_disconnects=${usb_disconnects//[^0-9]/}
    usb_disconnects=${usb_disconnects:-0}
    
    if [[ $reset_count -ge $USB_RESET_CRITICAL ]]; then
        if should_alert "usb_critical" 15; then
            send_alert "critical" "$reset_count USB storage resets detected - HIGH FREEZE RISK"
            record_alert "usb_critical"
            
            # Try to apply USB fixes immediately
            local fix_script="$SCRIPT_DIR/debug-fix-all.sh"
            if [[ -x "$fix_script" ]]; then
                log "Attempting emergency USB storage fixes..."
                "$fix_script" --usb-fix >/dev/null 2>&1 || log "USB fix failed"
            fi
        fi
        log "CRITICAL: $reset_count USB storage resets (threshold: $USB_RESET_CRITICAL)"
        return 1
    elif [[ $dock_failures -gt 20 ]]; then
        if should_alert "dock_critical" 5; then
            # Try to disable the failing network adapter to prevent thermal overload
            local failed_adapter
            failed_adapter=$(journalctl -b --no-pager 2>/dev/null | grep "ip-config-unavailable.*enx" | tail -1 | grep -oE 'enx[a-f0-9]{12}' | head -1)
            
            if [[ -n "$failed_adapter" ]]; then
                log "EMERGENCY: Disabling failing network adapter: $failed_adapter"
                if command -v nmcli >/dev/null 2>&1; then
                    # Disconnect the adapter and disable autoconnect temporarily
                    nmcli device disconnect "$failed_adapter" 2>/dev/null || true
                    
                    # Disable autoconnect for all connections on this device (ephemeral - resets at reboot)
                    nmcli connection show | grep "$failed_adapter" | awk '{print $1}' | while read -r conn_name; do
                        if [[ -n "$conn_name" ]]; then
                            nmcli connection modify "$conn_name" connection.autoconnect no 2>/dev/null || true
                        fi
                    done
                    
                    # Create a temporary marker file that expires
                    local marker_file="/tmp/network_disabled_${failed_adapter}"
                    echo "$(date): Disabled due to ${dock_failures} DHCP failures" > "$marker_file" 2>/dev/null || true
                    
                    log "Network adapter $failed_adapter temporarily disabled (autoconnect off until reboot)"
                    
                    # Send both system alert and desktop notification
                    send_alert "critical" "🚨 NETWORK ADAPTER TEMPORARILY DISABLED: '$failed_adapter' (${dock_failures} DHCP failures) - preventing thermal overload. Will auto-restore at reboot."
                    
                    # Desktop notification for immediate user awareness
                    if command -v notify-send >/dev/null 2>&1; then
                        notify-send -u critical -t 10000 "🚨 Network Adapter Temporarily Disabled" \
                            "Disabled '$failed_adapter' due to ${dock_failures} DHCP failures.\nPreventing thermal overload.\nWill auto-restore at reboot." 2>/dev/null || true
                    fi
                else
                    send_alert "critical" "Docking station ethernet failures: ${dock_failures} - REMOVE DOCK TO PREVENT THERMAL OVERLOAD (nmcli not available)"
                fi
            else
                send_alert "critical" "Docking station ethernet failures: ${dock_failures} - REMOVE DOCK TO PREVENT THERMAL OVERLOAD"
            fi
            record_alert "dock_critical"
        fi
        log "CRITICAL: Docking station ethernet failures: ${dock_failures} (thermal risk)"
        return 1
    elif [[ $usb_disconnects -gt 50 ]]; then
        if should_alert "usb_unstable" 10; then
            send_alert "normal" "USB instability: ${usb_disconnects} disconnects (check docking station)"
            record_alert "usb_unstable"
        fi
        log "WARNING: USB instability: ${usb_disconnects} disconnects"
        return 1
    elif [[ $reset_count -ge $USB_RESET_WARNING ]]; then
        if should_alert "usb_warning" 30; then
            send_alert "normal" "$reset_count USB storage resets detected (freeze risk)"
            record_alert "usb_warning"
        fi
        log "WARNING: $reset_count USB storage resets (threshold: $USB_RESET_WARNING)"
        return 1
    fi
    
    return 0
}

# Get top memory consuming processes
get_top_memory_processes() {
    # Get top 5 memory consuming processes with details
    ps -eo pid,ppid,cmd,pcpu,pmem --sort=-pmem --no-headers | head -5 | while read -r line; do
        echo "    $line"
    done
}

# Check memory pressure
check_memory() {
    local memory_info
    memory_info=$(free | grep '^Mem:')
    local total used available
    total=$(echo "$memory_info" | awk '{print $2}')
    used=$(echo "$memory_info" | awk '{print $3}')
    available=$(echo "$memory_info" | awk '{print $7}')
    
    if [[ $total -eq 0 ]]; then
        return 0  # Avoid division by zero
    fi
    
    local usage_percent
    usage_percent=$(( (used * 100) / total ))
    
    if [[ $usage_percent -ge $MEMORY_CRITICAL ]]; then
        if should_alert "memory_critical" 5; then
            local top_processes
            top_processes=$(get_top_memory_processes)
            send_alert "critical" "Memory usage ${usage_percent}% exceeds critical threshold (${MEMORY_CRITICAL}%) - OOM RISK. Top memory processes: $top_processes"
            record_alert "memory_critical"
        fi
        log "CRITICAL: Memory usage ${usage_percent}% (threshold: ${MEMORY_CRITICAL}%)"
        log "Available memory: $((available / 1024 / 1024))GB"
        log "Top memory consuming processes:"
        get_top_memory_processes | while read -r process_line; do
            log "$process_line"
        done
        return 1
    elif [[ $usage_percent -ge $MEMORY_WARNING ]]; then
        if should_alert "memory_warning" 15; then
            local top_processes
            top_processes=$(get_top_memory_processes | head -3)
            send_alert "normal" "Memory usage ${usage_percent}% elevated (threshold: ${MEMORY_WARNING}%). Top processes: $top_processes"
            record_alert "memory_warning"
        fi
        log "WARNING: Memory usage ${usage_percent}% (threshold: ${MEMORY_WARNING}%)"
        log "Available memory: $((available / 1024 / 1024))GB"
        log "Top memory consuming processes:"
        get_top_memory_processes | while read -r process_line; do
            log "$process_line"
        done
        return 1
    fi
    
    return 0
}

# Show help
show_help() {
    cat << 'EOF'
critical-monitor.sh - Real-time critical system monitoring

DESCRIPTION:
    Lightweight monitoring for fast-developing critical issues that can
    cause immediate system freezes or crashes. Designed to run every 1-2
    minutes via systemd service.

USAGE:
    ./critical-monitor.sh [OPTIONS]

OPTIONS:
    --help, -h          Show this help message
    --test-thermal      Test thermal monitoring only
    --test-usb          Test USB storage monitoring only  
    --test-memory       Test memory monitoring only

MONITORS:
    • Thermal: CPU temperature spikes (>65°C warning, >70°C critical, >80°C emergency)
    • USB Storage: Reset patterns that indicate freeze risk
    • Memory: Usage levels that can lead to OOM kills

ALERTS:
    • Desktop notifications for immediate user awareness
    • Syslog entries for system logging
    • Automatic cooldown periods to prevent spam
    • Emergency fixes for known critical issues

EMERGENCY ACTIONS:
    At 80°C+ thermal crisis:
    1. Kill high CPU processes (>20% usage) to reduce thermal load
    2. If no killable user processes, create comprehensive diagnostic dump
    3. Initiate clean shutdown to prevent hardware damage
    
DIAGNOSTIC DUMPS:
    Emergency shutdowns automatically create detailed logs:
    /var/log/emergency-thermal-dump-*.log
    
    Contains: temperatures, processes, hardware errors, system logs,
    CPU frequencies, thermal zones, recent events - complete investigation data

OPERATION:
    This script is designed to run continuously via systemd service:
    
        systemctl start critical-monitor.service
        systemctl enable critical-monitor.service
    
    Check logs with:
        journalctl -t critical-monitor -f

EOF
}

# Main function
main() {
    local test_mode=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --test-thermal)
                test_mode="thermal"
                shift
                ;;
            --test-usb)
                test_mode="usb"
                shift
                ;;
            --test-memory)
                test_mode="memory"
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    local issues_found=0
    
    # Run checks based on mode
    case $test_mode in
        thermal)
            check_thermal || issues_found=1
            ;;
        usb)
            check_usb_storage || issues_found=1
            ;;
        memory)
            check_memory || issues_found=1
            ;;
        *)
            # Normal operation - check everything
            check_thermal || issues_found=1
            check_usb_storage || issues_found=1
            check_memory || issues_found=1
            ;;
    esac
    
    if [[ $issues_found -eq 0 ]]; then
        log "All critical systems normal"
    fi
    
    exit 0
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
