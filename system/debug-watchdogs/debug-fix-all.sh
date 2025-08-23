#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#  debug-fix-all.sh - Unified system diagnostic and repair script
#
#  DEVELOPER NOTES
#  ---------------
#  This script consolidates three previously separate diagnostic scripts:
#  - debug-laggy-ubuntu.sh (performance diagnostics)
#  - frozen_had_to_hardboot_diags.sh (post-crash forensics)  
#  - post-reboot-check.sh (system health validation)
#
#  ARCHITECTURE
#  ------------
#  - Modular functions for different diagnostic modes
#  - Granular control via command-line flags
#  - Comprehensive system health checking and repair
#  - Integration with debug-watch.sh for automated diagnostics
#  - Avoids i915-specific monitoring (handled by i915-fix-all.sh)
#
#  TECHNICAL DETAILS
#  -----------------
#  - Performance monitoring: CPU, memory, disk I/O, compositor
#  - Hardware diagnostics: PCIe errors, NVMe issues, USB problems
#  - System health: Services, network, DNS, resource exhaustion
#  - Post-crash analysis: Journal forensics, hardware error correlation
#
# -----------------------------------------------------------------------------

set -euo pipefail

# Configuration
SCRIPT_NAME="$(basename "$0")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="/tmp/debug_${TIMESTAMP}"
NEED_REBOOT=0
QUIET=0

# Logging function
log() {
    if [[ $QUIET -eq 0 ]]; then
        echo "[$SCRIPT_NAME] $*"
    fi
    logger -t "debug-fix-all" "$*"
}

# Error logging function
error() {
    echo "[$SCRIPT_NAME ERROR] $*" >&2
    logger -t "debug-fix-all" "ERROR: $*"
}

# Show help
show_help() {
    cat << 'EOF'
debug-fix-all.sh - Unified system diagnostic and repair script

USAGE:
    ./debug-fix-all.sh [OPTIONS]

OPTIONS:
    --performance         Diagnose performance issues (lag, slow response)
    --post-crash          Post-freeze forensic analysis
    --health-check        System health validation and basic repairs
    --collect-all         Comprehensive diagnostic data collection
    --network-fix         Attempt network connectivity repairs
    --service-fix         Restart failed system services
    --cleanup             Clean up old logs and temporary files
    --usb-fix             Fix USB storage device issues (freeze prevention)
    --network-restore     Manually restore network adapters disabled by critical-monitor
    --quiet               Minimal output (suitable for cron/automation)
    --help, -h            Show this help message

EXAMPLES:
    ./debug-fix-all.sh --performance      # Diagnose system lag
    ./debug-fix-all.sh --post-crash       # Analyze after freeze/crash
    ./debug-fix-all.sh --health-check     # Quick system validation
    ./debug-fix-all.sh --collect-all      # Full diagnostic collection
    ./debug-fix-all.sh --network-fix      # Fix network issues

OUTPUT:
    Diagnostic modes create timestamped archives in /tmp/debug_*
    Fix modes apply repairs and log actions to syslog

INTEGRATION:
    Works with debug-watch.sh for automated system monitoring
    Complements i915-fix-all.sh (no i915-specific functionality)

EOF
}

# Check if running as root for operations that need it
check_root_if_needed() {
    local operation="$1"
    case $operation in
        "service-fix"|"network-fix"|"cleanup"|"usb-fix")
            if [[ $EUID -ne 0 ]]; then
                error "Operation '$operation' requires root privileges (use sudo)"
                return 1
            fi
            ;;
    esac
    return 0
}

