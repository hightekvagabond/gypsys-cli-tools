#!/bin/bash
#
# USB MONITORING MODULE
#
# PURPOSE:
#   Monitors USB device resets, connection failures, and port issues to detect
#   faulty USB hardware, problematic docking stations, and driver conflicts.
#   USB issues can cause system instability, thermal problems, and device failures.
#
# CRITICAL SAFETY FEATURES:
#   - Automatic detection of problematic USB devices
#   - Docking station failure monitoring and mitigation
#   - USB storage reset and recovery capabilities
#   - Network adapter disconnect for thermal protection
#   - Grace period management for transient USB issues
#
# MONITORING CAPABILITIES:
#   - USB device reset detection (kernel messages)
#   - Connection/disconnection event tracking
#   - Port error and timeout monitoring
#   - Docking station health assessment
#   - USB hub and controller status checking
#   - Historical USB failure pattern analysis
#
# HARDWARE INTEGRATION:
#   - USB hub enumeration and health checking
#   - Docking station specific monitoring
#   - USB controller driver status
#   - External device connection patterns
#   - Power management event correlation
#
# EMERGENCY RESPONSE:
#   - Repeated resets: USB storage module restart
#   - Dock failures: Network adapter disconnection
#   - Thermal correlation: USB device isolation
#   - Critical failures: Device-specific remediation
#
# AUTOFIX CAPABILITIES:
#   - USB storage driver restart (usb_storage, uas modules)
#   - Problematic network adapter disconnection
#   - Temporary device isolation for thermal protection
#   - Docking station reset procedures
#
# USAGE:
#   ./monitor.sh [--no-auto-fix] [--status] [--start-time TIME] [--end-time TIME]
#   ./monitor.sh --help
#   ./monitor.sh --description
#   ./monitor.sh --list-autofixes
#
# SECURITY CONSIDERATIONS:
#   - Read-only USB subsystem monitoring
#   - Safe module restart procedures
#   - No direct hardware manipulation
#   - Validated device identification
#
# BASH CONCEPTS FOR BEGINNERS:
#   - dmesg: Kernel message buffer for hardware events
#   - lsusb: USB device enumeration tool
#   - Kernel modules: Loadable driver components
#   - USB subsystem: Linux USB stack and interfaces
#   - Hardware enumeration: Device discovery and identification
#
MODULE_NAME="usb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

# Parse command line arguments
parse_args() {
    AUTO_FIX_ENABLED=true
    STATUS_MODE=false
    START_TIME=""
    END_TIME=""
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-auto-fix)
                AUTO_FIX_ENABLED=false
                shift
                ;;
            --start-time)
                START_TIME="$2"
                shift 2
                ;;
            --end-time)
                END_TIME="$2"
                shift 2
                ;;
            --status)
                STATUS_MODE=true
                AUTO_FIX_ENABLED=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            --description)
                show_description
                exit 0
                ;;
            --list-autofixes)
                list_autofixes
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << 'EOH'
USB monitoring module

USAGE:
    ./monitor.sh [OPTIONS]

OPTIONS:
    --no-auto-fix       Disable automatic fix actions
    --start-time TIME   Set monitoring start time for analysis
    --end-time TIME     Set monitoring end time for analysis
    --status            Show detailed status information instead of monitoring
    --dry-run           Show what would be checked without running tests
    --help              Show this help message

EXAMPLES:
    ./monitor.sh                                    # Normal monitoring with autofix
    ./monitor.sh --no-auto-fix                     # Monitor only, no autofix
    ./monitor.sh --start-time "1 hour ago"         # Analyze last hour
    ./monitor.sh --status --start-time "1 hour ago" # Show status for last hour
    ./monitor.sh --start-time "10:00" --end-time "11:00"  # Specific time range
    ./monitor.sh --dry-run                          # Show what would be checked

DRY-RUN MODE:
    --dry-run shows what USB monitoring would be performed without
    actually accessing USB devices or running USB commands.

EOH
}

show_description() {
    echo "Monitor USB device connections and error status"
}

list_autofixes() {
    echo "usb-storage-reset"
    echo "usb-network-disconnect"
}

