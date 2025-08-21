#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#  debug-install.sh - Installer for comprehensive system debug monitoring
#
#  PURPOSE
#  -------
#  Sets up the complete system debug monitoring system including:
#  • debug-fix-all.sh - Unified diagnostic and repair script
#  • debug-watch.sh - Proactive system health monitoring watchdog
#  • System integration (cron jobs, log rotation, cleanup automation)
#
#  WHAT IT INSTALLS
#  ----------------
#  1. Cron job for regular system health monitoring (every 15 minutes)
#  2. Log rotation for debug outputs
#  3. Automated cleanup of old diagnostic files
#  4. Initial system health baseline
#
#  USAGE
#  -----
#  sudo ./debug-install.sh [OPTIONS]
#
#  OPTIONS
#  -------
#  --cron-only           Install only the cron job (no log rotation or cleanup)
#  --no-baseline         Skip running initial system health baseline
#  --uninstall           Remove all installed components
#  --help, -h            Show this help message
#
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
FIX_SCRIPT="$SCRIPT_DIR/debug-fix-all.sh"
WATCH_SCRIPT="$SCRIPT_DIR/debug-watch.sh"
I915_INSTALL_SCRIPT="$SCRIPT_DIR/i915/i915-install.sh"

# Configuration
CRON_SCHEDULE_REBOOT="@reboot"     # Run at boot
CRON_SCHEDULE_REGULAR="0 */6 * * *" # Every 6 hours
LOGROTATE_FILE="/etc/logrotate.d/debug-monitoring"
CLEANUP_CRON_SCHEDULE="0 2 * * 0"  # Weekly at 2 AM on Sunday

# Logging function
log() {
    echo "[$SCRIPT_NAME] $*"
}

error() {
    echo "[$SCRIPT_NAME ERROR] $*" >&2
}

