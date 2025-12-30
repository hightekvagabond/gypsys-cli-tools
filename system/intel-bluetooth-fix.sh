#!/bin/bash

# Intel AX200 Bluetooth Fix Script
# Specifically addresses Intel Bluetooth firmware timeout issues

set -e

echo "=== Intel AX200 Bluetooth Fix ==="
echo "Date: $(date)"
echo "Issue: Intel Bluetooth firmware timeout (command 0xfc05 tx timeout)"
echo ""

# Function to run command with error handling
run_fix() {
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

# Check current status
echo "=== Current Status ==="
echo "USB Bluetooth device:"
lsusb | grep -i bluetooth
echo ""
echo "Loaded modules:"
lsmod | grep -E "(btusb|btintel|bluetooth)"
echo ""

# Step 1: Complete module reset with proper order
echo "=== Step 1: Complete Bluetooth Module Reset ==="
run_fix "Stopping Bluetooth service" "sudo systemctl stop bluetooth"

echo "Removing all Bluetooth modules in correct order..."
sudo modprobe -r bnep || true
sudo modprobe -r btusb || true  
sudo modprobe -r btintel || true
sudo modprobe -r btrtl || true
sudo modprobe -r btbcm || true
sudo modprobe -r btmtk || true
sudo modprobe -r bluetooth || true

echo "Waiting for modules to fully unload..."
sleep 5

echo "Reloading modules in correct order..."
run_fix "Loading bluetooth core module" "sudo modprobe bluetooth"
run_fix "Loading btintel module" "sudo modprobe btintel"
run_fix "Loading btusb module" "sudo modprobe btusb"

sleep 3

# Step 2: Reset USB device
echo "=== Step 2: Reset USB Bluetooth Device ==="
# Find the USB device path for Intel Bluetooth
USB_DEVICE=$(lsusb | grep "8087:0029" | cut -d' ' -f2,4 | tr -d ':')
if [ -n "$USB_DEVICE" ]; then
    BUS=$(echo $USB_DEVICE | cut -d' ' -f1)
    DEV=$(echo $USB_DEVICE | cut -d' ' -f2)
    echo "Found Intel Bluetooth at Bus $BUS Device $DEV"
    
    # Reset the USB device
    if [ -f "/sys/bus/usb/devices/$BUS-$DEV/authorized" ]; then
        echo "Resetting USB device..."
        echo 0 | sudo tee "/sys/bus/usb/devices/$BUS-$DEV/authorized" > /dev/null
        sleep 2
        echo 1 | sudo tee "/sys/bus/usb/devices/$BUS-$DEV/authorized" > /dev/null
        echo "✅ USB device reset completed"
    else
        echo "⚠️  USB device path not found, skipping USB reset"
    fi
else
    echo "⚠️  Intel Bluetooth USB device not found"
fi

sleep 3

# Step 3: Start Bluetooth service
echo "=== Step 3: Start Bluetooth Service ==="
run_fix "Starting Bluetooth service" "sudo systemctl start bluetooth"

sleep 5

# Step 4: Check for firmware loading
echo "=== Step 4: Check Firmware Loading ==="
echo "Checking recent kernel messages for firmware loading..."
dmesg | grep -i bluetooth | tail -10

echo ""
echo "Checking HCI interface status..."
hciconfig -a

# Step 5: Try to bring up interface with retries
echo "=== Step 5: Bring Up HCI Interface ==="
for i in {1..3}; do
    echo "Attempt $i to bring up hci0..."
    if sudo hciconfig hci0 up; then
        echo "✅ HCI interface brought up successfully"
        break
    else
        echo "❌ Attempt $i failed, waiting before retry..."
        sleep 5
    fi
done

# Step 6: Final status check
echo "=== Final Status Check ==="
echo "HCI interface status:"
hciconfig -a
echo ""
echo "Bluetoothctl status:"
timeout 5s bluetoothctl show || echo "Bluetoothctl timeout"
echo ""

echo "=== Fix Complete ==="
echo ""
echo "If this didn't work, the issue might be:"
echo "1. Firmware corruption - may need to reinstall linux-firmware package"
echo "2. Hardware failure - Bluetooth chip may be faulty"
echo "3. BIOS/UEFI issue - check if Bluetooth is enabled in BIOS"
echo "4. Power management issue - try: sudo systemctl disable bluetooth && sudo systemctl enable bluetooth"
echo ""
echo "Advanced troubleshooting commands:"
echo "- Check firmware files: ls -la /lib/firmware/intel/"
echo "- Reinstall firmware: sudo apt update && sudo apt install --reinstall linux-firmware"
echo "- Check power management: cat /sys/module/btusb/parameters/enable_autosuspend"




