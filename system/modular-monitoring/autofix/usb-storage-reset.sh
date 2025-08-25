#!/bin/bash
# USB Storage Reset Autofix Script
# Usage: usb-storage-reset.sh <calling_module> <grace_period_seconds>
# Restarts USB storage drivers to fix USB device reset issues

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Validate arguments
if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1
fi

CALLING_MODULE="$1"
GRACE_PERIOD="$2"

# The actual USB storage reset action
perform_usb_storage_reset() {
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
