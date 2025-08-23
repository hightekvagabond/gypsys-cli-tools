#!/bin/bash
# Modular Monitor Status Checker (with recovered functionality)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/modules/common.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}🛡️  MODULAR MONITOR STATUS${NC}"
    echo -e "${BLUE}   (including recovered i915 & system monitoring)${NC}"
    echo "========================================================"
}

check_systemd_status() {
    echo -e "\n${BLUE}SYSTEMD SERVICES:${NC}"
    
    local service="modular-monitor"
    
    # Check timer
    if systemctl is-active "${service}.timer" >/dev/null 2>&1; then
        echo -e "${GREEN}  ✅ Timer: ACTIVE${NC}"
    else
        echo -e "${RED}  ❌ Timer: INACTIVE${NC}"
    fi
    
    # Check if enabled
    if systemctl is-enabled "${service}.timer" >/dev/null 2>&1; then
        echo -e "${GREEN}  ✅ Timer: ENABLED${NC}"
    else
        echo -e "${RED}  ❌ Timer: DISABLED${NC}"
    fi
    
    # Show next run
    local next_run
    next_run=$(systemctl list-timers "${service}.timer" --no-pager 2>/dev/null | grep "${service}.timer" | awk '{print $1, $2, $3}' || echo "Unknown")
    echo -e "${BLUE}  📅 Next run: $next_run${NC}"
    
    # Recent activity
    local last_run
    last_run=$(journalctl -t modular-monitor --since "1 hour ago" --no-pager | tail -1 | awk '{print $1, $2, $3}' || echo "No recent activity")
    echo -e "${BLUE}  📊 Last activity: $last_run${NC}"
}

test_modules() {
    echo -e "\n${BLUE}MODULE TESTS:${NC}"
    
    local modules=("thermal-monitor" "usb-monitor" "memory-monitor" "i915-monitor" "system-monitor")
    local failed=0
    
    for module in "${modules[@]}"; do
        if [[ -f "$SCRIPT_DIR/modules/${module}.sh" ]]; then
            if bash "$SCRIPT_DIR/orchestrator.sh" --test "$module" >/dev/null 2>&1; then
                echo -e "${GREEN}  ✅ $module: OK${NC}"
            else
                echo -e "${RED}  ❌ $module: FAILED${NC}"
                failed=1
            fi
        else
            echo -e "${RED}  ❌ $module: MISSING${NC}"
            failed=1
        fi
    done
    
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}  🎉 All modules working (including recovered functionality)${NC}"
    fi
}

show_current_readings() {
    echo -e "\n${BLUE}CURRENT READINGS:${NC}"
    
    # Temperature
    local temp
    temp=$(get_cpu_package_temp)
    if [[ "$temp" != "unknown" ]]; then
        local temp_int
        temp_int=$(echo "$temp" | cut -d. -f1)
        if [[ $temp_int -lt 70 ]]; then
            echo -e "${GREEN}  🌡️  CPU Temperature: ${temp}°C (NORMAL)${NC}"
        elif [[ $temp_int -lt 85 ]]; then
            echo -e "${YELLOW}  🌡️  CPU Temperature: ${temp}°C (ELEVATED)${NC}"
        else
            echo -e "${RED}  🌡️  CPU Temperature: ${temp}°C (HIGH)${NC}"
        fi
    else
        echo -e "${YELLOW}  🌡️  CPU Temperature: Unknown${NC}"
    fi
    
    # Memory
    if command -v free >/dev/null 2>&1; then
        local mem_usage
        mem_usage=$(free | grep '^Mem:' | awk '{printf "%.1f", ($3/$2) * 100}')
        local mem_int
        mem_int=$(echo "$mem_usage" | cut -d. -f1)
        if [[ $mem_int -lt 80 ]]; then
            echo -e "${GREEN}  🧠 Memory Usage: ${mem_usage}% (NORMAL)${NC}"
        elif [[ $mem_int -lt 90 ]]; then
            echo -e "${YELLOW}  🧠 Memory Usage: ${mem_usage}% (HIGH)${NC}"
        else
            echo -e "${RED}  🧠 Memory Usage: ${mem_usage}% (CRITICAL)${NC}"
        fi
    fi
    
    # i915 Status
    local i915_errors
    i915_errors=$(journalctl --since "1 hour ago" --no-pager 2>/dev/null | grep -c -E "i915.*ERROR|workqueue: i915" || echo "0")
    if [[ $i915_errors -eq 0 ]]; then
        echo -e "${GREEN}  🎮 i915 GPU: No recent errors${NC}"
    else
        echo -e "${YELLOW}  🎮 i915 GPU: $i915_errors errors in last hour${NC}"
    fi
    
    # System Load
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | sed 's/^ *//')
    echo -e "${BLUE}  ⚡ System Load: $load_avg${NC}"
    
    # Uptime
    local uptime_info
    uptime_info=$(uptime -p 2>/dev/null || uptime)
    echo -e "${BLUE}  ⏱️  System uptime: $uptime_info${NC}"
}

