#!/bin/bash
# Modular Monitor Status Checker (with recovered functionality)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/modules/common.sh"

# Check if running as root for optimal monitoring tests
check_sudo_recommendation() {
    if [[ $EUID -ne 0 ]] && [[ "${SKIP_SUDO_CHECK:-}" != "true" ]]; then
        echo -e "${YELLOW}⚠️  Notice: Running as non-root user${NC}"
        echo -e "${YELLOW}   Some module tests may show permission errors (this is normal)${NC}"
        echo -e "${YELLOW}   For complete testing, run: sudo ./status.sh${NC}"
        echo -e "${YELLOW}   Or export SKIP_SUDO_CHECK=true to hide this notice${NC}"
        echo
    fi
}

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
    local since_time="$1"
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
    
    # Recent activity (use since_time if provided)
    local last_run
    local time_filter="${since_time:-1 hour ago}"
    last_run=$(journalctl -t modular-monitor --since "$time_filter" --no-pager | tail -1 | awk '{print $1, $2, $3}' || echo "No activity since $time_filter")
    echo -e "${BLUE}  📊 Last activity: $last_run${NC}"
}

test_modules() {
    echo -e "\n${BLUE}MODULE TESTS:${NC}"
    
    local modules=("thermal-monitor" "usb-monitor" "memory-monitor" "i915-monitor" "system-monitor")
    local missing=0
    local working=0
    local errors=0
    
    for module in "${modules[@]}"; do
        if [[ -f "$SCRIPT_DIR/modules/${module}.sh" ]]; then
            # Run the module test and capture both exit code and output
            local test_output
            local exit_code
            set +e  # Temporarily disable exit on error
            test_output=$(bash "$SCRIPT_DIR/orchestrator.sh" --test "$module" 2>&1)
            exit_code=$?
            set -e  # Re-enable exit on error
            
            # Check for actual module errors (not monitoring results)
            if echo "$test_output" | grep -q "No such file\|command not found\|syntax error\|bash.*line.*:" 2>/dev/null; then
                echo -e "${RED}  ❌ $module: ERROR (module malfunction)${NC}"
                errors=$((errors + 1))
            # Check for successful monitoring (including detecting issues or permission errors during fixes)
            elif echo "$test_output" | grep -q "OK\|ISSUES DETECTED\|Permission denied" 2>/dev/null; then
                if echo "$test_output" | grep -q "ISSUES DETECTED" 2>/dev/null; then
                    echo -e "${GREEN}  ✅ $module: MONITORING (issues detected - working correctly)${NC}"
                else
                    echo -e "${GREEN}  ✅ $module: MONITORING (system normal)${NC}"
                fi
                working=$((working + 1))
            else
                echo -e "${YELLOW}  ⚠️  $module: UNKNOWN (check manually)${NC}"
            fi
        else
            echo -e "${RED}  ❌ $module: MISSING${NC}"
            missing=$((missing + 1))
        fi
    done
    
    if [[ $missing -eq 0 && $errors -eq 0 ]]; then
        echo -e "${GREEN}  🎉 All $working modules operational (monitoring system working correctly)${NC}"
    elif [[ $errors -gt 0 ]]; then
        echo -e "${RED}  ⚠️  $errors modules have errors, $working working${NC}"
    elif [[ $missing -gt 0 ]]; then
        echo -e "${YELLOW}  ⚠️  $missing modules missing, $working working${NC}"
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

check_incident_analysis() {
    echo -e "\n${BLUE}🔍 INCIDENT ANALYSIS:${NC}"
    
    # Check if this is a recent boot (less than 10 minutes)
    local uptime_seconds
    uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 3600)
    
    if [[ $uptime_seconds -lt 600 ]]; then
        echo -e "${YELLOW}  ⚠️  Recent boot detected (uptime: $((uptime_seconds / 60)) minutes)${NC}"
        analyze_pre_shutdown_events
    else
        echo -e "${GREEN}  ✅ No recent incidents detected (uptime: $((uptime_seconds / 60)) minutes)${NC}"
    fi
}

