#!/bin/bash
# Memory Cleanup Autofix Script
# Usage: memory-cleanup.sh <calling_module> <grace_period_seconds> [trigger_reason] [trigger_value]
# Attempts to free memory when usage is high

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize autofix script with common setup
init_autofix_script "$@"

# Additional arguments specific to this script
TRIGGER_REASON="${3:-memory}"
TRIGGER_VALUE="${4:-unknown}"

# Configuration loaded automatically via modules/common.sh

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

# The actual memory cleanup action
perform_memory_cleanup() {
    local trigger_reason="$1"
    local trigger_value="$2"
    
    autofix_log "INFO" "Memory cleanup initiated - Trigger: $trigger_reason ($trigger_value)"
    
    # Get current memory stats
    local mem_info
    mem_info=$(free -m)
    local total_mem=$(echo "$mem_info" | awk 'NR==2{print $2}')
    local used_mem=$(echo "$mem_info" | awk 'NR==2{print $3}')
    local free_mem=$(echo "$mem_info" | awk 'NR==2{print $4}')
    local available_mem=$(echo "$mem_info" | awk 'NR==2{print $7}')
    
    autofix_log "INFO" "Memory status - Total: ${total_mem}MB, Used: ${used_mem}MB, Free: ${free_mem}MB, Available: ${available_mem}MB"
    
    # Safe memory cleanup actions
    local cleanup_success=false
    
    # 1. Drop caches (requires root, but safe)
    if [[ ${ENABLE_CACHE_DROP:-true} == "true" ]]; then
        autofix_log "INFO" "Attempting to drop system caches..."
        
        if [[ $EUID -eq 0 ]]; then
            # Running as root - can drop caches directly
            if sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null; then
                autofix_log "INFO" "System caches dropped successfully"
                cleanup_success=true
            else
                autofix_log "ERROR" "Failed to drop system caches"
            fi
        else
            # Not running as root - provide recommendation
            autofix_log "WARN" "Cache drop requires root privileges - providing recommendation"
            autofix_log "INFO" "RECOMMENDATION: Run 'sudo sync && sudo sh -c \"echo 3 > /proc/sys/vm/drop_caches\"' to drop caches"
            
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "Memory Cleanup" "Cache drop recommended (requires root): sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'" 2>/dev/null || true
            fi
        fi
    fi
    
    # 2. Find and analyze memory-heavy processes
    autofix_log "INFO" "Analyzing memory-heavy processes..."
    local memory_hogs=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            memory_hogs+=("$line")
        fi
    done < <(get_top_memory_processes | head -5)
    
    if [[ ${#memory_hogs[@]} -gt 0 ]]; then
        autofix_log "INFO" "Top memory-consuming processes:"
        for process in "${memory_hogs[@]}"; do
            autofix_log "INFO" "  $process"
        done
        
        # Look for processes that are safe to restart/kill
        local killable_processes=()
        for process_line in "${memory_hogs[@]}"; do
            local pid=$(echo "$process_line" | awk '{print $1}')
            local mem_percent=$(echo "$process_line" | awk '{print $2}')
            local command=$(echo "$process_line" | awk '{print $3}')
            
            # Skip if not a valid PID
            if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
                continue
            fi
            
            # Skip critical system processes
            if is_system_critical_process "$pid" "$command"; then
                autofix_log "DEBUG" "Skipping critical process: PID $pid ($command)"
                continue
            fi
            
            # Consider processes using significant memory
            local mem_int=$(echo "$mem_percent" | cut -d. -f1)
            if [[ $mem_int -ge ${MEMORY_KILL_THRESHOLD:-15} ]]; then
                killable_processes+=("$pid:$mem_percent:$command")
            fi
        done
        
        # If we have killable processes and emergency mode is enabled
        if [[ ${#killable_processes[@]} -gt 0 && ${ENABLE_EMERGENCY_MEMORY_KILL:-false} == "true" ]]; then
            # Kill the most memory-hungry non-critical process
            local target_process="${killable_processes[0]}"
            local target_pid=$(echo "$target_process" | cut -d: -f1)
            local target_mem=$(echo "$target_process" | cut -d: -f2)
            local target_cmd=$(echo "$target_process" | cut -d: -f3)
            local app_name=$(basename "$target_cmd" | cut -d' ' -f1)
            
            autofix_log "INFO" "Emergency terminating high-memory process: PID $target_pid ($app_name) - ${target_mem}% memory"
            
            # Send notification before kill
            if command -v notify-send >/dev/null 2>&1; then
                notify-send -u critical "Memory Emergency Kill" "Killing: $app_name (${target_mem}% memory)\nReason: $trigger_reason\nCaller: $CALLING_MODULE" 2>/dev/null || true
            fi
            
            # Kill the process
            if kill -TERM "$target_pid" 2>/dev/null; then
                autofix_log "INFO" "Sent SIGTERM to PID $target_pid"
                sleep "${KILL_PROCESS_WAIT_TIME:-2}"
                if kill -0 "$target_pid" 2>/dev/null; then
                    autofix_log "WARN" "Process still running, sending SIGKILL"
                    kill -KILL "$target_pid" 2>/dev/null || true
                fi
            else
                autofix_log "ERROR" "Failed to terminate process PID $target_pid"
            fi
            
            cleanup_success=true
            autofix_log "INFO" "Memory cleanup process termination completed"
        else
            autofix_log "INFO" "Emergency memory kill disabled or no suitable processes found"
            if [[ ${#killable_processes[@]} -gt 0 ]]; then
                autofix_log "INFO" "RECOMMENDATION: Consider terminating high-memory processes manually if memory pressure persists"
            fi
        fi
    fi
    
    # 3. Analyze swap usage
    local swap_info
    swap_info=$(free -m | grep Swap)
    if [[ -n "$swap_info" ]]; then
        local swap_total=$(echo "$swap_info" | awk '{print $2}')
        local swap_used=$(echo "$swap_info" | awk '{print $3}')
        
        if [[ $swap_total -gt 0 && $swap_used -gt 0 ]]; then
            local swap_percent=$((swap_used * 100 / swap_total))
            autofix_log "INFO" "Swap usage: ${swap_used}MB/${swap_total}MB (${swap_percent}%)"
            
            if [[ $swap_percent -ge ${SWAP_WARNING_THRESHOLD:-50} ]]; then
                autofix_log "WARN" "High swap usage detected - system may be thrashing"
                
                if command -v notify-send >/dev/null 2>&1; then
                    notify-send "High Swap Usage" "Swap: ${swap_percent}% - performance may be degraded" 2>/dev/null || true
                fi
            fi
        fi
    fi
    
    # Get updated memory stats after cleanup
    sleep 2  # Allow time for cleanup effects
    mem_info=$(free -m)
    local new_available=$(echo "$mem_info" | awk 'NR==2{print $7}')
    local freed_memory=$((new_available - available_mem))
    
    if [[ $freed_memory -gt 0 ]]; then
        autofix_log "INFO" "Memory cleanup freed approximately ${freed_memory}MB"
        
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "Memory Cleanup Complete" "Freed ~${freed_memory}MB of memory" 2>/dev/null || true
        fi
    else
        autofix_log "INFO" "Memory cleanup completed (no significant memory freed)"
    fi
    
    autofix_log "INFO" "Memory cleanup procedure completed"
    return 0  # Always return success - we've done what we can
}

# Execute with grace period management
autofix_log "INFO" "Memory cleanup requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "memory-cleanup" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_memory_cleanup" "$TRIGGER_REASON" "$TRIGGER_VALUE"