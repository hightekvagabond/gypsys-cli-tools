#!/bin/bash
# Common functions shared across all monitoring modules

set -euo pipefail

# Load configuration
MODULAR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$MODULAR_DIR/config"
FRAMEWORK_DIR="$MODULAR_DIR/framework"
STATE_DIR="/var/tmp/modular-monitor-state"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Load configuration files in order (framework config first, then module-specific)
if [[ -f "$FRAMEWORK_DIR/monitor-config.sh" ]]; then
    MONITOR_ROOT="$MODULAR_DIR"
    source "$FRAMEWORK_DIR/monitor-config.sh"
fi

# Legacy config support
if [[ -f "$CONFIG_DIR/thresholds.conf" ]]; then
    source "$CONFIG_DIR/thresholds.conf"
fi

# Logging functions
log() {
    local module="${MODULE_NAME:-monitor}"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_message="$timestamp [$module] $*"
    
    # Primary: Send to systemd journal/syslog
    if command -v logger >/dev/null 2>&1; then
        echo "$log_message" | logger -t "modular-monitor" || true
    fi
    
    # Secondary: Try systemd journal directly (if available)
    if command -v systemd-cat >/dev/null 2>&1; then
        echo "$log_message" | systemd-cat -t "modular-monitor" -p info || true
    fi
    
    # Fallback: Write to system log file (if writable)
    if [[ -w "/var/log" ]]; then
        echo "$log_message" >> "/var/log/modular-monitor.log" 2>/dev/null || true
    fi
    
    # Always output to console for immediate feedback
    echo "$log_message"
}

error() {
    local module="${MODULE_NAME:-monitor}"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local error_message="$timestamp [$module] ERROR: $*"
    
    # Primary: Send to systemd journal/syslog with error priority
    if command -v logger >/dev/null 2>&1; then
        echo "$error_message" | logger -t "modular-monitor" -p user.err || true
    fi
    
    # Secondary: Try systemd journal directly with error level
    if command -v systemd-cat >/dev/null 2>&1; then
        echo "$error_message" | systemd-cat -t "modular-monitor" -p err || true
    fi
    
    # Fallback: Write to system log file (if writable)
    if [[ -w "/var/log" ]]; then
        echo "$error_message" >> "/var/log/modular-monitor.log" 2>/dev/null || true
    fi
    
    # Always output to stderr for immediate feedback
    echo "$error_message" >&2
}

# Hardware existence check functions
check_hardware_exists() {
    local module="${MODULE_NAME:-$1}"
    
    case "$module" in
        "thermal")
            check_thermal_hardware
            ;;
        "usb")
            check_usb_hardware
            ;;
        "i915")
            check_i915_hardware
            ;;
        "memory")
            check_memory_hardware
            ;;
        "disk")
            check_disk_hardware
            ;;
        "kernel")
            check_kernel_hardware
            ;;
        "network")
            check_network_hardware
            ;;
        "nonexistent")
            check_nonexistent_hardware
            ;;
        *)
            log "Warning: No hardware check defined for module '$module', assuming hardware exists"
            return 0
            ;;
    esac
}

check_thermal_hardware() {
    # Check if we can read CPU temperature
    if command -v sensors >/dev/null 2>&1; then
        sensors 2>/dev/null | grep -q "°C" && return 0
    fi
    
    # Check thermal zones
    if [[ -d "/sys/class/thermal" ]]; then
        find /sys/class/thermal -name "temp" -readable 2>/dev/null | head -1 | grep -q . && return 0
    fi
    
    # Check for CPU package temp
    if [[ -r "/sys/class/thermal/thermal_zone0/temp" ]]; then
        return 0
    fi
    
    return 1
}

check_usb_hardware() {
    # Check if USB subsystem exists
    if command -v lsusb >/dev/null 2>&1; then
        lsusb 2>/dev/null | grep -q "Bus" && return 0
    fi
    
    # Check for USB devices in sysfs
    if [[ -d "/sys/bus/usb/devices" ]]; then
        find /sys/bus/usb/devices -mindepth 1 -maxdepth 1 2>/dev/null | head -1 | grep -q . && return 0
    fi
    
    return 1
}

