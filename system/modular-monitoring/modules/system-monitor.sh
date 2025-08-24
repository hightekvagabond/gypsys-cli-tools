#!/bin/bash
# System health monitoring module (comprehensive monitoring)

MODULE_NAME="system"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# System monitoring thresholds
DISK_USAGE_WARN=80
DISK_USAGE_CRITICAL=90
MEMORY_AVAILABLE_WARN=20
MEMORY_AVAILABLE_CRITICAL=10
FAILED_SERVICES_WARN=1
CPU_LOAD_WARN=80

check_status() {
    local issues_found=0
    
    # Check all system health areas
    check_disk_usage || issues_found=1
    check_memory_availability || issues_found=1
    check_service_failures || issues_found=1
    check_hardware_errors || issues_found=1
    check_network_connectivity || issues_found=1
    check_cpu_load || issues_found=1
    
    if [[ $issues_found -eq 0 ]]; then
        log "System health check: all normal"
        return 0
    else
        log "System health check: issues detected"
        return 1
    fi
}

check_disk_usage() {
    local max_usage=0
    local critical_mount=""
    
    # Check all mounted filesystems
    while IFS= read -r line; do
        local usage mount
        usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        mount=$(echo "$line" | awk '{print $6}')
        
        if [[ "$usage" =~ ^[0-9]+$ ]] && [[ $usage -gt $max_usage ]]; then
            max_usage=$usage
            critical_mount=$mount
        fi
    done < <(df -h | grep -E '^/dev/')
    
    if [[ $max_usage -ge $DISK_USAGE_CRITICAL ]]; then
        send_alert "critical" "💾 Critical disk usage: ${max_usage}% on $critical_mount"
        return 1
    elif [[ $max_usage -ge $DISK_USAGE_WARN ]]; then
        send_alert "warning" "💾 High disk usage: ${max_usage}% on $critical_mount"
        return 1
    fi
    
    return 0
}

check_memory_availability() {
    local mem_info available_pct
    mem_info=$(free | grep '^Mem:')
    local total available
    total=$(echo "$mem_info" | awk '{print $2}')
    available=$(echo "$mem_info" | awk '{print $7}')
    
    if [[ $total -gt 0 ]]; then
        available_pct=$(( (available * 100) / total ))
    else
        available_pct=100
    fi
    
    if [[ $available_pct -le $MEMORY_AVAILABLE_CRITICAL ]]; then
        send_alert "critical" "🧠 Critical: Only ${available_pct}% memory available"
        show_memory_hogs
        return 1
    elif [[ $available_pct -le $MEMORY_AVAILABLE_WARN ]]; then
        send_alert "warning" "🧠 Low memory: ${available_pct}% available"
        return 1
    fi
    
    return 0
}

show_memory_hogs() {
    log "Top memory consumers:"
    get_top_memory_processes | head -5 | while IFS= read -r line; do
        log "  $line"
    done
}

check_service_failures() {
    local failed_services
    failed_services=$(systemctl list-units --failed --no-pager --no-legend | wc -l)
    
    if [[ $failed_services -ge $FAILED_SERVICES_WARN ]]; then
        local services_list
        services_list=$(systemctl list-units --failed --no-pager --no-legend | awk '{print $1}' | tr '\n' ' ')
        send_alert "warning" "⚙️ Failed services ($failed_services): $services_list"
        return 1
    fi
    
    return 0
}

check_hardware_errors() {
    local error_count=0
    local recent_errors
    
    # Check for hardware errors in recent logs
    recent_errors=$(dmesg | grep -i -E "error|fail|critical" | grep -v -E "thermal|usb.*reset" | tail -10 || echo "")
    
    if [[ -n "$recent_errors" ]]; then
        local error_lines
        error_lines=$(echo "$recent_errors" | wc -l)
        if [[ $error_lines -gt 5 ]]; then
            send_alert "warning" "🔧 Multiple hardware errors detected ($error_lines recent errors)"
            log "Recent hardware errors:"
            echo "$recent_errors" | while IFS= read -r line; do
                log "  $line"
            done
            return 1
        fi
    fi
    
    return 0
}

check_network_connectivity() {
    # Basic connectivity check
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        # Try alternate DNS
        if ! ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
            send_alert "warning" "🌐 Network connectivity issues detected"
            check_network_interfaces
            return 1
        fi
    fi
    
    return 0
}

check_network_interfaces() {
    log "Network interface status:"
    ip link show | grep -E "^[0-9]+:" | while IFS= read -r line; do
        log "  $line"
    done
}

check_cpu_load() {
    local load_avg cpu_count load_pct
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | sed 's/^ *//')
    cpu_count=$(nproc)
    
    # Calculate load percentage
    load_pct=$(echo "$load_avg $cpu_count" | awk '{printf "%.0f", ($1/$2)*100}')
    
    if [[ $load_pct -ge $CPU_LOAD_WARN ]]; then
        send_alert "warning" "⚡ High CPU load: ${load_pct}% (${load_avg} avg, ${cpu_count} cores)"
        show_cpu_hogs
        return 1
    fi
    
    return 0
}

show_cpu_hogs() {
    log "Top CPU consumers:"
    get_top_cpu_processes | head -5 | while IFS= read -r line; do
        log "  $line"
    done
}

# Module validation
validate_module "$MODULE_NAME"

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_status
fi
