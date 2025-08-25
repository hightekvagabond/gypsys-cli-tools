#!/bin/bash
# USB monitoring module - restructured version

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
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << 'EOF'
USB Monitor Module

USAGE:
    ./monitor.sh [OPTIONS]

OPTIONS:
    --no-auto-fix       Disable automatic fix actions
    --start-time TIME   Set monitoring start time for analysis
    --end-time TIME     Set monitoring end time for analysis
    --status            Show detailed status information instead of monitoring
    --help              Show this help message

EXAMPLES:
    ./monitor.sh                                    # Normal monitoring with autofix
    ./monitor.sh --no-auto-fix                     # Monitor only, no autofix
    ./monitor.sh --start-time "1 hour ago"         # Analyze last hour
    ./monitor.sh --status --start-time "1 hour ago" # Show status for last hour
    ./monitor.sh --start-time "10:00" --end-time "11:00"  # Specific time range

EOF
}

check_status() {
    local usb_resets
    usb_resets=$(check_usb_resets)
    
    # Check for docking station ethernet failures (thermal risk)
    local dock_failures
    dock_failures=$(count_dock_failures)
    
    if [[ $usb_resets -ge ${USB_RESET_CRITICAL:-20} ]]; then
        local device_summary=$(get_problematic_usb_devices_summary)
        send_alert "critical" "🔌 Critical: $usb_resets USB device resets detected ($device_summary)"
        log "USB Device Details:"
        get_usb_device_details "${USB_DETAIL_ANALYSIS_TIMESPAN:-1 hour ago}" | while read -r line; do
            log "$line"
        done
        
        if [[ "${AUTO_FIX_ENABLED:-true}" == "true" && "${ENABLE_USB_AUTOFIX:-true}" == "true" ]]; then
            attempt_usb_fix
        else
            log "Autofix disabled - no automatic repair attempted"
        fi
        return 1
    elif [[ $dock_failures -gt ${DOCK_FAILURE_THRESHOLD:-20} ]]; then
        send_alert "critical" "🌐 Critical: $dock_failures docking station ethernet failures - attempting adapter disable"
        
        if [[ "${AUTO_FIX_ENABLED:-true}" == "true" && "${ENABLE_USB_AUTOFIX:-true}" == "true" ]]; then
            attempt_network_fix "$dock_failures"
        else
            log "Autofix disabled - no automatic repair attempted"
        fi
        return 1
    elif [[ $usb_resets -ge ${USB_RESET_WARNING:-10} ]]; then
        send_alert "warning" "🔌 Warning: $usb_resets USB device resets detected"
        log "USB Device Details:"
        get_usb_device_details "${USB_DETAIL_ANALYSIS_TIMESPAN:-1 hour ago}" | while read -r line; do
            log "$line"
        done
        return 1
    fi
    
    log "USB/Network status normal: $usb_resets USB resets, $dock_failures dock failures since boot"
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
    
    # USB resets with device identification
    local resets
    resets=$(eval "$journal_cmd" | grep "usb.*reset" | tail -${MAX_RECENT_USB_RESETS:-3})
    if [[ -n "$resets" ]]; then
        echo "  USB Resets with Device Identification:"
        echo "$resets" | while read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
            local usb_address=$(echo "$line" | grep -o "usb [0-9-]*:[0-9.]*" | head -1)
            local device_name=$(identify_usb_device_from_address "$usb_address")
            
            if [[ -n "$device_name" ]]; then
                echo "    [$timestamp] $usb_address: $device_name [RESET]"
            else
                echo "    [$timestamp] $usb_address: Unknown Device [RESET]"
            fi
        done
        echo ""
    fi
    
    # USB disconnections with device identification
    local disconnects
    disconnects=$(eval "$journal_cmd" | grep "USB disconnect" | tail -${MAX_RECENT_DISCONNECTS:-3})
    if [[ -n "$disconnects" ]]; then
        echo "  USB Disconnections with Device Identification:"
        echo "$disconnects" | while read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
            local usb_address=$(echo "$line" | grep -o "device [0-9-]*:[0-9.]*" | sed 's/device /usb /')
            local device_name=$(identify_usb_device_from_address "$usb_address")
            
            if [[ -n "$device_name" ]]; then
                echo "    [$timestamp] $usb_address: $device_name [DISCONNECT]"
            else
                echo "    [$timestamp] $usb_address: Unknown Device [DISCONNECT]"
            fi
        done
        echo ""
    fi
}

get_problematic_usb_devices_summary() {
    # Get a summary of devices that have had recent issues
    local time_filter="--since '${PROBLEMATIC_DEVICE_TIMESPAN:-1 hour ago}'"
    local problematic_devices=""
    
    # Look for recent USB resets and disconnects
    local recent_issues
    recent_issues=$(journalctl -k $time_filter --no-pager 2>/dev/null | grep -E "usb.*reset|USB disconnect" | tail -${MAX_RECENT_ISSUES:-5})
    
    if [[ -n "$recent_issues" ]]; then
        local device_types=()
        
        echo "$recent_issues" | while read -r line; do
            local usb_address=$(echo "$line" | grep -o -E "usb [0-9-]*[:.0-9]*|device [0-9-]*[:.0-9]*" | head -1)
            local device_name=$(identify_usb_device_from_address "$usb_address")
            
            if [[ -n "$device_name" ]]; then
                # Extract just the device type emoji and short name
                local short_name=$(echo "$device_name" | grep -o -E "🖱️ Mouse|⌨️ Keyboard|🔌 USB Hub|📷 Camera|🌐 Network Adapter|💾 Storage|📡 Bluetooth|🔊 Audio|🎮 Game Controller|📱 Device" | head -1)
                if [[ -n "$short_name" ]]; then
                    echo "$short_name"
                else
                    echo "📱 USB Device"
                fi
            fi
        done | sort | uniq -c | while read -r count device_type; do
            echo "${device_type}×${count}"
        done | tr '\n' ', ' | sed 's/,$//'
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

identify_usb_device_from_address() {
    local usb_address="$1"
    
    if [[ -z "$usb_address" ]]; then
        echo ""
        return
    fi
    
    # Extract bus and device from address (format: usb 1-1.2:1.0 or usb 1-1)
    local bus_dev=$(echo "$usb_address" | sed 's/usb //' | sed 's/:[0-9.]*$//')
    
    # Try to match with currently connected devices
    if command -v lsusb >/dev/null 2>&1; then
        # Look through lsusb output to find matching device
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

attempt_usb_fix() {
    log "Attempting USB fixes..."
    
    # Try USB storage reset
    if [[ -x "$SCRIPT_DIR/autofix/storage-reset.sh" ]]; then
        "$SCRIPT_DIR/autofix/storage-reset.sh"
    fi
    
    log "USB fix attempt completed"
}

attempt_network_fix() {
    local dock_failures="$1"
    log "Attempting network fixes..."
    
    # Try network adapter disconnect
    if [[ -x "$SCRIPT_DIR/autofix/network-disconnect.sh" ]]; then
        "$SCRIPT_DIR/autofix/network-disconnect.sh" "$dock_failures"
    fi
    
    log "Network fix attempt completed"
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

# If script is run directly, run check_status
# If script is run directly, run appropriate function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$STATUS_MODE" == "true" ]]; then
        show_status
    else
    check_status
fi

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

