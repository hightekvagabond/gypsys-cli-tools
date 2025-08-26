#!/bin/bash
# =============================================================================
# USB MODULE HARDWARE SCAN SCRIPT
# =============================================================================
#
# PURPOSE:
#   Detect USB hardware and generate appropriate configuration for the
#   USB monitoring module.
#
# CAPABILITIES:
#   - USB controller detection
#   - USB device enumeration
#   - USB version support analysis
#   - USB port configuration
#
# USAGE:
#   ./scan.sh                    # Human-readable scan results
#   ./scan.sh --config          # Machine-readable config format
#   ./scan.sh --help            # Show help information
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="usb"

show_help() {
    cat << 'EOF'
USB HARDWARE SCAN SCRIPT

PURPOSE:
    Detect USB hardware and generate configuration for the USB
    monitoring module.

USAGE:
    ./scan.sh                    # Human-readable scan results
    ./scan.sh --config          # Machine-readable config format for SYSTEM.conf
    ./scan.sh --help            # Show this help information

OUTPUT MODES:
    Default Mode:
        Human-readable hardware detection results with explanations
        
    Config Mode (--config):
        Shell variable assignments suitable for SYSTEM.conf

EXIT CODES:
    0 - USB hardware detected and configuration generated
    1 - No USB hardware detected or scan failed
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

detect_usb_hardware() {
    local config_mode=false
    if [[ "${1:-}" == "--config" ]]; then
        config_mode=true
    fi
    
    local controller_count=0
    local device_count=0
    local usb2_count=0
    local usb3_count=0
    local storage_devices=0
    local input_devices=0
    
    # Count USB controllers
    if command -v lspci >/dev/null 2>&1; then
        controller_count=$(lspci | grep -ci "usb\|xhci\|ehci\|ohci\|uhci" || echo "0")
    fi
    
    # Count USB devices and analyze them
    if command -v lsusb >/dev/null 2>&1; then
        device_count=$(lsusb 2>/dev/null | wc -l || echo "0")
        
        # Analyze USB versions (rough detection)
        usb2_count=$(lsusb -v 2>/dev/null | grep -c "bcdUSB.*2\." || echo "0")
        usb3_count=$(lsusb -v 2>/dev/null | grep -c "bcdUSB.*3\." || echo "0")
        
        # Count storage and input devices
        storage_devices=$(lsusb 2>/dev/null | grep -ci "storage\|disk\|flash" || echo "0")
        input_devices=$(lsusb 2>/dev/null | grep -ci "keyboard\|mouse\|hid" || echo "0")
    fi
    
    # Alternative method using /sys if lsusb not available
    if [[ $device_count -eq 0 && -d "/sys/bus/usb/devices" ]]; then
        device_count=$(find /sys/bus/usb/devices -name "usb*" -type l 2>/dev/null | wc -l || echo "0")
    fi
    
    if [[ "$config_mode" == "true" ]]; then
        # Machine-readable config format
        if [[ $controller_count -gt 0 || $device_count -gt 0 ]]; then
            echo "USB_CONTROLLER_COUNT=\"$controller_count\""
            echo "USB_DEVICE_COUNT=\"$device_count\""
            echo "USB_USB2_DEVICES=\"$usb2_count\""
            echo "USB_USB3_DEVICES=\"$usb3_count\""
            echo "USB_STORAGE_DEVICES=\"$storage_devices\""
            echo "USB_INPUT_DEVICES=\"$input_devices\""
            exit 0
        else
            exit 1
        fi
    else
        # Human-readable format
        if [[ $controller_count -eq 0 && $device_count -eq 0 ]]; then
            echo "❌ No USB hardware detected"
            exit 1
        fi
        
        echo "✅ USB hardware detected:"
        echo ""
        echo "🔧 Hardware Details:"
        echo "  USB controllers: $controller_count"
        echo "  USB devices: $device_count"
        echo "  USB 2.0 devices: $usb2_count"
        echo "  USB 3.0+ devices: $usb3_count"
        echo "  Storage devices: $storage_devices"
        echo "  Input devices: $input_devices"
        
        # Show USB controllers from lspci
        if command -v lspci >/dev/null 2>&1; then
            local usb_controllers
            usb_controllers=$(lspci | grep -i "usb\|xhci\|ehci" | head -3)
            if [[ -n "$usb_controllers" ]]; then
                echo ""
                echo "🔌 USB Controllers:"
                echo "$usb_controllers" | sed 's/^/  /'
            fi
        fi
        
        # Show connected USB devices
        if command -v lsusb >/dev/null 2>&1; then
            echo ""
            echo "🔗 Connected USB Devices:"
            lsusb | head -5 | sed 's/^/  /' || echo "  No USB devices listed"
        fi
        
        echo ""
        echo "⚙️  Configuration Recommendations:"
        echo "  USB_CONTROLLER_COUNT=\"$controller_count\""
        echo "  USB_DEVICE_COUNT=\"$device_count\""
        
        exit 0
    fi
}

# Execute detection
detect_usb_hardware "$@"
