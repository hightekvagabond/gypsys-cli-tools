#!/bin/bash

#####################################################################
# AUTO-SWAPPING CAMERA SCRIPT
#####################################################################
#
# PURPOSE:
#   Automatically switches to a preferred external camera when plugged in,
#   and falls back to laptop camera when unplugged. Ideal for docking 
#   station workflows.
#
# FEATURES:
#   • Interactive setup to choose preferred camera
#   • Non-interactive setup for automation (--camera N)
#   • Dual monitoring system (udev + systemd) for reliability
#   • Comprehensive logging and debugging tools
#   • Manual enable/disable controls for troubleshooting
#
# SYSTEM COMPONENTS:
#   1. This script (/path/to/auto-swapping-cameras.sh)
#   2. Config file (/etc/auto-swapping-camera.conf)
#   3. Udev rules (/etc/udev/rules.d/99-auto-swapping-camera.rules)
#   4. Systemd service (camera-swap-monitor.service)
#   5. Log file (/var/log/camera-swap.log)
#
# USAGE:
#   ./auto-swapping-cameras.sh           # Interactive setup
#   ./auto-swapping-cameras.sh --camera 0  # Non-interactive setup
#   ./auto-swapping-cameras.sh --test      # Test current setup
#   ./auto-swapping-cameras.sh --debug     # Debug USB paths
#   ./auto-swapping-cameras.sh --enable    # Manually enable all cameras
#   ./auto-swapping-cameras.sh --disable   # Manually disable non-preferred
#   ./auto-swapping-cameras.sh --monitor   # Run one monitoring cycle
#
# ARCHITECTURE:
#   ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
#   │   USB Event     │───▶│   Udev Rules     │───▶│  Script Action  │
#   │ (plug/unplug)   │    │ (fast trigger)   │    │ (enable/disable)│
#   └─────────────────┘    └──────────────────┘    └─────────────────┘
#   
#   ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
#   │ Systemd Timer   │───▶│ Monitor Function │───▶│  Script Action  │
#   │ (every 3 sec)   │    │ (state tracking) │    │ (enable/disable)│
#   └─────────────────┘    └──────────────────┘    └─────────────────┘
#
# TECHNICAL DETAILS:
#   • Uses /sys/bus/usb/drivers/uvcvideo/ for camera control
#   • Identifies cameras by USB Vendor:Product IDs
#   • Binds/unbinds camera interfaces from uvcvideo driver
#   • Tracks state changes to avoid redundant operations
#
# TROUBLESHOOTING:
#   • Check service: sudo systemctl status camera-swap-monitor.service
#   • View logs: sudo tail -f /var/log/camera-swap.log
#   • Test manually: ./auto-swapping-cameras.sh --test
#   • Debug USB paths: ./auto-swapping-cameras.sh --debug
#
# REQUIREMENTS:
#   • Root privileges for udev/systemd operations
#   • v4l2-ctl (video4linux-utils package)
#   • USB cameras using uvcvideo driver
#
# AUTHOR: Gypsy & AI Assistant
# VERSION: 2.0 - Dual monitoring system with comprehensive logging
#
#####################################################################
#####################################################################
# CONFIGURATION AND UTILITY FUNCTIONS
#####################################################################

# Global variables - file paths for configuration and rules
UDEV_RULES_FILE="/etc/udev/rules.d/99-auto-swapping-camera.rules"   # Udev rules for auto-switching
CONFIG_FILE="/etc/auto-swapping-camera.conf"                        # Stores preferred camera USB IDs
SCRIPT_PATH="$(readlink -f "$0")"                                    # Full path to this script

#---------------------------------------------------------------------
# check_root() - Ensures script is run with root privileges
#
# REQUIRED FOR: udev rule creation, systemd service management, 
#               camera binding/unbinding operations
# EXITS: Script if not root, with helpful error message
#---------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ This script needs root privileges."
        echo "   Please run: sudo $0 $*"
        exit 1
    fi
}

#---------------------------------------------------------------------
# load_config() - Loads preferred camera configuration
#
# READS: /etc/auto-swapping-camera.conf
# SETS: PREF_VENDOR and PREF_PRODUCT variables
# FORMAT: PREF_VENDOR=046d, PREF_PRODUCT=085c
# USED BY: All functions that need to identify the preferred camera
#---------------------------------------------------------------------
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