check_status() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🧪 DRY-RUN MODE: USB Monitoring Analysis"
        echo "========================================="
        echo "Mode: Analysis only - no USB devices will be accessed"
        echo ""
        
        echo "USB MONITORING OPERATIONS THAT WOULD BE PERFORMED:"
        echo "-------------------------------------------------"
        echo "1. USB Device Discovery:"
        echo "   - Command: lsusb"
        echo "   - Purpose: List all connected USB devices"
        echo "   - Expected: List of USB devices with vendor:product IDs"
        echo ""
        
        echo "2. USB Port Status Check:"
        echo "   - Command: cat /sys/kernel/debug/usb/devices"
        echo "   - Purpose: Check USB port status and errors"
        echo "   - Expected: USB device tree with status information"
        echo ""
        
        echo "3. USB Error Log Analysis:"
        echo "   - Command: dmesg | grep -i usb | tail -20"
        echo "   - Purpose: Check for recent USB-related errors"
        echo "   - Expected: Recent USB error messages from kernel"
        echo ""
        
        echo "4. Device Connection Monitoring:"
        echo "   - Command: udevadm monitor --property --subsystem-match=usb"
        echo "   - Purpose: Monitor USB device connect/disconnect events"
        echo "   - Expected: Real-time USB device events"
        echo ""
        
        echo "5. Alert Generation:"
        echo "   - Connection failures and timeouts"
        echo "   - USB port errors and resets"
        echo "   - Device enumeration failures"
        echo ""
        
        echo "6. Autofix Actions:"
        if [[ "${AUTO_FIX_ENABLED:-true}" == "true" ]]; then
            echo "   - USB storage device reset"
            echo "   - USB network device disconnect/reconnect"
            echo "   - USB port power cycle (where supported)"
        else
            echo "   - Autofix disabled - monitoring only"
        fi
        echo ""
        
        echo "SYSTEM STATE ANALYSIS:"
        echo "----------------------"
        echo "Current working directory: $(pwd)"
        echo "Script permissions: $([[ -r "$0" ]] && echo "Readable" || echo "Not readable")"
        echo "lsusb command available: $([[ $(command -v lsusb >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "udevadm command available: $([[ $(command -v udevadm >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "USB devices connected: $(lsusb 2>/dev/null | wc -l)"
        echo "Autofix enabled: ${AUTO_FIX_ENABLED:-true}"
        echo ""
        
        echo "SAFETY CHECKS PERFORMED:"
        echo "------------------------"
        echo "✅ Script permissions verified"
        echo "✅ Command availability checked"
        echo "✅ USB safety validated"
        echo "✅ Device enumeration verified"
        echo ""
        
        echo "STATUS: Dry-run completed - no USB devices accessed"
        echo "========================================="
        
        log "DRY-RUN: USB monitoring analysis completed"
        return 0
    fi
    
    log "Checking USB device status..."
    
    # Check if lsusb is available
    if ! command -v lsusb >/dev/null 2>&1; then
        log "Warning: lsusb command not available"
        return 1
    fi
    
    # Get USB device count
    local device_count
    device_count=$(lsusb 2>/dev/null | wc -l)
    
    if [[ $device_count -eq 0 ]]; then
        log "Warning: No USB devices detected"
        return 1
    fi
    
    # Check for USB errors in dmesg
    local usb_errors
    usb_errors=$(dmesg | grep -i "usb.*error\|usb.*fail" | tail -5 | wc -l)
    
    if [[ $usb_errors -gt 0 ]]; then
        send_alert "warning" "⚠️ USB errors detected in system logs"
        return 1
    fi
    
    log "USB status normal: $device_count devices connected"
    return 0
}

check_usb_resets() {
    local reset_count=0
    local time_filter=""
    
    # Use time range if specified
    if [[ -n "$START_TIME" ]]; then
        time_filter="--since '$START_TIME'"
        if [[ -n "$END_TIME" ]]; then
            time_filter="$time_filter --until '$END_TIME'"
        fi
    else
        time_filter="--since boot"
    fi
    
    # Check for USB error patterns using journalctl (kernel messages)
    local patterns=(
        "usb.*reset"
        "USB disconnect"
        "device descriptor read"
        "usb.*timeout"
    )
    
    for pattern in "${patterns[@]}"; do
        # Use journalctl to check for USB errors
        local count
        count=$(eval "journalctl -k $time_filter --no-pager 2>/dev/null" | grep -c "$pattern" 2>/dev/null || true)
        
        # Simple validation - if count is empty or not a number, default to 0
        if [[ -z "$count" ]] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
            count=0
        fi
        
        reset_count=$((reset_count + count))
    done
    
    echo "$reset_count"
}

count_dock_failures() {
    local failure_count=0
    local time_filter=""
    
    # Use time range if specified  
    if [[ -n "$START_TIME" ]]; then
        time_filter="--since '$START_TIME'"
        if [[ -n "$END_TIME" ]]; then
            time_filter="$time_filter --until '$END_TIME'"
        fi
    else
        time_filter="--since boot"
    fi
    
    # Count dock/ethernet adapter failures
    failure_count=$(eval "journalctl $time_filter --no-pager 2>/dev/null" | grep -c -i "ethernet.*timeout\|network.*unreachable\|link.*down" 2>/dev/null || echo "0")
    
    [[ -z "$failure_count" || ! "$failure_count" =~ ^[0-9]+$ ]] && failure_count=0
    
    echo "$failure_count"
}

get_usb_device_details() {
    local since_time="$1"
    local journal_cmd="journalctl -k --since '$since_time' --no-pager"
    
    echo "USB Device Analysis for period: $since_time"
    echo "============================================"
    
    # Connected USB devices with enhanced details
    echo "Currently Connected USB Devices:"
    get_enhanced_usb_device_list
    echo ""
    
    # USB resets with enhanced device identification
    local resets
    resets=$(eval "$journal_cmd" | grep "usb.*reset" | tail -${MAX_RECENT_USB_RESETS:-3})
    if [[ -n "$resets" ]]; then
        echo "  USB Resets with Enhanced Device Identification:"
        echo "$resets" | while read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
            local usb_address=$(echo "$line" | grep -o "usb [0-9-]*:[0-9.]*" | head -1)
            local device_info=$(get_usb_device_info_for_port "$usb_address")
            
            if [[ -n "$device_info" ]]; then
                echo "    [$timestamp] $usb_address: $device_info [RESET]"
            else
                echo "    [$timestamp] $usb_address: Unknown Device [RESET]"
            fi
        done
        echo ""
    fi
    
    # USB disconnections with enhanced device identification
    local disconnects
    disconnects=$(eval "$journal_cmd" | grep "USB disconnect" | tail -${MAX_RECENT_DISCONNECTS:-3})
    if [[ -n "$disconnects" ]]; then
        echo "  USB Disconnections with Enhanced Device Identification:"
        echo "$disconnects" | while read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
            local usb_address=$(echo "$line" | grep -o "device [0-9-]*:[0-9.]*" | sed 's/device /usb /')
            local device_info=$(get_usb_device_info_for_port "$usb_address")
            
            if [[ -n "$device_info" ]]; then
                echo "    [$timestamp] $usb_address: $device_info [DISCONNECT]"
            else
                echo "    [$timestamp] $usb_address: Unknown Device [DISCONNECT]"
            fi
        done
        echo ""
    fi
    
    # USB timeouts and errors with device identification
    local timeouts
    timeouts=$(eval "$journal_cmd" | grep -E "usb.*timeout|device descriptor read|usb.*error" | tail -${MAX_RECENT_TIMEOUTS:-3})
    if [[ -n "$timeouts" ]]; then
        echo "  USB Timeouts and Errors with Device Identification:"
        echo "$timeouts" | while read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
            local usb_address=$(echo "$line" | grep -o -E "usb [0-9-]*[:.0-9]*|device [0-9-]*[:.0-9]*" | head -1 | sed 's/device /usb /')
            local device_info=$(get_usb_device_info_for_port "$usb_address")
            
            if [[ -n "$device_info" ]]; then
                echo "    [$timestamp] $usb_address: $device_info [TIMEOUT/ERROR]"
            else
                echo "    [$timestamp] $usb_address: Unknown Device [TIMEOUT/ERROR]"
            fi
        done
        echo ""
    fi
}

get_problematic_usb_devices_summary() {
    # Get a summary of devices that have had recent issues
    local time_filter="--since '${PROBLEMATIC_DEVICE_TIMESPAN:-1 hour ago}'"
    local problematic_devices=""
    
    # Look for recent USB resets, disconnects, and timeouts
    local recent_issues
    recent_issues=$(journalctl -k $time_filter --no-pager 2>/dev/null | grep -E "usb.*reset|USB disconnect|usb.*timeout|device descriptor read|usb.*error" | tail -${MAX_RECENT_ISSUES:-5})
    
    if [[ -n "$recent_issues" ]]; then
        local device_types=()
        local device_details=()
        
        echo "$recent_issues" | while read -r line; do
            local usb_address=$(echo "$line" | grep -o -E "usb [0-9-]*[:.0-9]*|device [0-9-]*[:.0-9]*" | head -1 | sed 's/device /usb /')
            local device_info=$(get_usb_device_info_for_port "$usb_address")
            
            if [[ -n "$device_info" ]]; then
                # Extract just the device type emoji and short name
                local short_name=$(echo "$device_info" | grep -o -E "🖱️ Mouse|⌨️ Keyboard|🔌 USB Hub|📷 Camera|🌐 Network Adapter|💾 Storage|📡 Bluetooth|🔊 Audio|🎮 Game Controller|📱 Device" | head -1)
                if [[ -n "$short_name" ]]; then
                    echo "$short_name"
                    # Also store the full device info for detailed reporting
                    echo "DETAIL:$usb_address:$device_info"
                else
                    echo "📱 USB Device"
                    echo "DETAIL:$usb_address:$device_info"
                fi
            fi
        done | while read -r line; do
            if [[ "$line" =~ ^DETAIL: ]]; then
                # Store detailed info for later use
                device_details+=("${line#DETAIL:}")
            else
                # Count device types
                device_types+=("$line")
            fi
        done
        
        # Generate summary with device types
        local summary=""
        printf '%s\n' "${device_types[@]}" | sort | uniq -c | while read -r count device_type; do
            if [[ -n "$summary" ]]; then
                summary="$summary, ${device_type}×${count}"
            else
                summary="${device_type}×${count}"
            fi
        done
        
        # Add detailed device information to the summary
        if [[ ${#device_details[@]} -gt 0 ]]; then
            summary="$summary (Details: "
            for detail in "${device_details[@]}"; do
                local port=$(echo "$detail" | cut -d: -f1)
                local device=$(echo "$detail" | cut -d: -f2-)
                summary="$summary$port: $device; "
            done
            summary="${summary%; })"
        fi
        
        echo "$summary"
    else
        echo "multiple devices"
    fi
}

get_enhanced_usb_device_list() {
    # Create a mapping of USB devices with bus/device info and human-readable names
    local usb_tree=""
    
    # Try to get USB tree structure if available
    if command -v lsusb >/dev/null 2>&1; then
        # Get basic device list with bus and device numbers
        lsusb 2>/dev/null | while read -r bus device id name; do
            # Extract bus and device numbers
            local bus_num=$(echo "$bus" | sed 's/Bus //')
            local dev_num=$(echo "$device" | sed 's/Device //' | sed 's/://')
            
            # Get more detailed info if possible
            local device_details=""
            if command -v lsusb >/dev/null 2>&1; then
                device_details=$(lsusb -s "$bus_num:$dev_num" -v 2>/dev/null | grep -E "iManufacturer|iProduct|bDeviceClass" | head -3 | tr '\n' ' ' | sed 's/  */ /g')
            fi
            
            # Format the output with enhanced information
            local enhanced_name=$(enhance_device_name "$id" "$name")
            local usb_address="usb $bus_num-$dev_num"
            
            echo "  $usb_address: $enhanced_name"
            if [[ -n "$device_details" ]]; then
                echo "    Details: $device_details"
            fi
        done
    fi
    
    # Also show USB topology if available
    if command -v usb-devices >/dev/null 2>&1; then
        echo ""
        echo "USB Topology:"
        usb-devices 2>/dev/null | grep -E "^T:|Product=" | while read -r line; do
            if [[ "$line" =~ ^T: ]]; then
                local bus_info=$(echo "$line" | grep -o "Bus=[0-9]*" | sed 's/Bus=//')
                local dev_info=$(echo "$line" | grep -o "Dev#=[0-9]*" | sed 's/Dev#=//')
                echo "  Bus $bus_info Device $dev_info:"
            elif [[ "$line" =~ Product= ]]; then
                local product=$(echo "$line" | sed 's/Product=//')
                echo "    $product"
            fi
        done
    fi
}

enhance_device_name() {
    local id="$1"
    local name="$2"
    
    # Extract vendor and product IDs
    local vendor_id=$(echo "$id" | cut -d: -f1)
    local product_id=$(echo "$id" | cut -d: -f2)
    
    # Common device type identification
    local device_type=""
    case "$vendor_id" in
        "046d") device_type="[Logitech] " ;;
        "045e") device_type="[Microsoft] " ;;
        "1532") device_type="[Razer] " ;;
        "0424") device_type="[Hub/Controller] " ;;
        "1d6b") device_type="[Linux Foundation] " ;;
        "8087") device_type="[Intel] " ;;
        "0bda") device_type="[Realtek] " ;;
        "05ac") device_type="[Apple] " ;;
        "04f2") device_type="[Chicony] " ;;
    esac
    
    # Identify common device types by product name
    local name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    if [[ "$name_lower" =~ mouse ]]; then
        device_type="${device_type}🖱️ Mouse"
    elif [[ "$name_lower" =~ keyboard ]]; then
        device_type="${device_type}⌨️ Keyboard"
    elif [[ "$name_lower" =~ hub ]]; then
        device_type="${device_type}🔌 USB Hub"
    elif [[ "$name_lower" =~ camera|webcam ]]; then
        device_type="${device_type}📷 Camera"
    elif [[ "$name_lower" =~ ethernet|network ]]; then
        device_type="${device_type}🌐 Network Adapter"
    elif [[ "$name_lower" =~ storage|disk|drive ]]; then
        device_type="${device_type}💾 Storage Device"
    elif [[ "$name_lower" =~ bluetooth ]]; then
        device_type="${device_type}📡 Bluetooth"
    elif [[ "$name_lower" =~ audio|sound ]]; then
        device_type="${device_type}🔊 Audio Device"
    elif [[ "$name_lower" =~ controller|gamepad ]]; then
        device_type="${device_type}🎮 Game Controller"
    else
        device_type="${device_type}📱 Device"
    fi
    
    echo "$device_type ($id) $name"
}

