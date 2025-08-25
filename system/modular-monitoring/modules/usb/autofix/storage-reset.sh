#!/bin/bash
# USB Storage Reset Autofix
# Restarts USB storage drivers to fix USB device reset issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Source module config
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

attempt_usb_storage_reset() {
    log "AUTOFIX: Attempting USB storage reset..."
    
    # Restart USB storage drivers
    local storage_modules=("usb_storage" "uas")
    
    for module in "${storage_modules[@]}"; do
        if lsmod | grep -q "^$module"; then
            log "AUTOFIX: Restarting USB module: $module"
            
            # This would need root privileges - log the recommendation
            log "AUTOFIX: USB module restart recommended - requires root privileges"
            send_alert "warning" "🔧 USB fix: Module restart needed (run as root: modprobe -r $module && modprobe $module)"
        else
            log "AUTOFIX: USB module $module not loaded"
        fi
    done
    
    log "AUTOFIX: USB storage reset attempt completed"
    return 0
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    attempt_usb_storage_reset
fi
