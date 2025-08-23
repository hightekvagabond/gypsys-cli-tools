#!/bin/bash
# USB monitoring module

MODULE_NAME="usb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

check_status() {
    local usb_resets
    usb_resets=$(check_usb_resets)
    
    if [[ $usb_resets -ge ${USB_RESET_CRITICAL:-20} ]]; then
        send_alert "critical" "🔌 Critical: $usb_resets USB device resets detected (may cause freeze)"
        attempt_usb_fix
        return 1
    elif [[ $usb_resets -ge ${USB_RESET_WARNING:-10} ]]; then
        send_alert "warning" "🔌 Warning: $usb_resets USB device resets detected"
        return 1
    fi
    
    log "USB status normal: $usb_resets resets since boot"
    return 0
}

check_usb_resets() {
    local reset_count=0
    
    # Check for USB error patterns using journalctl
    local patterns=(
        "usb.*reset"
        "USB disconnect"
        "device descriptor read"
        "uas_eh_abort_handler"
    )
    
    for pattern in "${patterns[@]}"; do
        # Use journalctl with a simple approach
        local count
        count=$(journalctl --since "1 hour ago" --no-pager 2>/dev/null | grep -c "$pattern" 2>/dev/null || true)
        
        # Simple validation - if count is empty or not a number, default to 0
        if [[ -z "$count" ]] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
            count=0
        fi
        
        reset_count=$((reset_count + count))
    done
    
    echo "$reset_count"
}

attempt_usb_fix() {
    log "Attempting USB storage fix..."
    
    # Restart USB storage drivers
    if lsmod | grep -q "usb_storage"; then
        log "Restarting USB storage module"
        modprobe -r usb_storage 2>/dev/null || true
        sleep 1
        modprobe usb_storage 2>/dev/null || true
    fi
    
    # Reset USB controllers if available
    for usb_dev in /sys/bus/pci/drivers/xhci_hcd/*/power/control; do
        if [[ -f "$usb_dev" ]]; then
            echo "auto" > "$usb_dev" 2>/dev/null || true
        fi
    done
    
    log "USB fix attempt completed"
}

# Module validation
validate_module "$MODULE_NAME"

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_status
fi