# Performance diagnostics (from debug-laggy-ubuntu.sh)
diagnose_performance() {
    local output_file="$OUTPUT_DIR/performance_diagnostics.log"
    log "Running performance diagnostics..."
    
    mkdir -p "$OUTPUT_DIR"
    exec 3>&1 4>&2 1> >(tee "$output_file") 2>&1
    
    echo "=== System Overview ==="
    hostnamectl || true
    uptime
    free -h
    swapon --show || true
    
    echo -e "\n=== CPU Analysis ==="
    lscpu | grep -E 'Model name|Socket|Thread|CPU\(s\)' || true
    echo -e "\nTop 15 CPU consumers:"
    ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 16
    
    echo -e "\n=== Memory Analysis ==="
    echo "Top 15 memory consumers:"
    ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 16
    
    echo -e "\n=== GPU/Compositor Analysis ==="
    inxi -Gxx 2>/dev/null || lspci | grep -i vga || true
    glxinfo | grep -E "OpenGL renderer|OpenGL core" 2>/dev/null || echo "glxinfo not available"
    
    # KDE/Plasma specific checks
    if command -v qdbus >/dev/null 2>&1; then
        echo -e "\n=== KDE Compositor Info ==="
        qdbus org.kde.KWin /KWin supportInformation 2>/dev/null | grep -iE 'Compositing|Backend|Renderer' || true
        
        echo -e "\n=== Plasma Process Info ==="
        ps aux | grep -E 'plasma|kwin' | grep -v grep || true
    fi
    
    echo -e "\n=== Disk I/O Analysis ==="
    iostat -xz 1 3 2>/dev/null || echo "iostat not available"
    
    if command -v iotop >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
        echo -e "\n=== Disk I/O by Process ==="
        timeout 10s iotop -b -n 3 | head -n 30 || true
    fi
    
    echo -e "\n=== File Indexer Status ==="
    balooctl status 2>/dev/null || echo "Baloo not available"
    
    echo -e "\n=== Recent Performance-Related Errors ==="
    journalctl -p 3 -b --since "1 hour ago" | grep -vE 'i915|nvidia' | head -n 50 || true
    
    exec 1>&3 2>&4 3>&- 4>&-
    log "Performance diagnostics saved to: $output_file"
}

# Post-crash forensics (from frozen_had_to_hardboot_diags.sh)
analyze_post_crash() {
    local output_file="$OUTPUT_DIR/post_crash_analysis.log"
    log "Running post-crash forensic analysis..."
    
    mkdir -p "$OUTPUT_DIR"
    exec 3>&1 4>&2 1> >(tee "$output_file") 2>&1
    
    echo "=== Hardware Status ==="
    lspci -nnk | grep -A3 -E 'VGA|3D|Display|Ethernet|Network' || true
    lsusb || true
    
    echo -e "\n=== DKMS Module Status ==="
    dkms status || true
    
    echo -e "\n=== Loaded Modules (excluding i915) ==="
    lsmod | grep -vE 'i915' | grep -E 'nvidia|evdi|alx|r8169|e1000|iwl|ath|rtw' || echo "No relevant modules found"
    
    echo -e "\n=== PCIe/Hardware Errors (Current Boot) ==="
    journalctl -k -b | grep -iE 'pcie|aer|dpc|fatal|correctable|uncorrectable|BadTLP|BadDLLP' || echo "No PCIe errors found"
    
    echo -e "\n=== Hardware Errors (Previous Boot) ==="
    journalctl -k -b -1 | grep -iE 'pcie|aer|dpc|fatal|correctable|uncorrectable|mce|machine check' 2>/dev/null || echo "No previous boot or hardware errors"
    
    echo -e "\n=== NVMe/Storage Errors ==="
    dmesg -T | grep -iE 'nvme.*(err|timeout|reset)' || echo "No NVMe errors"
    journalctl -k -b | grep -iE 'ata.*error|scsi.*error|ext4.*error' || echo "No storage errors"
    
    echo -e "\n=== Network Hardware Issues ==="
    journalctl -k -b | grep -iE 'alx.*timeout|r8169.*link|network.*error' || echo "No network hardware errors"
    
    echo -e "\n=== USB Issues ==="
    journalctl -k -b | grep -iE 'usb.*error|xhci.*error|hub.*error' || echo "No USB errors"
    
    echo -e "\n=== System Hang/Lockup Indicators ==="
    journalctl -b -1 2>/dev/null | grep -iE 'rcu.*stall|soft.*lockup|hard.*lockup|hung.*task|blocked.*task' || echo "No lockup indicators found"
    
    echo -e "\n=== Critical System Errors (Last 24h) ==="
    journalctl --since "24 hours ago" -p 0..2 | grep -vE 'i915' | head -n 100 || echo "No critical errors"
    
    exec 1>&3 2>&4 3>&- 4>&-
    log "Post-crash analysis saved to: $output_file"
}