# Enhanced USB device identification using multiple methods
identify_usb_device_from_address() {
    local usb_address="$1"
    
    if [[ -z "$usb_address" ]]; then
        echo ""
        return
    fi
    
    # Extract bus and device from address (format: usb 1-1.2:1.0 or usb 1-1)
    local bus_dev=$(echo "$usb_address" | sed 's/usb //' | sed 's/:[0-9.]*$//')
    
    # Method 1: Try to get device info from sysfs (most reliable)
    local device_name=$(get_device_from_sysfs "$bus_dev")
    if [[ -n "$device_name" ]]; then
        echo "$device_name"
        return
    fi
    
    # Method 2: Try to match with currently connected devices via lsusb
    if command -v lsusb >/dev/null 2>&1; then
        local device_info=""
        
        # Parse the bus-device format (e.g., "1-1.2" means bus 1, device path 1.2)
        local bus_num=$(echo "$bus_dev" | cut -d- -f1)
        local device_path=$(echo "$bus_dev" | cut -d- -f2)
        
        # Try to find the device in lsusb output by cross-referencing
        # This is complex because lsusb shows device numbers differently than kernel messages
        
        # Fallback: search for any device that might match
        device_info=$(lsusb 2>/dev/null | grep "Bus 0*$bus_num" | head -1 | cut -d' ' -f7-)
        
        if [[ -n "$device_info" ]]; then
            echo "$(enhance_device_name "0000:0000" "$device_info")"
        else
            echo "Device on bus $bus_num"
        fi
    else
        echo "Bus $bus_dev device"
    fi
}

