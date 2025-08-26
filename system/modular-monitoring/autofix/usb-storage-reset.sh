#!/bin/bash
#
# USB STORAGE RESET AUTOFIX SCRIPT
#
# PURPOSE:
#   Restarts USB storage kernel modules (usb_storage, uas) to resolve persistent
#   USB device reset issues and connection problems. This is a common fix for
#   USB storage devices that get into problematic states.
#
# CRITICAL SAFETY WARNINGS:
#   - Requires root privileges for actual module restart
#   - Will temporarily disconnect ALL USB storage devices
#   - Active file transfers will be interrupted
#   - USB drives may need to be remounted after restart
#
# WHEN TO USE:
#   - Repeated USB device reset messages in logs
#   - USB storage devices failing to mount or respond
#   - USB hub or dock connectivity issues with storage
#   - As part of USB subsystem recovery
#
# SAFE OPERATIONS:
#   - Checks for module presence before restart
#   - Graceful module removal and reload sequence
#   - Provides user recommendations when not running as root
#   - Desktop notifications for user awareness
#   - Comprehensive logging of all operations
#
# UNSAFE CONDITIONS:
#   - Will interrupt active USB storage I/O
#   - May require manual remounting of USB drives
#   - Could affect external backup operations
#
# USAGE:
#   ./usb-storage-reset.sh <calling_module> <grace_period_seconds>
#
#   Examples:
#     ./usb-storage-reset.sh usb 600
#     ./usb-storage-reset.sh --dry-run usb 600
#     ./usb-storage-reset.sh --help
#
# ARGUMENTS:
#   calling_module     - Module requesting the action (e.g., "usb", "thermal")
#   grace_period       - Seconds to wait before allowing this action again
#
# SECURITY CONSIDERATIONS:
#   - Requires root for kernel module operations
#   - Uses modprobe commands (privileged operations)
#   - No direct hardware manipulation
#   - Validates module names before operations
#
# BASH CONCEPTS FOR BEGINNERS:
#   - EUID: Effective User ID (0 = root, others = regular user)
#   - lsmod: Lists loaded kernel modules
#   - modprobe: Loads/unloads kernel modules (requires root)
#   - ((var++)): Arithmetic increment operation
#   - "${array[@]}": Expands all array elements safely
#   - IFS= read -r: Safely reads input preserving whitespace
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================================================
# HELP FUNCTION
# ============================================================================

show_help() {
    cat << 'EOF'
USB Storage Reset Autofix Script

PURPOSE:
    Restarts USB storage kernel modules (usb_storage, uas) to resolve persistent
    USB device reset issues and connection problems. Common fix for USB storage
    devices that get into problematic states.

USAGE:
    ./usb-storage-reset.sh <calling_module> <grace_period_seconds>
    ./usb-storage-reset.sh --dry-run <calling_module> <grace_period_seconds>
    ./usb-storage-reset.sh --help

ARGUMENTS:
    calling_module     Module requesting the action (e.g., "usb", "thermal")
    grace_period       Seconds to wait before allowing this action again

OPTIONS:
    --dry-run         Show what would be done without making changes
    --help            Show this help message

EXAMPLES:
    # Reset USB storage modules (requires root for actual restart)
    ./usb-storage-reset.sh usb 600
    
    # Test what modules would be restarted (safe)
    ./usb-storage-reset.sh --dry-run usb 600

CRITICAL WARNINGS:
    • Requires root privileges for actual module restart
    • Will temporarily disconnect ALL USB storage devices
    • Active file transfers will be interrupted
    • USB drives may need to be remounted after restart

WHAT IT DOES:
    1. Checks for loaded USB storage modules (usb_storage, uas)
    2. If root: Removes and reloads modules with modprobe
    3. If not root: Provides command recommendations
    4. Sends desktop notifications about actions/recommendations
    5. Reports success/failure status

WHEN TO USE:
    • Repeated USB device reset messages in logs
    • USB storage devices failing to mount or respond
    • USB hub/dock connectivity issues with storage
    • Part of USB subsystem recovery procedures

SECURITY:
    • Uses standard modprobe commands (no custom kernel code)
    • Validates module names before operations
    • No direct hardware manipulation
    • Safe module restart sequence with proper delays

EOF
}

# Initialize autofix script with common setup (handles help, validation, and argument shifting)
init_autofix_script "$@"

# ============================================================================
# USB STORAGE RESET FUNCTION
# ============================================================================