check_i915_hardware() {
    # Check if Intel GPU is present
    if command -v lspci >/dev/null 2>&1; then
        lspci 2>/dev/null | grep -qi "intel.*graphics\|intel.*display" && return 0
    fi
    
    # Check for i915 module
    if lsmod 2>/dev/null | grep -q "^i915"; then
        return 0
    fi
    
    # Check for Intel GPU in sysfs
    if [[ -d "/sys/class/drm" ]]; then
        find /sys/class/drm -name "*i915*" 2>/dev/null | head -1 | grep -q . && return 0
    fi
    
    return 1
}

check_memory_hardware() {
    # Check if we can read memory information
    if command -v free >/dev/null 2>&1; then
        free -b 2>/dev/null | grep -q "Mem:" && return 0
    fi
    
    # Check /proc/meminfo
    if [[ -r "/proc/meminfo" ]]; then
        grep -q "MemTotal:" /proc/meminfo 2>/dev/null && return 0
    fi
    
    return 1
}

check_disk_hardware() {
    # Check if we can read disk information
    if command -v df >/dev/null 2>&1; then
        df / 2>/dev/null | grep -q "/" && return 0
    fi
    
    # Check for mounted filesystems
    if [[ -r "/proc/mounts" ]]; then
        grep -q "^/" /proc/mounts 2>/dev/null && return 0
    fi
    
    return 1
}