analyze_pre_shutdown_events() {
    echo -e "\n${BLUE}📊 PRE-SHUTDOWN ANALYSIS:${NC}"
    
    # Get the previous boot's logs
    local previous_boot_logs
    previous_boot_logs=$(journalctl -b -1 --no-pager 2>/dev/null | tail -100 || echo "")
    
    if [[ -z "$previous_boot_logs" ]]; then
        echo -e "${YELLOW}  ⚠️  Unable to access previous boot logs${NC}"
        return
    fi
    
    # Check for emergency shutdown by monitor
    local emergency_shutdown
    emergency_shutdown=$(echo "$previous_boot_logs" | grep -i "SYSTEM SHUTDOWN.*Thermal crisis\|emergency.*shutdown" | tail -1 || echo "")
    
    if [[ -n "$emergency_shutdown" ]]; then
        echo -e "${RED}  🚨 EMERGENCY SHUTDOWN DETECTED:${NC}"
        echo "    $(echo "$emergency_shutdown" | sed 's/^.*modular-monitor//' | cut -c1-80)"
        analyze_thermal_emergency "$previous_boot_logs"
        return
    fi
    
    # Check for critical alerts before shutdown
    local critical_alerts
    critical_alerts=$(echo "$previous_boot_logs" | grep "ALERT\[critical\]" | tail -5 || echo "")
    
    if [[ -n "$critical_alerts" ]]; then
        echo -e "${RED}  🔥 CRITICAL ALERTS BEFORE SHUTDOWN:${NC}"
        echo "$critical_alerts" | while read -r alert; do
            local timestamp=$(echo "$alert" | awk '{print $1, $2, $3}')
            local message=$(echo "$alert" | sed 's/^.*ALERT\[critical\]://')
            echo -e "${RED}    [$timestamp]${NC}$message"
        done
    fi
    
    # Check for hardware errors before shutdown
    analyze_hardware_patterns "$previous_boot_logs"
    
    # Check for thermal events
    analyze_thermal_patterns "$previous_boot_logs"
    
    # Check for USB issues
    analyze_usb_patterns "$previous_boot_logs"
    
    # Check for process kills
    analyze_process_kills "$previous_boot_logs"
}

analyze_thermal_emergency() {
    local logs="$1"
    
    # Look for temperature readings before shutdown
    local temp_readings
    temp_readings=$(echo "$logs" | grep -i "temperature\|thermal\|°C" | tail -3 || echo "")
    
    if [[ -n "$temp_readings" ]]; then
        echo -e "${RED}  🌡️  THERMAL READINGS BEFORE SHUTDOWN:${NC}"
        echo "$temp_readings" | while read -r reading; do
            echo "    $(echo "$reading" | sed 's/^.*modular-monitor//' | cut -c1-80)"
        done
    fi
    
    # Look for killed processes
    local killed_processes
    killed_processes=$(echo "$logs" | grep -i "killed.*PID\|terminated.*process" | tail -3 || echo "")
    
    if [[ -n "$killed_processes" ]]; then
        echo -e "${RED}  ⚔️  PROCESSES KILLED:${NC}"
        echo "$killed_processes" | while read -r kill; do
            echo "    $(echo "$kill" | sed 's/^.*modular-monitor//' | cut -c1-80)"
        done
    fi
}

analyze_hardware_patterns() {
    local logs="$1"
    
    # Count different types of hardware errors
    local i915_errors usb_errors network_errors
    i915_errors=$(echo "$logs" | grep "i915.*ERROR\|drm.*ERROR" 2>/dev/null | wc -l)
    usb_errors=$(echo "$logs" | grep "usb.*reset\|USB disconnect" 2>/dev/null | wc -l)
    network_errors=$(echo "$logs" | grep "network.*error\|ethernet.*fail" 2>/dev/null | wc -l)
    
    # Ensure we have valid numbers
    [[ -z "$i915_errors" || ! "$i915_errors" =~ ^[0-9]+$ ]] && i915_errors=0
    [[ -z "$usb_errors" || ! "$usb_errors" =~ ^[0-9]+$ ]] && usb_errors=0
    [[ -z "$network_errors" || ! "$network_errors" =~ ^[0-9]+$ ]] && network_errors=0
    
    if [[ $i915_errors -gt 0 || $usb_errors -gt 0 || $network_errors -gt 0 ]]; then
        echo -e "${YELLOW}  ⚠️  HARDWARE ERROR SUMMARY:${NC}"
        [[ $i915_errors -gt 0 ]] && echo "    🎮 i915 GPU errors: $i915_errors"
        [[ $usb_errors -gt 0 ]] && echo "    🔌 USB errors: $usb_errors"
        [[ $network_errors -gt 0 ]] && echo "    🌐 Network errors: $network_errors"
    fi
}

