#!/bin/bash
#
#  hybrid-install.sh – Install hybrid monitoring system (services + cron)
#
#  DEVELOPER NOTES
#  ---------------
#  Installs a hybrid monitoring approach:
#  - Critical monitoring via systemd services (1-2 minute intervals)
#  - Comprehensive monitoring via cron (6-hour intervals)
#  
#  This provides real-time protection against fast-developing issues
#  (thermal, USB, memory) while maintaining efficient comprehensive checks.
#
#  ARCHITECTURE
#  ------------
#  SERVICES (Real-time, 2-minute intervals):
#  - critical-monitor.service/timer: Thermal, USB, memory monitoring
#  
#  CRON (Comprehensive, 6-hour intervals):
#  - debug-watch.sh: Full system health checks
#  - i915-watch.sh: GPU-specific monitoring
#  - Weekly cleanup job
#  
#  DYNAMIC PATHS:
#  All service files use script location detection to survive folder moves.

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
I915_SCRIPT_DIR="$SCRIPT_DIR/i915"
LOG_TAG="hybrid-install"

# Service and timer files
CRITICAL_SERVICE="critical-monitor.service"
CRITICAL_TIMER="critical-monitor.timer"

# Cron schedules
CRON_SCHEDULE_REBOOT="@reboot"
CRON_SCHEDULE_REGULAR="0 */6 * * *"  # Every 6 hours
CRON_SCHEDULE_CLEANUP="0 2 * * 0"    # Sunday 2 AM

# Logging function
log() {
    echo "[hybrid-install.sh] $*"
    logger -t "$LOG_TAG" "$*" 2>/dev/null || true
}

