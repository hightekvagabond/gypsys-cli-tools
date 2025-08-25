#!/bin/bash
# Emergency Process Kill Autofix Script
# Usage: emergency-process-kill.sh <calling_module> <grace_period_seconds> [trigger_reason] [trigger_value]
# Handles kill requests from multiple monitors with intelligent grace period tracking

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Load modules common.sh for helper functions like get_top_cpu_processes
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/modules/common.sh"

# Validate arguments
if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1
fi

CALLING_MODULE="$1"
GRACE_PERIOD="$2"
TRIGGER_REASON="${3:-emergency}"
TRIGGER_VALUE="${4:-unknown}"

# Load autofix configuration
AUTOFIX_CONFIG="$PROJECT_ROOT/config/autofix.conf"
if [[ -f "$AUTOFIX_CONFIG" ]]; then
    source "$AUTOFIX_CONFIG"
fi

# Check if a process is system critical
is_system_critical_process() {
    local pid="$1"
    local cmd="$2"
    
    # Skip kernel threads (processes in brackets)
    if [[ "$cmd" =~ ^\[.*\]$ ]]; then
        return 0  # Critical
    fi
    
    # Skip essential system processes
    case "$cmd" in
        systemd|init|kthreadd|ksoftirqd|rcu_*|watchdog|migration|systemd-*|dbus|NetworkManager|sshd)
            return 0  # Critical
            ;;
        */systemd|*/init|*/dbus|*/NetworkManager|*/sshd)
            return 0  # Critical
            ;;
    esac
    
    # Skip processes with PID 1, 2, or in the first 100 PIDs (likely system)
    if [[ $pid -le 100 ]]; then
        return 0  # Critical
    fi
    
    return 1  # Not critical
}

# The actual emergency process kill action
perform_emergency_process_kill() {
    local trigger_reason="$1"
    local trigger_value="$2"
    
    autofix_log "INFO" "Emergency process kill request - Trigger: $trigger_reason ($trigger_value)"
    
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
                autofix_log "DEBUG" "Skipping critical process: PID $pid ($cmd)"
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
        autofix_log "WARN" "No suitable processes found for emergency kill (all processes below ${PROCESS_CPU_THRESHOLD:-10}% CPU or critical)"
        return 0  # Not an error - just no targets
    fi
    
    local app_name=$(basename "$target_cmd" | cut -d' ' -f1)
    autofix_log "INFO" "Target identified: $app_name (PID $target_pid, ${target_pcpu}% CPU)"
    
    # Check current status
    if ! kill -0 "$target_pid" 2>/dev/null; then
        autofix_log "INFO" "Target process PID $target_pid no longer exists"
        return 0
    fi
    
    # Re-check CPU usage to make sure it's still high
    local current_cpu
    current_cpu=$(ps -p "$target_pid" -o %cpu= 2>/dev/null | tr -d ' ' || echo "0")
    local current_cpu_int=$(echo "$current_cpu" | cut -d. -f1)
    
    if [[ $current_cpu_int -lt ${PROCESS_CPU_THRESHOLD:-10} ]]; then
        autofix_log "INFO" "Target process CPU usage dropped to $current_cpu% - no longer a threat"
        return 0
    fi
    
    # Send notifications before kill
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical "Emergency Process Kill" "Killing: $app_name (${current_cpu}% CPU)\nReason: $trigger_reason\nCaller: $CALLING_MODULE" 2>/dev/null || true
    fi
    
    autofix_log "INFO" "Terminating PID $target_pid ($app_name) - ${current_cpu}% CPU - trigger: $trigger_reason"
    
    # Try graceful termination first
    if kill -TERM "$target_pid" 2>/dev/null; then
        autofix_log "INFO" "Sent SIGTERM to PID $target_pid"
        
        # Wait for graceful shutdown
        local wait_time="${KILL_PROCESS_WAIT_TIME:-3}"
        sleep "$wait_time"
        
        # Check if process still exists
        if kill -0 "$target_pid" 2>/dev/null; then
            autofix_log "WARN" "Process PID $target_pid still running after SIGTERM, sending SIGKILL"
            if kill -KILL "$target_pid" 2>/dev/null; then
                autofix_log "INFO" "Sent SIGKILL to PID $target_pid"
            else
                autofix_log "ERROR" "Failed to send SIGKILL to PID $target_pid"
                return 1
            fi
        else
            autofix_log "INFO" "Process PID $target_pid terminated gracefully"
        fi
    else
        autofix_log "ERROR" "Failed to send SIGTERM to PID $target_pid"
        return 1
    fi
    
    # Final verification
    sleep 1
    if kill -0 "$target_pid" 2>/dev/null; then
        autofix_log "ERROR" "Process PID $target_pid still running after both SIGTERM and SIGKILL"
        return 1
    else
        autofix_log "INFO" "Process $app_name (PID $target_pid) successfully terminated"
        
        # Send success notification
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "Emergency Kill Complete" "Successfully terminated: $app_name\nCPU usage: ${current_cpu}%\nReason: $trigger_reason" 2>/dev/null || true
        fi
        
        return 0
    fi
}

# Execute with grace period management
autofix_log "INFO" "Emergency process kill requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "emergency-process-kill" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_emergency_process_kill" "$TRIGGER_REASON" "$TRIGGER_VALUE"