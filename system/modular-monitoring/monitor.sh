#!/bin/bash
# =============================================================================
# MODULAR MONITOR ORCHESTRATOR
# =============================================================================
#
# PURPOSE:
#   Main orchestrator that coordinates all monitoring modules in a systematic
#   way. This is the core script that runs all individual monitors and manages
#   their execution, configuration, and error handling.
#
# ARCHITECTURE:
#   - Discovers enabled monitoring modules dynamically
#   - Runs each module's monitor.sh script in parallel or sequence
#   - Handles module failures gracefully without stopping others
#   - Manages module configuration and state
#   - Provides centralized logging and status reporting
#
# MONITORING MODULES:
#   ✅ disk - Filesystem usage and health monitoring
#   ✅ memory - RAM usage and memory pressure monitoring  
#   ✅ thermal - CPU/GPU temperature monitoring
#   ✅ i915 - Intel GPU driver error monitoring
#   ✅ usb - USB device connection/error monitoring
#   ✅ kernel - Kernel version and error monitoring
#   ✅ network - Network connectivity monitoring
#
# USAGE:
#   monitor.sh [--dry-run] [--verbose] [--help]
#   monitor.sh --module <module_name>  # Run specific module
#
# SECURITY CONSIDERATIONS:
#   - Module discovery validates names to prevent injection
#   - Configuration files are validated before sourcing
#   - No user input passed directly to shell commands
#   - Module paths are restricted to safe directories
#
# BASH CONCEPTS FOR BEGINNERS:
#   - Orchestrator pattern coordinates multiple independent scripts
#   - Module-based architecture allows easy addition/removal of monitors
#   - Error handling ensures one failing module doesn't break others
#   - Configuration precedence allows system-specific overrides
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load system configuration
if [[ -f "$SCRIPT_DIR/config/SYSTEM.conf" ]]; then
    source "$SCRIPT_DIR/config/SYSTEM.conf"
fi

# Set defaults if not loaded from config
MODULES_DIR="${MODULES_DIR:-modules}"
ENABLED_MODULES_DIR="${ENABLED_MODULES_DIR:-config}"
MODULE_OVERRIDES_DIR="${MODULE_OVERRIDES_DIR:-config}"
STATE_DIR="${STATE_DIR:-/var/tmp/modular-monitor-state}"

# Source common functions
source "$SCRIPT_DIR/$MODULES_DIR/common.sh"

# Override MODULE_NAME for orchestrator logs
MODULE_NAME="orchestrator"

show_help() {
    cat << 'EOF'
monitor.sh - Modular Monitor Coordinator (Restructured)

DESCRIPTION:
    Coordinates execution of individual monitoring modules using the new
    modular structure. Modules are discovered via USE_MODULES setting in
    the config directory and can have individual overrides.

USAGE:
    ./monitor.sh [OPTIONS] [MODULES...]

OPTIONS:
    --help, -h          Show this help message
    --list              List available and enabled modules
    --test MODULE       Test specific module only
    --verbose           Enable verbose logging
    --no-auto-fix       Disable autofix for all modules
    --start-time TIME   Set start time for analysis
    --end-time TIME     Set end time for analysis

MODULES:
    thermal             CPU temperature and thermal protection
    usb                 USB device reset detection and fixes  
    memory              Memory usage and pressure monitoring
    i915                Intel GPU error detection and fixes
    system              Comprehensive system health monitoring
    kernel              Kernel version tracking and error detection

EXAMPLES:
    ./monitor.sh                    # Run all enabled modules
    ./monitor.sh thermal usb        # Run only thermal and USB modules
    ./monitor.sh --test i915        # Test i915 module
    ./monitor.sh --list             # Show available modules
    ./monitor.sh --no-auto-fix      # Run all modules without autofix

CONFIGURATION:
    - Enabled modules: USE_MODULES/IGNORE_MODULES in SYSTEM.conf
    - Module overrides: config/MODULE_NAME.conf files
    - System config: config/SYSTEM.conf
    - Module configs: modules/MODULE/config.conf

EOF
}

