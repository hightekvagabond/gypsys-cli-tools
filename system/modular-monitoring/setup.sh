#!/bin/bash
# Modular Monitor Setup & Configuration Script
# Installs systemd services and configures the modular monitoring system
# Also acts as a reconfiguration tool for existing installations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="modular-monitor"

# Load system configuration
if [[ -f "$SCRIPT_DIR/config/SYSTEM.conf" ]]; then
    source "$SCRIPT_DIR/config/SYSTEM.conf"
fi

# Set defaults
STATE_DIR="${STATE_DIR:-/var/tmp/modular-monitor-state}"
MODULES_DIR="${MODULES_DIR:-modules}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}🛡️  MODULAR MONITOR INSTALLER (Restructured)${NC}"
    echo -e "${BLUE}   New modular architecture with individual configs${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_requirements() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        return 1
    fi
    
    # Check if restructured modules exist
    if [[ ! -d "$SCRIPT_DIR/$MODULES_DIR" ]]; then
        print_error "Modules directory not found: $MODULES_DIR"
        return 1
    fi
    
    # Check for essential scripts
    if [[ ! -f "$SCRIPT_DIR/monitor.sh" ]]; then
        print_error "Monitor script not found"
        return 1
    fi
    
    print_status "Requirements check complete"
    return 0
}

detect_hardware() {
    print_status "Detecting hardware configuration..."
    
    local hardware_type="generic"
    local cpu_vendor=""
    local gpu_vendor=""
    
    # Detect CPU vendor
    if grep -q "Intel" /proc/cpuinfo 2>/dev/null; then
        cpu_vendor="intel"
    elif grep -q "AMD" /proc/cpuinfo 2>/dev/null; then
        cpu_vendor="amd"
    fi
    
    # Detect GPU vendor
    if lspci 2>/dev/null | grep -q -i "intel.*graphics\|i915"; then
        gpu_vendor="intel"
    elif lspci 2>/dev/null | grep -q -i "nvidia"; then
        gpu_vendor="nvidia" 
    elif lspci 2>/dev/null | grep -q -i "amd.*radeon\|amd.*graphics"; then
        gpu_vendor="amd"
    fi
    
    # Detect specific hardware
    if dmidecode -s system-product-name 2>/dev/null | grep -q -i "predator"; then
        hardware_type="predator"
        print_status "Detected Acer Predator hardware"
    fi
    
    # Update SYSTEM.conf with detected hardware
    sed -i "s/HARDWARE_TYPE=\"\"/HARDWARE_TYPE=\"$hardware_type\"/" "$SCRIPT_DIR/config/SYSTEM.conf" 2>/dev/null || true
    sed -i "s/CPU_VENDOR=\"\"/CPU_VENDOR=\"$cpu_vendor\"/" "$SCRIPT_DIR/config/SYSTEM.conf" 2>/dev/null || true
    sed -i "s/GPU_VENDOR=\"\"/GPU_VENDOR=\"$gpu_vendor\"/" "$SCRIPT_DIR/config/SYSTEM.conf" 2>/dev/null || true
    
    print_status "Hardware detection: $hardware_type, CPU: $cpu_vendor, GPU: $gpu_vendor"
}

