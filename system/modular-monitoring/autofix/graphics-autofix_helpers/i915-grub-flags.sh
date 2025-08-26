#!/bin/bash
# =============================================================================
# i915 GRUB FLAGS AUTOFIX SCRIPT
# =============================================================================
#
# 🚨 CRITICAL DANGER WARNING:
#   This script modifies GRUB bootloader configuration which can make your
#   system UNBOOTABLE if done incorrectly. Always have recovery media ready.
#
# PURPOSE:
#   Applies Intel i915 GPU kernel parameters via GRUB to resolve hardware
#   compatibility issues, GPU hangs, and display problems. These parameters
#   modify how the i915 driver initializes and operates.
#
# COMMON i915 KERNEL PARAMETERS:
#   - i915.enable_psr=0     : Disable Panel Self Refresh (fixes flickering)
#   - i915.enable_fbc=0     : Disable Framebuffer Compression (stability)
#   - i915.enable_dc=0      : Disable Display C-states (power management)
#   - i915.modeset=1        : Enable kernel mode setting
#   - i915.enable_guc=0     : Disable GuC firmware loading
#
# WHEN TO USE:
#   - GPU hangs or system freezes
#   - Display flickering or corruption
#   - Screen tearing or artifacts
#   - Power management issues with display
#   - After hardware changes affecting GPU
#
# BOOTLOADER SAFETY:
#   ⚠️  GRUB modification risks making system unbootable
#   ⚠️  Always backup /etc/default/grub before changes
#   ⚠️  Test parameters manually before permanent application
#   ⚠️  Have recovery/rescue media available
#
# USAGE:
#   i915-grub-flags.sh <calling_module> <grace_period_seconds>
#
# EXAMPLES:
#   i915-grub-flags.sh i915 7200    # 2-hour grace (rare operation)
#   i915-grub-flags.sh manual 3600  # Manual application
#
# SECURITY CONSIDERATIONS:
#   - Requires root privileges for GRUB modification
#   - Validates GRUB configuration before modification
#   - Creates backup of original GRUB configuration
#   - All changes logged for audit and recovery
#
# BASH CONCEPTS FOR BEGINNERS:
#   - GRUB is the bootloader that starts your operating system
#   - Kernel parameters control low-level hardware behavior
#   - Bootloader changes affect system startup process
#   - Always backup before modifying boot configuration
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Validate arguments
if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1
fi

CALLING_MODULE="$1"
GRACE_PERIOD="$2"

# The actual GRUB flags application
apply_i915_grub_flags() {
    # Check if we're in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        autofix_log "INFO" "[DRY-RUN] Would start i915 GRUB flags application"
        autofix_log "INFO" "[DRY-RUN] Would check GRUB configuration at /etc/default/grub"
        autofix_log "INFO" "[DRY-RUN] Would check if i915 flags are already present: grep 'i915.enable_psr=0'"
        autofix_log "INFO" "[DRY-RUN] Would backup GRUB config: cp /etc/default/grub /etc/default/grub.backup.TIMESTAMP"
        autofix_log "INFO" "[DRY-RUN] Would add i915 stability flags: 'i915.enable_psr=0 i915.enable_fbc=0'"
        autofix_log "INFO" "[DRY-RUN] Would update GRUB configuration: update-grub"
        autofix_log "INFO" "[DRY-RUN] Would recommend system reboot to apply kernel parameters"
        autofix_log "INFO" "[DRY-RUN] i915 GRUB flags application would complete successfully"
        return 0
    fi
    
    autofix_log "INFO" "Starting i915 GRUB flags application"
    
    # Check current GRUB configuration
    local grub_file="/etc/default/grub"
    if [[ ! -f "$grub_file" ]]; then
        autofix_log "ERROR" "GRUB configuration file not found: $grub_file"
        return 1
    fi
    
    # Check if i915 flags are already set
    if grep -q "i915.enable_psr=0" "$grub_file" 2>/dev/null; then
        autofix_log "INFO" "i915 GRUB flags already present in configuration"
        return 0  # Already configured
    fi
    
    autofix_log "INFO" "i915 stability flags not found in GRUB configuration"
    
    # Check if running as root (required for GRUB modifications)
    if [[ $EUID -ne 0 ]]; then
        autofix_log "WARN" "GRUB modification requires root privileges - providing recommendation"
        
        # Send desktop notification if available
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "i915 Fix Required" "GRUB flags needed: i915.enable_psr=0 i915.enable_fbc=0" 2>/dev/null || true
        fi
        
        autofix_log "INFO" "RECOMMENDATION: Add 'i915.enable_psr=0 i915.enable_fbc=0' to GRUB_CMDLINE_LINUX in $grub_file"
        autofix_log "INFO" "RECOMMENDATION: Run 'sudo update-grub' after making changes"
        autofix_log "INFO" "RECOMMENDATION: Reboot to apply new kernel parameters"
        
        return 0  # Success - we provided the recommendation
    fi
    
    # Apply GRUB flags (when running as root)
    autofix_log "INFO" "Applying i915 stability flags to GRUB configuration (running as root)..."
    
    # Create backup of GRUB configuration
    local backup_file="${grub_file}.backup.$(date +%Y%m%d-%H%M%S)"
    if cp "$grub_file" "$backup_file"; then
        autofix_log "INFO" "Created GRUB backup: $backup_file"
    else
        autofix_log "ERROR" "Failed to create GRUB backup - aborting"
        return 1
    fi
    
    # Apply the i915 flags by modifying GRUB_CMDLINE_LINUX
    local i915_flags="i915.enable_psr=0 i915.enable_fbc=0"
    
    if grep -q "^GRUB_CMDLINE_LINUX=" "$grub_file"; then
        # Append to existing GRUB_CMDLINE_LINUX
        sed -i "/^GRUB_CMDLINE_LINUX=/ s/\"$/ $i915_flags\"/" "$grub_file"
        autofix_log "INFO" "Added i915 flags to existing GRUB_CMDLINE_LINUX"
    else
        # Add new GRUB_CMDLINE_LINUX line
        echo "GRUB_CMDLINE_LINUX=\"$i915_flags\"" >> "$grub_file"
        autofix_log "INFO" "Added new GRUB_CMDLINE_LINUX with i915 flags"
    fi
    
    # Update GRUB
    autofix_log "INFO" "Updating GRUB configuration..."
    if update-grub 2>&1 | while IFS= read -r line; do
        autofix_log "INFO" "GRUB: $line"
    done; then
        autofix_log "INFO" "GRUB configuration updated successfully"
        
        # Recommend reboot
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "i915 Fix Complete" "GRUB flags applied - reboot required" 2>/dev/null || true
        fi
        
        autofix_log "INFO" "i915 GRUB flags applied - system reboot required for changes to take effect"
        return 0
    else
        autofix_log "ERROR" "Failed to update GRUB configuration - restoring backup"
        
        # Restore backup on failure
        if cp "$backup_file" "$grub_file"; then
            autofix_log "INFO" "GRUB configuration restored from backup"
        else
            autofix_log "ERROR" "Failed to restore GRUB backup - manual intervention required"
        fi
        
        return 1
    fi
}

# Execute with grace period management
autofix_log "INFO" "i915 GRUB flags requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "i915-grub-flags" "$CALLING_MODULE" "$GRACE_PERIOD" "apply_i915_grub_flags"