# System health check and basic repairs
check_system_health() {
    log "Running comprehensive system health check..."
    
    local issues_found=0
    
    # System services check
    log "Checking system services..."
    local failed_services
    failed_services=$(systemctl --failed --no-pager --no-legend | wc -l)
    if [[ $failed_services -gt 0 ]]; then
        log "WARNING: $failed_services failed services detected"
        systemctl --failed --no-pager
        issues_found=1
    else
        log "All system services running normally"
    fi
    
    # Network connectivity check
    log "Checking network connectivity..."
    if ! ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        log "WARNING: No internet connectivity to 1.1.1.1"
        issues_found=1
    else
        log "Internet connectivity OK"
    fi
    
    # DNS resolution check
    if command -v resolvectl >/dev/null 2>&1; then
        if ! resolvectl query example.com >/dev/null 2>&1; then
            log "WARNING: DNS resolution failing"
            issues_found=1
        else
            log "DNS resolution OK"
        fi
    fi
    
    # Disk space check
    log "Checking disk space..."
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        log "CRITICAL: Root filesystem ${disk_usage}% full"
        issues_found=1
    elif [[ $disk_usage -gt 80 ]]; then
        log "WARNING: Root filesystem ${disk_usage}% full"
        issues_found=1
    else
        log "Disk space OK (${disk_usage}% used)"
    fi
    
    # Memory pressure check
    log "Checking memory pressure..."
    local mem_available
    mem_available=$(free | awk 'NR==2 {printf "%.0f", $7/$2*100}')
    if [[ $mem_available -lt 10 ]]; then
        log "CRITICAL: Only ${mem_available}% memory available"
        issues_found=1
    elif [[ $mem_available -lt 20 ]]; then
        log "WARNING: Only ${mem_available}% memory available"
        issues_found=1
    else
        log "Memory pressure OK (${mem_available}% available)"
    fi
    
    # Check for recent crashes
    log "Checking for recent system crashes..."
    if journalctl --since "24 hours ago" | grep -qi "kernel panic\|oops\|segfault\|core dump"; then
        log "WARNING: Recent system crashes detected"
        issues_found=1
    else
        log "No recent crashes detected"
    fi
    
    return $issues_found
}

# Network connectivity fixes
fix_network_issues() {
    log "Attempting network connectivity fixes..."
    
    # Restart NetworkManager
    if systemctl is-active NetworkManager >/dev/null 2>&1; then
        log "Restarting NetworkManager..."
        systemctl restart NetworkManager
        sleep 5
    fi
    
    # Restart systemd-resolved
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        log "Restarting systemd-resolved..."
        systemctl restart systemd-resolved
        sleep 3
    fi
    
    # Flush DNS cache
    if command -v resolvectl >/dev/null 2>&1; then
        log "Flushing DNS cache..."
        resolvectl flush-caches
    fi
    
    # Test connectivity
    sleep 5
    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        log "Network connectivity restored"
        return 0
    else
        log "Network connectivity still failing"
        return 1
    fi
}

