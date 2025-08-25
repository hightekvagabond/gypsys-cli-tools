#!/bin/bash
# Kernel Version Monitor - Track kernel changes and correlate with system issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Module metadata
MODULE_NAME="kernel"
MODULE_DESCRIPTION="Kernel version tracking and change detection"

check_status() {
    log "Checking kernel version history and changes..."
    
    # Get current kernel version
    local current_kernel
    current_kernel=$(uname -r)
    log "Current kernel: $current_kernel"
    
    # Scan for kernel version changes
    local kernel_changes
    kernel_changes=$(get_kernel_version_history)
    
    if [[ -n "$kernel_changes" ]]; then
        log "Kernel version history found:"
        echo "$kernel_changes" | while IFS= read -r line; do
            log "  $line"
        done
        
        # Check for recent kernel changes (last 30 days)
        local recent_changes
        recent_changes=$(echo "$kernel_changes" | head -5)
        local change_count
        change_count=$(echo "$recent_changes" | wc -l 2>/dev/null || echo "0")
        
        if [[ $change_count -gt 1 ]]; then
            send_alert "info" "📋 Kernel change history: $change_count versions detected in recent logs"
        fi
    else
        log "No kernel version history found in logs"
    fi
    
    # Check for kernel-related errors
    check_kernel_errors
    
    return 0
}

get_kernel_version_history() {
    local kernel_versions=()
    local unique_versions=()
    
    # Method 1: Check all available journal logs for kernel boot messages
    local all_boots
    all_boots=$(journalctl --list-boots --no-pager 2>/dev/null | awk '{print $1}' | sort -n)
    
    if [[ -n "$all_boots" ]]; then
        echo "$all_boots" | while read -r boot_id; do
            if [[ -n "$boot_id" ]]; then
                local kernel_version
                kernel_version=$(journalctl -b "$boot_id" --no-pager -q 2>/dev/null | grep -m 1 "Linux version" | sed 's/.*Linux version \([^ ]*\).*/\1/' 2>/dev/null || echo "")
                
                if [[ -n "$kernel_version" ]]; then
                    local boot_time
                    boot_time=$(journalctl -b "$boot_id" --no-pager -q --output=short-iso 2>/dev/null | head -1 | awk '{print $1}' || echo "unknown")
                    echo "$boot_time: $kernel_version"
                fi
            fi
        done | sort -r | awk '!seen[$2]++' # Remove duplicates, keep newest occurrence
    fi
    
    # Method 2: Search for kernel version strings in all logs
    local version_strings
    version_strings=$(journalctl --no-pager -q --since "30 days ago" 2>/dev/null | grep -o "Linux version [0-9][^[:space:]]*" | sort | uniq -c | sort -nr 2>/dev/null || echo "")
    
    if [[ -n "$version_strings" ]] && [[ $(echo "$version_strings" | wc -l) -gt 0 ]]; then
        echo ""
        echo "Kernel versions mentioned in logs (last 30 days):"
        echo "$version_strings" | while read -r count version_line; do
            local version
            version=$(echo "$version_line" | sed 's/Linux version //')
            echo "  $version (mentioned $count times)"
        done
    fi
    
    # Method 3: Check dpkg/rpm logs for kernel package installations
    check_kernel_package_history
}

check_kernel_package_history() {
    # Check for Debian/Ubuntu kernel package history
    if [[ -f /var/log/dpkg.log ]]; then
        echo ""
        echo "Kernel package installation history (dpkg):"
        local kernel_installs
        kernel_installs=$(grep -h "install.*linux-image\|upgrade.*linux-image" /var/log/dpkg.log* 2>/dev/null | tail -10 || echo "")
        if [[ -n "$kernel_installs" ]]; then
            echo "$kernel_installs" | while IFS= read -r line; do
                local date_time
                local action
                local package
                date_time=$(echo "$line" | awk '{print $1, $2}')
                action=$(echo "$line" | awk '{print $3}')
                package=$(echo "$line" | awk '{print $4}')
                echo "  [$date_time] $action: $package"
            done
        else
            echo "  No kernel package history found"
        fi
    fi
    
    # Check for Red Hat/CentOS kernel package history
    if command -v rpm >/dev/null 2>&1; then
        echo ""
        echo "Kernel package installation history (rpm):"
        local rpm_kernels
        rpm_kernels=$(rpm -qa --last kernel* 2>/dev/null | head -10 || echo "")
        if [[ -n "$rpm_kernels" ]]; then
            echo "$rpm_kernels" | while IFS= read -r line; do
                echo "  $line"
            done
        else
            echo "  No RPM kernel history found"
        fi
    fi
}

check_kernel_errors() {
    local error_count
    error_count=$(journalctl -k --since "24 hours ago" --no-pager 2>/dev/null | grep -c -i "kernel.*error\|kernel.*warning\|kernel.*critical\|oops\|panic" || echo "0")
    
    [[ -z "$error_count" || ! "$error_count" =~ ^[0-9]+$ ]] && error_count=0
    
    if [[ $error_count -gt 0 ]]; then
        send_alert "warning" "⚠️ Kernel errors detected: $error_count errors in last 24 hours"
        
        # Show recent kernel errors
        local recent_errors
        recent_errors=$(journalctl -k --since "24 hours ago" --no-pager 2>/dev/null | grep -i "kernel.*error\|kernel.*warning\|oops" | tail -3 || echo "")
        if [[ -n "$recent_errors" ]]; then
            log "Recent kernel errors:"
            echo "$recent_errors" | while IFS= read -r line; do
                local timestamp
                timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
                local error_msg
                error_msg=$(echo "$line" | sed 's/^[^:]*: //' | cut -c1-80)
                log "  [$timestamp] $error_msg"
            done
        fi
        return 1
    else
        log "No kernel errors detected in last 24 hours"
        return 0
    fi
}

show_kernel_timeline() {
    echo "=== KERNEL VERSION TIMELINE ==="
    echo ""
    
    # Get comprehensive kernel history
    get_kernel_version_history
    
    echo ""
    echo "=== CURRENT SYSTEM INFO ==="
    echo "Current kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Kernel build date: $(uname -v)"
    
    # Show loaded kernel modules count
    local module_count
    module_count=$(lsmod | wc -l 2>/dev/null || echo "0")
    echo "Loaded kernel modules: $((module_count - 1))"
    
    # Show kernel command line
    if [[ -f /proc/cmdline ]]; then
        echo "Kernel command line: $(cat /proc/cmdline)"
    fi
}

# Handle command line arguments for standalone testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --check)
            check_status
            ;;
        --timeline)
            show_kernel_timeline
            ;;
        --help)
            echo "Kernel Monitor Module"
            echo ""
            echo "Usage: $0 [--check|--timeline|--help]"
            echo ""
            echo "Options:"
            echo "  --check     Run kernel monitoring check"
            echo "  --timeline  Show complete kernel version timeline"
            echo "  --help      Show this help message"
            ;;
        *)
            # Default behavior when called by orchestrator
            check_status
            ;;
    esac
fi