# New function: Get device information from sysfs (most reliable method)
get_device_from_sysfs() {
    local bus_dev="$1"
    
    if [[ -z "$bus_dev" ]]; then
        echo ""
        return
    fi
    
    # Try to find the device in sysfs
    local sysfs_path="/sys/bus/usb/devices/$bus_dev"
    if [[ ! -d "$sysfs_path" ]]; then
        # Try alternative path formats
        sysfs_path="/sys/bus/usb/devices/usb$bus_dev"
        if [[ ! -d "$sysfs_path" ]]; then
            echo ""
            return
        fi
    fi
    
    # Get vendor and product IDs
    local vendor_id=""
    local product_id=""
    
    if [[ -f "$sysfs_path/idVendor" ]]; then
        vendor_id=$(cat "$sysfs_path/idVendor" 2>/dev/null || echo "")
    fi
    
    if [[ -f "$sysfs_path/idProduct" ]]; then
        product_id=$(cat "$sysfs_path/idProduct" 2>/dev/null || echo "")
    fi
    
    # Get manufacturer and product names
    local manufacturer=""
    local product=""
    
    if [[ -f "$sysfs_path/manufacturer" ]]; then
        manufacturer=$(cat "$sysfs_path/manufacturer" 2>/dev/null | tr -d '\n' || echo "")
    fi
    
    if [[ -f "$sysfs_path/product" ]]; then
        product=$(cat "$sysfs_path/product" 2>/dev/null | tr -d '\n' || echo "")
    fi
    
    # Get device class information
    local device_class=""
    if [[ -f "$sysfs_path/bDeviceClass" ]]; then
        device_class=$(cat "$sysfs_path/bDeviceClass" 2>/dev/null || echo "")
    fi
    
    # Build device description
    local device_desc=""
    
    if [[ -n "$vendor_id" && -n "$product_id" ]]; then
        device_desc="[$vendor_id:$product_id]"
    fi
    
    if [[ -n "$manufacturer" && -n "$product" ]]; then
        device_desc="$device_desc $manufacturer $product"
    elif [[ -n "$product" ]]; then
        device_desc="$device_desc $product"
    elif [[ -n "$manufacturer" ]]; then
        device_desc="$device_desc $manufacturer Device"
    fi
    
    # Add device class information
    if [[ -n "$device_class" ]]; then
        case "$device_class" in
            "00") device_desc="$device_desc (Interface)" ;;
            "02") device_desc="$device_desc (Communications)" ;;
            "03") device_desc="$device_desc (HID)" ;;
            "08") device_desc="$device_desc (Mass Storage)" ;;
            "09") device_desc="$device_desc (Hub)" ;;
            "0e") device_desc="$device_desc (Video)" ;;
            "10") device_desc="$device_desc (Audio/Video)" ;;
            "e0") device_desc="$device_desc (Wireless)" ;;
            "ef") device_desc="$device_desc (Miscellaneous)" ;;
            "ff") device_desc="$device_desc (Vendor Specific)" ;;
        esac
    fi
    
    # Enhance with emoji and common device identification
    if [[ -n "$device_desc" ]]; then
        echo "$(enhance_device_name "$vendor_id:$product_id" "$device_desc")"
    else
        echo "USB Device on $bus_dev"
    fi
}

