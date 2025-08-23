#!/bin/bash
# Memory monitoring module

MODULE_NAME="memory"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

check_status() {
    local memory_usage
    memory_usage=$(get_memory_usage)
    
    if [[ $memory_usage -ge ${MEMORY_CRITICAL:-95} ]]; then
        send_alert "critical" "🧠 Critical memory usage: ${memory_usage}% (OOM risk)"
        show_memory_hogs
        return 1
    elif [[ $memory_usage -ge ${MEMORY_WARNING:-85} ]]; then
        send_alert "warning" "🧠 High memory usage: ${memory_usage}%"
        return 1
    fi
    
    log "Memory usage normal: ${memory_usage}%"
    return 0
}

get_memory_usage() {
    # Get memory usage percentage
    local mem_info
    mem_info=$(free | grep '^Mem:')
    local total used
    total=$(echo "$mem_info" | awk '{print $2}')
    used=$(echo "$mem_info" | awk '{print $3}')
    
    if [[ $total -gt 0 ]]; then
        echo $(( (used * 100) / total ))
    else
        echo "0"
    fi
}

show_memory_hogs() {
    log "Top memory consuming processes:"
    get_top_memory_processes | while IFS= read -r line; do
        log "  $line"
    done
}

# Module validation
validate_module "$MODULE_NAME"

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_status
fi
