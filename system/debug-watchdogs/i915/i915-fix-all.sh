#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#  i915-fix-all.sh - Unified Intel i915 GPU issue resolution script
#
#  DEVELOPER NOTES
#  ---------------
#  This script consolidates three previously separate scripts:
#  - fix_i915_flags.sh (GRUB kernel parameter management)  
#  - fix_gpu_modules.sh (DKMS module rebuilding)
#  - install_auto_fix_gpu_modules_after_package_upgrade.sh (system integration)
#
#  ARCHITECTURE
#  ------------
#  - Modular functions for each fix type (flags, DKMS, headers, checks)
#  - Granular control via command-line flags
#  - Consistent logging with both stdout and syslog
#  - Idempotent operations - safe to run multiple times
#  - Integration with i915-watch.sh for automated fixes
#
#  TECHNICAL DETAILS
#  -----------------
#  - Kernel flags applied: i915.enable_psr=0 i915.enable_dc=0 i915.enable_fbc=0 i915.disable_power_well=0
#  - DKMS modules handled: nvidia, evdi, virtualbox
#  - GRUB configuration: /etc/default/grub with automatic grub-mkconfig
#  - Error handling: Graceful degradation, non-zero exit only on critical failures
#
# -----------------------------------------------------------------------------

set -euo pipefail

# Configuration
SCRIPT_NAME="$(basename "$0")"
KERNEL=$(uname -r)
NEED_REBOOT=0
QUIET=0
FORCE_REBOOT=0

# i915 kernel flags - consolidated and consistent
REQUIRED_FLAGS="i915.enable_psr=0 i915.enable_dc=0 i915.enable_fbc=0 i915.disable_power_well=0"

# DKMS modules to check/rebuild
DKMS_MODULES=("nvidia" "evdi" "virtualbox")

# Logging function
log() {
    if [[ $QUIET -eq 0 ]]; then
        echo "[$SCRIPT_NAME] $*"
    fi
    logger -t "i915-fix-all" "$*"
}

# Error logging function
error() {
    echo "[$SCRIPT_NAME ERROR] $*" >&2
    logger -t "i915-fix-all" "ERROR: $*"
}

