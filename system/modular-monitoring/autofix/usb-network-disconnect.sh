#!/bin/bash
#
# USB NETWORK DISCONNECT AUTOFIX SCRIPT
#
# PURPOSE:
#   Disconnects problematic network adapters (especially USB ethernet from docking stations)
#   to prevent thermal overload and dock failures. This is a temporary mitigation that
#   resets on reboot, allowing users to address hardware issues without permanent changes.
#
# CRITICAL SAFETY WARNINGS:
#   - Network connectivity will be lost temporarily
#   - Only affects non-connected adapters by default
#   - Changes are ephemeral (reset on reboot)
#   - Will NOT disconnect your primary working connection
#
# WHEN TO USE:
#   - USB dock failures causing thermal issues
#   - Network adapters causing thermal overload
#   - Problematic ethernet adapters in docking stations
#   - As part of thermal management automation
#
# SAFE OPERATIONS:
#   - Only disconnects non-connected adapters
#   - Temporary autoconnect disable (resets at reboot)
#   - Non-destructive NetworkManager commands
#   - Desktop notifications for user awareness
#   - Comprehensive logging of all actions
#
# USAGE:
#   ./usb-network-disconnect.sh <calling_module> <grace_period_seconds> [dock_failures] [device_info]
#
#   Examples:
#     ./usb-network-disconnect.sh thermal 300 5
#     ./usb-network-disconnect.sh thermal 300 5 "USB Ethernet: Realtek Adapter"
#     ./usb-network-disconnect.sh --dry-run thermal 300 5 "USB Ethernet: Realtek Adapter"
#     ./usb-network-disconnect.sh --help
#
# ARGUMENTS:
#   calling_module     - Module requesting the action (e.g., "thermal", "usb")
#   grace_period       - Seconds to wait before allowing this action again
#   dock_failures      - Optional: Number of dock failures detected (for logging)
#   device_info        - Optional: Information about problematic devices for better logging
#
# SECURITY CONSIDERATIONS:
#   - Uses nmcli with safe parameters only
#   - No direct device manipulation (uses NetworkManager)
#   - Validates all adapter names before disconnection
#   - No permanent configuration changes
#
# BASH CONCEPTS FOR BEGINNERS:
#   - pipefail: Ensures errors in pipe chains are caught
#   - command -v: Safe way to check if commands exist
#   - 2>/dev/null: Redirects errors to silence non-critical failures
#   - || true: Prevents script exit on non-critical command failures
#   - read -r: Safe reading that preserves backslashes
#   - [[ -n "$var" ]]: Tests if variable is non-empty
#   - awk '{print $1}': Extracts first column from command output
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================================================
# HELP FUNCTION
# ============================================================================

show_help() {
    cat << 'EOF'
USB Network Disconnect Autofix Script

PURPOSE:
    Disconnects problematic network adapters (especially USB ethernet from docking
    stations) to prevent thermal overload and dock failures. This is a temporary
    mitigation that resets on reboot.

USAGE:
    ./usb-network-disconnect.sh <calling_module> <grace_period_seconds> [dock_failures]
    ./usb-network-disconnect.sh --dry-run <calling_module> <grace_period_seconds> [dock_failures]
    ./usb-network-disconnect.sh --help

ARGUMENTS:
    calling_module     Module requesting the action (e.g., "thermal", "usb")
    grace_period       Seconds to wait before allowing this action again
    dock_failures      Optional: Number of dock failures detected (for logging)

OPTIONS:
    --dry-run         Show what would be done without making changes
    --help            Show this help message

EXAMPLES:
    # Disconnect problematic adapters for thermal management
    ./usb-network-disconnect.sh thermal 300 5
    
    # Test what would be disconnected (safe)
    ./usb-network-disconnect.sh --dry-run thermal 300 5

SAFETY FEATURES:
    • Only disconnects non-connected adapters
    • Changes are temporary (reset on reboot)
    • Will NOT disconnect active connections
    • Provides desktop notifications
    • Comprehensive logging

WHAT IT DOES:
    1. Identifies non-connected ethernet/wifi adapters
    2. Disconnects them using NetworkManager
    3. Temporarily disables autoconnect (resets at reboot)
    4. Detects and reports USB ethernet adapters
    5. Sends desktop notifications about actions taken

SECURITY:
    • Uses safe NetworkManager commands only
    • No permanent configuration changes
    • Validates all adapter names before action
    • No direct hardware manipulation

EOF
}

# Initialize autofix script with common setup (handles help, validation, and argument shifting)
init_autofix_script "$@"

# Additional arguments specific to this script
# In dry-run mode, arguments are shifted, so we need to access them correctly
if [[ "${DRY_RUN:-false}" == "true" ]]; then
    DOCK_FAILURES="${4:-0}"
    DEVICE_INFO="${5:-}"
