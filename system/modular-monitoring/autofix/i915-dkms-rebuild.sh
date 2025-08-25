#!/bin/bash
# i915 DKMS Rebuild Autofix Script
# Usage: i915-dkms-rebuild.sh <calling_module> <grace_period_seconds>
# Attempts to rebuild DKMS modules for i915 GPU issues

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Validate arguments
if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1
fi

CALLING_MODULE="$1"
GRACE_PERIOD="$2"

# The actual DKMS rebuild action
perform_dkms_rebuild() {
    autofix_log "INFO" "Starting i915 DKMS rebuild process"
    
    # Check if DKMS is available
    if ! command -v dkms >/dev/null 2>&1; then
        autofix_log "ERROR" "DKMS not available on system"
        return 1
    fi
    
    # List i915-related DKMS modules
    local dkms_modules
    dkms_modules=$(dkms status 2>/dev/null | grep -i "i915\|intel" || echo "")
    
    if [[ -z "$dkms_modules" ]]; then
        autofix_log "WARN" "No i915 DKMS modules found"
        # Still return success since this isn't necessarily an error
        return 0
    fi
    
    autofix_log "INFO" "Found DKMS modules: $dkms_modules"
    
    # Check if running as root (required for DKMS operations)
    if [[ $EUID -ne 0 ]]; then
        autofix_log "WARN" "DKMS rebuild requires root privileges - providing recommendation"
        
        # Send desktop notification if available
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "i915 Fix Required" "DKMS rebuild needed (requires root): sudo dkms autoinstall" 2>/dev/null || true
        fi
        
        autofix_log "INFO" "RECOMMENDATION: Run 'sudo dkms autoinstall' to rebuild i915 modules"
        autofix_log "INFO" "RECOMMENDATION: After successful rebuild, reboot the system"
        
        return 0  # Success - we provided the recommendation
    fi
    
    # Perform actual DKMS rebuild (when running as root)
    autofix_log "INFO" "Rebuilding DKMS modules (running as root)..."
    
    if dkms autoinstall 2>&1 | while IFS= read -r line; do
        autofix_log "INFO" "DKMS: $line"
    done; then
        autofix_log "INFO" "DKMS autoinstall completed successfully"
        
        # Recommend reboot if modules were rebuilt
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "i915 Fix Complete" "DKMS modules rebuilt - reboot recommended" 2>/dev/null || true
        fi
        
        autofix_log "INFO" "DKMS rebuild complete - system reboot recommended for changes to take effect"
        return 0
    else
        autofix_log "ERROR" "DKMS autoinstall failed - check system logs for details"
        return 1
    fi
}

# Execute with grace period management
autofix_log "INFO" "i915 DKMS rebuild requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "i915-dkms-rebuild" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_dkms_rebuild"