show_recent_alerts() {
    echo -e "\n${BLUE}RECENT ALERTS (last hour):${NC}"
    
    local alerts
    alerts=$(journalctl -t modular-monitor --since "1 hour ago" --no-pager | grep -i "alert\|critical\|warning\|emergency" | tail -5 || echo "")
    
    if [[ -n "$alerts" ]]; then
        echo "$alerts" | while IFS= read -r line; do
            echo -e "${YELLOW}  ⚠️  $line${NC}"
        done
    else
        echo -e "${GREEN}  ✅ No alerts in the last hour${NC}"
    fi
}

show_recovered_features() {
    echo -e "\n${BLUE}RECOVERED FEATURES STATUS:${NC}"
    
    # i915 Module
    if [[ -f "$SCRIPT_DIR/modules/i915-monitor.sh" ]]; then
        echo -e "${GREEN}  ✅ i915 GPU monitoring: RECOVERED${NC}"
    else
        echo -e "${RED}  ❌ i915 GPU monitoring: MISSING${NC}"
    fi
    
    # System Module
    if [[ -f "$SCRIPT_DIR/modules/system-monitor.sh" ]]; then
        echo -e "${GREEN}  ✅ Comprehensive system monitoring: RECOVERED${NC}"
    else
        echo -e "${RED}  ❌ Comprehensive system monitoring: MISSING${NC}"
    fi
    
    # Check if we have all original functionality
    local original_modules=("thermal-monitor" "usb-monitor" "memory-monitor" "i915-monitor" "system-monitor")
    local missing_count=0
    for module in "${original_modules[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/modules/${module}.sh" ]]; then
            missing_count=$((missing_count + 1))
        fi
    done
    
    if [[ $missing_count -eq 0 ]]; then
        echo -e "${GREEN}  🎉 ALL original functionality restored and modularized${NC}"
    else
        echo -e "${YELLOW}  ⚠️  $missing_count modules still missing${NC}"
    fi
}

main() {
    print_header
    
    # System uptime first
    local uptime_info
    uptime_info=$(uptime -p 2>/dev/null || uptime)
    echo -e "${BLUE}System uptime: $uptime_info${NC}"
    
    check_systemd_status
    test_modules  
    show_current_readings
    show_recovered_features
    show_recent_alerts
    
    echo -e "\n${BLUE}📋 QUICK COMMANDS:${NC}"
    echo "  Monitor logs: journalctl -t modular-monitor -f"
    echo "  Test i915:    $SCRIPT_DIR/orchestrator.sh --test i915-monitor"
    echo "  Test system:  $SCRIPT_DIR/orchestrator.sh --test system-monitor"
    echo "  Run manual:   $SCRIPT_DIR/orchestrator.sh"
}

main "$@"