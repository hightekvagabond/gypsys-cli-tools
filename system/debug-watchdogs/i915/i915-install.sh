#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#  i915-install.sh - Unified installer for i915 self-healing system
#
#  PURPOSE
#  -------
#  Sets up the complete i915 self-healing system including:
#  • i915-fix-all.sh - Unified fix script with modular functions
#  • i915-watch.sh - Self-healing watchdog with automatic fixes
#  • System integration (cron jobs, systemd services, apt hooks)
#
#  WHAT IT INSTALLS
#  ----------------
#  1. Cron job for hourly watchdog monitoring
#  2. APT hook for automatic fixes after package updates
#  3. Systemd service for boot-time checks
#  4. Initial system fix (GRUB flags and DKMS modules)
#
#  USAGE
#  -----
#  sudo ./i915-install.sh [OPTIONS]
#
#  OPTIONS
#  -------
#  --cron-only           Install only the cron job (no apt hooks or systemd)
#  --no-initial-fix      Skip running initial fixes during installation
#  --force-initial-fix   Force initial fixes even on existing installations
#  --uninstall           Remove all installed components
#  --help, -h            Show this help message
#
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
FIX_SCRIPT="$SCRIPT_DIR/i915-fix-all.sh"
WATCH_SCRIPT="$SCRIPT_DIR/i915-watch.sh"

# Configuration
CRON_SCHEDULE_REBOOT="@reboot"     # Run at boot
CRON_SCHEDULE_REGULAR="0 */6 * * *" # Every 6 hours
APT_HOOK_FILE="/etc/apt/apt.conf.d/99-i915-fix"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/i915-fix.service"
CURRENT_USER="${SUDO_USER:-$USER}"

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
i915-install.sh - Unified installer for i915 self-healing system

USAGE:
    sudo ./i915-install.sh [OPTIONS]

OPTIONS:
    --cron-only           Install only the cron job (no apt hooks or systemd)
    --no-initial-fix      Skip running initial fixes during installation
    --force-initial-fix   Force initial fixes even on existing installations
    --uninstall           Remove all installed components
    --help, -h            Show this help message

WHAT IT INSTALLS:
    • Cron jobs for i915-watch.sh (at boot + every 6 hours)
    • APT hook to run fixes after package updates
    • Systemd service for boot-time system checks
    • Initial GRUB flags and DKMS module fixes

EXAMPLES:
    sudo ./i915-install.sh                # Full installation
    sudo ./i915-install.sh --cron-only   # Just the watchdog cron job
    sudo ./i915-install.sh --uninstall   # Remove everything

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
        error "Please ensure both i915-fix-all.sh and i915-watch.sh are present and executable"
        exit 1
    fi
}

# Install cron job for watchdog
install_cron_job() {
    log "Installing cron jobs for i915-watch.sh (boot + 6-hourly)"
    
    # Check if cron jobs already exist and remove them (including old paths)
    if crontab -l 2>/dev/null | grep -q "i915-watch.sh"; then
        log "Existing cron jobs found, updating..."
        # Remove existing cron jobs (any path containing i915-watch.sh)
        crontab -l 2>/dev/null | grep -v "i915-watch.sh" | crontab -
    fi
    
    # Add new cron jobs (both @reboot and regular schedule)
    (crontab -l 2>/dev/null; echo "$CRON_SCHEDULE_REBOOT $WATCH_SCRIPT"; echo "$CRON_SCHEDULE_REGULAR $WATCH_SCRIPT") | crontab -
    log "Cron jobs installed:"
    log "  At boot: $CRON_SCHEDULE_REBOOT $WATCH_SCRIPT"
    log "  Regular: $CRON_SCHEDULE_REGULAR $WATCH_SCRIPT"
}

# Install APT hook
install_apt_hook() {
    if [[ -f "$APT_HOOK_FILE" ]]; then
        log "APT hook already exists, checking if update needed..."
        if grep -q "$FIX_SCRIPT" "$APT_HOOK_FILE"; then
            log "APT hook is current, no changes needed"
            return 0
        else
            log "Updating existing APT hook..."
        fi
    else
        log "Installing APT hook for automatic fixes after package updates"
    fi
    
    cat > "$APT_HOOK_FILE" << EOF
// i915 GPU fix automation
// Rebuild DKMS modules and re-apply i915 flags after package updates
DPkg::Post-Invoke-Success { "/usr/bin/env bash $FIX_SCRIPT --quiet --dkms-only || true"; };
EOF
    
    log "APT hook installed: $APT_HOOK_FILE"
}