check_kernel_hardware() {
    # Kernel monitoring should work on any Linux system
    if [[ -r "/proc/version" ]]; then
        return 0
    fi
    
    # Check if we can access kernel logs
    if command -v dmesg >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

check_network_hardware() {
    # Check if we have network interfaces
    if command -v ip >/dev/null 2>&1; then
        ip link show 2>/dev/null | grep -q ":" && return 0
    fi
    
    # Check /proc/net/dev
    if [[ -r "/proc/net/dev" ]]; then
        tail -n +3 /proc/net/dev 2>/dev/null | grep -q ":" && return 0
    fi
    
    # Check sysfs
    if [[ -d "/sys/class/net" ]]; then
        find /sys/class/net -mindepth 1 -maxdepth 1 -not -name "lo" 2>/dev/null | head -1 | grep -q . && return 0
    fi
    
    return 1
}

check_nonexistent_hardware() {
    # This should always fail - testing for non-existent quantum flux capacitor
    return 1
}

# Helper function to check enabled modules and their hardware existence
check_enabled_modules_hardware() {
    local config_dir="${CONFIG_DIR:-$(dirname "$MODULAR_DIR")/config}"
    local modules_dir="${MODULAR_DIR}/modules"
    local skipped_modules=()
    local missing_hardware=()
    local available_modules=()
    
    # Find all enabled modules
    for enabled_file in "$config_dir"/*.enabled; do
        if [[ -L "$enabled_file" && -f "$enabled_file" ]]; then
            local module_name
            module_name=$(basename "$enabled_file" .enabled)
            local exists_script="$modules_dir/$module_name/exists.sh"
            
            if [[ -f "$exists_script" && -x "$exists_script" ]]; then
                if "$exists_script" >/dev/null 2>&1; then
                    available_modules+=("$module_name")
                else
                    missing_hardware+=("$module_name")
                fi
            else
                # No exists.sh script - assume available for backwards compatibility
                available_modules+=("$module_name")
            fi
        fi
    done
    
    # Report results
    if [[ ${#missing_hardware[@]} -gt 0 ]]; then
        log "⚠️  Enabled modules with missing hardware: ${missing_hardware[*]}"
        for module in "${missing_hardware[@]}"; do
            log "   • $module: enabled but required hardware not detected"
        done
    fi
    
    if [[ ${#available_modules[@]} -gt 0 ]]; then
        log "✅ Available modules: ${available_modules[*]}"
    fi
    
    # Return arrays via global variables for caller to use
    AVAILABLE_MODULES=("${available_modules[@]}")
    MISSING_HARDWARE_MODULES=("${missing_hardware[@]}")
    
    return 0
}

# Autofix management functions
list_autofix_scripts() {
    local module_name="${MODULE_NAME:-unknown}"
    
    echo "AUTOFIX SCRIPTS FOR MODULE: $module_name"
    echo "==========================================="
    
    # Get list of autofixes this module declares it uses
    local declared_autofixes
    if declared_autofixes=$("$SCRIPT_DIR/monitor.sh" --list-autofixes 2>/dev/null); then
        echo "Module declares the following autofixes:"
        while IFS= read -r autofix_name; do
            [[ -z "$autofix_name" ]] && continue
            echo "  📄 ${autofix_name}.sh"
            
            # Check if the autofix exists in global directory
            local global_autofix_dir="$(dirname "$SCRIPT_DIR")/autofix"
            local autofix_script="$global_autofix_dir/${autofix_name}.sh"
            if [[ -f "$autofix_script" && -x "$autofix_script" ]]; then
                echo "     Status: ✅ Available in global autofix directory"
                
                # Try to extract description from script comments
                local description
                description=$(grep -m1 "^# " "$autofix_script" 2>/dev/null | sed 's/^# //' || echo "No description available")
                echo "     Description: $description"
            else
                echo "     Status: ❌ NOT FOUND in global autofix directory"
            fi
            
        done <<< "$declared_autofixes"
    else
        echo "ℹ️  Module does not declare any autofixes (--list-autofixes not supported or empty)"
    fi
    
    echo ""
    
    # Check for configuration variables that might control autofixes
    echo "Configuration variables (from config.conf):"
    if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
        grep -E "(AUTOFIX|THRESHOLD|ENABLE_.*)" "$SCRIPT_DIR/config.conf" 2>/dev/null | while IFS= read -r line; do
            echo "  🔧 $line"
        done
    else
        echo "  ❌ No config.conf found"
    fi
}

get_expected_autofix_scripts() {
    local module_name="${MODULE_NAME:-unknown}"
    local expected_scripts=()
    
    # Get autofix scripts declared by the module
    if [[ -f "$SCRIPT_DIR/monitor.sh" ]]; then
        local declared_autofixes
        if declared_autofixes=$("$SCRIPT_DIR/monitor.sh" --list-autofixes 2>/dev/null); then
            while IFS= read -r autofix_name; do
                [[ -z "$autofix_name" ]] && continue
                expected_scripts+=("${autofix_name}.sh")
            done <<< "$declared_autofixes"
        fi
    fi
    
    printf '%s\n' "${expected_scripts[@]}"
}

# Alert functions
send_alert() {
    local level="$1"
    local message="$2"
    local module="${MODULE_NAME:-monitor}"
    
    if ! should_alert "$level" "$module"; then
        return 0
    fi
    
    # Desktop notification
    if command -v notify-send >/dev/null 2>&1; then
        local urgency="normal"
        local icon="dialog-information"
        case "$level" in
            critical|emergency)
                urgency="critical"
                icon="dialog-error"
                ;;
            warning)
                urgency="normal"
                icon="dialog-warning"
                ;;
        esac
        
        DISPLAY=:0 notify-send -u "$urgency" -i "$icon" -t 10000 \
            "🛡️ Modular Monitor: $module" "$message" 2>/dev/null &
    fi
    
    # Log alert
    log "ALERT[$level]: $message"
    
    # Record alert timestamp
    record_alert "$level" "$module"
}

# Alert cooldown management
should_alert() {
    local level="$1"
    local module="$2"
    local cooldown_file="$STATE_DIR/${module}_${level}_last_alert"
    local current_time=$(date +%s)
    
    # Default cooldowns (in seconds)
    local cooldown=300  # 5 minutes default
    case "$level" in
        critical|emergency) cooldown=180 ;;  # 3 minutes
        warning) cooldown=600 ;;             # 10 minutes
    esac
    
    if [[ -f "$cooldown_file" ]]; then
        local last_alert
        last_alert=$(cat "$cooldown_file" 2>/dev/null || echo "0")
        local time_diff=$((current_time - last_alert))
        if [[ $time_diff -lt $cooldown ]]; then
            return 1  # Still in cooldown
        fi
    fi
    
    return 0  # Can alert
}

record_alert() {
    local level="$1"
    local module="$2"
    local cooldown_file="$STATE_DIR/${module}_${level}_last_alert"
    date +%s > "$cooldown_file"
}

# Process utilities
get_top_cpu_processes() {
    ps -eo pid,pcpu,cmd --sort=-pcpu --no-headers | head -10
}

get_top_memory_processes() {
    ps -eo pid,pmem,cmd --sort=-pmem --no-headers | head -10
}

is_system_critical_process() {
    local pid="$1"
    local cmd="$2"
    
    # System critical patterns
    local critical_patterns=(
        "^\[.*\]$"                    # Kernel threads
        "^(systemd|kthreadd|ksoftirqd|migration|rcu_|watchdog)"
        "^(dbus|networkd|resolved|login)"
        "^(Xorg|gdm|lightdm|sddm)"
        "^(pipewire|pulseaudio|alsa)"
        "^ssh"
    )
    
    for pattern in "${critical_patterns[@]}"; do
        if [[ "$cmd" =~ $pattern ]]; then
            return 0  # Is critical
        fi
    done
    
    return 1  # Not critical
}

# Temperature utilities
get_cpu_package_temp() {
    # Try sensors first (most reliable)
    if command -v sensors >/dev/null 2>&1; then
        local temp
        temp=$(sensors 2>/dev/null | grep -E "Package id 0|Tctl" | head -1 | grep -oE '[0-9]+\.[0-9]+°C' | head -1 | sed 's/°C//')
        if [[ -n "$temp" ]]; then
            echo "$temp"
            return 0
        fi
    fi
    
    # Fallback to thermal zones
    local max_temp=0
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        if [[ -f "$zone" ]]; then
            local temp_millic
            temp_millic=$(cat "$zone" 2>/dev/null || echo "0")
            local temp_c=$((temp_millic / 1000))
            if [[ $temp_c -gt $max_temp && $temp_c -lt 200 ]]; then
                max_temp=$temp_c
            fi
        fi
    done
    
    if [[ $max_temp -gt 0 ]]; then
        echo "$max_temp"
        return 0
    fi
    
    echo "unknown"
    return 1
}

# Module validation
validate_module() {
    local module_name="$1"
    
    # Check required variables
    if [[ -z "${MODULE_NAME:-}" ]]; then
        error "Module must set MODULE_NAME variable"
        return 1
    fi
    
    # Check required functions
    if ! declare -f check_status >/dev/null 2>&1; then
        error "Module must implement check_status() function"
        return 1
    fi
    
    return 0
}

# System utilities
get_uptime_seconds() {
    awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 3600
}

# Framework initialization  
init_framework() {
    local module_name="$1"
    MODULE_NAME="$module_name"
    LOG_TAG="$module_name"
    mkdir -p "$STATE_DIR/$module_name"
    log "Framework initialized for module: $module_name"
}

# Module help and status function
show_module_help() {
    local module_name="$1"
    local calling_script="$2"  # monitor.sh, status.sh, or test.sh
    local script_dir="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    
    if [[ -z "$module_name" ]]; then
        echo "❌ Error: Module name required"
        echo "Usage: show_module_help MODULE_NAME [CALLING_SCRIPT] [SCRIPT_DIR]"
        return 1
    fi
    
    # Default to monitor.sh if calling script not specified
    calling_script="${calling_script:-monitor.sh}"
    
    echo "🔍 MODULE HELP: $module_name"
    echo "$(echo "MODULE HELP: $module_name" | sed 's/./=/g')"
    echo ""
    
    # Check if module is enabled
    local enabled_file="$script_dir/config/$module_name.enabled"
    if [[ -L "$enabled_file" && -f "$enabled_file" ]]; then
        echo "✅ Status: ENABLED"
    else
        echo "❌ Status: DISABLED"
        echo "   To enable: cd config && ln -sf ../modules/$module_name/config.conf $module_name.enabled"
        echo ""
    fi
    
    # Check if module directory exists
    local module_dir="$script_dir/modules/$module_name"
    if [[ ! -d "$module_dir" ]]; then
        echo "❌ Error: Module directory not found: $module_dir"
        return 1
    fi
    
    # Run module test to check hardware availability
    local test_script="$module_dir/test.sh"
    if [[ -x "$test_script" ]]; then
        echo "🧪 Hardware Check:"
        if "$test_script" >/dev/null 2>&1; then
            echo "   ✅ All dependencies and hardware available"
        else
            echo "   ⚠️  Some dependencies or hardware missing"
            echo "   For details: $test_script"
        fi
    else
        echo "🧪 Hardware Check: No test script available"
    fi
    echo ""
    
    # Show module README first (comprehensive overview)
    local readme_file="$module_dir/README.md"
    if [[ -f "$readme_file" ]]; then
        echo "📖 MODULE DOCUMENTATION:"
        echo "========================================"
        cat "$readme_file"
        echo "========================================"
        echo ""
    else
        echo "📖 Module Documentation: No README.md found"
        echo ""
    fi
    
    # Show help for the specific script that was called
    local target_script="$module_dir/$calling_script"
    local script_type
    case "$calling_script" in
        monitor.sh) script_type="Monitor" ;;
        status.sh) script_type="Status" ;;
        test.sh) script_type="Test" ;;
        *) script_type="Module" ;;
    esac
    
    if [[ -x "$target_script" ]]; then
        echo "📖 $script_type Script Documentation:"
        echo "----------------------------------------"
        if "$target_script" --help 2>/dev/null; then
            echo "----------------------------------------"
        else
            echo "   ⚠️  $script_type help not available or script has issues"
            echo "   Try running: $target_script --help"
        fi
    else
        echo "📖 $script_type Script: Not found or not executable ($target_script)"
        
        # If the requested script doesn't exist, fall back to monitor.sh
        if [[ "$calling_script" != "monitor.sh" ]]; then
            local monitor_script="$module_dir/monitor.sh"
            if [[ -x "$monitor_script" ]]; then
                echo ""
                echo "📖 Monitor Script Documentation (fallback):"
                echo "----------------------------------------"
                if "$monitor_script" --help 2>/dev/null; then
                    echo "----------------------------------------"
                fi
            fi
        fi
    fi
    
    echo ""
    echo "📁 Module Files:"
    echo "   Config: $module_dir/config.conf"
    echo "   Monitor: $module_dir/monitor.sh"
    echo "   Test: $test_script"
    echo "   Status: $module_dir/status.sh"
    if [[ -f "$module_dir/README.md" ]]; then
        echo "   Documentation: $module_dir/README.md"
    fi
    # Check for declared autofixes in global directory
    local declared_autofixes
    if declared_autofixes=$("$module_dir/monitor.sh" --list-autofixes 2>/dev/null); then
        local autofix_count
        autofix_count=$(echo "$declared_autofixes" | grep -c . || echo "0")
        echo "   Declared autofixes: $autofix_count (in global autofix directory)"
    fi
    
    echo ""
    echo "💡 Quick Commands:"
    echo "   Test module: $test_script"
    echo "   Check status: $module_dir/status.sh"
    echo "   Monitor once: $module_dir/monitor.sh --no-auto-fix"
    if [[ -f "$module_dir/README.md" ]]; then
        echo "   Read docs: cat $module_dir/README.md"
    fi
}

# Export functions for modules
export -f log error send_alert should_alert record_alert
export -f get_top_cpu_processes get_top_memory_processes is_system_critical_process
export -f get_cpu_package_temp get_uptime_seconds init_framework validate_module
export -f show_module_help
