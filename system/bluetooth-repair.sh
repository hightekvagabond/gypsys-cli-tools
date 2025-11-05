#!/bin/bash

# Bluetooth Repair Script
# Attempts to fix common Bluetooth issues

set -e

echo "=== Bluetooth Repair Script ==="
echo "Date: $(date)"
echo ""

# Function to run command with error handling
run_repair() {
    local description="$1"
    local command="$2"
    echo "--- $description ---"
    if eval "$command"; then
        echo "✅ $description completed successfully"
    else
        echo "❌ $description failed"
        return 1
    fi
    echo ""
}

# Function to check status
check_status() {
    echo "--- Current Bluetooth Status ---"
    echo "RF Kill status:"
    rfkill list bluetooth
    echo ""
    echo "HCI interface status:"
    hciconfig -a
    echo ""
    echo "Bluetoothctl show:"
    timeout 5s bluetoothctl show || echo "Bluetoothctl timeout or no controller"
    echo ""
}

echo "Initial status check:"
check_status

# Step 1: Ensure RF Kill is unblocked
echo "=== Step 1: Unblock RF Kill ==="
run_repair "Unblocking Bluetooth via RF Kill" "sudo rfkill unblock bluetooth"

# Step 2: Restart Bluetooth service
echo "=== Step 2: Restart Bluetooth Service ==="
run_repair "Stopping Bluetooth service" "sudo systemctl stop bluetooth"
sleep 2
run_repair "Starting Bluetooth service" "sudo systemctl start bluetooth"
sleep 3

# Step 3: Reset USB Bluetooth module
echo "=== Step 3: Reset Bluetooth USB Module ==="
run_repair "Removing btusb module" "sudo modprobe -r btusb"
sleep 2
run_repair "Reloading btusb module" "sudo modprobe btusb"
sleep 3

# Step 4: Bring up HCI interface
echo "=== Step 4: Bring Up HCI Interface ==="
run_repair "Bringing up hci0 interface" "sudo hciconfig hci0 up"

# Step 5: Reset HCI interface
echo "=== Step 5: Reset HCI Interface ==="
run_repair "Resetting hci0 interface" "sudo hciconfig hci0 reset"

# Step 6: Enable Bluetooth controller
echo "=== Step 6: Enable Bluetooth Controller ==="
echo "Attempting to power on via bluetoothctl..."
timeout 10s bash -c '
echo "power on" | bluetoothctl
sleep 2
echo "agent on" | bluetoothctl
sleep 1
echo "default-agent" | bluetoothctl
' || echo "Bluetoothctl commands may have timed out"

echo ""
echo "=== Final Status Check ==="
check_status

echo "=== Repair Complete ==="
echo "If Bluetooth is still not working, you may need to:"
echo "1. Check BIOS/UEFI settings for Bluetooth"
echo "2. Update Bluetooth firmware/drivers"
echo "3. Check for hardware conflicts"
echo "4. Reboot the system"


