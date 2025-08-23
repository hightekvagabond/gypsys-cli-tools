#!/bin/bash
# Modular Monitor Orchestrator
# Runs individual monitoring modules in a coordinated fashion

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Source common functions
source "$MODULES_DIR/common.sh"

# Override MODULE_NAME for orchestrator logs
MODULE_NAME="orchestrator"

# Available modules
MODULES=(
    "thermal-monitor"
    "usb-monitor" 
    "memory-monitor"
)

show_help() {
    cat << 'EOF'
orchestrator.sh - Modular Monitor Orchestrator

DESCRIPTION:
    Coordinates execution of individual monitoring modules.
    Each module is a focused, single-purpose monitor that can run
    independently or as part of the complete monitoring suite.

USAGE:
    ./orchestrator.sh [OPTIONS] [MODULES...]

OPTIONS:
    --help, -h          Show this help message
    --list              List available modules
    --test MODULE       Test specific module only
    --verbose           Enable verbose logging
    --config FILE       Use specific config file

MODULES:
    thermal-monitor     CPU temperature and thermal protection
    usb-monitor         USB device reset detection and fixes  
    memory-monitor      Memory usage and pressure monitoring

EXAMPLES:
    ./orchestrator.sh                    # Run all modules
    ./orchestrator.sh thermal-monitor    # Run only thermal monitoring
    ./orchestrator.sh --test thermal-monitor  # Test thermal module
    ./orchestrator.sh --list             # Show available modules

SYSTEMD INTEGRATION:
    This orchestrator is designed to run via systemd service:
    
        systemctl start modular-monitor.service
        systemctl enable modular-monitor.service
    
    Check logs with:
        journalctl -t modular-monitor -f

EOF
}

list_modules() {
    echo "Available monitoring modules:"
    for module in "${MODULES[@]}"; do
        local module_file="$MODULES_DIR/${module}.sh"
        if [[ -f "$module_file" ]]; then
            echo "  ✅ $module"
        else
            echo "  ❌ $module (missing)"
        fi
    done
}

run_module() {
    local module_name="$1"
    local module_file="$MODULES_DIR/${module_name}.sh"
    
    if [[ ! -f "$module_file" ]]; then
        error "Module not found: $module_name"
        return 1
    fi
    
    log "Running module: $module_name"
    
    # Run module and capture result
    if bash "$module_file"; then
        log "Module $module_name: OK"
        return 0
    else
        log "Module $module_name: ISSUES DETECTED"
        return 1
    fi
}

run_all_modules() {
    local failed_modules=()
    local total_modules=0
    
    for module in "${MODULES[@]}"; do
        total_modules=$((total_modules + 1))
        if ! run_module "$module"; then
            failed_modules+=("$module")
        fi
    done
    
    # Summary
    local failed_count=${#failed_modules[@]}
    local success_count=$((total_modules - failed_count))
    
    if [[ $failed_count -eq 0 ]]; then
        log "All $total_modules modules completed successfully"
        return 0
    else
        log "Completed: $success_count/$total_modules modules successful"
        log "Failed modules: ${failed_modules[*]}"
        return 1
    fi
}

main() {
    local test_mode=""
    local verbose=false
    local specific_modules=()
    
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
            --config)
                if [[ -n "${2:-}" && -f "$2" ]]; then
                    source "$2"
                    shift 2
                else
                    error "--config requires a valid file"
                    exit 1
                fi
                ;;
            *)
                # Treat as module name
                specific_modules+=("$1")
                shift
                ;;
        esac
    done
    
    log "Modular Monitor Orchestrator starting"
    
    # Test mode
    if [[ -n "$test_mode" ]]; then
        log "Testing module: $test_mode"
        run_module "$test_mode"
        exit $?
    fi
    
    # Specific modules mode
    if [[ ${#specific_modules[@]} -gt 0 ]]; then
        log "Running specific modules: ${specific_modules[*]}"
        local failed=0
        for module in "${specific_modules[@]}"; do
            if ! run_module "$module"; then
                failed=1
            fi
        done
        exit $failed
    fi
    
    # Default: run all modules
    log "Running all monitoring modules"
    run_all_modules
    exit $?
}

main "$@"