analyze_thermal_patterns() {
    local logs="$1"
    
    # Look for high temperature warnings
    local thermal_warnings
    thermal_warnings=$(echo "$logs" | grep -i "temperature.*warning\|thermal.*critical\|°C.*high" 2>/dev/null | wc -l)
    [[ -z "$thermal_warnings" || ! "$thermal_warnings" =~ ^[0-9]+$ ]] && thermal_warnings=0
    
    if [[ $thermal_warnings -gt 0 ]]; then
        echo -e "${YELLOW}  🌡️  THERMAL WARNINGS: $thermal_warnings events${NC}"
        
        # Show the last thermal reading
        local last_temp
        last_temp=$(echo "$logs" | grep -i "temperature.*[0-9][0-9]°C" | tail -1 | sed 's/^.*temperature[^0-9]*\([0-9]*\)°C.*/\1/' || echo "unknown")
        if [[ "$last_temp" != "unknown" && $last_temp -gt 0 ]]; then
            echo "    Last reading: ${last_temp}°C"
        fi
    fi
}

analyze_usb_patterns() {
    local logs="$1"
    
    # Count USB resets in the last session
    local usb_resets
    usb_resets=$(echo "$logs" | grep "USB device resets detected" 2>/dev/null | wc -l)
    [[ -z "$usb_resets" || ! "$usb_resets" =~ ^[0-9]+$ ]] && usb_resets=0
    
    if [[ $usb_resets -gt 0 ]]; then
        echo -e "${YELLOW}  🔌 USB RESET WARNINGS: $usb_resets alerts${NC}"
        
        # Get the last USB reset count
        local last_count
        last_count=$(echo "$logs" | grep "USB device resets detected" | tail -1 | sed 's/.*detected.*(\([0-9]*\).*/\1/' || echo "unknown")
        if [[ "$last_count" != "unknown" ]]; then
            echo "    Last count: $last_count resets"
        fi
    fi
}

analyze_process_kills() {
    local logs="$1"
    
    # Look for emergency process terminations
    local process_kills
    process_kills=$(echo "$logs" | grep -i "emergency.*killed\|terminated.*PID" 2>/dev/null | wc -l)
    [[ -z "$process_kills" || ! "$process_kills" =~ ^[0-9]+$ ]] && process_kills=0
    
    if [[ $process_kills -gt 0 ]]; then
        echo -e "${RED}  ⚔️  EMERGENCY PROCESS KILLS: $process_kills events${NC}"
        
        # Show what was killed
        local killed_apps
        killed_apps=$(echo "$logs" | grep -i "killed.*PID\|terminated.*process" | tail -2 | sed 's/^.*killed.*PID [0-9]* (\([^)]*\)).*/\1/' || echo "")
        if [[ -n "$killed_apps" ]]; then
            echo "$killed_apps" | while read -r app; do
                [[ -n "$app" ]] && echo "    Killed: $app"
            done
        fi
    fi
}