# Show help
show_help() {
    cat << 'EOF'
debug-install.sh - Installer for comprehensive system debug monitoring

USAGE:
    sudo ./debug-install.sh [OPTIONS]

OPTIONS:
    --cron-only           Install only the cron job (no log rotation or cleanup)
    --no-baseline         Skip running initial system health baseline
    --uninstall           Remove all installed components
    --help, -h            Show this help message

WHAT IT INSTALLS:
    • System health monitoring cron jobs (at boot + every 6 hours)
    • Log rotation for debug outputs
    • Automated cleanup of old diagnostic files
    • Initial system health baseline
    • i915 GPU monitoring (automatically detected and installed if Intel GPU present)

EXAMPLES:
    sudo ./debug-install.sh                # Full installation
    sudo ./debug-install.sh --cron-only   # Just the monitoring cron job
    sudo ./debug-install.sh --uninstall   # Remove everything

COMPATIBILITY:
    Designed and tested specifically for Ubuntu/Kubuntu on Acer Predator laptops.
    May require modifications for other systems or hardware configurations.

EOF
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check if required scripts exist
check_dependencies() {
    local missing=0
    
    if [[ ! -x "$FIX_SCRIPT" ]]; then
        error "Fix script not found or not executable: $FIX_SCRIPT"
        missing=1
    fi
    
    if [[ ! -x "$WATCH_SCRIPT" ]]; then
        error "Watch script not found or not executable: $WATCH_SCRIPT"
        missing=1
    fi
    
    if [[ $missing -eq 1 ]]; then
        error "Please ensure both debug-fix-all.sh and debug-watch.sh are present and executable"
        exit 1
    fi
}

# Detect Intel GPU and check if i915 module is available
detect_intel_gpu() {
    local has_intel=0
    
    # Check for Intel GPU via lspci
    if lspci 2>/dev/null | grep -i "vga.*intel" >/dev/null; then
        has_intel=1
        log "Intel GPU detected via lspci"
    fi
    
    # Check for Intel graphics via /proc/driver/nvidia/gpus (absence indicates integrated)
    if [[ ! -d /proc/driver/nvidia ]] && lspci 2>/dev/null | grep -i "display.*intel" >/dev/null; then
        has_intel=1
        log "Intel integrated graphics detected"
    fi
    
    # Check for i915 kernel module
    if [[ $has_intel -eq 1 ]]; then
        if lsmod | grep -q "^i915 " || modinfo i915 >/dev/null 2>&1; then
            log "Intel i915 kernel module available"
            return 0
        else
            log "Intel GPU detected but i915 module not available"
            return 1
        fi
    fi
    
    return 1
}

# Install i915 monitoring if Intel GPU is detected
install_i915_monitoring() {
    if [[ ! -x "$I915_INSTALL_SCRIPT" ]]; then
        log "i915 installer not found at $I915_INSTALL_SCRIPT, skipping i915 monitoring"
        return 0
    fi
    
    log "Installing i915 GPU monitoring subsystem..."
    if "$I915_INSTALL_SCRIPT" "$@"; then
        log "i915 monitoring installed successfully"
        return 0
    else
        error "Failed to install i915 monitoring"
        return 1
    fi
}

# Install cron job for system monitoring
install_cron_job() {
    log "Installing cron jobs for debug monitoring (boot + 6-hourly)"
    
    # Check if cron jobs already exist and remove them (including old paths)
    if crontab -l 2>/dev/null | grep -q "debug-watch.sh"; then
        log "Existing cron jobs found, updating..."
        # Remove existing cron jobs (any path containing debug-watch.sh)
        crontab -l 2>/dev/null | grep -v "debug-watch.sh" | crontab -
    fi
    
    # Add new cron jobs (both @reboot and regular schedule)
    (crontab -l 2>/dev/null; echo "$CRON_SCHEDULE_REBOOT $WATCH_SCRIPT"; echo "$CRON_SCHEDULE_REGULAR $WATCH_SCRIPT") | crontab -
    log "Cron jobs installed:"
    log "  At boot: $CRON_SCHEDULE_REBOOT $WATCH_SCRIPT"
    log "  Regular: $CRON_SCHEDULE_REGULAR $WATCH_SCRIPT"
}

# Install log rotation
install_log_rotation() {
    if [[ -f "$LOGROTATE_FILE" ]]; then
        log "Log rotation already exists, checking if update needed..."
        if grep -q "/tmp/debug_" "$LOGROTATE_FILE"; then
            log "Log rotation is current, no changes needed"
            return 0
        else
            log "Updating existing log rotation..."
        fi
    else
        log "Installing log rotation for debug files"
    fi
    
    cat > "$LOGROTATE_FILE" << 'EOF'
# Log rotation for debug monitoring files
/tmp/debug_*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}

/tmp/lag_debug_*.log {
    daily
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
    
    log "Log rotation installed: $LOGROTATE_FILE"
}

# Install automated cleanup
install_cleanup_automation() {
    log "Installing automated cleanup cron job"
    
    # Check if cleanup cron job already exists
    if crontab -l 2>/dev/null | grep -q "debug-fix-all.sh --.*cleanup"; then
        log "Cleanup cron job already exists, updating..."
        crontab -l 2>/dev/null | grep -v "debug-fix-all.sh --.*cleanup" | crontab -
    fi
    
    # Add cleanup cron job
    (crontab -l 2>/dev/null; echo "$CLEANUP_CRON_SCHEDULE $FIX_SCRIPT --quiet --cleanup") | crontab -
    log "Cleanup cron job installed: $CLEANUP_CRON_SCHEDULE (weekly cleanup)"
}

# Run initial system health baseline
run_baseline_check() {
    log "Running initial system health baseline"
    
    log "Checking current system status..."
    if "$FIX_SCRIPT" --health-check; then
        log "Initial system health check completed"
    else
        log "System health check completed with warnings (check logs for details)"
    fi
    
    log "System baseline established"
}

# Uninstall all components
uninstall_system() {
    log "Uninstalling debug monitoring system"
    
    # Remove monitoring cron jobs (including old paths)
    if crontab -l 2>/dev/null | grep -q "debug-watch.sh"; then
        log "Removing monitoring cron jobs..."
        crontab -l 2>/dev/null | grep -v "debug-watch.sh" | crontab -
    fi
    
    # Remove cleanup cron job
    if crontab -l 2>/dev/null | grep -q "debug-fix-all.sh --cleanup"; then
        log "Removing cleanup cron job..."
        crontab -l 2>/dev/null | grep -v "debug-fix-all.sh --cleanup" | crontab -
    fi
    
    # Remove log rotation
    if [[ -f "$LOGROTATE_FILE" ]]; then
        log "Removing log rotation..."
        rm -f "$LOGROTATE_FILE"
    fi
    
    # Remove state file
    if [[ -f "/var/tmp/debug-watch-state" ]]; then
        log "Removing watchdog state file..."
        rm -f "/var/tmp/debug-watch-state"
    fi
    
    # Clean up old debug files
    log "Cleaning up old debug files..."
    find /tmp -name "debug_*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    find /tmp -name "lag_debug_*.log" -mtime +1 -delete 2>/dev/null || true
    
    log "Uninstallation completed"
}

# Show installation summary
show_summary() {
    log "=== Installation Summary ==="
    log "Scripts location: $SCRIPT_DIR"
    log "Monitoring cron jobs: @reboot and every 6 hours"
    log "Cleanup cron job: $CLEANUP_CRON_SCHEDULE (weekly)"
    log "Log rotation: $LOGROTATE_FILE"
    log ""
    log "The system will now:"
    log "• Monitor system health at boot and every 6 hours"
    log "• Automatically fix common issues (network, services)"
    log "• Clean up old diagnostic files weekly"
    log "• Rotate debug logs to prevent disk space issues"
    log ""
    log "You can manually run diagnostics with:"
    log "  $FIX_SCRIPT --help"
    log ""
    log "Monitor the watchdog with:"
    log "  sudo journalctl -t debug-watch -f"
    log "=== End Summary ==="
}

# Main function
main() {
    local cron_only=0
    local no_baseline=0
    local do_uninstall=0
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cron-only)
                cron_only=1
                shift
                ;;
            --no-baseline)
                no_baseline=1
                shift
                ;;
            --uninstall)
                do_uninstall=1
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    check_root
    check_dependencies
    
    if [[ $do_uninstall -eq 1 ]]; then
        uninstall_system
        exit 0
    fi
    
    log "Installing debug monitoring system"
    
    # Always install cron job
    install_cron_job
    
    # Install additional components unless cron-only
    if [[ $cron_only -eq 0 ]]; then
        install_log_rotation
        install_cleanup_automation
    fi
    
    # Check for Intel GPU and install i915 monitoring if detected
    if detect_intel_gpu; then
        log "Intel GPU with i915 module detected, installing i915 monitoring..."
        # Pass through relevant arguments to i915 installer
        local i915_args=()
        [[ $cron_only -eq 1 ]] && i915_args+=("--cron-only")
        [[ $no_baseline -eq 1 ]] && i915_args+=("--no-initial-fix")
        
        if install_i915_monitoring "${i915_args[@]}"; then
            log "i915 monitoring integration completed"
        else
            log "Warning: i915 monitoring installation failed, continuing with general monitoring"
        fi
    else
        log "No Intel GPU detected or i915 module not available, skipping i915 monitoring"
    fi
    
    # Run baseline check unless disabled
    if [[ $no_baseline -eq 0 ]]; then
        # Check if this is a fresh install or update
        if [[ -f "/var/tmp/debug-watch-state" ]]; then
            log "Existing installation detected, skipping baseline check"
            log "Run '$FIX_SCRIPT --health-check' manually if needed"
        else
            log "Fresh installation detected, running baseline check"
            run_baseline_check
        fi
    fi
    
    show_summary
    
    log "Installation completed successfully!"
    log "NOTE: This system is optimized for Ubuntu/Kubuntu on Acer Predator hardware"
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