#####################################################################
# USB DEVICE IDENTIFICATION FUNCTIONS
#####################################################################

#---------------------------------------------------------------------
# get_camera_usb_ids() - Extracts USB Vendor:Product IDs for a camera
#
# INPUT: camera_name (e.g. "C922 Pro Stream Webcam")
# OUTPUT: USB IDs in format "046d:085c" or empty string if not found
# METHOD: 
#   1. First tries lsusb command for quick lookup
#   2. Falls back to /sys/class/video4linux/* path traversal
#   3. Follows symlinks to find USB device directory
#   4. Reads idVendor and idProduct files
# USED BY: setup_rules() to identify preferred camera
#---------------------------------------------------------------------
get_camera_usb_ids() {
    local camera_name="$1"
    local usb_ids=""
    
    # Try to find USB IDs by matching camera name in lsusb output
    usb_ids=$(lsusb | grep -i "$(echo "$camera_name" | cut -d' ' -f1,2,3)" | awk '{print $6}' | head -n1)
    
    if [[ -z "$usb_ids" ]]; then
        # Fallback: try to find by looking at /sys/class/video4linux devices
        for video_dev in /sys/class/video4linux/video*; do
            if [[ -L "$video_dev" ]]; then
                local dev_path=$(readlink "$video_dev")
                if [[ "$dev_path" == *"usb"* ]]; then
                    local usb_path=$(echo "$dev_path" | sed 's|.*usb\([0-9]*\)/\([0-9]*\)/.*|usb\1/\2|' | sed 's|:[0-9.]*$||')
                    if [[ -f "/sys/bus/usb/devices/$usb_path/idVendor" && -f "/sys/bus/usb/devices/$usb_path/idProduct" ]]; then
                        local vid=$(cat "/sys/bus/usb/devices/$usb_path/idVendor")
                        local pid=$(cat "/sys/bus/usb/devices/$usb_path/idProduct")
                        usb_ids="${vid}:${pid}"
                        break
                    fi
                fi
            fi
        done
    fi
    
    echo "$usb_ids"
}

# Extract base USB device name from uvcvideo device path
#---------------------------------------------------------------------
# get_base_usb_path() - Extracts base USB device name from full path
#
# INPUT: dev_path (e.g. "/sys/bus/usb/drivers/uvcvideo/1-1.2.4.1.1.4:1.0")
# OUTPUT: base_device (e.g. "1-1.2.4.1.1.4")
# PURPOSE: Removes interface suffix (:1.0) to get parent device directory
# CRITICAL: This is needed because USB cameras create multiple interfaces
#           but we need the parent device to read idVendor/idProduct
# USED BY: disable_nonpreferred(), enable_all(), test_unbind_rebind()
#---------------------------------------------------------------------
get_base_usb_path() {
    local dev_path="$1"
    
    # Extract device name from path like /sys/bus/usb/drivers/uvcvideo/1-1.2.4.1.1.4:1.0
    local device_name=$(basename "$dev_path")
    
    # Remove interface part (e.g., 1-1.2.4.1.1.4:1.0 -> 1-1.2.4.1.1.4)
    local base_device=$(echo "$device_name" | sed 's|:[0-9]\.[0-9]$||')
    
    echo "$base_device"
}

#####################################################################
# CAMERA CONTROL FUNCTIONS
#####################################################################

