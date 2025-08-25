#!/bin/bash
# Generic Memory Cleanup Autofix
# Attempts to free memory when usage is high
# Can be triggered by memory, swap, or performance-related conditions

# Get the project root directory
AUTOFIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$AUTOFIX_DIR")"
source "$PROJECT_ROOT/modules/common.sh"

memory_cleanup() {
    local trigger_reason="${1:-memory}"
    local trigger_value="${2:-unknown}"
    local calling_module="${3:-unknown}"
    
    log "AUTOFIX: Memory cleanup initiated - Trigger: $trigger_reason ($trigger_value) from $calling_module module"
    
    # Load global autofix configuration
    local autofix_config="$PROJECT_ROOT/config/autofix.conf"
    if [[ -f "$autofix_config" ]]; then
        source "$autofix_config"
    fi
    
    # Get current memory stats
    local mem_info
    mem_info=$(free -m)
    local total_mem=$(echo "$mem_info" | awk 'NR==2{print $2}')
    local used_mem=$(echo "$mem_info" | awk 'NR==2{print $3}')
    local free_mem=$(echo "$mem_info" | awk 'NR==2{print $4}')
    local available_mem=$(echo "$mem_info" | awk 'NR==2{print $7}')
    
    log "AUTOFIX: Memory status - Total: ${total_mem}MB, Used: ${used_mem}MB, Free: ${free_mem}MB, Available: ${available_mem}MB"
    
    # Safe memory cleanup actions
    local cleanup_success=false
    
    # 1. Drop caches (requires root, but safe)
    if [[ ${ENABLE_CACHE_DROP:-true} == "true" ]]; then
        log "AUTOFIX: Attempting to drop system caches..."
        if sync && echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1; then
            log "AUTOFIX: System caches dropped successfully"
            cleanup_success=true
        else
            log "AUTOFIX: Cache drop failed (requires root privileges)"
        fi
    fi
    
    # 2. Find and suggest memory-heavy processes for termination
    log "AUTOFIX: Analyzing memory-heavy processes..."
    local memory_hogs=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            memory_hogs+=("$line")
        fi
    done < <(get_top_memory_processes | head -5)
    
    if [[ ${#memory_hogs[@]} -gt 0 ]]; then
        log "AUTOFIX: Top memory-consuming processes:"
        for process in "${memory_hogs[@]}"; do
            log "AUTOFIX:   $process"
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
                log "AUTOFIX: Skipping critical process: PID $pid ($command)"
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
            
            log "AUTOFIX: Emergency terminating high-memory process: PID $target_pid ($app_name) - ${target_mem}% memory"
            send_alert "warning" "🧠 MEMORY: Killed '$app_name' (${target_mem}% memory) due to $trigger_reason"
            
            # Kill the process
            kill -TERM "$target_pid" 2>/dev/null || true
            sleep "${KILL_PROCESS_WAIT_TIME:-2}"
            if kill -0 "$target_pid" 2>/dev/null; then
                kill -KILL "$target_pid" 2>/dev/null || true
            fi
            
            cleanup_success=true
            log "AUTOFIX: Process terminated successfully"
        else
            log "AUTOFIX: Emergency memory kill disabled or no suitable processes found"
        fi
    fi
    
    # 3. Suggest swap management
    local swap_info
    swap_info=$(free -m | grep Swap)
    if [[ -n "$swap_info" ]]; then
        local swap_total=$(echo "$swap_info" | awk '{print $2}')
        local swap_used=$(echo "$swap_info" | awk '{print $3}')
        
        if [[ $swap_total -gt 0 && $swap_used -gt 0 ]]; then
            local swap_percent=$((swap_used * 100 / swap_total))
            log "AUTOFIX: Swap usage: ${swap_used}MB/${swap_total}MB (${swap_percent}%)"
            
            if [[ $swap_percent -ge ${SWAP_WARNING_THRESHOLD:-50} ]]; then
                log "AUTOFIX: High swap usage detected - system may be thrashing"
                send_alert "warning" "🔄 SWAP: High swap usage ${swap_percent}% - performance may be degraded"
            fi
        fi
    fi
    
    # Get updated memory stats after cleanup
    mem_info=$(free -m)
    local new_available=$(echo "$mem_info" | awk 'NR==2{print $7}')
    local freed_memory=$((new_available - available_mem))
    
    if [[ $freed_memory -gt 0 ]]; then
        log "AUTOFIX: Memory cleanup freed approximately ${freed_memory}MB"
        send_alert "info" "🧠 Memory cleanup completed - freed ~${freed_memory}MB"
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trigger_reason="${1:-memory}"
    trigger_value="${2:-unknown}"
    calling_module="${3:-direct}"
    memory_cleanup "$trigger_reason" "$trigger_value" "$calling_module"
fi

