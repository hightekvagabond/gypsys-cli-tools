#!/bin/bash
# USB monitoring module

MODULE_NAME="usb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

check_status() {
    local usb_resets
    usb_resets=$(check_usb_resets)
    
    # Check for docking station ethernet failures (thermal risk)
    local dock_failures
    dock_failures=$(count_dock_failures)
    
    if [[ $usb_resets -ge ${USB_RESET_CRITICAL:-20} ]]; then
        send_alert "critical" "🔌 Critical: $usb_resets USB device resets detected (may cause freeze)"
        log "USB Device Details:"
        get_usb_device_details "1 hour ago" | while read -r line; do
            log "$line"
        done
        attempt_usb_fix
        return 1
    elif [[ $dock_failures -gt 20 ]]; then
        send_alert "critical" "🌐 Critical: $dock_failures docking station ethernet failures - attempting adapter disable"
        attempt_network_fix "$dock_failures"
        return 1
    elif [[ $usb_resets -ge ${USB_RESET_WARNING:-10} ]]; then
        send_alert "warning" "🔌 Warning: $usb_resets USB device resets detected"
        log "USB Device Details:"
        get_usb_device_details "1 hour ago" | while read -r line; do
            log "$line"
        done
        return 1
    fi
    
    log "USB/Network status normal: $usb_resets USB resets, $dock_failures dock failures since boot"
    return 0
}

check_usb_resets() {
    local reset_count=0
    
    # Check for USB error patterns using journalctl (kernel messages)
    local patterns=(
        "usb.*reset"
        "USB disconnect"
        "device descriptor read"
        "uas_eh_abort_handler"
    )
    
    for pattern in "${patterns[@]}"; do
        # Use journalctl with kernel messages to get device details
        local count
        count=$(journalctl -k --since "1 hour ago" --no-pager 2>/dev/null | grep -c "$pattern" 2>/dev/null || true)
        
        # Simple validation - if count is empty or not a number, default to 0
        if [[ -z "$count" ]] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
            count=0
        fi
        
        reset_count=$((reset_count + count))
    done
    
    echo "$reset_count"
}

get_usb_device_details() {
    local time_period="${1:-1 hour ago}"
    
    # Get recent USB issues with device details
    echo "Recent USB issues ($time_period):"
    
    # Handle "boot" parameter specially
    local journal_cmd
    if [[ "$time_period" == "boot" ]]; then
        journal_cmd="journalctl -k -b 0 --no-pager 2>/dev/null"
    else
        journal_cmd="journalctl -k --since \"$time_period\" --no-pager 2>/dev/null"
    fi
    
    # USB disconnects with device info
    local disconnects
    disconnects=$(eval "$journal_cmd" | grep "USB disconnect" | tail -5)
    if [[ -n "$disconnects" ]]; then
        echo "  USB Disconnects:"
        echo "$disconnects" | while read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
            local device_info=$(echo "$line" | sed 's/.*usb /usb /' | sed 's/: USB disconnect.*//')
            local device_num=$(echo "$line" | grep -o "device number [0-9]*" || echo "")
            echo "    [$timestamp] $device_info $device_num"
        done
    fi
    
    # USB resets with device info
    local resets
    resets=$(eval "$journal_cmd" | grep "usb.*reset" | tail -3)
    if [[ -n "$resets" ]]; then
        echo "  USB Resets:"
        echo "$resets" | while read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
            local device_info=$(echo "$line" | sed 's/.*usb /usb /' | sed 's/ using.*/ [reset event]/')
            echo "    [$timestamp] $device_info"
        done
    fi
    
    # Device descriptor errors
    local descriptor_errors
    descriptor_errors=$(eval "$journal_cmd" | grep "device descriptor read" | tail -3)
    if [[ -n "$descriptor_errors" ]]; then
        echo "  Device Descriptor Errors:"
        echo "$descriptor_errors" | while read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
            local device_info=$(echo "$line" | sed 's/.*usb /usb /' | sed 's/: device descriptor.*/ [descriptor read error]/')
            echo "    [$timestamp] $device_info"
        done
    fi
    
    # Current USB device mapping for reference
    echo "  Current Connected USB Devices:"
    lsusb 2>/dev/null | while read -r line; do
        local bus_dev=$(echo "$line" | awk '{print $2, $4}' | sed 's/://')
        local device_name=$(echo "$line" | cut -d' ' -f7-)
        echo "    $bus_dev: $device_name"
    done
}

count_dock_failures() {
    # Count docking station ethernet/DHCP failures
    local dock_count
    dock_count=$(journalctl -b --no-pager 2>/dev/null | grep -c "ip-config-unavailable.*enx" 2>/dev/null || echo "0")
    
    # Simple validation
    if [[ -z "$dock_count" ]] || ! [[ "$dock_count" =~ ^[0-9]+$ ]]; then
        dock_count=0
    fi
    
    echo "$dock_count"
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

attempt_network_fix() {
    local dock_failures="$1"
    log "Attempting network adapter fix for $dock_failures dock failures..."
    
    # Try to disable the failing network adapter to prevent thermal overload
    local failed_adapter
    failed_adapter=$(journalctl -b --no-pager 2>/dev/null | grep "ip-config-unavailable.*enx" | tail -1 | grep -oE 'enx[a-f0-9]{12}' | head -1)
    
    if [[ -n "$failed_adapter" ]]; then
        log "EMERGENCY: Disabling failing network adapter: $failed_adapter"
        if command -v nmcli >/dev/null 2>&1; then
            # Disconnect the adapter and disable autoconnect temporarily
            nmcli device disconnect "$failed_adapter" 2>/dev/null || true
            
            # Disable autoconnect for all connections on this device (ephemeral - resets at reboot)
            nmcli connection show | grep "$failed_adapter" | awk '{print $1}' | while read -r conn_name; do
                if [[ -n "$conn_name" ]]; then
                    nmcli connection modify "$conn_name" connection.autoconnect no 2>/dev/null || true
                fi
            done
            
            # Create a temporary marker file that expires
            local marker_file="/tmp/network_disabled_${failed_adapter}"
            echo "$(date): Disabled due to ${dock_failures} DHCP failures" > "$marker_file" 2>/dev/null || true
            
            log "Network adapter $failed_adapter temporarily disabled (autoconnect off until reboot)"
            
            # Send both system alert and desktop notification
            send_alert "critical" "🚨 NETWORK ADAPTER TEMPORARILY DISABLED: '$failed_adapter' (${dock_failures} DHCP failures) - preventing thermal overload. Will auto-restore at reboot."
            
            # Desktop notification for immediate user awareness
            if command -v notify-send >/dev/null 2>&1; then
                DISPLAY=:0 notify-send -u critical -t 15000 "🚨 Network Adapter Disabled" \
                    "Disabled '$failed_adapter' due to ${dock_failures} DHCP failures.\nPreventing thermal overload.\nWill auto-restore at reboot." 2>/dev/null || true
            fi
        else
            send_alert "critical" "Docking station ethernet failures: ${dock_failures} - REMOVE DOCK TO PREVENT THERMAL OVERLOAD (nmcli not available)"
        fi
    else
        send_alert "critical" "Docking station ethernet failures: ${dock_failures} - REMOVE DOCK TO PREVENT THERMAL OVERLOAD"
    fi
    
    log "Network fix attempt completed"
}

# Module validation
validate_module "$MODULE_NAME"

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_status
fi