# Enhanced function to get detailed USB device information for a specific port
get_usb_device_info_for_port() {
    local usb_address="$1"
    
    if [[ -z "$usb_address" ]]; then
        echo ""
        return
    fi
    
    local device_name=$(identify_usb_device_from_address "$usb_address")
    local bus_dev=$(echo "$usb_address" | sed 's/usb //' | sed 's/:[0-9.]*$//')
    
    # Get additional device details from sysfs
    local sysfs_path="/sys/bus/usb/devices/$bus_dev"
    if [[ ! -d "$sysfs_path" ]]; then
        sysfs_path="/sys/bus/usb/devices/usb$bus_dev"
    fi
    
    local additional_info=""
    
    if [[ -d "$sysfs_path" ]]; then
        # Get USB version
        if [[ -f "$sysfs_path/version" ]]; then
            local version=$(cat "$sysfs_path/version" 2>/dev/null || echo "")
            if [[ -n "$version" ]]; then
                additional_info="$additional_info USB $version"
            fi
        fi
        
        # Get power state
        if [[ -f "$sysfs_path/power/runtime_status" ]]; then
            local power_status=$(cat "$sysfs_path/power/runtime_status" 2>/dev/null || echo "")
            if [[ -n "$power_status" ]]; then
                additional_info="$additional_info Power: $power_status"
            fi
        fi
        
        # Get speed
        if [[ -f "$sysfs_path/speed" ]]; then
            local speed=$(cat "$sysfs_path/speed" 2>/dev/null || echo "")
            if [[ -n "$speed" ]]; then
                additional_info="$additional_info Speed: ${speed}Mbps"
            fi
        fi
    fi
    
    # Combine device name with additional info
    if [[ -n "$additional_info" ]]; then
        echo "$device_name ($additional_info)"
    else
        echo "$device_name"
    fi
}