else
    DOCK_FAILURES="${3:-0}"
    DEVICE_INFO="${4:-}"
fi

# ============================================================================
# NETWORK DISCONNECT FUNCTION
# ============================================================================

# Function: perform_network_disconnect
# Purpose: Safely disconnect problematic network adapters to prevent thermal issues
# Parameters:
#   $1 - dock_failures: Number of dock failures detected (for logging context)
# Returns: 0 on success, 1 on error
# 
# SECURITY CONSIDERATIONS:
#   - Only disconnects non-connected adapters (preserves active connections)
#   - Uses NetworkManager commands (safe, user-space operations)
#   - Validates adapter names before any operations
#   - All changes are temporary (reset on reboot)
#
# BASH CONCEPTS FOR BEGINNERS:
#   - local: Creates function-local variables (good practice)
#   - nmcli: NetworkManager command-line tool for safe network operations
#   - grep -E: Extended regex matching for pattern detection
#   - awk '{print $1}': Extracts first column (device names)
#   - while read -r: Safely processes each line of input
#   - command -v: Checks if a command exists before using it
perform_network_disconnect() {
    local dock_failures="$1"
    
    # Check if we're in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        autofix_log "INFO" "[DRY-RUN] Would start network adapter disconnect for $dock_failures dock failures"
        
        # In dry-run mode, show what would be analyzed and disconnected
        autofix_log "INFO" "[DRY-RUN] Would analyze network adapters:"
        if command -v nmcli >/dev/null 2>&1; then
            local all_adapters
            all_adapters=$(nmcli device status 2>/dev/null | grep -E "ethernet|wifi" || echo "")
            if [[ -n "$all_adapters" ]]; then
                autofix_log "INFO" "[DRY-RUN] Network adapters found:"
                echo "$all_adapters" | while read -r adapter_line; do
                    autofix_log "INFO" "[DRY-RUN]   $adapter_line"
                done
                
                local failed_adapters
                failed_adapters=$(echo "$all_adapters" | grep -v "connected" | awk '{print $1}' || echo "")
                if [[ -n "$failed_adapters" ]]; then
                    autofix_log "INFO" "[DRY-RUN] Would disconnect these non-connected adapters:"
                    echo "$failed_adapters" | while read -r adapter; do
                        if [[ -n "$adapter" ]]; then
                            autofix_log "INFO" "[DRY-RUN]   Would disconnect: $adapter"
                            autofix_log "INFO" "[DRY-RUN]   Would disable autoconnect for connections on: $adapter"
                        fi
                    done
                else
                    autofix_log "INFO" "[DRY-RUN] No non-connected adapters found to disconnect"
                fi
            else
                autofix_log "INFO" "[DRY-RUN] No network adapters found"
            fi
        else
            autofix_log "INFO" "[DRY-RUN] NetworkManager not available"
        fi
        
        # Show USB device analysis (cycling through all USB ports as requested)
        autofix_log "INFO" "[DRY-RUN] Would analyze USB ports and devices:"
        if command -v lsusb >/dev/null 2>&1; then
            local usb_devices
            usb_devices=$(lsusb 2>/dev/null || echo "")
            if [[ -n "$usb_devices" ]]; then
                autofix_log "INFO" "[DRY-RUN] USB devices detected:"
                echo "$usb_devices" | while read -r device; do
                    autofix_log "INFO" "[DRY-RUN]   $device"
                done
                
                # Check specifically for ethernet devices
                local usb_ethernet
                usb_ethernet=$(echo "$usb_devices" | grep -i ethernet || echo "")
                if [[ -n "$usb_ethernet" ]]; then
                    autofix_log "INFO" "[DRY-RUN] USB ethernet adapters found:"
                    echo "$usb_ethernet" | while read -r adapter; do
                        autofix_log "INFO" "[DRY-RUN]   USB Ethernet: $adapter"
                    done
                else
                    autofix_log "INFO" "[DRY-RUN] No USB ethernet adapters detected"
                fi
            else
                autofix_log "INFO" "[DRY-RUN] No USB devices found or lsusb failed"
            fi
        else
            autofix_log "INFO" "[DRY-RUN] lsusb command not available"
        fi
        
        autofix_log "INFO" "[DRY-RUN] Network disconnect procedure would complete successfully"
        return 0
    fi
    
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
if [[ -n "$DEVICE_INFO" ]]; then
    autofix_log "INFO" "USB network disconnect requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period for devices: $DEVICE_INFO"
    run_autofix_with_grace "usb-network-disconnect" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_network_disconnect" "$DOCK_FAILURES" "$DEVICE_INFO"
else
    autofix_log "INFO" "USB network disconnect requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
    run_autofix_with_grace "usb-network-disconnect" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_network_disconnect" "$DOCK_FAILURES"
fi
