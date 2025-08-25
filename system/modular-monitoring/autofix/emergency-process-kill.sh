#!/bin/bash
# Emergency Process Kill Autofix with Centralized Grace Period Management
# Handles kill requests from multiple monitors with intelligent grace period tracking
# Usage: emergency-process-kill.sh <trigger_reason> <trigger_value> <grace_seconds>

# Get the project root directory
AUTOFIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$AUTOFIX_DIR")"
source "$PROJECT_ROOT/modules/common.sh"

# Grace period tracking directory
GRACE_DIR="/tmp/modular-monitor-grace"
mkdir -p "$GRACE_DIR"

emergency_process_kill() {
    local trigger_reason="${1:-emergency}"
    local trigger_value="${2:-unknown}"
    local grace_seconds="${3:-45}"
    local calling_module="${4:-unknown}"
    
    log "AUTOFIX: Emergency process kill request - Trigger: $trigger_reason ($trigger_value) from $calling_module module (grace: ${grace_seconds}s)"
    
    # Load global autofix configuration
    local autofix_config="$PROJECT_ROOT/config/autofix.conf"
    if [[ -f "$autofix_config" ]]; then
        source "$autofix_config"
    fi
    
    # Find the top CPU process first
    local target_pid target_pcpu target_cmd
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
            
            # Found our target
            target_pid="$pid"
            target_pcpu="$pcpu"  
            target_cmd="$cmd"
            found_target=true
            break
        fi
    done <<< "$(get_top_cpu_processes)"
    
    if [[ "$found_target" != "true" ]]; then
        log "AUTOFIX: No suitable processes found for emergency kill"
        return 1
    fi
    
    local app_name=$(basename "$target_cmd" | cut -d' ' -f1)
    local grace_file="$GRACE_DIR/kill_${target_pid}_${app_name}"
    local current_time=$(date +%s)
    
    # Check if we already have a grace period active for this process
    if [[ -f "$grace_file" ]]; then
        local grace_start=$(cat "$grace_file" 2>/dev/null || echo "0")
        local elapsed=$((current_time - grace_start))
        
        if [[ $elapsed -lt $grace_seconds ]]; then
            local remaining=$((grace_seconds - elapsed))
            log "AUTOFIX: Process $app_name (PID $target_pid) still in grace period (${remaining}s remaining)"
            log "AUTOFIX: Kill request from $calling_module noted but grace period active"
            
            # Log the additional kill request
            echo "$(date '+%Y-%m-%d %H:%M:%S') $calling_module requested kill due to $trigger_reason ($trigger_value)" >> "${grace_file}.requests"
            
            return 0  # Don't kill yet, grace period active
        else
            log "AUTOFIX: Grace period expired for $app_name (PID $target_pid) after ${elapsed}s"
        fi
    else
        # First kill request for this process - start grace period
        echo "$current_time" > "$grace_file"
        echo "$(date '+%Y-%m-%d %H:%M:%S') $calling_module initiated grace period due to $trigger_reason ($trigger_value)" > "${grace_file}.requests"
        
        log "AUTOFIX: Starting ${grace_seconds}s grace period for $app_name (PID $target_pid) - ${target_pcpu}% CPU"
        log "AUTOFIX: Target: $app_name (PID $target_pid, ${target_pcpu}% CPU) from $calling_module"
        
        send_alert "warning" "⏳ Grace period started: $app_name (${target_pcpu}% CPU) - ${grace_seconds}s to cool down"
        
        return 0  # Don't kill yet, just started grace period
    fi
    
    # Grace period has expired - proceed with kill
    log "AUTOFIX: Terminating PID $target_pid ($app_name) - ${target_pcpu}% CPU - grace period expired"
    
    # Show all the kill requests that led to this
    if [[ -f "${grace_file}.requests" ]]; then
        log "AUTOFIX: Kill requests during grace period:"
        while IFS= read -r request_line; do
            log "AUTOFIX:   $request_line"
        done < "${grace_file}.requests"
    fi
    
    # Send notifications
    send_alert "emergency" "🚨 EMERGENCY: Killed '$app_name' (${target_pcpu}% CPU) - grace period expired after multiple requests"
    
    if command -v notify-send >/dev/null 2>&1; then
        DISPLAY=:0 notify-send -u critical -t 15000 "🚨 Emergency Protection" \
            "Killed: $app_name\nCPU: ${target_pcpu}%\nFinal Trigger: $trigger_reason\nValue: $trigger_value\nModule: $calling_module\nGrace Period: Expired" 2>/dev/null &
    fi
    
    echo "🚨 EMERGENCY: Monitor killed '$app_name' (${target_pcpu}% CPU) after grace period - Final trigger: $trigger_reason ($trigger_value)" | wall 2>/dev/null || true
    
    # Kill process
    kill -TERM "$target_pid" 2>/dev/null || true
    sleep "${KILL_PROCESS_WAIT_TIME:-2}"
    if kill -0 "$target_pid" 2>/dev/null; then
        kill -KILL "$target_pid" 2>/dev/null || true
    fi
    
    # Clean up grace tracking files
    rm -f "$grace_file" "${grace_file}.requests"
    
    log "AUTOFIX: Process terminated successfully"
    return 0
}

# Cleanup function for old grace files
cleanup_old_grace_files() {
    find "$GRACE_DIR" -name "kill_*" -mtime +1 -delete 2>/dev/null || true
}

# Clean up old files on startup
cleanup_old_grace_files

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trigger_reason="${1:-emergency}"
    trigger_value="${2:-unknown}"
    grace_seconds="${3:-45}"
    calling_module="${4:-direct}"
    emergency_process_kill "$trigger_reason" "$trigger_value" "$grace_seconds" "$calling_module"
fi