test_enabled_modules() {
    print_status "Testing enabled modules..."
    
    local modules_tested=0
    local modules_passed=0
    local modules_failed=0
    local failed_modules=()
    
    for enabled_file in "$SCRIPT_DIR/config"/*.enabled; do
        if [[ -L "$enabled_file" && -f "$enabled_file" ]]; then
            local module_name
            module_name=$(basename "$enabled_file" .enabled)
            local test_script="$SCRIPT_DIR/$MODULES_DIR/$module_name/test.sh"
            
            if [[ -x "$test_script" ]]; then
                print_status "Testing $module_name module..."
                modules_tested=$((modules_tested + 1))
                
                if "$test_script" >/dev/null 2>&1; then
                    print_status "$module_name: All tests passed ✅"
                    modules_passed=$((modules_passed + 1))
                else
                    print_warning "$module_name: Some tests failed ⚠️"
                    modules_failed=$((modules_failed + 1))
                    failed_modules+=("$module_name")
                fi
            else
                print_status "$module_name: No test script found (skipping)"
            fi
        fi
    done
    
    print_status "Module testing complete: $modules_passed passed, $modules_failed failed, $modules_tested total"
    
    if [[ $modules_failed -gt 0 ]]; then
        print_warning "Some modules failed tests. For details, run:"
        for module in "${failed_modules[@]}"; do
            echo "  ./modules/$module/test.sh"
        done
        echo ""
        print_warning "Modules may still function with reduced capabilities."
    fi
}

find_run_on_install_modules() {
    print_status "Checking for modules that need initial setup..."
    
    local run_on_install_modules=()
    local warned_modules=()
    
    # Check each enabled module for RUN_ON_INSTALL flag
    for enabled_file in "$SCRIPT_DIR/config"/*.enabled; do
        if [[ -L "$enabled_file" && -f "$enabled_file" ]]; then
            local module_name
            module_name=$(basename "$enabled_file" .enabled)
            
            # Source the module config to check RUN_ON_INSTALL
            local module_config="$SCRIPT_DIR/$MODULES_DIR/$module_name/config.conf"
            if [[ -f "$module_config" ]]; then
                # Extract RUN_ON_INSTALL setting
                local run_on_install
                run_on_install=$(grep "^RUN_ON_INSTALL=" "$module_config" | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "false")
                
                if [[ "$run_on_install" == "true" ]]; then
                    run_on_install_modules+=("$module_name")
                    
                    # Check for warning message
                    local warning_msg
                    warning_msg=$(grep "^RUN_ON_INSTALL_WARNING=" "$module_config" | cut -d= -f2- | tr -d '"' 2>/dev/null || echo "")
                    if [[ -n "$warning_msg" ]]; then
                        warned_modules+=("$module_name: $warning_msg")
                    fi
                fi
            fi
        fi
    done
    
    if [[ ${#run_on_install_modules[@]} -gt 0 ]]; then
        print_warning "Found ${#run_on_install_modules[@]} modules requiring initial setup: ${run_on_install_modules[*]}"
        
        # Show warnings
        for warning in "${warned_modules[@]}"; do
            print_warning "$warning"
        done
        
        # Update SYSTEM.conf
        sed -i "s/RUN_ON_INSTALL_MODULES_DETECTED=false/RUN_ON_INSTALL_MODULES_DETECTED=true/" "$SCRIPT_DIR/config/SYSTEM.conf" 2>/dev/null || true
        
        echo "${run_on_install_modules[@]}"
    else
        print_status "No modules require initial setup"
        echo ""
    fi
}

run_initial_setup_modules() {
    local modules_to_run=("$@")
    
    if [[ ${#modules_to_run[@]} -eq 0 ]]; then
        return 0
    fi
    
    print_status "Running initial setup for modules: ${modules_to_run[*]}"
    print_warning "This may take a while for some modules..."
    
    for module in "${modules_to_run[@]}"; do
        print_status "Running initial setup for $module module..."
        
        # Run the module once to establish baselines
        if bash "$SCRIPT_DIR/monitor.sh" --test "$module" >/dev/null 2>&1; then
            print_status "$module initial setup completed successfully"
        else
            print_warning "$module initial setup completed with issues (this may be normal)"
        fi
    done
    
    print_status "All initial setup modules completed"
}

install_systemd_service() {
    print_status "Installing systemd service..."
    
    # Stop and disable existing service if running (safe upgrade) [[memory:7056079]]
    if systemctl is-active --quiet "${SERVICE_NAME}.timer" 2>/dev/null; then
        print_status "Stopping existing ${SERVICE_NAME} service for upgrade..."
        systemctl stop "${SERVICE_NAME}.timer" 2>/dev/null || true
    fi
    
    # Check if template files exist
    if [[ ! -f "$SCRIPT_DIR/systemd/${SERVICE_NAME}.service" ]]; then
        print_error "Template file missing: systemd/${SERVICE_NAME}.service"
        return 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/systemd/${SERVICE_NAME}.timer" ]]; then
        print_error "Template file missing: systemd/${SERVICE_NAME}.timer"
        return 1
    fi
    
    # Check for existing service files to prevent duplicates [[memory:7056079]]
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        print_status "Updating existing systemd service..."
    else
        print_status "Creating new systemd service..."
    fi
    
    # Install service file (substitute script directory path)
    sed "s|__SCRIPT_DIR__|$SCRIPT_DIR|g" \
        "$SCRIPT_DIR/systemd/${SERVICE_NAME}.service" \
        > "/etc/systemd/system/${SERVICE_NAME}.service"
    
    # Install timer file (no substitutions needed)
    cp "$SCRIPT_DIR/systemd/${SERVICE_NAME}.timer" \
       "/etc/systemd/system/${SERVICE_NAME}.timer"

    systemctl daemon-reload
    print_status "Systemd service and timer installed"
}

enable_and_start() {
    # Check if already enabled to prevent duplicate entries [[memory:7056079]]
    if systemctl is-enabled "${SERVICE_NAME}.timer" >/dev/null 2>&1; then
        print_status "Service already enabled, restarting..."
    else
        print_status "Enabling service..."
        systemctl enable "${SERVICE_NAME}.timer"
    fi
    
    systemctl start "${SERVICE_NAME}.timer"
    print_status "Service started successfully"
}

create_state_directories() {
    mkdir -p "$STATE_DIR"
    chmod 755 "$STATE_DIR"
    
    # Create module-specific state directories
    for module_dir in "$SCRIPT_DIR/$MODULES_DIR"/*/; do
        if [[ -d "$module_dir" ]]; then
            local module_name
            module_name=$(basename "$module_dir")
            mkdir -p "$STATE_DIR/$module_name"
            chmod 755 "$STATE_DIR/$module_name"
        fi
    done
    
    print_status "State directories created: $STATE_DIR"
}