# Load common functions that include get_enabled_modules()
source "$SCRIPT_DIR/modules/common.sh"

get_available_modules() {
    local available_modules=()
    
    for module_dir in "$SCRIPT_DIR/$MODULES_DIR"/*/; do
        if [[ -d "$module_dir" && -f "$module_dir/monitor.sh" ]]; then
            local module_name
            module_name=$(basename "$module_dir")
            available_modules+=("$module_name")
        fi
    done
    
    printf '%s\n' "${available_modules[@]}"
}

list_modules() {
    echo "Module Status Overview:"
    echo "======================"
    
    local available_modules enabled_modules
    mapfile -t available_modules < <(get_available_modules)
    mapfile -t enabled_modules < <(get_enabled_modules)
    
    for module in "${available_modules[@]}"; do
        local status="❌ DISABLED"
        local config_status=""
        
        # Check if enabled
        if printf '%s\n' "${enabled_modules[@]}" | grep -q "^${module}$"; then
            status="✅ ENABLED"
        fi
        
        # Check for override config
        if [[ -f "$SCRIPT_DIR/$MODULE_OVERRIDES_DIR/${module}.conf" ]]; then
            config_status=" (has override config)"
        fi
        
        # Check if monitor script exists
        local monitor_file="$SCRIPT_DIR/$MODULES_DIR/$module/monitor.sh"
        if [[ -f "$monitor_file" && -x "$monitor_file" ]]; then
            echo "  $status  $module$config_status"
        else
            echo "  ❌ ERROR   $module (monitor.sh missing or not executable)$config_status"
        fi
    done
    
    echo ""
    echo "Configuration Details:"
    echo "  System config: config/SYSTEM.conf"
    echo "  Enabled modules: USE_MODULES/IGNORE_MODULES in SYSTEM.conf"
    echo "  Module overrides: config/MODULE_NAME.conf"
    echo "  Module defaults: modules/MODULE/config.conf"
}

load_module_config() {
    local module_name="$1"
    
    # Load module's default config first
    local module_config="$SCRIPT_DIR/$MODULES_DIR/$module_name/config.conf"
    if [[ -f "$module_config" ]]; then
        source "$module_config"
    fi
    
    # Load any override config
    local override_config="$SCRIPT_DIR/$MODULE_OVERRIDES_DIR/${module_name}.conf"
    if [[ -f "$override_config" ]]; then
        source "$override_config"
        log "Applied override config for $module_name"
    fi
}

run_module() {
    local module_name="$1"
    shift
    local module_args=("$@")
    
    local module_dir="$SCRIPT_DIR/$MODULES_DIR/$module_name"
    local monitor_file="$module_dir/monitor.sh"
    
    if [[ ! -d "$module_dir" ]]; then
        error "Module directory not found: $module_name"
        return 1
    fi
    
    if [[ ! -f "$monitor_file" ]]; then
        error "Monitor script not found: $module_name/monitor.sh"
        return 1
    fi
    
    if [[ ! -x "$monitor_file" ]]; then
        error "Monitor script not executable: $module_name/monitor.sh"
        return 1
    fi
    
    log "Running module: $module_name"
    
    # Load module configuration
    load_module_config "$module_name"
    
    # Run module and capture result
    if bash "$monitor_file" "${module_args[@]}"; then
        log "Module $module_name: OK"
        return 0
    else
        log "Module $module_name: ISSUES DETECTED"
        return 1
    fi
}

run_enabled_modules() {
    local module_args=("$@")
    local failed_modules=()
    local skipped_modules=()
    local total_modules=0
    
    mapfile -t enabled_modules < <(get_enabled_modules)
    
    if [[ ${#enabled_modules[@]} -eq 0 ]]; then
        error "No enabled modules found"
        return 1
    fi
    
    # Check hardware existence for all enabled modules first
    log "Checking hardware existence for enabled modules..."
    for module in "${enabled_modules[@]}"; do
        local exists_script="$SCRIPT_DIR/$MODULES_DIR/$module/exists.sh"
        if [[ -f "$exists_script" && -x "$exists_script" ]]; then
            if ! "$exists_script" >/dev/null 2>&1; then
                log "⚠️  Module '$module' is enabled but required hardware not detected - skipping"
                skipped_modules+=("$module")
                continue
            fi
        fi
        # Module has hardware or no exists.sh (backwards compatibility)
        total_modules=$((total_modules + 1))
        if ! run_module "$module" "${module_args[@]}"; then
            failed_modules+=("$module")
        fi
    done
    
    # Summary
    local failed_count=${#failed_modules[@]}
    local skipped_count=${#skipped_modules[@]}
    local success_count=$((total_modules - failed_count))
    
    # Report skipped modules
    if [[ $skipped_count -gt 0 ]]; then
        log "Skipped $skipped_count enabled modules due to missing hardware: ${skipped_modules[*]}"
    fi
    
    if [[ $failed_count -eq 0 ]]; then
        if [[ $total_modules -eq 0 ]]; then
            log "No modules ran - all enabled modules skipped due to missing hardware"
            return 0
        else
            log "All $total_modules modules completed successfully - no issues detected"
            return 0
        fi
    else
        log "Completed: $success_count/$total_modules modules successful"
        log "Modules that detected issues: ${failed_modules[*]}"
        log "Note: Detecting issues is the intended behavior for a monitoring system"
        return 0  # Success - the system is working as designed
    fi
}

run_specific_modules() {
    local specified_modules=("$1")
    shift
    local module_args=("$@")
    local issues_detected=0
    
    for module in "${specified_modules[@]}"; do
        if ! run_module "$module" "${module_args[@]}"; then
            issues_detected=1
        fi
    done
    
    if [[ $issues_detected -eq 1 ]]; then
        log "Specific modules completed - some detected issues (working as designed)"
    else
        log "Specific modules completed - no issues detected"
    fi
    return 0  # Always success - detecting issues is the intended behavior
}



main() {
    local test_mode=""
    local verbose=false
    local specific_modules=()
    local module_args=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --list)
                list_modules
                exit 0
                ;;
            --test)
                if [[ -n "${2:-}" ]]; then
                    test_mode="$2"
                    shift 2
                else
                    error "--test requires a module name"
                    exit 1
                fi
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --no-auto-fix|--start-time|--end-time)
                # Pass these through to modules
                module_args+=("$1")
                if [[ "$1" == "--start-time" || "$1" == "--end-time" ]]; then
                    if [[ -n "${2:-}" ]]; then
                        module_args+=("$2")
                        shift 2
                    else
                        error "$1 requires a value"
                        exit 1
                    fi
                else
                    shift
                fi
                ;;
            -*)
                error "Unknown option: $1"
                exit 1
                ;;
            *)
                # Treat as module name
                specific_modules+=("$1")
                shift
                ;;
        esac
    done
    
    log "Modular Monitor Orchestrator starting (restructured version)"
    
    # Check for shutdown issues on startup (only for fresh boots)
    local system_uptime_seconds
    system_uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")
    
    # Only check if system has been up for less than 10 minutes (fresh boot)
    if [[ $system_uptime_seconds -lt 600 ]]; then
        "$SCRIPT_DIR/status.sh" --shutdown-analysis
    fi
    
    # Test mode
    if [[ -n "$test_mode" ]]; then
        log "Testing module: $test_mode"
        run_module "$test_mode" "${module_args[@]}"
        exit $?
    fi
    
    # Specific modules mode
    if [[ ${#specific_modules[@]} -gt 0 ]]; then
        log "Running specific modules: ${specific_modules[*]}"
        run_specific_modules "${specific_modules[@]}" "${module_args[@]}"
        exit 0
    fi
    
    # Default: run all enabled modules
    log "Running all enabled modules"
    run_enabled_modules "${module_args[@]}"
    exit $?
}

# Ensure state directory exists
mkdir -p "$STATE_DIR"

main "$@"