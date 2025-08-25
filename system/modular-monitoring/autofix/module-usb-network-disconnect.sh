#!/bin/bash
# Network Adapter Disconnect Autofix
# Disconnects failing network adapters to prevent thermal overload

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Source module config
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

attempt_network_disconnect() {
    local dock_failures="$1"
    log "AUTOFIX: Attempting network adapter disconnect for $dock_failures dock failures..."
    
    # Try to disable the failing network adapter to prevent thermal overload
    local failed_adapters
    failed_adapters=$(nmcli device status 2>/dev/null | grep -E "ethernet|wifi" | grep -v "connected" | awk '{print $1}' || echo "")
    
    if [[ -n "$failed_adapters" ]]; then
        echo "$failed_adapters" | while read -r failed_adapter; do
            if [[ -n "$failed_adapter" ]]; then
                log "AUTOFIX: Disconnecting potentially problematic adapter: $failed_adapter"
                
                # Check if NetworkManager is available
                if command -v nmcli >/dev/null 2>&1; then
                    nmcli device disconnect "$failed_adapter" 2>/dev/null || true
                    
                    # Disable autoconnect for all connections on this device (ephemeral - resets at reboot)
                    nmcli connection show | grep "$failed_adapter" | awk '{print $1}' | while read -r conn_name; do
                        if [[ -n "$conn_name" ]]; then
                            nmcli connection modify "$conn_name" connection.autoconnect no 2>/dev/null || true
                            log "AUTOFIX: Disabled autoconnect for connection: $conn_name"
                        fi
                    done
                    
                    send_alert "warning" "🌐 Network fix: Disconnected adapter $failed_adapter (temporary - resets at reboot)"
                else
                    log "AUTOFIX: NetworkManager not available for network disconnect"
                fi
            fi
        done
    else
        log "AUTOFIX: No problematic network adapters found"
    fi
    
    # Check for USB ethernet adapters specifically (common dock issue)
    local usb_ethernet
    usb_ethernet=$(lsusb | grep -i ethernet || echo "")
    
    if [[ -n "$usb_ethernet" ]]; then
        log "AUTOFIX: Found USB ethernet adapters:"
        echo "$usb_ethernet" | while read -r adapter; do
            log "AUTOFIX:   $adapter"
        done
        send_alert "info" "🔌 Note: USB ethernet adapters detected - may be related to dock failures"
    fi
    
    log "AUTOFIX: Network disconnect attempt completed"
    return 0
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    dock_failures="${1:-0}"
    attempt_network_disconnect "$dock_failures"
fi
