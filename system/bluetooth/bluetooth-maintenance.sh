#!/bin/bash

# Bluetooth Maintenance Script
# Prevents and fixes common Bluetooth issues after updates or improper shutdowns

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
    echo "Bluetooth Maintenance Script"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  -c, --check       Check Bluetooth status and health"
    echo "  -f, --fix         Attempt to fix Bluetooth issues"
    echo "  -u, --update      Update Bluetooth packages safely"
    echo "  -p, --post-update Run after system updates (recommended)"
    echo "  -r, --reset       Full reset (use after improper shutdown)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Recommended usage:"
    echo "  After system updates: $0 --post-update"
    echo "  After improper shutdown: $0 --reset"
    echo "  Regular maintenance: $0 --check"
}

check_bluetooth() {
    echo "=== Bluetooth Health Check ==="
    echo "Date: $(date)"
    echo ""
    
    # Check if Bluetooth hardware is detected
    if lsusb | grep -q "8087:0029"; then
        echo "✅ Intel AX200 Bluetooth hardware detected"
    else
        echo "❌ Bluetooth hardware not detected"
        return 1
    fi
    
    # Check service status
    if systemctl is-active --quiet bluetooth; then
        echo "✅ Bluetooth service is running"
    else
        echo "❌ Bluetooth service is not running"
        return 1
    fi
    
    # Check HCI interface
    if hciconfig hci0 | grep -q "UP RUNNING"; then
        echo "✅ Bluetooth interface is UP and RUNNING"
        echo "   Address: $(hciconfig hci0 | grep 'BD Address' | cut -d' ' -f3)"
    else
        echo "❌ Bluetooth interface is DOWN"
        return 1
    fi
    
    # Check for recent errors
    if journalctl -u bluetooth --since "1 hour ago" --no-pager | grep -q "timeout\|failed\|error"; then
        echo "⚠️  Recent Bluetooth errors detected"
        echo "Recent errors:"
        journalctl -u bluetooth --since "1 hour ago" --no-pager | grep -i "timeout\|failed\|error" | tail -3
        return 1
    else
        echo "✅ No recent Bluetooth errors"
    fi
    
    echo ""
    echo "✅ Bluetooth is healthy and working properly"
    return 0
}

fix_bluetooth() {
    echo "=== Bluetooth Fix ==="
    echo "Running Intel AX200 specific fix..."
    
    if [ -f "$SCRIPT_DIR/intel-bluetooth-fix.sh" ]; then
        "$SCRIPT_DIR/intel-bluetooth-fix.sh"
    else
        echo "❌ Intel Bluetooth fix script not found"
        return 1
    fi
}

update_bluetooth() {
    echo "=== Safe Bluetooth Update ==="
    
    # Check for pending Bluetooth updates
    BLUETOOTH_UPDATES=$(apt list --upgradable 2>/dev/null | grep -E "bluez|bluetooth|firmware" || true)
    
    if [ -n "$BLUETOOTH_UPDATES" ]; then
        echo "Pending Bluetooth-related updates:"
        echo "$BLUETOOTH_UPDATES"
        echo ""
        
        read -p "Apply these updates? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Updating Bluetooth packages..."
            sudo apt update
            sudo apt upgrade bluez bluez-cups bluez-obexd libbluetooth3 linux-firmware firmware-sof-signed
            
            echo "Restarting Bluetooth service after update..."
            sudo systemctl restart bluetooth
            sleep 3
            
            echo "Checking Bluetooth status after update..."
            check_bluetooth
        else
            echo "Updates cancelled"
        fi
    else
        echo "✅ No pending Bluetooth updates"
    fi
}

post_update_maintenance() {
    echo "=== Post-Update Bluetooth Maintenance ==="
    
    # Check if Bluetooth is working
    if check_bluetooth; then
        echo "✅ Bluetooth is working fine after updates"
    else
        echo "⚠️  Bluetooth issues detected after updates, attempting fix..."
        fix_bluetooth
    fi
}

reset_bluetooth() {
    echo "=== Full Bluetooth Reset ==="
    echo "This will perform a complete Bluetooth reset (recommended after improper shutdown)"
    
    read -p "Continue with full reset? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        fix_bluetooth
        
        # Additional reset steps for post-crash recovery
        echo "Clearing Bluetooth cache..."
        sudo rm -rf /var/lib/bluetooth/*/cache || true
        
        echo "Resetting Bluetooth configuration..."
        sudo systemctl stop bluetooth
        sleep 2
        sudo systemctl start bluetooth
        sleep 5
        
        check_bluetooth
    else
        echo "Reset cancelled"
    fi
}

# Main script logic
case "${1:-}" in
    -c|--check)
        check_bluetooth
        ;;
    -f|--fix)
        fix_bluetooth
        ;;
    -u|--update)
        update_bluetooth
        ;;
    -p|--post-update)
        post_update_maintenance
        ;;
    -r|--reset)
        reset_bluetooth
        ;;
    -h|--help)
        show_help
        ;;
    "")
        echo "No option specified. Use --help for usage information."
        echo "Quick check:"
        check_bluetooth
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information."
        exit 1
        ;;
esac