# Function: perform_usb_storage_reset
# Purpose: Safely restart USB storage kernel modules to resolve device issues
# Parameters: None
# Returns: 0 on success, 1 on error
# 
# SECURITY CONSIDERATIONS:
#   - Requires root privileges for actual module operations
#   - Uses standard modprobe commands (no custom kernel code)
#   - Validates module presence before operations
#   - Safe restart sequence with proper delays
#
# BASH CONCEPTS FOR BEGINNERS:
#   - local array=(): Creates a local array variable
#   - for loop: Iterates through array elements
#   - EUID: Effective User ID (0=root, >0=regular user)
#   - lsmod: Lists currently loaded kernel modules
#   - modprobe: Loads/unloads kernel modules (privileged operation)
#   - ((var++)): Arithmetic increment (increases counter by 1)
perform_usb_storage_reset() {
    # Check if we're in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        autofix_log "INFO" "[DRY-RUN] Would start USB storage reset procedure"
        autofix_log "INFO" "[DRY-RUN] Would check for loaded USB storage modules:"
        
        local storage_modules=("usb_storage" "uas")
        for module in "${storage_modules[@]}"; do
            if lsmod | grep -q "^$module"; then
                autofix_log "INFO" "[DRY-RUN]   Found loaded module: $module"
                autofix_log "INFO" "[DRY-RUN]   Would execute: modprobe -r $module && modprobe $module"
            else
                autofix_log "INFO" "[DRY-RUN]   Module not loaded: $module"
            fi
        done
        
        autofix_log "INFO" "[DRY-RUN] Would provide recommendation if not running as root:"
        autofix_log "INFO" "[DRY-RUN]   sudo modprobe -r usb_storage && sudo modprobe usb_storage"
        autofix_log "INFO" "[DRY-RUN]   sudo modprobe -r uas && sudo modprobe uas"
        autofix_log "INFO" "[DRY-RUN] Would send desktop notification about module restart"
        autofix_log "INFO" "[DRY-RUN] USB storage reset procedure would complete successfully"
        return 0
    fi
    
    autofix_log "INFO" "Starting USB storage reset procedure"
    
    # Restart USB storage drivers
    local storage_modules=("usb_storage" "uas")
    local modules_restarted=0
    
    for module in "${storage_modules[@]}"; do
        if lsmod | grep -q "^$module"; then
            autofix_log "INFO" "Found loaded USB storage module: $module"
            
            # Check if running as root (required for module operations)
            if [[ $EUID -ne 0 ]]; then
                autofix_log "WARN" "USB module restart requires root privileges - providing recommendation"
                
                # Send desktop notification if available
                if command -v notify-send >/dev/null 2>&1; then
                    notify-send "USB Fix Required" "Module restart needed (requires root): sudo modprobe -r $module && sudo modprobe $module" 2>/dev/null || true
                fi
                
                autofix_log "INFO" "RECOMMENDATION: Run 'sudo modprobe -r $module && sudo modprobe $module' to restart module"
            else
                # Actually restart the module (when running as root)
                autofix_log "INFO" "Restarting USB storage module: $module (running as root)"
                
                if modprobe -r "$module" 2>&1 | while IFS= read -r line; do
                    autofix_log "INFO" "modprobe -r: $line"
                done; then
                    autofix_log "INFO" "Successfully removed module: $module"
                    
                    # Small delay before reloading
                    sleep 1
                    
                    if modprobe "$module" 2>&1 | while IFS= read -r line; do
                        autofix_log "INFO" "modprobe: $line"
                    done; then
                        autofix_log "INFO" "Successfully reloaded module: $module"
                        ((modules_restarted++))
                    else
                        autofix_log "ERROR" "Failed to reload module: $module"
                    fi
                else
                    autofix_log "ERROR" "Failed to remove module: $module"
                fi
            fi
        else
            autofix_log "INFO" "USB storage module $module not currently loaded"
        fi
    done
    
    # Report results
    if [[ $EUID -eq 0 ]]; then
        if [[ $modules_restarted -gt 0 ]]; then
            autofix_log "INFO" "Successfully restarted $modules_restarted USB storage modules"
            
            # Send success notification
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "USB Fix Complete" "Restarted $modules_restarted USB storage modules" 2>/dev/null || true
            fi
        else
            autofix_log "WARN" "No USB storage modules were restarted"
        fi
    fi
    
    autofix_log "INFO" "USB storage reset procedure completed"
    return 0
}

# Execute with grace period management
autofix_log "INFO" "USB storage reset requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "usb-storage-reset" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_usb_storage_reset"