# Install systemd service
install_systemd_service() {
    local service_needs_update=0
    
    if [[ -f "$SYSTEMD_SERVICE_FILE" ]]; then
        log "Systemd service already exists, checking if update needed..."
        if grep -q "$FIX_SCRIPT" "$SYSTEMD_SERVICE_FILE"; then
            log "Systemd service is current"
            # Check if it's enabled
            if systemctl is-enabled i915-fix.service >/dev/null 2>&1; then
                log "Systemd service already enabled, no changes needed"
                return 0
            else
                log "Systemd service exists but not enabled, enabling..."
                systemctl enable i915-fix.service
                return 0
            fi
        else
            log "Updating existing systemd service..."
            service_needs_update=1
        fi
    else
        log "Installing systemd service for boot-time checks"
        service_needs_update=1
    fi
    
    if [[ $service_needs_update -eq 1 ]]; then
        cat > "$SYSTEMD_SERVICE_FILE" << EOF
[Unit]
Description=i915 GPU system check and fix
After=dkms.service
ConditionKernelCommandLine=!norepair

[Service]
Type=oneshot
ExecStart=$FIX_SCRIPT --quiet --check-only
RemainAfterExit=yes
SuccessExitStatus=0

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable i915-fix.service
        log "Systemd service installed and enabled: i915-fix.service"
    fi
}

# Run initial fixes
run_initial_fixes() {
    log "Running initial system fixes"
    
    # Check if fixes are actually needed first
    log "Checking current system status..."
    if "$FIX_SCRIPT" --check-only --quiet; then
        log "System status check completed"
    fi
    
    log "Applying GRUB flags (idempotent)..."
    if "$FIX_SCRIPT" --flags-only; then
        log "GRUB flags processed successfully"
    else
        error "Failed to apply GRUB flags"
        return 1
    fi
    
    log "Processing DKMS modules (idempotent)..."
    if "$FIX_SCRIPT" --dkms-only; then
        log "DKMS modules processed successfully"
    else
        log "DKMS module processing completed with warnings (this may be normal if no DKMS modules are installed)"
    fi
    
    log "Initial fixes completed"
}

# Uninstall all components
uninstall_system() {
    log "Uninstalling i915 self-healing system"
    
    # Remove cron jobs (including old paths)
    if crontab -l 2>/dev/null | grep -q "i915-watch.sh"; then
        log "Removing cron jobs..."
        crontab -l 2>/dev/null | grep -v "i915-watch.sh" | crontab -
    fi
    
    # Remove APT hook
    if [[ -f "$APT_HOOK_FILE" ]]; then
        log "Removing APT hook..."
        rm -f "$APT_HOOK_FILE"
    fi
    
    # Remove systemd service
    if [[ -f "$SYSTEMD_SERVICE_FILE" ]]; then
        log "Removing systemd service..."
        systemctl disable i915-fix.service 2>/dev/null || true
        rm -f "$SYSTEMD_SERVICE_FILE"
        systemctl daemon-reload
    fi
    
    # Remove state file
    if [[ -f "/var/tmp/i915-watch-state" ]]; then
        log "Removing watchdog state file..."
        rm -f "/var/tmp/i915-watch-state"
    fi
    
    log "Uninstallation completed"
}

# Show installation summary
show_summary() {
    log "=== Installation Summary ==="
    log "Scripts location: $SCRIPT_DIR"
    log "Cron jobs: @reboot and every 6 hours"
    log "APT hook: $APT_HOOK_FILE"
    log "Systemd service: i915-fix.service"
    log ""
    log "The system will now:"
    log "• Monitor i915 errors at boot and every 6 hours with automatic fixes"
    log "• Rebuild DKMS modules after package updates"
    log "• Check system health at boot time"
    log ""
    log "You can manually run fixes with:"
    log "  sudo $FIX_SCRIPT --help"
    log ""
    log "Monitor the watchdog with:"
    log "  sudo journalctl -t i915-watch -f"
    log "=== End Summary ==="
}

# Main function
main() {
    local cron_only=0
    local no_initial_fix=0
    local force_initial_fix=0
    local do_uninstall=0
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cron-only)
                cron_only=1
                shift
                ;;
            --no-initial-fix)
                no_initial_fix=1
                shift
                ;;
            --force-initial-fix)
                force_initial_fix=1
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
    
    log "Installing i915 self-healing system"
    
    # Always install cron job
    install_cron_job
    
    # Install additional components unless cron-only
    if [[ $cron_only -eq 0 ]]; then
        install_apt_hook
        install_systemd_service
    fi
    
    # Run initial fixes based on flags
    if [[ $no_initial_fix -eq 1 ]]; then
        log "Skipping initial fixes (--no-initial-fix specified)"
    elif [[ $force_initial_fix -eq 1 ]]; then
        log "Forcing initial fixes (--force-initial-fix specified)"
        run_initial_fixes
    else
        # Default behavior: skip on existing installations
        if [[ -f "/var/tmp/i915-watch-state" ]]; then
            log "Existing installation detected, skipping initial fixes"
            log "Use --force-initial-fix to reapply fixes, or run 'sudo $FIX_SCRIPT' manually"
        else
            log "Fresh installation detected, running initial fixes"
            run_initial_fixes
        fi
    fi
    
    show_summary
    
    log "Installation completed successfully!"
    log "Note: A reboot is recommended to ensure all GRUB flags take effect"
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
