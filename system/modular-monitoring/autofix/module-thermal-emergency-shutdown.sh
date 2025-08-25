#!/bin/bash
# Thermal Emergency Shutdown Autofix
# Initiates clean shutdown when no killable processes are found during thermal crisis

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Source module config
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

emergency_shutdown() {
    local temp="$1"
    
    log "AUTOFIX: Initiating system shutdown - thermal crisis at ${temp}°C"
    send_alert "emergency" "🚨 SYSTEM SHUTDOWN: Thermal crisis at ${temp}°C - no killable processes found"
    
    # Create emergency diagnostic dump
    create_emergency_dump "$temp"
    
    # Initiate shutdown
    log "AUTOFIX: Executing clean shutdown"
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

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    temp="${1:-unknown}"
    emergency_shutdown "$temp"
fi
