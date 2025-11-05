#!/bin/bash

# Bluetooth Diagnostic Script
# Comprehensive system check for Bluetooth issues

set -e

echo "=== Bluetooth System Diagnostic ==="
echo "Date: $(date)"
echo "User: $(whoami)"
echo "Hostname: $(hostname)"
echo ""

# Function to run command and capture output safely
run_check() {
    local description="$1"
    local command="$2"
    echo "--- $description ---"
    if eval "$command" 2>/dev/null; then
        echo "✅ Success"
    else
        echo "❌ Failed or not available"
    fi
    echo ""
}

# Function to check service status
check_service() {
    local service="$1"
    echo "--- $service Service Status ---"
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "✅ $service is running"
        systemctl status "$service" --no-pager -l
    else
        echo "❌ $service is not running"
        systemctl status "$service" --no-pager -l 2>/dev/null || echo "Service not found"
    fi
    echo ""
}

# Basic system info
echo "--- System Information ---"
uname -a
lsb_release -a 2>/dev/null || cat /etc/os-release
echo ""

# Check if running in container
if [ -f /.dockerenv ] || grep -q 'container=docker' /proc/1/environ 2>/dev/null; then
    echo "⚠️  Running in Docker container - Bluetooth may not be available"
    echo ""
fi

# Hardware detection
run_check "Bluetooth Hardware Detection" "lsusb | grep -i bluetooth"
run_check "PCI Bluetooth Devices" "lspci | grep -i bluetooth"
run_check "USB Bluetooth Devices" "lsusb | grep -i bluetooth"

# Kernel modules
echo "--- Bluetooth Kernel Modules ---"
lsmod | grep -i bluetooth || echo "❌ No Bluetooth modules loaded"
echo ""

# Check if bluetooth module can be loaded
run_check "Loading Bluetooth Module" "sudo modprobe bluetooth"
run_check "Loading BTUSB Module" "sudo modprobe btusb"

# Service checks
check_service "bluetooth"
check_service "bluetoothd"

# Bluetooth controller status
run_check "Bluetooth Controller Status" "bluetoothctl show"
run_check "Bluetooth Power Status" "bluetoothctl show | grep -i powered"

# Check if bluetooth is blocked
echo "--- RF Kill Status ---"
rfkill list bluetooth 2>/dev/null || echo "❌ rfkill not available or no bluetooth devices"
echo ""

# Check bluetooth configuration
echo "--- Bluetooth Configuration ---"
if [ -f /etc/bluetooth/main.conf ]; then
    echo "Bluetooth config exists:"
    grep -v '^#' /etc/bluetooth/main.conf | grep -v '^$' || echo "Default configuration"
else
    echo "❌ No bluetooth configuration found"
fi
echo ""

# Check for common issues
echo "--- Common Issue Checks ---"

# Check if bluetooth service is masked
if systemctl is-masked bluetooth >/dev/null 2>&1; then
    echo "❌ Bluetooth service is masked"
else
    echo "✅ Bluetooth service is not masked"
fi

# Check for conflicting services
run_check "Checking for PulseAudio Bluetooth" "systemctl status pulseaudio --no-pager" 
run_check "Checking for PipeWire" "systemctl --user status pipewire --no-pager"

# Dmesg bluetooth related messages
echo "--- Recent Bluetooth Kernel Messages ---"
dmesg | grep -i bluetooth | tail -20 || echo "No recent bluetooth messages"
echo ""

# Journal logs for bluetooth
echo "--- Recent Bluetooth Service Logs ---"
journalctl -u bluetooth --no-pager -n 20 --since "1 hour ago" || echo "No recent bluetooth logs"
echo ""

# Check bluetooth tools availability
echo "--- Bluetooth Tools Availability ---"
which bluetoothctl >/dev/null && echo "✅ bluetoothctl available" || echo "❌ bluetoothctl not found"
which hciconfig >/dev/null && echo "✅ hciconfig available" || echo "❌ hciconfig not found"
which hcitool >/dev/null && echo "✅ hcitool available" || echo "❌ hcitool not found"
echo ""

# Try to get bluetooth interface info
run_check "Bluetooth Interface Info" "hciconfig -a"

echo "=== Diagnostic Complete ==="
echo "If Bluetooth is not working, common solutions:"
echo "1. sudo systemctl restart bluetooth"
echo "2. sudo rfkill unblock bluetooth"
echo "3. sudo modprobe -r btusb && sudo modprobe btusb"
echo "4. Check if bluetooth is disabled in BIOS/UEFI"
echo "5. Install bluetooth packages: sudo apt install bluetooth bluez bluez-tools"


