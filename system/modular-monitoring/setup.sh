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
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}🛡️  MODULAR MONITOR SETUP & CONFIGURATION${NC}"
    echo -e "${BLUE}   Intelligent system monitoring with autofix${NC}"
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

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

check_requirements() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        return 1
    fi
    
    print_status "Checking system requirements..."
    
    # Check for required commands
    local required_commands=("systemctl" "journalctl" "df" "ps" "sensors")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            print_warning "Optional command '$cmd' not found (some features may be limited)"
        fi
    done
    
    return 0
}

# Phase 1: Pre-flight Module Testing
run_preflight_tests() {
    print_header
    echo -e "${CYAN}🧪 PHASE 1: Pre-flight Module Testing${NC}"
    echo ""
    print_info "Running comprehensive module tests to ensure system readiness..."
    echo ""
    
    # Use the existing robust test script instead of duplicating logic
    if ! "$SCRIPT_DIR/test.sh" 2>/dev/null; then
        echo ""
        print_error "Pre-flight testing failed!"
        print_info "Some modules have validation or functionality issues."
        print_info "Please run './test.sh' for detailed diagnostics."
        return 1
    fi
    
    echo ""
    print_status "All modules passed comprehensive pre-flight testing!"
    echo ""
}

# Phase 2: Hardware Detection & Module Selection
configure_modules() {
    print_header
    echo -e "${CYAN}🔍 PHASE 2: Hardware Detection & Module Configuration${NC}"
    echo ""
    print_info "Detecting available hardware and configuring modules..."
    echo ""
    
    local modules_changed=false
    
    # Check each module for hardware existence and enable/disable status
    for module_dir in "$SCRIPT_DIR/modules"/*; do
        if [[ -d "$module_dir" && -f "$module_dir/exists.sh" ]]; then
            local module_name=$(basename "$module_dir")
            local exists_result
            local is_enabled
            
            # Check if hardware exists
            if exists_result=$("$module_dir/exists.sh" 2>/dev/null); then
                local hardware_exists=true
            else
                local hardware_exists=false
            fi
            
            # Check if module is currently enabled
            if [[ -L "$SCRIPT_DIR/config/$module_name.enabled" ]]; then
                is_enabled=true
            else
                is_enabled=false
            fi
            
            # Handle different scenarios
            if [[ "$hardware_exists" == "true" && "$is_enabled" == "false" ]]; then
                echo -e "📡 Found ${YELLOW}$module_name${NC} hardware"
                echo -n "   Enable $module_name monitoring? [Y/n]: "
                read -r response
                if [[ "$response" =~ ^[Nn]$ ]]; then
                    # User explicitly said No
                    print_status "Skipped $module_name module"
                else
                    # Default Yes (empty response or anything else that's not No)
                    ln -sf "../modules/$module_name/config.conf" "$SCRIPT_DIR/config/$module_name.enabled"
                    print_status "Enabled $module_name module"
                    modules_changed=true
                fi
                
            elif [[ "$hardware_exists" == "false" && "$is_enabled" == "true" ]]; then
                echo -e "❓ ${YELLOW}$module_name${NC} module is enabled but hardware not detected"
                echo "   (This might be an external device that's sometimes connected)"
                echo -n "   Keep $module_name monitoring enabled? [Y/n]: "
                read -r response
                if [[ "$response" =~ ^[Nn]$ ]]; then
                    rm -f "$SCRIPT_DIR/config/$module_name.enabled"
                    print_status "Disabled $module_name module"
                    modules_changed=true
                fi
                
            elif [[ "$hardware_exists" == "true" && "$is_enabled" == "true" ]]; then
                echo -e "✅ ${GREEN}$module_name${NC} hardware detected and monitoring enabled"
                
            elif [[ "$hardware_exists" == "false" && "$is_enabled" == "false" ]]; then
                # Hardware not detected and module not enabled - ask if they want to enable anyway
                local description=""
                if [[ -f "$module_dir/monitor.sh" && -x "$module_dir/monitor.sh" ]]; then
                    # Get description from the module
                    description=$("$module_dir/monitor.sh" --description 2>/dev/null || echo "")
                fi
                
                if [[ -n "$description" ]]; then
                    echo -e "🔍 ${CYAN}$module_name${NC}: $description"
                else
                    echo -e "🔍 ${CYAN}$module_name${NC} monitoring available (hardware not currently detected)"
                fi
                echo -n "   Enable $module_name monitoring anyway? [y/N]: "
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    ln -sf "../modules/$module_name/config.conf" "$SCRIPT_DIR/config/$module_name.enabled"
                    print_status "Enabled $module_name module"
                    modules_changed=true
                else
                    print_status "Skipped $module_name module"
                fi
            fi
        fi
    done
    
    if [[ "$modules_changed" == "true" ]]; then
        echo ""
        print_status "Module configuration updated!"
    fi
    echo ""
}

# Phase 3: Interactive Configuration Review
configure_settings() {
    print_header
    echo -e "${CYAN}⚙️  PHASE 3: Configuration Review${NC}"
    echo ""
    print_info "Review and adjust monitoring settings (press Enter to keep defaults)..."
    echo ""
    
    # Load current configuration
    local config_file="$SCRIPT_DIR/config/thresholds.conf"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    fi
    
    echo -e "${YELLOW}Temperature Monitoring:${NC}"
    echo -n "  Warning temperature (current: ${TEMP_WARNING:-85}°C): "
    read -r new_temp_warning
    if [[ -n "$new_temp_warning" ]]; then
        TEMP_WARNING="$new_temp_warning"
    fi
    
    echo -n "  Critical temperature (current: ${TEMP_CRITICAL:-90}°C): "
    read -r new_temp_critical
    if [[ -n "$new_temp_critical" ]]; then
        TEMP_CRITICAL="$new_temp_critical"
    fi
    
    echo -n "  Emergency temperature (current: ${TEMP_EMERGENCY:-95}°C): "
    read -r new_temp_emergency
    if [[ -n "$new_temp_emergency" ]]; then
        TEMP_EMERGENCY="$new_temp_emergency"
    fi
    
    echo ""
    echo -e "${YELLOW}Memory Monitoring:${NC}"
    echo -n "  Warning threshold (current: ${MEMORY_WARNING:-85}%): "
    read -r new_memory_warning
    if [[ -n "$new_memory_warning" ]]; then
        MEMORY_WARNING="$new_memory_warning"
    fi
    
    echo -n "  Critical threshold (current: ${MEMORY_CRITICAL:-95}%): "
    read -r new_memory_critical
    if [[ -n "$new_memory_critical" ]]; then
        MEMORY_CRITICAL="$new_memory_critical"
    fi
    
    echo ""
    echo -e "${YELLOW}USB Monitoring:${NC}"
    echo -n "  Reset warning threshold (current: ${USB_RESET_WARNING:-10}): "
    read -r new_usb_warning
    if [[ -n "$new_usb_warning" ]]; then
        USB_RESET_WARNING="$new_usb_warning"
    fi
    
    echo -n "  Reset critical threshold (current: ${USB_RESET_CRITICAL:-20}): "
    read -r new_usb_critical
    if [[ -n "$new_usb_critical" ]]; then
        USB_RESET_CRITICAL="$new_usb_critical"
    fi
    
    # Save updated configuration
    cat > "$config_file" << EOF
# Modular Monitor Configuration
# Temperature thresholds (°C)
TEMP_WARNING=${TEMP_WARNING:-85}
TEMP_CRITICAL=${TEMP_CRITICAL:-90}
TEMP_EMERGENCY=${TEMP_EMERGENCY:-95}

# Memory thresholds (%)
MEMORY_WARNING=${MEMORY_WARNING:-85}
MEMORY_CRITICAL=${MEMORY_CRITICAL:-95}

# USB thresholds
USB_RESET_WARNING=${USB_RESET_WARNING:-10}
USB_RESET_CRITICAL=${USB_RESET_CRITICAL:-20}

# Network thresholds  
NETWORK_TIMEOUT=5
NETWORK_RETRY_COUNT=3

# Process management
PROCESS_CPU_THRESHOLD=10  # Minimum CPU % to consider for emergency killing
GRACE_PERIOD_SECONDS=60   # Grace period for new processes

# Alert cooldowns (seconds)
WARNING_COOLDOWN=600      # 10 minutes
CRITICAL_COOLDOWN=180     # 3 minutes
EMERGENCY_COOLDOWN=60     # 1 minute
EOF
    
    print_status "Configuration saved!"
    echo ""
}

install_systemd_service() {
    print_status "Installing systemd service..."
    
    # Stop and disable existing service if running (safe upgrade)
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
    print_status "Enabling and starting monitoring service..."
    
    systemctl enable "${SERVICE_NAME}.timer"
    systemctl start "${SERVICE_NAME}.timer"
    
    # Verify service is running
    if systemctl is-active --quiet "${SERVICE_NAME}.timer"; then
        print_status "Monitoring service is active and running"
    else
        print_error "Failed to start monitoring service"
        return 1
    fi
}

# Phase 4: Installation & Final Status
complete_installation() {
    print_header
    echo -e "${CYAN}🚀 PHASE 4: Installation & Verification${NC}"
    echo ""
    
    print_status "Creating state directories..."
    mkdir -p "$STATE_DIR"
    
    install_systemd_service
    enable_and_start
    
    # Run final comprehensive test
    print_status "Running final verification tests..."
    local final_test_result=0
    
    echo ""
    echo "🧪 Final Module Tests:"
    for module_dir in "$SCRIPT_DIR/modules"/*; do
        if [[ -d "$module_dir" && -f "$module_dir/monitor.sh" ]]; then
            local module_name=$(basename "$module_dir")
            if [[ "$module_name" != "common.sh" && -L "$SCRIPT_DIR/config/$module_name.enabled" ]]; then
                echo -n "  $module_name: "
                if "$SCRIPT_DIR/monitor.sh" --test "$module_name" >/dev/null 2>&1; then
                    echo -e "${GREEN}OK${NC}"
                else
                    echo -e "${RED}FAILED${NC}"
                    final_test_result=1
                fi
            fi
        fi
    done
    
    echo ""
    if [[ $final_test_result -eq 0 ]]; then
        print_status "All enabled modules verified successfully!"
    else
        print_warning "Some modules failed final verification (check logs for details)"
    fi
    
    # Show final status
    print_header
    echo -e "${GREEN}🎉 INSTALLATION COMPLETE!${NC}"
    echo ""
    echo -e "${GREEN}🛡️  Your monitoring system is now protecting your computer!${NC}"
    echo ""
    
    # Show current system status
    echo -e "${BLUE}📊 Current System Status:${NC}"
    echo ""
    "$SCRIPT_DIR/status.sh" | head -20
    echo ""
    
    echo -e "${BLUE}💡 Helpful Information:${NC}"
    echo -e "  📊 Check system status anytime: ${GREEN}./status.sh${NC}"
    echo -e "  📜 View monitoring logs: ${GREEN}journalctl -t modular-monitor -f --no-pager${NC}"
    echo -e "  ⚙️  Reconfigure settings: ${GREEN}sudo ./setup.sh${NC}"
    echo ""
    echo -e "${CYAN}The monitoring system runs automatically every 2 minutes.${NC}"
    echo -e "${CYAN}For headless deployments, notifications can be configured via email/webhook.${NC}"
    echo ""
}

main() {
    # Parse command line arguments
    local reconfigure=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --reconfigure)
                reconfigure=true
                shift
                ;;
            --help|-h)
                echo "Modular Monitor Setup Script"
                echo ""
                echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
                echo "  --reconfigure    Reconfigure existing installation"
                echo "  --help, -h       Show this help message"
            exit 0
            ;;
            *)
                print_error "Unknown option: $1"
                exit 1
            ;;
    esac
    done
    
    check_requirements
    
    if [[ "$reconfigure" == "true" ]]; then
        print_header
        echo -e "${CYAN}🔧 RECONFIGURATION MODE${NC}"
        echo ""
        configure_modules
        configure_settings
        print_status "Reconfiguration complete!"
        echo ""
        echo -e "${GREEN}Run ${CYAN}./status.sh${GREEN} to verify your changes.${NC}"
    else
        run_preflight_tests
        configure_modules  
        configure_settings
        complete_installation
    fi
}

main "$@"