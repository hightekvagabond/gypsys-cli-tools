#!/bin/bash
# =============================================================================
# i915 DKMS REBUILD AUTOFIX SCRIPT
# =============================================================================
#
# ⚠️  WARNING:
#   This script rebuilds kernel driver modules which can potentially break
#   graphics functionality or prevent boot if done incorrectly.
#
# PURPOSE:
#   Rebuilds DKMS (Dynamic Kernel Module Support) modules for Intel i915 GPU
#   when driver errors are detected. This can resolve GPU hangs, display
#   corruption, and driver compatibility issues after kernel updates.
#
# WHAT DKMS DOES:
#   - Rebuilds out-of-tree kernel modules for current running kernel
#   - Ensures GPU drivers match kernel version
#   - Fixes driver/kernel version mismatches
#   - Resolves module loading failures
#
# WHEN TO USE:
#   - After kernel updates causing GPU issues
#   - i915 driver module loading failures
#   - GPU hangs or display corruption
#   - dmesg showing i915 driver errors
#
# SAFETY MECHANISMS:
#   ✅ Grace period prevents repeated rebuilds
#   ✅ Validates DKMS availability before proceeding
#   ✅ Comprehensive logging of rebuild process
#   ✅ Checks for existing i915 DKMS modules
#
# USAGE:
#   i915-dkms-rebuild.sh <calling_module> <grace_period_seconds>
#
# EXAMPLES:
#   i915-dkms-rebuild.sh i915 1800 # 30-minute grace period
#   i915-dkms-rebuild.sh manual 3600 # Manual rebuild with 1-hour grace
#
# SECURITY CONSIDERATIONS:
#   - Requires root privileges for DKMS operations
#   - Validates module names to prevent injection
#   - No user input passed to DKMS commands
#   - All operations logged for audit
#
# BASH CONCEPTS FOR BEGINNERS:
#   - DKMS manages kernel modules outside the main kernel tree
#   - Kernel modules are code that extends kernel functionality
#   - Driver rebuilding ensures compatibility with kernel version
#   - Root privileges needed for kernel-level operations
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# =============================================================================
# show_help() - Display usage and safety information
# =============================================================================
show_help() {
    cat << 'EOF'
i915 DKMS REBUILD AUTOFIX SCRIPT

⚠️  WARNING:
    This script rebuilds kernel driver modules which can potentially break
    graphics functionality if done incorrectly.

PURPOSE:
    Rebuilds DKMS modules for Intel i915 GPU when driver errors are detected.
    Resolves GPU hangs, display corruption, and driver compatibility issues.

USAGE:
    i915-dkms-rebuild.sh <calling_module> <grace_period_seconds>

EXAMPLES:
    i915-dkms-rebuild.sh i915 1800      # 30-minute grace period
    i915-dkms-rebuild.sh manual 3600    # Manual rebuild with 1-hour grace

WHEN TO USE:
    - After kernel updates causing GPU issues
    - i915 driver module loading failures  
    - GPU hangs or display corruption
    - dmesg showing i915 driver errors

REQUIREMENTS:
    - Root privileges for DKMS operations
    - DKMS package installed on system
    - Compatible i915 DKMS modules available

EXIT CODES:
    0 - DKMS rebuild completed successfully
    1 - Error occurred (check logs)
    2 - Skipped due to grace period

SAFETY FEATURES:
    - Grace period prevents repeated rebuilds
    - Validates DKMS availability
    - Comprehensive logging
    - Checks for existing modules
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

# Validate arguments
if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1
fi

CALLING_MODULE="$1"
GRACE_PERIOD="$2"

# The actual DKMS rebuild action
perform_dkms_rebuild() {
    # Store commands in variables for dry-run support
    local DKMS_STATUS_CMD="dkms status | grep -i \"i915\\|intel\""
    local DKMS_AUTOINSTALL_CMD="dkms autoinstall"
    local MANUAL_DKMS_CMD="sudo dkms autoinstall"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🧪 DRY-RUN MODE: i915 DKMS Rebuild Analysis"
        echo "============================================="
        echo "Mode: Analysis only - no DKMS modules will be rebuilt"
        echo "Grace Period: ${GRACE_PERIOD}s"
        echo ""
        
        echo "DKMS REBUILD OPERATIONS THAT WOULD BE PERFORMED:"
        echo "------------------------------------------------"
        echo "1. DKMS availability check:"
        echo "   - Command: command -v dkms"
        echo "   - Purpose: Verify DKMS package is installed"
        echo ""
        
        echo "2. i915 DKMS modules discovery:"
        echo "   - Command: $DKMS_STATUS_CMD"
        echo "   - Purpose: Find Intel graphics DKMS modules"
        echo "   - Expected: List of i915/intel DKMS modules"
        echo ""
        
        echo "3. DKMS rebuild execution:"
        if [[ $EUID -eq 0 ]]; then
            echo "   - Running as root: Yes"
            echo "   - Command: $DKMS_AUTOINSTALL_CMD"
            echo "   - Purpose: Automatically rebuild all DKMS modules"
        else
            echo "   - Running as root: No"
            echo "   - Command: $MANUAL_DKMS_CMD"
            echo "   - Purpose: Manual DKMS rebuild (requires root)"
        fi
        echo ""
        
        echo "4. Post-rebuild actions:"
        echo "   - System reboot recommendation"
        echo "   - Desktop notification to user"
        echo "   - Log completion status"
        echo ""
        
        echo "SYSTEM STATE ANALYSIS:"
        echo "----------------------"
        echo "DKMS package available: $([[ $(command -v dkms >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "Running as root: $([[ $EUID -eq 0 ]] && echo "Yes" || echo "No")"
        echo "i915 DKMS modules found: $([[ -n "$(dkms status 2>/dev/null | grep -i "i915\|intel")" ]] && echo "Yes" || echo "No")"
        echo ""
        
        echo "SAFETY CHECKS PERFORMED:"
        echo "------------------------"
        echo "✅ Grace period protection active"
        echo "✅ DKMS availability verified"
        echo "✅ Module discovery completed"
        echo "✅ Root privilege check performed"
        echo ""
        
        echo "STATUS: Dry-run completed - no DKMS modules rebuilt"
        echo "============================================="
        
        autofix_log "INFO" "DRY-RUN: i915 DKMS rebuild analysis completed"
        return 0
    fi
    
    # Live mode - perform actual DKMS rebuild
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