# Show help
show_help() {
    cat << 'EOF'
i915-fix-all.sh - Unified Intel i915 GPU issue resolution script

USAGE:
    sudo ./i915-fix-all.sh [OPTIONS]

OPTIONS:
    --flags-only          Apply GRUB kernel flags only
    --dkms-only           Rebuild DKMS modules only  
    --headers-only        Install kernel headers only
    --check-only          Check system status without making changes
    --force-reboot        Force reboot prompt even if no changes made
    --quiet               Minimal output (suitable for cron/automation)
    --help, -h            Show this help message

EXAMPLES:
    sudo ./i915-fix-all.sh                    # Run all fixes
    sudo ./i915-fix-all.sh --flags-only       # Only apply GRUB flags
    sudo ./i915-fix-all.sh --check-only       # Health check only
    sudo ./i915-fix-all.sh --quiet --dkms-only # Silent DKMS rebuild

KERNEL FLAGS APPLIED:
    i915.enable_psr=0        # Disable Panel Self-Refresh
    i915.enable_dc=0         # Disable display C-states
    i915.enable_fbc=0        # Disable framebuffer compression
    i915.disable_power_well=0 # Keep power wells active

TESTED ON:
    • Kubuntu 24.04 with Intel UHD 630 + NVIDIA RTX 2060
    • Hybrid GPU laptops with DisplayLink support
    • Any systemd-based distro with GRUB

EOF
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Install kernel headers if missing
install_kernel_headers() {
    log "Checking kernel headers for $KERNEL"
    
    if [[ -e "/lib/modules/$KERNEL/build" ]]; then
        log "Kernel headers already present for $KERNEL"
        return 0
    fi

    log "Installing kernel headers for $KERNEL"
    
    if ! apt-get -y update; then
        error "Failed to update package lists"
        return 1
    fi
    
    if ! apt-get -y install "linux-headers-$KERNEL" "linux-modules-extra-$KERNEL"; then
        error "Failed to install headers for $KERNEL"
        return 1
    fi
    
    log "Kernel headers installed successfully"
    return 0
}

# Rebuild DKMS modules
rebuild_dkms_modules() {
    log "Checking DKMS modules for kernel $KERNEL"
    
    local modules_rebuilt=0
    
    for mod in "${DKMS_MODULES[@]}"; do
        if dkms status | grep -q "$mod/.*,$KERNEL,.*installed"; then
            log "DKMS module $mod already built for $KERNEL"
            continue
        fi
        
        # Check if module source is available
        if ! dkms status | grep -q "$mod/"; then
            log "DKMS module $mod not available (skipping)"
            continue
        fi
        
        log "Building DKMS module $mod for $KERNEL"
        
        if dkms autoinstall -k "$KERNEL"; then
            log "Successfully built $mod for $KERNEL"
            modules_rebuilt=1
        else
            error "Failed to build DKMS module $mod"
            # Don't fail completely - other modules might work
        fi
    done
    
    if [[ $modules_rebuilt -eq 1 ]]; then
        NEED_REBOOT=1
        log "DKMS modules rebuilt - reboot recommended"
    fi
    
    return 0
}

# Apply i915 kernel flags to GRUB
apply_grub_flags() {
    local grub_file="/etc/default/grub"
    log "Checking i915 kernel flags in $grub_file"
    
    # Check if flags are already active in current boot
    if grep -q "$REQUIRED_FLAGS" /proc/cmdline; then
        log "Required i915 flags already active in current boot"
        return 0
    fi
    
    # Check if GRUB file exists
    if [[ ! -f "$grub_file" ]]; then
        error "GRUB configuration file not found: $grub_file"
        return 1
    fi
    
    # Get current GRUB_CMDLINE_LINUX line
    local current_line
    current_line=$(grep -E '^GRUB_CMDLINE_LINUX=' "$grub_file" || true)
    
    if [[ -z "$current_line" ]]; then
        log "Adding GRUB_CMDLINE_LINUX with i915 flags"
        echo "GRUB_CMDLINE_LINUX=\"$REQUIRED_FLAGS\"" >> "$grub_file"
    else
        # Extract existing flags
        local existing_flags
        existing_flags=$(echo "$current_line" | sed -E 's/^GRUB_CMDLINE_LINUX="(.*)"$/\1/')
        
        if echo "$existing_flags" | grep -q "i915.enable_psr=0"; then
            log "i915 flags already present in GRUB configuration"
            return 0
        fi
        
        log "Appending i915 flags to existing GRUB_CMDLINE_LINUX"
        local new_flags="$existing_flags $REQUIRED_FLAGS"
        sed -i -E "s|^GRUB_CMDLINE_LINUX=\".*\"|GRUB_CMDLINE_LINUX=\"${new_flags}\"|" "$grub_file"
    fi
    
    log "Regenerating GRUB configuration"
    if ! grub-mkconfig -o /boot/grub/grub.cfg; then
        error "Failed to regenerate GRUB configuration"
        return 1
    fi
    
    log "i915 flags applied successfully: $REQUIRED_FLAGS"
    NEED_REBOOT=1
    return 0
}

# Check system status
check_system_status() {
    log "=== i915 System Status Check ==="
    
    # Check kernel version
    log "Kernel: $KERNEL"
    
    # Check current i915 flags
    log "Active i915 flags:"
    if grep -o "i915\.[^[:space:]]*" /proc/cmdline | sort -u; then
        true  # grep found flags
    else
        log "  No i915 flags currently active"
    fi
    
    # Check GRUB configuration
    log "GRUB i915 configuration:"
    if grep -E '^GRUB_CMDLINE_LINUX=' /etc/default/grub | head -1; then
        true  # grep found config
    else
        log "  No GRUB_CMDLINE_LINUX found"
    fi
    
    # Check kernel headers
    if [[ -e "/lib/modules/$KERNEL/build" ]]; then
        log "Kernel headers: Present"
    else
        log "Kernel headers: Missing"
    fi
    
    # Check DKMS modules
    log "DKMS modules status:"
    for mod in "${DKMS_MODULES[@]}"; do
        if dkms status | grep -q "$mod/.*,$KERNEL,.*installed"; then
            log "  $mod: Built for $KERNEL"
        elif dkms status | grep -q "$mod/"; then
            log "  $mod: Available but not built for $KERNEL"
        else
            log "  $mod: Not available"
        fi
    done
    
    # Check recent i915 errors
    local error_count
    error_count=$(journalctl -b | grep -cE "i915.*ERROR|workqueue: i915_hpd" || echo "0")
    log "i915 errors this boot: $error_count"
    
    log "=== End Status Check ==="
}

# Trigger KDE reboot notification (same as Discover updates)
trigger_kde_reboot_notification() {
    # Try to trigger KDE's reboot notification via systemd
    if command -v systemctl >/dev/null 2>&1; then
        # This creates a reboot-required flag that KDE's system monitor picks up
        touch /var/run/reboot-required 2>/dev/null || true
        echo "i915-fix-all: GPU configuration updated" > /var/run/reboot-required.pkgs 2>/dev/null || true
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
            "i915 GPU configuration has been updated. Please reboot to apply changes." 2>/dev/null || true
    fi
}

# Handle reboot prompt
handle_reboot() {
    if [[ $NEED_REBOOT -eq 1 ]] || [[ $FORCE_REBOOT -eq 1 ]]; then
        if [[ $QUIET -eq 0 ]]; then
            log "Changes made that require a reboot to take effect"
            wall "i915-fix-all: GPU configuration updated - reboot recommended"
            trigger_kde_reboot_notification
        else
            log "Reboot required for changes to take effect"
            trigger_kde_reboot_notification
        fi
    fi
}

# Main execution function
main() {
    local do_flags=0
    local do_dkms=0
    local do_headers=0
    local do_check=0
    local flags_only=0
    local dkms_only=0
    local headers_only=0
    local check_only=0
    
    # Parse arguments (handle --help before root check)
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --flags-only)
                flags_only=1
                shift
                ;;
            --dkms-only)
                dkms_only=1
                shift
                ;;
            --headers-only)
                headers_only=1
                shift
                ;;
            --check-only)
                check_only=1
                shift
                ;;
            --force-reboot)
                FORCE_REBOOT=1
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
    
    # Determine what to do first
    if [[ $check_only -eq 1 ]]; then
        do_check=1
    elif [[ $flags_only -eq 1 ]]; then
        do_flags=1
    elif [[ $dkms_only -eq 1 ]]; then
        do_dkms=1
        do_headers=1  # Headers needed for DKMS
    elif [[ $headers_only -eq 1 ]]; then
        do_headers=1
    else
        # Default: do everything
        do_flags=1
        do_dkms=1
        do_headers=1
        do_check=1
    fi
    
    # Check for root only if we need to make changes
    if [[ $do_flags -eq 1 ]] || [[ $do_dkms -eq 1 ]] || [[ $do_headers -eq 1 ]]; then
        check_root
    fi
    
    # Execute requested actions
    log "Starting i915 fix-all script"
    
    if [[ $do_check -eq 1 ]]; then
        check_system_status
    fi
    
    if [[ $do_headers -eq 1 ]]; then
        install_kernel_headers || error "Failed to install kernel headers"
    fi
    
    if [[ $do_dkms -eq 1 ]]; then
        rebuild_dkms_modules || error "Failed to rebuild DKMS modules"
    fi
    
    if [[ $do_flags -eq 1 ]]; then
        apply_grub_flags || error "Failed to apply GRUB flags"
    fi
    
    handle_reboot
    
    log "i915 fix-all script completed"
    exit 0
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