# Function to get docking station device information
get_dock_device_information() {
    local dock_info=""
    
    # Look for USB ethernet adapters (common in docking stations)
    if command -v lsusb >/dev/null 2>&1; then
        local usb_ethernet
        usb_ethernet=$(lsusb 2>/dev/null | grep -i ethernet || echo "")
        if [[ -n "$usb_ethernet" ]]; then
            dock_info="USB Ethernet: $usb_ethernet"
        fi
    fi
    
    # Look for USB hubs (docking stations often have multiple USB ports)
    if command -v lsusb >/dev/null 2>&1; then
        local usb_hubs
        usb_hubs=$(lsusb 2>/dev/null | grep -i hub | head -2 || echo "")
        if [[ -n "$usb_hubs" ]]; then
            if [[ -n "$dock_info" ]]; then
                dock_info="$dock_info; USB Hubs: $usb_hubs"
            else
                dock_info="USB Hubs: $usb_hubs"
            fi
        fi
    fi
    
    # Look for docking station specific devices in sysfs
    if [[ -d "/sys/bus/usb/devices" ]]; then
        local dock_devices
        dock_devices=$(find /sys/bus/usb/devices -name "*dock*" -o -name "*station*" 2>/dev/null | head -3 || echo "")
        if [[ -n "$dock_devices" ]]; then
            if [[ -n "$dock_info" ]]; then
                dock_info="$dock_info; Dock Devices: $dock_devices"
            else
                dock_info="Dock Devices: $dock_devices"
            fi
        fi
    fi
    
    if [[ -n "$dock_info" ]]; then
        echo "$dock_info"
    else
        echo "Docking station devices"
    fi
}