# Restart failed services
fix_failed_services() {
    log "Restarting failed system services..."
    
    # Remove obsolete services first
    if systemctl is-failed fix-gpu.service >/dev/null 2>&1; then
        log "Removing obsolete fix-gpu.service (points to missing script)"
        systemctl stop fix-gpu.service 2>/dev/null || true
        systemctl disable fix-gpu.service 2>/dev/null || true
        rm -f /etc/systemd/system/fix-gpu.service
        systemctl daemon-reload
        systemctl reset-failed fix-gpu.service 2>/dev/null || true
        log "Obsolete service removed successfully"
    fi
    
    local failed_services
    failed_services=$(systemctl --failed --no-pager --no-legend --plain | awk '{print $1}')
    
    if [[ -z "$failed_services" ]]; then
        log "No failed services to restart"
        return 0
    fi
    
    log "Found failed services: $failed_services"
    
    local restarted=0
    local failed_restarts=0
    for service in $failed_services; do
        # Skip certain services that shouldn't be auto-restarted
        case $service in
            *@*|*.mount|*.swap|*.device)
                log "SKIP: $service (template/mount/swap/device services not suitable for restart)"
                continue
                ;;
        esac
        
        # Get service status before restart attempt
        local service_status
        service_status=$(systemctl is-active "$service" 2>/dev/null || echo "failed")
        log "ATTEMPTING: Restart $service (current status: $service_status)"
        
        # Try restart with timeout
        if timeout 30s systemctl restart "$service" 2>/dev/null; then
            local new_status
            new_status=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
            log "SUCCESS: $service restarted (new status: $new_status)"
            restarted=$((restarted + 1))
        else
            local exit_code=$?
            failed_restarts=$((failed_restarts + 1))
            
            # Get detailed error information
            local error_details
            error_details=$(systemctl status "$service" --no-pager --lines=3 2>/dev/null | tail -n 3 || echo "Status unavailable")
            
            if [[ $exit_code -eq 124 ]]; then
                log "TIMEOUT: $service restart timed out after 30 seconds"
                error "Service $service restart timeout - may indicate hardware or configuration issues"
            else
                log "FAILED: $service restart failed (exit code: $exit_code)"
            fi
            
            log "ERROR DETAILS for $service: $error_details"
            
            # Notify user of the specific failure
            notify-send -u normal "debug-watch: Failed to restart $service" \
                "Check 'journalctl -xeu $service' for details" 2>/dev/null || true
        fi
    done
    
    local total_services
    total_services=$(echo "$failed_services" | wc -w)
    
    if [[ $failed_restarts -gt 0 ]]; then
        error "Service restart summary: $restarted/$total_services succeeded, $failed_restarts failed"
        log "RECOMMENDATION: Check failed services with 'systemctl status <service>' and 'journalctl -xeu <service>'"
        return 1
    else
        log "Service restart summary: Successfully restarted $restarted/$total_services services"
        return 0
    fi
}

# Trigger KDE reboot notification (same as Discover updates)
trigger_kde_reboot_notification() {
    # Try to trigger KDE's reboot notification via systemd
    if command -v systemctl >/dev/null 2>&1; then
        # This creates a reboot-required flag that KDE's system monitor picks up
        touch /var/run/reboot-required 2>/dev/null || true
        echo "debug-fix-all: System configuration updated" > /var/run/reboot-required.pkgs 2>/dev/null || true
    fi
    
    # Also try KDE-specific notification methods
    if [[ -n "${DISPLAY:-}" ]] && command -v qdbus >/dev/null 2>&1; then
        # Try to notify KDE's system tray about pending reboot
        qdbus org.kde.kded5 /kded org.kde.kded5.setModuleAutoloading kded_reboot true 2>/dev/null || true
    fi
    
    # Fallback: desktop notification
    if [[ -n "${DISPLAY:-}" ]]; then
        notify-send -u critical -i system-reboot \
            "System Reboot Required" \
            "System configuration has been updated. Please reboot to apply changes." 2>/dev/null || true
    fi
}

# Clean up old logs and temporary files
cleanup_system() {
    log "Cleaning up system logs and temporary files..."
    
    # Clean journal logs older than 7 days
    journalctl --vacuum-time=7d >/dev/null 2>&1 || true
    
    # Clean old debug files
    find /tmp -name "debug_*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    find /tmp -name "gpu_diag_*" -type f -mtime +7 -delete 2>/dev/null || true
    find /tmp -name "lag_debug_*" -type f -mtime +7 -delete 2>/dev/null || true
    
    # Clean package cache
    if command -v apt-get >/dev/null 2>&1; then
        apt-get clean >/dev/null 2>&1 || true
    fi
    
    log "System cleanup completed"
}