# Error function
error() {
    log "ERROR: $*" >&2
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Install critical monitoring service
install_critical_service() {
    log "Installing critical monitoring systemd service and timer..."
    
    # Create service file with dynamic path
    cat > "/etc/systemd/system/$CRITICAL_SERVICE" << EOF
[Unit]
Description=Critical System Monitor - Real-time thermal, USB, and memory monitoring
Documentation=man:systemd.service(5)
After=multi-user.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/critical-monitor.sh
User=root
Group=root

# Resource limits (keep it lightweight)
MemoryMax=50M
CPUQuota=5%

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=critical-monitor

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/tmp/critical-monitor-state /var/log
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF

    # Create timer file
    cp "$SCRIPT_DIR/$CRITICAL_TIMER" "/etc/systemd/system/$CRITICAL_TIMER"
    
    # Reload systemd and enable services
    systemctl daemon-reload
    systemctl enable "$CRITICAL_SERVICE"
    systemctl enable "$CRITICAL_TIMER"
    systemctl start "$CRITICAL_TIMER"
    
    log "Critical monitoring service installed and started"
    log "  Service: $CRITICAL_SERVICE"
    log "  Timer: $CRITICAL_TIMER (every 2 minutes)"
}

# Install comprehensive monitoring cron jobs
install_comprehensive_crons() {
    log "Installing comprehensive monitoring cron jobs (6-hourly)..."
    
    # Remove any existing debug/i915 monitoring cron jobs
    if crontab -l 2>/dev/null | grep -q -E "debug-watch|i915-watch|debug-fix-all.*cleanup"; then
        log "Removing existing monitoring cron jobs..."
        crontab -l 2>/dev/null | grep -v -E "debug-watch|i915-watch|debug-fix-all.*cleanup" | crontab -
    fi
    
    # Add new cron jobs
    log "Adding comprehensive monitoring cron jobs..."
    (
        crontab -l 2>/dev/null || true
        echo "# Debug watchdog monitoring (6-hourly comprehensive checks)"
        echo "$CRON_SCHEDULE_REBOOT $SCRIPT_DIR/debug-watch.sh"
        echo "$CRON_SCHEDULE_REGULAR $SCRIPT_DIR/debug-watch.sh"
        echo ""
        echo "# i915 GPU monitoring (6-hourly)"
        echo "$CRON_SCHEDULE_REBOOT $I915_SCRIPT_DIR/i915-watch.sh"
        echo "$CRON_SCHEDULE_REGULAR $I915_SCRIPT_DIR/i915-watch.sh"
        echo ""
        echo "# Weekly system cleanup"
        echo "$CRON_SCHEDULE_CLEANUP $SCRIPT_DIR/debug-fix-all.sh --quiet --cleanup"
    ) | crontab -
    
    log "Comprehensive monitoring cron jobs installed:"
    log "  debug-watch.sh: @reboot and every 6 hours"
    log "  i915-watch.sh: @reboot and every 6 hours"
    log "  cleanup: weekly on Sunday 2 AM"
}

# Install i915 subsystem (if Intel GPU detected)
install_i915_subsystem() {
    if [[ ! -x "$I915_SCRIPT_DIR/i915-install.sh" ]]; then
        log "i915 installer not found, skipping i915 monitoring"
        return 0
    fi
    
    # Check for Intel GPU
    local has_intel=0
    if lspci 2>/dev/null | grep -i "vga.*intel" >/dev/null; then
        has_intel=1
        log "Intel GPU detected via lspci"
    fi
    
    if [[ $has_intel -eq 1 ]]; then
        if lsmod | grep -q "^i915 " || modinfo i915 >/dev/null 2>&1; then
            log "Installing i915 GPU monitoring subsystem..."
            
            # First, ensure any existing i915 cron jobs are removed
            log "Removing any existing i915 cron jobs (will be managed by hybrid system)..."
            if crontab -l 2>/dev/null | grep -q "i915-watch.sh"; then
                crontab -l 2>/dev/null | grep -v "i915-watch.sh" | crontab -
            fi
            
            # Run i915 installer without cron (APT hooks and systemd only)
            if "$I915_SCRIPT_DIR/i915-install.sh" --cron-only; then
                # Remove the cron job it just installed (we'll manage it)
                if crontab -l 2>/dev/null | grep -q "i915-watch.sh"; then
                    crontab -l 2>/dev/null | grep -v "i915-watch.sh" | crontab -
                fi
                log "i915 monitoring subsystem installed successfully"
            else
                log "Warning: i915 monitoring installation failed, continuing"
            fi
        else
            log "Intel GPU detected but i915 module not available"
        fi
    else
        log "No Intel GPU detected, skipping i915 monitoring"
    fi
}

# Install log rotation
install_log_rotation() {
    log "Installing log rotation for monitoring logs..."
    
    cat > /etc/logrotate.d/debug-monitoring << 'EOF'
# Log rotation for debug monitoring system
/var/log/debug-*.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}

# Critical monitor state cleanup
/var/tmp/critical-monitor-state/* {
    weekly
    rotate 2
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
    
    log "Log rotation configured"
}

# Uninstall function
uninstall_system() {
    log "Uninstalling hybrid monitoring system..."
    
    # Stop and disable services
    systemctl stop "$CRITICAL_TIMER" 2>/dev/null || true
    systemctl disable "$CRITICAL_TIMER" 2>/dev/null || true
    systemctl disable "$CRITICAL_SERVICE" 2>/dev/null || true
    
    # Remove service files
    rm -f "/etc/systemd/system/$CRITICAL_SERVICE" "/etc/systemd/system/$CRITICAL_TIMER"
    systemctl daemon-reload
    
    # Remove cron jobs
    if crontab -l 2>/dev/null | grep -q -E "debug-watch|i915-watch|debug-fix-all.*cleanup"; then
        crontab -l 2>/dev/null | grep -v -E "debug-watch|i915-watch|debug-fix-all.*cleanup" | crontab -
    fi
    
    # Remove log rotation
    rm -f /etc/logrotate.d/debug-monitoring
    
    log "Hybrid monitoring system uninstalled"
}

# Show installation summary
show_summary() {
    log "=== Hybrid Monitoring System Installation Summary ==="
    log "Location: $SCRIPT_DIR"
    log ""
    log "REAL-TIME MONITORING (every 2 minutes):"
    log "  Service: $CRITICAL_SERVICE"
    log "  Timer: $CRITICAL_TIMER"
    log "  Monitors: Thermal spikes, USB storage resets, memory pressure"
    log ""
    log "COMPREHENSIVE MONITORING (every 6 hours):"
    log "  debug-watch.sh: Full system health checks"
    log "  i915-watch.sh: GPU-specific monitoring"
    log "  Weekly cleanup: Sunday 2 AM"
    log ""
    log "MONITORING:"
    log "  Critical alerts: journalctl -t critical-monitor -f"
    log "  Comprehensive: journalctl -t debug-watch -t i915-watch -f"
    log "  Service status: systemctl status $CRITICAL_TIMER"
    log ""
    log "MANUAL OPERATIONS:"
    log "  Test critical monitor: $SCRIPT_DIR/critical-monitor.sh --help"
    log "  Run diagnostics: $SCRIPT_DIR/debug-fix-all.sh --health-check"
    log "  Check GPU status: $I915_SCRIPT_DIR/i915-fix-all.sh --check-only"
    log "=== End Summary ==="
}

# Show help
show_help() {
    cat << 'EOF'
hybrid-install.sh - Install hybrid monitoring system (services + cron)

DESCRIPTION:
    Installs a hybrid monitoring approach combining real-time systemd services
    for critical issues with comprehensive cron-based monitoring for system health.

USAGE:
    ./hybrid-install.sh [OPTIONS]

OPTIONS:
    --help, -h              Show this help message
    --uninstall             Remove the hybrid monitoring system
    --service-only          Install only critical monitoring services
    --cron-only             Install only comprehensive cron monitoring
    --no-i915               Skip i915 GPU monitoring installation

MONITORING STRATEGY:
    REAL-TIME (2-minute intervals):
    • Thermal monitoring (>75°C warning, >85°C critical)
    • USB storage reset detection (freeze prevention)
    • Memory pressure monitoring (>90% warning, >95% critical)
    
    COMPREHENSIVE (6-hour intervals):
    • Full system health checks
    • Service failure detection and repair
    • Network connectivity monitoring
    • i915 GPU error monitoring
    • Hardware error analysis

INSTALLATION:
    sudo ./hybrid-install.sh

    The system will automatically:
    • Install systemd services for critical monitoring
    • Set up cron jobs for comprehensive checks
    • Configure log rotation
    • Enable Intel GPU monitoring if detected

MONITORING:
    journalctl -t critical-monitor -f    # Real-time critical alerts
    journalctl -t debug-watch -f         # Comprehensive monitoring
    systemctl status critical-monitor.timer  # Service status

EOF
}

# Main function
main() {
    local uninstall=0
    local service_only=0
    local cron_only=0
    local no_i915=0
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --uninstall)
                uninstall=1
                shift
                ;;
            --service-only)
                service_only=1
                shift
                ;;
            --cron-only)
                cron_only=1
                shift
                ;;
            --no-i915)
                no_i915=1
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    check_root
    
    if [[ $uninstall -eq 1 ]]; then
        uninstall_system
        exit 0
    fi
    
    log "Installing hybrid monitoring system..."
    
    # Install components based on options
    if [[ $service_only -eq 0 ]]; then
        install_comprehensive_crons
        if [[ $no_i915 -eq 0 ]]; then
            install_i915_subsystem
        fi
    fi
    
    if [[ $cron_only -eq 0 ]]; then
        install_critical_service
    fi
    
    # Always install log rotation
    install_log_rotation
    
    log "Installation completed successfully!"
    
    # Show summary unless in quiet mode
    show_summary
    
    exit 0
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
