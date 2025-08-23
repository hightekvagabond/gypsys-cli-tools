#!/bin/bash
# Thermal monitoring module

MODULE_NAME="thermal"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

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
        handle_emergency_thermal "$temp"
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
    
    # Find single highest CPU process to kill (smart targeting)
    local target_pid target_pcpu target_cmd target_age
    local found_target=false
    
    while IFS= read -r line; do
        local pid pcpu cmd
        read -r pid pcpu cmd <<< "$line"
        
        if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]]; then
            local cpu_int=$(echo "$pcpu" | cut -d. -f1)
            
            # Only target processes using significant CPU
            if [[ $cpu_int -lt ${PROCESS_CPU_THRESHOLD:-10} ]]; then
                continue
            fi
            
            # Skip system critical processes
            if is_system_critical_process "$pid" "$cmd"; then
                log "EMERGENCY: Skipping critical process: PID $pid ($cmd)"
                continue
            fi
            
            # Check grace periods
            local uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 3600)
            if [[ $uptime_seconds -lt ${GRACE_PERIOD_SECONDS:-60} ]]; then
                log "EMERGENCY: System boot grace period active"
                continue
            fi
            
            local process_age=0
            if [[ -f "/proc/$pid/stat" ]]; then
                local start_time=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || echo 0)
                local boot_time=$(awk '/btime/ {print $2}' /proc/stat 2>/dev/null || echo 0)
                local current_time=$(date +%s)
                process_age=$((current_time - boot_time - start_time/100))
                
                if [[ $process_age -lt ${GRACE_PERIOD_SECONDS:-60} ]]; then
                    log "EMERGENCY: Process startup grace period active for PID $pid"
                    continue
                fi
            fi
            
            # Found our target
            target_pid="$pid"
            target_pcpu="$pcpu"  
            target_cmd="$cmd"
            target_age="$process_age"
            found_target=true
            break
        fi
    done <<< "$(get_top_cpu_processes)"
    
    if [[ "$found_target" == "true" ]]; then
        local app_name=$(basename "$target_cmd" | cut -d' ' -f1)
        
        log "EMERGENCY: Terminating PID $target_pid ($app_name) - ${target_pcpu}% CPU"
        
        # Send notifications
        send_alert "emergency" "🚨 EMERGENCY: Killed '$app_name' (${target_pcpu}% CPU) at ${temp}°C to prevent thermal damage"
        
        if command -v notify-send >/dev/null 2>&1; then
            DISPLAY=:0 notify-send -u critical -t 15000 "🚨 Thermal Protection" \
                "Killed: $app_name\nCPU: ${target_pcpu}%\nTemp: ${temp}°C\nReason: Emergency thermal protection" 2>/dev/null &
        fi
        
        echo "🚨 EMERGENCY: Thermal monitor killed '$app_name' (${target_pcpu}% CPU) at ${temp}°C" | wall 2>/dev/null || true
        
        # Kill process
        kill -TERM "$target_pid" 2>/dev/null || true
        sleep 2
        if kill -0 "$target_pid" 2>/dev/null; then
            kill -KILL "$target_pid" 2>/dev/null || true
        fi
        
        log "EMERGENCY: Process terminated successfully"
        return 0
    else
        log "EMERGENCY: No suitable processes found - system-level thermal issue"
        handle_thermal_shutdown "$temp"
        return 1
    fi
}

handle_thermal_shutdown() {
    local temp="$1"
    
    log "EMERGENCY: Initiating system shutdown - thermal crisis at ${temp}°C"
    send_alert "emergency" "🚨 SYSTEM SHUTDOWN: Thermal crisis at ${temp}°C - no killable processes found"
    
    # Create emergency diagnostic dump
    create_emergency_dump "$temp"
    
    # Initiate shutdown
    log "EMERGENCY: Executing clean shutdown"
    /sbin/shutdown -h +1 "EMERGENCY: Thermal protection shutdown - CPU at ${temp}°C" 2>/dev/null || \
    systemctl poweroff 2>/dev/null || \
    /sbin/poweroff 2>/dev/null || true
}

create_emergency_dump() {
    local temp="$1"
    local dump_file="/var/log/emergency-thermal-dump-$(date +%Y%m%d-%H%M%S).log"
    
    log "Creating emergency diagnostic dump: $dump_file"
    
    {
        echo "EMERGENCY THERMAL DIAGNOSTIC DUMP"
        echo "=================================="
        echo "Timestamp: $(date)"
        echo "Trigger Temperature: ${temp}°C"
        echo ""
        
        echo "TEMPERATURES:"
        sensors 2>/dev/null || echo "sensors not available"
        echo ""
        
        echo "TOP CPU PROCESSES:"
        get_top_cpu_processes
        echo ""
        
        echo "TOP MEMORY PROCESSES:"
        get_top_memory_processes
        echo ""
        
        echo "THERMAL ZONES:"
        for zone in /sys/class/thermal/thermal_zone*/temp; do
            if [[ -f "$zone" ]]; then
                local zone_temp=$(($(cat "$zone" 2>/dev/null || echo 0) / 1000))
                echo "$(basename "$(dirname "$zone")"): ${zone_temp}°C"
            fi
        done
        echo ""
        
        echo "SYSTEM UPTIME:"
        uptime
        echo ""
        
        echo "MEMORY INFO:"
        free -h
        echo ""
        
        echo "RECENT HARDWARE ERRORS:"
        dmesg | tail -50 | grep -iE "error|warn|fail|critical" || echo "No recent errors"
        
    } > "$dump_file" 2>/dev/null || log "Failed to create diagnostic dump"
}

# Module validation
validate_module "$MODULE_NAME"

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_status
fi