validate_module_structure() {
    print_status "Validating modular structure..."
    
    local validation_errors=0
    
    # Check for enabled modules
    local enabled_count
    enabled_count=$(find "$SCRIPT_DIR/config" -name "*.enabled" -type l | wc -l)
    if [[ $enabled_count -eq 0 ]]; then
        print_error "No enabled modules found (no *.enabled symlinks in config/)"
        validation_errors=$((validation_errors + 1))
    else
        print_status "Found $enabled_count enabled modules"
    fi
    
    # Validate each enabled module
    for enabled_file in "$SCRIPT_DIR/config"/*.enabled; do
        if [[ -L "$enabled_file" && -f "$enabled_file" ]]; then
            local module_name
            module_name=$(basename "$enabled_file" .enabled)
            
            # Check module structure
            local module_dir="$SCRIPT_DIR/$MODULES_DIR/$module_name"
            if [[ ! -d "$module_dir" ]]; then
                print_error "Module directory missing: $module_name"
                validation_errors=$((validation_errors + 1))
                continue
            fi
            
            if [[ ! -f "$module_dir/monitor.sh" ]]; then
                print_error "Module monitor script missing: $module_name/monitor.sh"
                validation_errors=$((validation_errors + 1))
            fi
            
            if [[ ! -x "$module_dir/monitor.sh" ]]; then
                print_error "Module monitor script not executable: $module_name/monitor.sh"
                validation_errors=$((validation_errors + 1))
            fi
            
            if [[ ! -f "$module_dir/config.conf" ]]; then
                print_warning "Module config missing: $module_name/config.conf (will use defaults)"
            fi
        fi
    done
    
    if [[ $validation_errors -eq 0 ]]; then
        print_status "Module structure validation passed"
        return 0
    else
        print_error "Module structure validation failed with $validation_errors errors"
        return 1
    fi
}

update_first_run_flag() {
    # Mark that first run after install is complete
    sed -i "s/FIRST_RUN_AFTER_INSTALL=true/FIRST_RUN_AFTER_INSTALL=false/" "$SCRIPT_DIR/config/SYSTEM.conf" 2>/dev/null || true
    print_status "Installation flags updated"
}

main() {
    case "${1:-}" in
        -h|--help)
            echo "Usage: $0 [--uninstall|--validate]"
            echo ""
            echo "Options:"
            echo "  --uninstall    Remove the monitoring service"
            echo "  --validate     Validate installation without installing"
            echo ""
            echo "The installer will:"
            echo "  1. Detect hardware configuration"
            echo "  2. Validate modular structure"
            echo "  3. Install systemd service"
            echo "  4. Run initial setup for modules that require it"
            echo "  5. Start monitoring service"
            exit 0
            ;;
        --uninstall)
            print_header
            systemctl stop "${SERVICE_NAME}.timer" 2>/dev/null || true
            systemctl disable "${SERVICE_NAME}.timer" 2>/dev/null || true
            rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
            rm -f "/etc/systemd/system/${SERVICE_NAME}.timer"
            systemctl daemon-reload
            rm -rf "$STATE_DIR"
            print_status "Uninstall complete"
            exit 0
            ;;
        --validate)
            print_header
            check_requirements
            detect_hardware
            validate_module_structure
            print_status "Validation complete - system ready for installation"
            exit 0
            ;;
    esac
    
    print_header
    check_requirements
    detect_hardware
    validate_module_structure
    create_state_directories
    test_enabled_modules
    
    # Find modules that need initial setup
    local run_on_install_modules
    mapfile -t run_on_install_modules < <(find_run_on_install_modules)
    
    install_systemd_service
    enable_and_start
    
    # Run initial setup modules
    if [[ ${#run_on_install_modules[@]} -gt 0 ]]; then
        run_initial_setup_modules "${run_on_install_modules[@]}"
    fi
    
    update_first_run_flag
    
    echo -e "\n${GREEN}🎉 INSTALLATION COMPLETE!${NC}"
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo "  Check status: ./status.sh"
    echo "  Monitor logs: journalctl -t modular-monitor -f --no-pager"
    echo "  List modules: ./monitor.sh --list"
    echo "  Test module: ./monitor.sh --test MODULE_NAME"
    echo ""
    echo -e "${BLUE}Module Configuration:${NC}"
    echo "  Enabled modules: config/*.enabled symlinks"
    echo "  Override configs: config/MODULE_NAME.conf"
    echo "  Module defaults: modules/MODULE/config.conf"
    echo "  System config: config/SYSTEM.conf"
}

main "$@"