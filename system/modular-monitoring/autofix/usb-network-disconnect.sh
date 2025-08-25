#!/bin/bash
# USB Network Disconnect Autofix Script
# Usage: usb-network-disconnect.sh <calling_module> <grace_period_seconds> [dock_failures]
# Disconnects failing network adapters to prevent thermal overload

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Validate arguments
if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1
fi

CALLING_MODULE="$1"
GRACE_PERIOD="$2"
DOCK_FAILURES="${3:-0}"

# The actual network disconnect action
perform_network_disconnect() {
    local dock_failures="$1"
    
    autofix_log "INFO" "Starting network adapter disconnect for $dock_failures dock failures"
    
    # Try to disable the failing network adapter to prevent thermal overload
    local failed_adapters
    failed_adapters=$(nmcli device status 2>/dev/null | grep -E "ethernet|wifi" | grep -v "connected" | awk '{print $1}' || echo "")
    
    if [[ -n "$failed_adapters" ]]; then
        echo "$failed_adapters" | while read -r failed_adapter; do
            if [[ -n "$failed_adapter" ]]; then
                autofix_log "INFO" "Disconnecting potentially problematic adapter: $failed_adapter"
                
                # Check if NetworkManager is available
                if command -v nmcli >/dev/null 2>&1; then
                    if nmcli device disconnect "$failed_adapter" 2>/dev/null; then
                        autofix_log "INFO" "Successfully disconnected adapter: $failed_adapter"
                    else
                        autofix_log "WARN" "Failed to disconnect adapter: $failed_adapter"
                    fi
                    
                    # Disable autoconnect for all connections on this device (ephemeral - resets at reboot)
                    nmcli connection show | grep "$failed_adapter" | awk '{print $1}' | while read -r conn_name; do
                        if [[ -n "$conn_name" ]]; then
                            if nmcli connection modify "$conn_name" connection.autoconnect no 2>/dev/null; then
                                autofix_log "INFO" "Disabled autoconnect for connection: $conn_name"
                            else
                                autofix_log "WARN" "Failed to disable autoconnect for: $conn_name"
                            fi
                        fi
                    done
                    
                    # Send desktop notification if available
                    if command -v notify-send >/dev/null 2>&1; then
                        notify-send "Network Fix Applied" "Disconnected adapter $failed_adapter (temporary - resets at reboot)" 2>/dev/null || true
                    fi
                else
                    autofix_log "ERROR" "NetworkManager not available for network disconnect"
                    return 1
                fi
            fi
        done
    else
        autofix_log "INFO" "No problematic network adapters found"
    fi
    
    # Check for USB ethernet adapters specifically (common dock issue)
    local usb_ethernet
    usb_ethernet=$(lsusb | grep -i ethernet || echo "")
    
    if [[ -n "$usb_ethernet" ]]; then
        autofix_log "INFO" "Found USB ethernet adapters:"
        echo "$usb_ethernet" | while read -r adapter; do
            autofix_log "INFO" "  $adapter"
        done
        
        # Send notification about USB ethernet detection
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "USB Ethernet Detected" "USB ethernet adapters may be related to dock failures" 2>/dev/null || true
        fi
    else
        autofix_log "INFO" "No USB ethernet adapters detected"
    fi
    
    autofix_log "INFO" "Network disconnect procedure completed"
    return 0
}

# Execute with grace period management
autofix_log "INFO" "USB network disconnect requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "usb-network-disconnect" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_network_disconnect" "$DOCK_FAILURES"