#---------------------------------------------------------------------
# disable_nonpreferred() - Disables all cameras except the preferred one
#
# REQUIRES: Root privileges, loaded config (PREF_VENDOR, PREF_PRODUCT)
# METHOD:
#   1. Iterates through /sys/bus/usb/drivers/uvcvideo/* (active cameras)
#   2. For each camera, gets base USB device using get_base_usb_path()
#   3. Reads idVendor/idProduct from USB device directory
#   4. Unbinds non-preferred cameras by writing to uvcvideo/unbind
#   5. Keeps preferred camera active
# CALLED BY: udev rules when preferred camera is plugged in
# SIDE EFFECTS: Disables camera devices, makes them unavailable to apps
#---------------------------------------------------------------------
disable_nonpreferred() {
    load_config
    if [[ -z "$PREF_VENDOR" || -z "$PREF_PRODUCT" ]]; then
        echo "❌ Configuration not found. Run setup first."
        return 1
    fi
    
    echo "[auto-swapping-camera] Disabling non-preferred cameras..."
    local disabled_count=0
    
    # Look for uvcvideo driver entries
    for dev in /sys/bus/usb/drivers/uvcvideo/*; do
        if [[ -d "$dev" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/bind" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/unbind" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/new_id" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/remove_id" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/uevent" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/module" ]]; then
            # Extract the base USB device name from the device path
            local usb_device=$(get_base_usb_path "$dev")
            if [[ -f "/sys/bus/usb/devices/$usb_device/idVendor" && -f "/sys/bus/usb/devices/$usb_device/idProduct" ]]; then
                local vid=$(cat "/sys/bus/usb/devices/$usb_device/idVendor")
                local pid=$(cat "/sys/bus/usb/devices/$usb_device/idProduct")
                    
                    if [[ "$vid" == "$PREF_VENDOR" && "$pid" == "$PREF_PRODUCT" ]]; then
                        echo "✅ Keeping preferred camera ($vid:$pid)"
                    else
                        echo "❌ Disabling non-preferred camera ($vid:$pid)"
                        echo "$(basename "$dev")" > /sys/bus/usb/drivers/uvcvideo/unbind 2>/dev/null
                        if [[ $? -eq 0 ]]; then
                            ((disabled_count++))
                        fi
                    fi
                fi
        fi
    done
    
    echo "Disabled $disabled_count non-preferred camera(s)"
}

#---------------------------------------------------------------------
# enable_all() - Re-enables all available cameras
#
# REQUIRES: Root privileges
# METHOD:
#   1. Checks already active cameras (reports status)
#   2. Iterates through /sys/bus/usb/devices/* looking for camera devices
#   3. Identifies cameras by common vendor IDs (046d, 04f2, 1d4d, etc.)
#   4. Attempts to bind unbound camera interfaces to uvcvideo driver
#   5. Falls back to kernel module reload if no cameras found
# CALLED BY: udev rules when preferred camera is unplugged
# ROBUST: Multiple strategies ensure cameras are re-enabled reliably
#---------------------------------------------------------------------
enable_all() {
    echo "[auto-swapping-camera] Re-enabling all cameras..."
    local enabled_count=0
    
    # First method: Re-bind any currently bound devices that are cameras
    for dev in /sys/bus/usb/drivers/uvcvideo/*; do
        if [[ -d "$dev" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/bind" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/unbind" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/new_id" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/remove_id" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/uevent" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/module" ]]; then
            local usb_device=$(get_base_usb_path "$dev")
            if [[ -f "/sys/bus/usb/devices/$usb_device/idVendor" && -f "/sys/bus/usb/devices/$usb_device/idProduct" ]]; then
                local vid=$(cat "/sys/bus/usb/devices/$usb_device/idVendor")
                local pid=$(cat "/sys/bus/usb/devices/$usb_device/idProduct")
                echo "✅ Camera already active ($vid:$pid)"
            fi
        fi
    done
    
    # Second method: Find unbound camera devices and try to bind them
    for usb_dev in /sys/bus/usb/devices/*; do
        if [[ -d "$usb_dev" && -f "$usb_dev/idVendor" && -f "$usb_dev/idProduct" ]]; then
            local vid=$(cat "$usb_dev/idVendor")
            local pid=$(cat "$usb_dev/idProduct")
            local dev_name=$(basename "$usb_dev")
            
            # Check if this device supports video (common camera vendor IDs)
            if [[ "$vid" == "046d" || "$vid" == "04f2" || "$vid" == "1d4d" || "$vid" == "0c45" || "$vid" == "05a9" ]]; then
                # Try to find and bind interface devices for this camera
                for interface in "$usb_dev"/*:*; do
                    if [[ -d "$interface" ]]; then
                        local interface_name=$(basename "$interface")
                        # Check if this interface is already bound to uvcvideo
                        if [[ ! -L "/sys/bus/usb/drivers/uvcvideo/$interface_name" ]]; then
                            echo "🔄 Attempting to bind camera interface ($vid:$pid) - $interface_name"
                            echo "$interface_name" > /sys/bus/usb/drivers/uvcvideo/bind 2>/dev/null
                            if [[ $? -eq 0 ]]; then
                                echo "✅ Successfully bound camera ($vid:$pid) - $interface_name"
                                ((enabled_count++))
                            fi
                        fi
                    fi
                done
            fi
        fi
    done
    
    # Third method: Force module reload if no cameras were found
    if [[ $enabled_count -eq 0 ]]; then
        echo "🔄 No cameras found to bind, reloading uvcvideo module..."
        modprobe -r uvcvideo 2>/dev/null
        modprobe uvcvideo 2>/dev/null
        if [[ $? -eq 0 ]]; then
            echo "✅ uvcvideo module reloaded"
            enabled_count=1
        fi
    fi
    
    echo "Re-enabled $enabled_count camera device(s)"
}

#####################################################################
# TESTING AND DEBUGGING FUNCTIONS
#####################################################################

#---------------------------------------------------------------------
# test_unbind_rebind() - Comprehensive test of camera switching system
#
# PURPOSE: User-friendly diagnostic tool for troubleshooting
# DISPLAYS:
#   • Current configuration (preferred camera, file locations)
#   • Active video devices and their paths
#   • USB camera analysis with vendor/product IDs
#   • Status of preferred vs other cameras
#   • Manual control commands for troubleshooting
# NO SIDE EFFECTS: Read-only function, safe to run anytime
# USED BY: --test flag, automatic after setup completion
#---------------------------------------------------------------------
test_unbind_rebind() {
    check_root
    load_config
    
    echo "🔍 Camera Auto-Swapping Test Results"
    echo "====================================="
    
    if [[ -z "$PREF_VENDOR" || -z "$PREF_PRODUCT" ]]; then
        echo "❌ No configuration found. Run setup first."
        return 1
    fi
    
    echo "📋 Configuration:"
    echo "   Preferred camera: $PREF_VENDOR:$PREF_PRODUCT"
    echo "   Config file: $CONFIG_FILE"
    echo "   Udev rules: $UDEV_RULES_FILE"
    echo
    
    echo "📹 Current camera status:"
    local video_devices=$(ls /dev/video* 2>/dev/null | wc -w)
    echo "   Video devices: $video_devices"
    
    if [[ $video_devices -gt 0 ]]; then
        echo "   Available devices:"
        ls /dev/video* 2>/dev/null | while read dev; do
            echo "     $dev"
        done
    fi
    echo
    
    echo "🔌 USB Camera Analysis:"
    local preferred_found=false
    local other_cameras=()
    
    for dev in /sys/bus/usb/drivers/uvcvideo/*; do
        if [[ -d "$dev" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/bind" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/unbind" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/new_id" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/remove_id" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/uevent" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/module" ]]; then
            # Extract the base USB device name from the device path
            local usb_device=$(get_base_usb_path "$dev")
            if [[ -f "/sys/bus/usb/devices/$usb_device/idVendor" && -f "/sys/bus/usb/devices/$usb_device/idProduct" ]]; then
                local vid=$(cat "/sys/bus/usb/devices/$usb_device/idVendor")
                local pid=$(cat "/sys/bus/usb/devices/$usb_device/idProduct")
                    
                    if [[ "$vid" == "$PREF_VENDOR" && "$pid" == "$PREF_PRODUCT" ]]; then
                        echo "   ✅ Preferred camera ($vid:$pid) - ACTIVE"
                        preferred_found=true
                    else
                        echo "   ❌ Other camera ($vid:$pid) - ACTIVE"
                        other_cameras+=("$vid:$pid")
                    fi
                fi
        fi
    done
    
    echo
    echo "📊 Test Summary:"
    if [[ "$preferred_found" == true ]]; then
        echo "   ✅ Preferred camera is connected and active"
        if [[ ${#other_cameras[@]} -eq 0 ]]; then
            echo "   ✅ No other cameras are active (expected behavior)"
        else
            echo "   ⚠️  Other cameras are still active (may need manual intervention)"
            echo "   💡 Try running: sudo $0 --disable"
        fi
    else
        echo "   ❌ Preferred camera is not connected or not active"
        echo "   💡 Connect your preferred camera and run: sudo $0 --disable"
    fi
    
    echo
    echo "🔄 Manual control commands:"
    echo "   Disable non-preferred: sudo $0 --disable"
    echo "   Enable all cameras: sudo $0 --enable"
    echo "   Re-run test: sudo $0 --test"
    echo "   Debug mode: sudo $0 --debug"
}

#---------------------------------------------------------------------
# debug_usb_paths() - Advanced debugging for USB device path issues
#
# PURPOSE: Deep diagnostic tool for troubleshooting path extraction
# DISPLAYS:
#   • Raw symlink paths from /sys/bus/usb/drivers/uvcvideo/*
#   • Real device paths after following symlinks
#   • Extracted USB device paths using get_base_usb_path()
#   • Vendor/Product ID lookup results
#   • Step-by-step path transformation process
# WHEN TO USE: When cameras aren't being detected correctly
# USED BY: --debug flag for technical troubleshooting
#---------------------------------------------------------------------
debug_usb_paths() {
    check_root
    load_config
    
    echo "🔧 USB Path Debug Analysis"
    echo "=========================="
    echo
    
    if [[ -z "$PREF_VENDOR" || -z "$PREF_PRODUCT" ]]; then
        echo "❌ No configuration found. Run setup first."
        return 1
    fi
    
    echo "📋 Configuration:"
    echo "   Preferred camera: $PREF_VENDOR:$PREF_PRODUCT"
    echo
    
    echo "🔍 Detailed USB Device Analysis:"
    echo "--------------------------------"
    
    for dev in /sys/bus/usb/drivers/uvcvideo/*; do
        if [[ -d "$dev" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/bind" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/unbind" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/new_id" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/remove_id" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/uevent" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/module" ]]; then
            echo "📹 Device: $dev"
            local usb_device=$(get_base_usb_path "$dev")
            echo "   USB device: $usb_device"
                
                if [[ -f "/sys/bus/usb/devices/$usb_device/idVendor" && -f "/sys/bus/usb/devices/$usb_device/idProduct" ]]; then
                    local vid=$(cat "/sys/bus/usb/devices/$usb_device/idVendor")
                    local pid=$(cat "/sys/bus/usb/devices/$usb_device/idProduct")
                    echo "   ✅ Vendor: $vid"
                    echo "   ✅ Product: $pid"
                    
                    if [[ "$vid" == "$PREF_VENDOR" && "$pid" == "$PREF_PRODUCT" ]]; then
                        echo "   🎯 MATCHES PREFERRED CAMERA!"
                    else
                        echo "   ❌ Different camera"
                    fi
                else
                    echo "   ❌ No vendor/product files found"
                    echo "   💡 Checking if path exists:"
                    ls -la "/sys/bus/usb/devices/$usb_device/" 2>/dev/null | head -5 || echo "      Path does not exist"
                fi
            echo "---"
        fi
    done
    
    echo
    echo "🔧 Troubleshooting Tips:"
    echo "   • If USB paths are incorrect, the sed pattern may need adjustment"
    echo "   • Check if your system uses a different PCI path structure"
    echo "   • Run 'ls -la /sys/bus/usb/drivers/uvcvideo/' to see device structure"
    echo "   • Check 'dmesg | grep uvcvideo' for driver messages"
}

#####################################################################
# SETUP AND INSTALLATION FUNCTIONS
#####################################################################

#---------------------------------------------------------------------
# setup_rules() - Complete system setup and installation
#
# PARAMETERS: 
#   camera_index (optional) - for non-interactive setup (--camera N)
# FUNCTION:
#   1. Detects available cameras using v4l2-ctl
#   2. Interactive camera selection OR uses provided index
#   3. Extracts USB Vendor:Product IDs for chosen camera
#   4. Creates configuration file (/etc/auto-swapping-camera.conf)
#   5. Generates udev rules for automatic triggering
#   6. Creates systemd monitoring service as backup
#   7. Enables and starts monitoring service
#   8. Immediately applies preferred camera setting
#   9. Runs comprehensive test to verify setup
# CREATES: Config file, udev rules, systemd service, log file
# SIDE EFFECTS: Modifies system configuration, starts background service
#---------------------------------------------------------------------
setup_rules() {
    local camera_index="$1"
    check_root

    echo "🔍 Detecting available cameras..."
    mapfile -t CAMERAS < <(v4l2-ctl --list-devices 2>/dev/null | grep -v '^$' | grep -v -E '^\s')

    if [[ ${#CAMERAS[@]} -lt 2 ]]; then
        echo "❌ Less than two cameras detected. Exiting."
        exit 1
    fi

    echo "📹 Cameras detected:"
    for i in "${!CAMERAS[@]}"; do
        echo "  [$i] ${CAMERAS[$i]}"
    done

    if [[ -n "$camera_index" ]]; then
        PREFERRED_INDEX="$camera_index"
        echo "🎯 Using camera index: $PREFERRED_INDEX (non-interactive mode)"
    else
        read -p "Enter the index of the camera you want as default (e.g., 0): " PREFERRED_INDEX
    fi

    if [[ ! "$PREFERRED_INDEX" =~ ^[0-9]+$ ]] || [[ "$PREFERRED_INDEX" -ge ${#CAMERAS[@]} ]]; then
        echo "❌ Invalid index. Please enter a number between 0 and $(( ${#CAMERAS[@]} - 1 ))"
        exit 1
    fi

    PREFERRED="${CAMERAS[$PREFERRED_INDEX]}"
    echo "🎯 Preferred camera: $PREFERRED"

    # Get USB IDs for the preferred camera
    PREF_ID=$(get_camera_usb_ids "$PREFERRED")
    
    if [[ -z "$PREF_ID" ]]; then
        echo "❌ Could not determine USB IDs for preferred camera."
        echo "   Please check the camera connection and try again."
        exit 1
    fi
    
    PREF_VENDOR=$(echo "$PREF_ID" | cut -d: -f1)
    PREF_PRODUCT=$(echo "$PREF_ID" | cut -d: -f2)

    echo "🔌 Preferred camera USB IDs: $PREF_VENDOR:$PREF_PRODUCT"

    # Save config file
    echo "PREF_VENDOR=$PREF_VENDOR" > "$CONFIG_FILE"
    echo "PREF_PRODUCT=$PREF_PRODUCT" >> "$CONFIG_FILE"
    echo "✅ Saved config to $CONFIG_FILE"

    # Write udev rules - FIXED LOGIC: disable others when preferred is added
    echo "📝 Writing udev rules to $UDEV_RULES_FILE..."
    cat > "$UDEV_RULES_FILE" <<EOF
# Auto camera swap: disable non-preferred cameras when preferred cam is connected
SUBSYSTEM=="usb", ATTR{idVendor}=="$PREF_VENDOR", ATTR{idProduct}=="$PREF_PRODUCT", ACTION=="add", RUN+="/bin/bash -c 'echo \"\$(date): Camera plugged in, disabling others\" >> /var/log/camera-swap.log; $SCRIPT_PATH --disable >> /var/log/camera-swap.log 2>&1'"
SUBSYSTEM=="usb", ATTR{idVendor}=="$PREF_VENDOR", ATTR{idProduct}=="$PREF_PRODUCT", ACTION=="remove", RUN+="/bin/bash -c 'echo \"\$(date): Camera unplugged, enabling all\" >> /var/log/camera-swap.log; $SCRIPT_PATH --enable >> /var/log/camera-swap.log 2>&1'"
EOF

    # Create systemd service as backup monitor
    echo "📝 Creating systemd monitoring service..."
    cat > "/etc/systemd/system/camera-swap-monitor.service" <<EOF
[Unit]
Description=Camera Auto-Swap Monitor
After=multi-user.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do $SCRIPT_PATH --monitor; sleep 3; done'
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    echo "🔄 Reloading udev rules..."
    udevadm control --reload-rules
    udevadm trigger
    
    echo "🔄 Setting up systemd monitoring service..."
    systemctl daemon-reload
    systemctl enable camera-swap-monitor.service
    systemctl start camera-swap-monitor.service

    echo "✅ Setup complete! $PREFERRED is now the default camera."
    echo "   Non-preferred cameras will be automatically disabled when it's connected."
    echo "   📡 Monitoring service is running for reliable auto-switching"
    echo
    echo "🔧 Automatically disabling non-preferred cameras..."
    disable_nonpreferred
    echo
    echo "🧪 Running initial test..."
    test_unbind_rebind
}

#####################################################################
# MONITORING SYSTEM
#####################################################################

#---------------------------------------------------------------------
# monitor_cameras() - Background monitoring function for systemd service
#
# PURPOSE: Continuously monitors camera state changes every 3 seconds
# ALGORITHM:
#   1. Loads configuration to identify preferred camera
#   2. Scans /sys/bus/usb/drivers/uvcvideo/* for connected cameras
#   3. Determines if preferred camera is currently connected
#   4. Compares current state with last known state (/tmp/camera-swap-state)
#   5. Only acts when state changes (avoids redundant operations)
#   6. Logs all state changes and actions to /var/log/camera-swap.log
# STATES: "preferred_connected" or "preferred_disconnected"
# ACTIONS: Calls disable_nonpreferred() or enable_all() as needed
# ROBUST: State tracking prevents infinite loops and redundant actions
# CALLED BY: systemd service (camera-swap-monitor.service) every 3 seconds
#---------------------------------------------------------------------
monitor_cameras() {
    load_config
    if [[ -z "$PREF_VENDOR" || -z "$PREF_PRODUCT" ]]; then
        return 0  # No config, nothing to monitor
    fi
    
    # Check if preferred camera is connected
    local preferred_connected=false
    for dev in /sys/bus/usb/drivers/uvcvideo/*; do
        if [[ -d "$dev" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/bind" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/unbind" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/new_id" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/remove_id" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/uevent" && "$dev" != "/sys/bus/usb/drivers/uvcvideo/module" ]]; then
            local usb_device=$(get_base_usb_path "$dev")
            if [[ -f "/sys/bus/usb/devices/$usb_device/idVendor" && -f "/sys/bus/usb/devices/$usb_device/idProduct" ]]; then
                local vid=$(cat "/sys/bus/usb/devices/$usb_device/idVendor")
                local pid=$(cat "/sys/bus/usb/devices/$usb_device/idProduct")
                if [[ "$vid" == "$PREF_VENDOR" && "$pid" == "$PREF_PRODUCT" ]]; then
                    preferred_connected=true
                    break
                fi
            fi
        fi
    done
    
    # Read last state if exists
    local last_state_file="/tmp/camera-swap-state"
    local last_state=""
    if [[ -f "$last_state_file" ]]; then
        last_state=$(cat "$last_state_file")
    fi
    
    # Determine current state
    local current_state=""
    if [[ "$preferred_connected" == true ]]; then
        current_state="preferred_connected"
    else
        current_state="preferred_disconnected"
    fi
    
    # Only act if state changed
    if [[ "$current_state" != "$last_state" ]]; then
        echo "$(date): Camera state changed from '$last_state' to '$current_state'" >> /var/log/camera-swap.log
        echo "$current_state" > "$last_state_file"
        
        if [[ "$current_state" == "preferred_connected" ]]; then
            echo "$(date): Preferred camera detected, disabling others" >> /var/log/camera-swap.log
            disable_nonpreferred >> /var/log/camera-swap.log 2>&1
        else
            echo "$(date): Preferred camera removed, enabling all cameras" >> /var/log/camera-swap.log
            enable_all >> /var/log/camera-swap.log 2>&1
        fi
    fi
}

#####################################################################
# MAIN ENTRY POINT
#####################################################################

#---------------------------------------------------------------------
# Command-line argument processing and function dispatch
#
# USAGE MODES:
#   ./script                     → Interactive setup (detect & choose camera)
#   ./script --camera N          → Non-interactive setup (use camera index N)
#   ./script --disable           → Manually disable non-preferred cameras
#   ./script --enable            → Manually enable all cameras
#   ./script --test              → Run diagnostic test (safe, read-only)
#   ./script --debug             → Advanced USB path debugging
#   ./script --monitor           → Run one monitoring cycle (used by systemd)
#
# NOTES:
#   • Most operations require root privileges (checked in functions)
#   • --test and --debug are safe for troubleshooting
#   • --monitor is called automatically by systemd service
#   • Setup creates persistent system configuration
#---------------------------------------------------------------------
### MAIN
case "$1" in
    --disable) check_root; disable_nonpreferred ;;
    --enable)  check_root; enable_all ;;
    --test)    test_unbind_rebind ;;
    --debug)   debug_usb_paths ;;
    --camera)  setup_rules "$2" ;;
    --monitor) monitor_cameras ;;
    *)         setup_rules ;;
esac

#####################################################################
# END OF SCRIPT
#####################################################################