analyze_pre_shutdown_hour() {
    echo -e "${BLUE}🕐 PRE-SHUTDOWN HOUR ANALYSIS${NC}"
    echo "========================================================"
    
    # Find the last shutdown/boot time
    local current_boot_time
    local previous_shutdown_time
    
    # Get current boot time
    current_boot_time=$(journalctl -b 0 --no-pager -q --output=short-iso | head -1 | awk '{print $1}' 2>/dev/null || echo "")
    
    if [[ -z "$current_boot_time" ]]; then
        echo -e "${RED}❌ Unable to determine current boot time${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Current boot started: ${NC}$current_boot_time"
    
    # Find the last log entry before current boot (previous shutdown)
    local previous_logs
    previous_logs=$(journalctl -b -1 --no-pager -q --output=short-iso 2>/dev/null | tail -1 || echo "")
    
    if [[ -z "$previous_logs" ]]; then
        echo -e "${RED}❌ Unable to access previous boot logs${NC}"
        echo -e "${YELLOW}Try running with sudo for full log access${NC}"
        return 1
    fi
    
    # Extract the timestamp of the last log before shutdown
    previous_shutdown_time=$(echo "$previous_logs" | awk '{print $1}' || echo "")
    
    if [[ -z "$previous_shutdown_time" ]]; then
        echo -e "${RED}❌ Unable to determine previous shutdown time${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Previous shutdown around: ${NC}$previous_shutdown_time"
    
    # Calculate one hour before the shutdown
    local one_hour_before
    if command -v date >/dev/null 2>&1; then
        # Convert ISO timestamp to epoch, subtract 3600 seconds (1 hour), convert back
        local shutdown_epoch
        shutdown_epoch=$(date -d "$previous_shutdown_time" +%s 2>/dev/null || echo "")
        
        if [[ -n "$shutdown_epoch" ]]; then
            local hour_before_epoch=$((shutdown_epoch - 3600))
            one_hour_before=$(date -d "@$hour_before_epoch" --iso-8601=seconds 2>/dev/null || echo "")
        fi
    fi
    
    if [[ -z "$one_hour_before" ]]; then
        echo -e "${RED}❌ Unable to calculate time window${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Analyzing period: ${NC}$one_hour_before ${BLUE}to${NC} $previous_shutdown_time"
    echo
    
    # Run analysis on that time window using existing functions
    analyze_time_period "$one_hour_before" "$previous_shutdown_time"
}

