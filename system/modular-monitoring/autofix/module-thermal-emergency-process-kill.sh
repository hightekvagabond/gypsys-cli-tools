#!/bin/bash
# Thermal Emergency Process Kill Autofix
# Surgically targets the highest CPU-consuming process during thermal emergencies

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Source module config
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

emergency_process_kill() {
    local temp="$1"
    log "AUTOFIX: Emergency process kill activated at ${temp}°C"
    
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
                log "AUTOFIX: Skipping critical process: PID $pid ($cmd)"
                continue
            fi
            
            # Check grace periods
            local uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 3600)
            if [[ $uptime_seconds -lt ${GRACE_PERIOD_SECONDS:-60} ]]; then
                log "AUTOFIX: System boot grace period active"
                continue
            fi
            
            local process_age=0
            if [[ -f "/proc/$pid/stat" ]]; then
                local start_time=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || echo 0)
                local boot_time=$(awk '/btime/ {print $2}' /proc/stat 2>/dev/null || echo 0)
                local current_time=$(date +%s)
                process_age=$((current_time - boot_time - start_time/100))
                
                if [[ $process_age -lt ${GRACE_PERIOD_SECONDS:-60} ]]; then
                    log "AUTOFIX: Process startup grace period active for PID $pid"
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
        
        log "AUTOFIX: Terminating PID $target_pid ($app_name) - ${target_pcpu}% CPU"
        
        # Send notifications
        send_alert "emergency" "🚨 EMERGENCY: Killed '$app_name' (${target_pcpu}% CPU) at ${temp}°C to prevent thermal damage"
        
        if command -v notify-send >/dev/null 2>&1; then
            DISPLAY=:0 notify-send -u critical -t 15000 "🚨 Thermal Protection" \
                "Killed: $app_name\nCPU: ${target_pcpu}%\nTemp: ${temp}°C\nReason: Emergency thermal protection" 2>/dev/null &
        fi
        
        echo "🚨 EMERGENCY: Thermal monitor killed '$app_name' (${target_pcpu}% CPU) at ${temp}°C" | wall 2>/dev/null || true
        
        # Kill process
        kill -TERM "$target_pid" 2>/dev/null || true
        sleep "${KILL_PROCESS_WAIT_TIME:-2}"
        if kill -0 "$target_pid" 2>/dev/null; then
            kill -KILL "$target_pid" 2>/dev/null || true
        fi
        
        log "AUTOFIX: Process terminated successfully"
        return 0
    else
        log "AUTOFIX: No suitable processes found for emergency kill"
        return 1
    fi
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    temp="${1:-unknown}"
    emergency_process_kill "$temp"
fi