# Fix USB storage device issues (can prevent freezes)
fix_usb_storage() {
    log "Checking and fixing USB storage device issues..."
    
    # Check for problematic USB storage resets
    local reset_count
    reset_count=$(dmesg 2>/dev/null | grep -cE 'uas_eh.*reset|USB device.*reset' 2>/dev/null || echo "0")
    reset_count=${reset_count//[^0-9]/}
    reset_count=${reset_count:-0}
    
    if [[ $reset_count -eq 0 ]]; then
        log "No USB storage reset issues detected"
        return 0
    fi
    
    log "Detected $reset_count USB storage resets - attempting fixes..."
    
    # Try to identify problematic USB devices
    local problematic_devices
    problematic_devices=$(dmesg | grep -E 'uas_eh.*reset' | grep -oE 'sd [a-z]+' | sort -u | awk '{print $2}' | head -5)
    
    if [[ -n "$problematic_devices" ]]; then
        log "Problematic USB storage devices detected: $problematic_devices"
        
        # For each problematic device, try to remount if it's mounted
        for device in $problematic_devices; do
            if mount | grep -q "/dev/${device}"; then
                log "Attempting to remount /dev/${device} to clear errors..."
                local mount_point
                mount_point=$(mount | grep "/dev/${device}" | awk '{print $3}' | head -1)
                if [[ -n "$mount_point" ]]; then
                    # Try to sync and remount
                    sync
                    if umount "$mount_point" 2>/dev/null; then
                        sleep 2
                        if mount "$mount_point" 2>/dev/null; then
                            log "Successfully remounted $mount_point"
                        else
                            log "WARNING: Failed to remount $mount_point"
                        fi
                    else
                        log "WARNING: Unable to unmount $mount_point (device busy)"
                    fi
                fi
            fi
        done
    fi
    
    # Try to reset the USB subsystem for severe issues
    if [[ $reset_count -gt 20 ]]; then
        log "Severe USB reset issues detected ($reset_count resets) - attempting USB subsystem reset..."
        
        # Restart USB-related services
        if systemctl is-active --quiet udisks2; then
            log "Restarting udisks2 service..."
            systemctl restart udisks2 2>/dev/null || log "Failed to restart udisks2"
        fi
        
        # Clear USB device cache
        if command -v udevadm >/dev/null 2>&1; then
            log "Refreshing USB device enumeration..."
            udevadm trigger --subsystem-match=usb 2>/dev/null || log "Failed to trigger USB subsystem"
        fi
        
        notify-send -u normal "System: USB storage fixes applied" \
            "Detected and attempted to fix USB storage issues that can cause freezes" 2>/dev/null || true
    fi
    
    log "USB storage fix completed"
}

# Manually restore network adapters that were disabled by critical-monitor
restore_network_adapters() {
    log "Restoring network adapters disabled by critical-monitor..."
    
    if ! command -v nmcli >/dev/null 2>&1; then
        log "NetworkManager not available, skipping network adapter restore"
        return 0
    fi
    
    # Check for marker files indicating disabled adapters
    local marker_files
    marker_files=$(ls /tmp/network_disabled_* 2>/dev/null || echo "")
    
    if [[ -n "$marker_files" ]]; then
        local count=0
        for marker_file in $marker_files; do
            if [[ -f "$marker_file" ]]; then
                local adapter
                adapter=$(basename "$marker_file" | sed 's/network_disabled_//')
                
                if [[ -n "$adapter" && "$adapter" =~ ^enx[a-f0-9]{12}$ ]]; then
                    log "Restoring network adapter: $adapter"
                    
                    # Re-enable autoconnect for all connections on this device
                    nmcli connection show | grep "$adapter" | awk '{print $1}' | while read -r conn_name; do
                        if [[ -n "$conn_name" ]]; then
                            nmcli connection modify "$conn_name" connection.autoconnect yes 2>/dev/null || true
                        fi
                    done
                    
                    # Try to connect
                    nmcli device connect "$adapter" 2>/dev/null || true
                    
                    # Remove marker file
                    rm -f "$marker_file" 2>/dev/null || true
                    
                    log "Network adapter $adapter restored"
                    ((count++))
                fi
            fi
        done
        
        if [[ $count -gt 0 ]]; then
            log "Network adapter restore completed: $count adapters restored"
            # Desktop notification
            if command -v notify-send >/dev/null 2>&1; then
                notify-send -u normal -t 5000 "🔌 Network Adapters Restored" \
                    "Manually restored $count network adapter(s) that were disabled for thermal protection." 2>/dev/null || true
            fi
        fi
    else
        log "No disabled network adapters found (no marker files in /tmp/)"
    fi
    
    return 0
}

# Comprehensive data collection
collect_all_diagnostics() {
    log "Collecting comprehensive diagnostic data..."
    
    mkdir -p "$OUTPUT_DIR"
    
    # System information
    {
        echo "=== System Information ==="
        hostnamectl || true
        uname -a
        uptime
        date
        
        echo -e "\n=== Hardware Information ==="
        lscpu | head -20 || true
        free -h
        lsblk || true
        lspci -nn || true
        lsusb || true
        
        echo -e "\n=== Network Configuration ==="
        ip addr show || true
        ip route show || true
        cat /etc/resolv.conf 2>/dev/null || true
        
    } > "$OUTPUT_DIR/system_info.txt"
    
    # Service status
    systemctl list-units --failed > "$OUTPUT_DIR/failed_services.txt" 2>/dev/null || true
    systemctl status > "$OUTPUT_DIR/service_status.txt" 2>/dev/null || true
    
    # Logs
    journalctl -b > "$OUTPUT_DIR/journal_current.log" 2>/dev/null || true
    journalctl -b -1 > "$OUTPUT_DIR/journal_previous.log" 2>/dev/null || true
    journalctl -p 0..3 --since "24 hours ago" > "$OUTPUT_DIR/recent_errors.log" 2>/dev/null || true
    dmesg -T > "$OUTPUT_DIR/dmesg.log" 2>/dev/null || true
    
    # Process information
    ps auxf > "$OUTPUT_DIR/processes.txt" 2>/dev/null || true
    
    # Create archive
    local archive="/tmp/debug_diagnostics_${TIMESTAMP}.tar.gz"
    tar -czf "$archive" -C /tmp "debug_${TIMESTAMP}" 2>/dev/null || true
    
    log "Comprehensive diagnostics saved to: $archive"
    return 0
}

# Main function
main() {
    local do_performance=0
    local do_post_crash=0
    local do_health_check=0
    local do_collect_all=0
    local do_network_fix=0
    local do_service_fix=0
    local do_cleanup=0
    local do_usb_fix=0
    
    # Parse arguments (handle --help before other checks)
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --performance)
                do_performance=1
                shift
                ;;
            --post-crash)
                do_post_crash=1
                shift
                ;;
            --health-check)
                do_health_check=1
                shift
                ;;
            --collect-all)
                do_collect_all=1
                shift
                ;;
            --network-fix)
                do_network_fix=1
                shift
                ;;
            --service-fix)
                do_service_fix=1
                shift
                ;;
            --cleanup)
                do_cleanup=1
                shift
                ;;
            --usb-fix)
                do_usb_fix=1
                shift
                ;;
            --network-restore)
                do_network_restore=1
                shift
                ;;
            --quiet)
                QUIET=1
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Default behavior if no specific action requested
    if [[ $do_performance -eq 0 && $do_post_crash -eq 0 && $do_health_check -eq 0 && $do_collect_all -eq 0 && $do_network_fix -eq 0 && $do_service_fix -eq 0 && $do_cleanup -eq 0 ]]; then
        do_health_check=1
    fi
    
    log "Starting debug fix-all script"
    
    # Execute requested actions
    if [[ $do_performance -eq 1 ]]; then
        diagnose_performance
    fi
    
    if [[ $do_post_crash -eq 1 ]]; then
        analyze_post_crash
    fi
    
    if [[ $do_health_check -eq 1 ]]; then
        check_system_health || log "System health issues detected"
    fi
    
    if [[ $do_collect_all -eq 1 ]]; then
        collect_all_diagnostics
    fi
    
    if [[ $do_network_fix -eq 1 ]]; then
        check_root_if_needed "network-fix" || exit 1
        fix_network_issues || log "Network fix unsuccessful"
    fi
    
    if [[ $do_service_fix -eq 1 ]]; then
        check_root_if_needed "service-fix" || exit 1
        fix_failed_services
    fi
    
    if [[ $do_cleanup -eq 1 ]]; then
        check_root_if_needed "cleanup" || exit 1
        cleanup_system
    fi
    
    if [[ $do_usb_fix -eq 1 ]]; then
        check_root_if_needed "usb-fix" || exit 1
        fix_usb_storage
    fi
    
    if [[ ${do_network_restore:-0} -eq 1 ]]; then
        restore_network_adapters
    fi

    log "Debug fix-all script completed"
    exit 0
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