analyze_time_period() {
    local start_time="$1"
    local end_time="$2"
    
    echo -e "${BLUE}📊 ACTIVITY ANALYSIS FOR TIME PERIOD:${NC}"
    
    # Get logs for the specific time period
    local period_logs
    period_logs=$(journalctl --since "$start_time" --until "$end_time" --no-pager 2>/dev/null || echo "")
    
    if [[ -z "$period_logs" ]]; then
        echo -e "${YELLOW}  ⚠️  No logs found for this time period${NC}"
        return
    fi
    
    # Monitor alerts during this period
    local monitor_alerts
    monitor_alerts=$(echo "$period_logs" | grep -i "modular-monitor.*ALERT" || echo "")
    
    if [[ -n "$monitor_alerts" ]]; then
        echo -e "${RED}🚨 MONITOR ALERTS DURING PERIOD:${NC}"
        echo "$monitor_alerts" | while read -r alert; do
            local timestamp=$(echo "$alert" | awk '{print $1, $2, $3}')
            local alert_type=$(echo "$alert" | sed -n 's/.*ALERT\[\([^]]*\)\].*/\1/p')
            local message=$(echo "$alert" | sed 's/^.*ALERT\[[^]]*\]://')
            echo -e "${RED}  [$timestamp] [$alert_type]${NC}$message"
        done
        echo
    fi
    
    # Check for hardware errors
    local hw_errors
    hw_errors=$(echo "$period_logs" | grep -c -i "hardware error\|machine check\|mce:" 2>/dev/null || echo "0")
    [[ -z "$hw_errors" || ! "$hw_errors" =~ ^[0-9]+$ ]] && hw_errors=0
    
    if [[ $hw_errors -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Hardware errors detected: $hw_errors${NC}"
    fi
    
    # Check for thermal events
    local thermal_events
    thermal_events=$(echo "$period_logs" | grep -c -i "thermal\|temperature\|overheating" 2>/dev/null || echo "0")
    [[ -z "$thermal_events" || ! "$thermal_events" =~ ^[0-9]+$ ]] && thermal_events=0
    
    if [[ $thermal_events -gt 0 ]]; then
        echo -e "${YELLOW}🌡️  Thermal events detected: $thermal_events${NC}"
    fi
    
    # Check for USB issues
    local usb_issues
    usb_issues=$(echo "$period_logs" | grep -c -i "usb.*reset\|usb disconnect\|device descriptor" 2>/dev/null || echo "0")
    [[ -z "$usb_issues" || ! "$usb_issues" =~ ^[0-9]+$ ]] && usb_issues=0
    
    if [[ $usb_issues -gt 0 ]]; then
        echo -e "${YELLOW}🔌 USB issues detected: $usb_issues${NC}"
        
        # Show recent USB issues
        echo "$period_logs" | grep -i "usb.*reset\|usb disconnect\|device descriptor" | tail -5 | while read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
            local usb_event=$(echo "$line" | sed 's/.*kernel: //')
            echo -e "${YELLOW}    [$timestamp] $usb_event${NC}"
        done
        echo
    fi
    
    # Check for i915 GPU errors
    local i915_errors
    i915_errors=$(echo "$period_logs" | grep -c -i "i915.*error\|workqueue.*i915" 2>/dev/null || echo "0")
    [[ -z "$i915_errors" || ! "$i915_errors" =~ ^[0-9]+$ ]] && i915_errors=0
    
    if [[ $i915_errors -gt 0 ]]; then
        echo -e "${YELLOW}🎮 i915 GPU errors detected: $i915_errors${NC}"
    fi
    
    # Check for memory issues
    local memory_issues
    memory_issues=$(echo "$period_logs" | grep -c -i "out of memory\|oom-killer\|memory pressure" 2>/dev/null || echo "0")
    [[ -z "$memory_issues" || ! "$memory_issues" =~ ^[0-9]+$ ]] && memory_issues=0
    
    if [[ $memory_issues -gt 0 ]]; then
        echo -e "${YELLOW}🧠 Memory issues detected: $memory_issues${NC}"
    fi
    
    # Summary
    local total_issues=$((hw_errors + thermal_events + usb_issues + i915_errors + memory_issues))
    
    if [[ $total_issues -eq 0 ]] && [[ -z "$monitor_alerts" ]]; then
        echo -e "${GREEN}✅ No significant issues detected during this period${NC}"
    else
        echo -e "${YELLOW}📊 Summary: $total_issues hardware/system issues detected${NC}"
        if [[ -n "$monitor_alerts" ]]; then
            local alert_count
            alert_count=$(echo "$monitor_alerts" | wc -l 2>/dev/null || echo "0")
            echo -e "${YELLOW}📊 Monitor alerts: $alert_count${NC}"
        fi
    fi
}

show_usb_analysis() {
    local since_time="$1"
    local time_filter="${since_time:-1 hour ago}"
    
    # Check if there are USB issues to analyze
    local usb_issues
    usb_issues=$(journalctl -t modular-monitor --since "$time_filter" --no-pager 2>/dev/null | grep -c "USB device resets detected" || echo "0")
    
    if [[ $usb_issues -gt 0 ]]; then
        echo -e "\n${BLUE}🔌 USB DEVICE ANALYSIS:${NC}"
        
        # Source the USB monitoring functions
        if [[ -f "$SCRIPT_DIR/modules/usb-monitor.sh" ]]; then
            source "$SCRIPT_DIR/modules/usb-monitor.sh"
            
            # Run USB device analysis
            if [[ $EUID -eq 0 ]]; then
                get_usb_device_details "$time_filter"
            else
                echo -e "${YELLOW}  ⚠️  Detailed USB analysis requires root access${NC}"
                echo -e "${YELLOW}  Run: sudo ./status.sh --since '$time_filter' for device details${NC}"
                
                # Show basic info we can get without root
                echo "  Recent USB alerts:"
                journalctl -t modular-monitor --since "$time_filter" --no-pager 2>/dev/null | grep "USB device resets" | tail -3 | while read -r line; do
                    local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
                    local message=$(echo "$line" | sed 's/.*USB device resets detected.*/USB resets detected/')
                    echo -e "${YELLOW}    [$timestamp] $message${NC}"
                done
            fi
        fi
    fi
}

show_help() {
    cat << 'EOF'
status.sh - Modular Monitor Status Checker with Incident Analysis

USAGE:
    ./status.sh [OPTIONS]

OPTIONS:
    --help, -h          Show this help message
    --since TIME        Only analyze events since specified time
                        Formats: "1 hour ago", "30 minutes ago", "2025-08-23 18:25:00"
                        Use this to set a baseline after configuration changes
    --usb-details       Show detailed USB device analysis (requires sudo)
    --pre-shutdown      Analyze the hour before the previous shutdown/boot
                        Useful for identifying what led to system issues

EXAMPLES:
    ./status.sh                           # Full status report
    ./status.sh --since "1 hour ago"      # Only show activity from last hour
    ./status.sh --since "18:25:00"        # Only show activity since 6:25 PM today
    ./status.sh --since "2025-08-23 18:25:00"  # Full timestamp
    sudo ./status.sh --usb-details        # Detailed USB port/device analysis
    ./status.sh --pre-shutdown            # Analyze hour before previous shutdown

INCIDENT ANALYSIS:
    - Automatically detects recent boots (< 10 minutes)
    - Analyzes previous boot logs for emergency shutdowns
    - Reports critical alerts, hardware errors, and thermal events
    - Shows emergency process kills and system patterns

USB ANALYSIS:
    - Identifies specific USB ports with issues
    - Shows device disconnect/reset patterns
    - Maps current connected devices
    - Requires sudo for detailed kernel message access

EOF
}

main() {
    local since_time=""
    local usb_details_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --since)
                if [[ -n "${2:-}" ]]; then
                    since_time="$2"
                    shift 2
                else
                    echo "Error: --since requires a time specification"
                    echo "Examples: --since '1 hour ago' or --since '18:25:00'"
                    exit 1
                fi
                ;;
            --usb-details)
                usb_details_only=true
                shift
                ;;
            --pre-shutdown)
                # New flag for pre-shutdown analysis
                analyze_pre_shutdown_hour
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # USB details only mode
    if [[ "$usb_details_only" == "true" ]]; then
        echo -e "${BLUE}🔌 USB DEVICE DETAILED ANALYSIS${NC}"
        echo "========================================================"
        
        if [[ $EUID -ne 0 ]]; then
            echo -e "${RED}❌ This feature requires root access${NC}"
            echo "Run: sudo ./status.sh --usb-details"
            exit 1
        fi
        
        # Determine appropriate time period based on uptime
        local analysis_period
        local uptime_seconds
        uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 7200)
        
        if [[ $uptime_seconds -lt 7200 ]]; then
            # Less than 2 hours uptime - analyze since boot
            analysis_period="boot"
            echo "Analyzing USB activity since boot ($(($uptime_seconds / 60)) minutes ago)..."
        else
            # More than 2 hours uptime - use specified time or default to 2 hours
            analysis_period="${since_time:-2 hours ago}"
            echo "Analyzing USB activity since: $analysis_period"
        fi
        echo
        
        # Source USB monitoring functions
        if [[ -f "$SCRIPT_DIR/modules/usb-monitor.sh" ]]; then
            source "$SCRIPT_DIR/modules/usb-monitor.sh"
            get_usb_device_details "$analysis_period"
        else
            echo "USB monitoring module not found"
            exit 1
        fi
        exit 0
    fi
    
    print_header
    
    # Check sudo recommendation
    check_sudo_recommendation
    
    # System uptime first
    local uptime_info
    uptime_info=$(uptime -p 2>/dev/null || uptime)
    echo -e "${BLUE}System uptime: $uptime_info${NC}"
    
    # Show time filter if specified
    if [[ -n "$since_time" ]]; then
        echo -e "${YELLOW}📅 Time filter: Only showing data since '$since_time'${NC}"
    fi
    
    # Incident analysis (new feature)
    check_incident_analysis
    
    check_systemd_status "$since_time"
    test_modules  
    show_current_readings "$since_time"
    show_recovered_features
    show_recent_alerts "$since_time"
    
    # USB Analysis (if USB issues detected)
    show_usb_analysis "$since_time"
    
    echo -e "\n${BLUE}📋 QUICK COMMANDS:${NC}"
    echo "  Monitor logs: journalctl -t modular-monitor -f"
    if [[ -n "$since_time" ]]; then
        echo "  Monitor logs (filtered): journalctl -t modular-monitor --since '$since_time' -f"
    fi
    echo "  USB analysis: sudo ./status.sh --usb-details"
    echo "  Pre-shutdown: ./status.sh --pre-shutdown"
    echo "  Test i915:    $SCRIPT_DIR/orchestrator.sh --test i915-monitor"
    echo "  Test system:  $SCRIPT_DIR/orchestrator.sh --test system-monitor"
    echo "  Run manual:   $SCRIPT_DIR/orchestrator.sh"
}

main "$@"