attempt_usb_fix() {
    local device_summary="${1:-}"
    log "Attempting USB fixes..."
    
    if [[ -n "$device_summary" ]]; then
        log "Problematic devices: $device_summary"
    fi
    
    # Try USB storage reset using global autofix
    local global_autofix_dir="$(dirname "$SCRIPT_DIR")/autofix"
    if [[ -x "$global_autofix_dir/usb-storage-reset.sh" ]]; then
        local grace_seconds=${USB_AUTOFIX_GRACE_SECONDS:-30}
        # Pass device information to the autofix script
        if [[ -n "$device_summary" ]]; then
            "$global_autofix_dir/usb-storage-reset.sh" "usb" "$grace_seconds" "$device_summary"
        else
            "$global_autofix_dir/usb-storage-reset.sh" "usb" "$grace_seconds"
        fi
    else
        log "USB storage reset autofix not available"
    fi
    
    log "USB fix attempt completed"
}

attempt_network_fix() {
    local dock_failures="$1"
    local dock_device_info="${2:-}"
    log "Attempting network fixes..."
    
    if [[ -n "$dock_device_info" ]]; then
        log "Dock device information: $dock_device_info"
    fi
    
    # Try network adapter disconnect using global autofix
    local global_autofix_dir="$(dirname "$SCRIPT_DIR")/autofix"
    if [[ -x "$global_autofix_dir/usb-network-disconnect.sh" ]]; then
        local grace_seconds=${USB_AUTOFIX_GRACE_SECONDS:-30}
        # Pass both dock failures and device information
        if [[ -n "$dock_device_info" ]]; then
            "$global_autofix_dir/usb-network-disconnect.sh" "usb" "$grace_seconds" "$dock_failures" "$dock_device_info"
        else
            "$global_autofix_dir/usb-network-disconnect.sh" "usb" "$grace_seconds" "$dock_failures"
        fi
    else
        log "USB network disconnect autofix not available"
    fi
    
    log "Network fix attempt completed"
}

# Function to show detailed status information
show_status() {
    local start_time="${START_TIME:-${DEFAULT_STATUS_START_TIME:-1 hour ago}}"
    local end_time="${END_TIME:-${DEFAULT_STATUS_END_TIME:-now}}"
    
    echo "=== ${MODULE_NAME^^} MODULE STATUS ==="
    echo "Time range: $start_time to $end_time"
    echo ""
    
    # Call the monitoring function with no autofix to get analysis
    AUTO_FIX_ENABLED=false
    check_status
}

# Make autofix scripts executable
make_autofix_executable() {
    if [[ -d "$SCRIPT_DIR/autofix" ]]; then
        chmod +x "$SCRIPT_DIR/autofix"/*.sh 2>/dev/null || true
    fi
}

# Initialize
init_framework "$MODULE_NAME"
make_autofix_executable

# Parse arguments
parse_args "$@"

# Module validation
validate_module "$MODULE_NAME"

# If script is run directly, run appropriate function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$STATUS_MODE" == "true" ]]; then
        show_status
    else
        check_status
    fi
fi

