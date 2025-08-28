#!/bin/bash
# Modular Monitor Uninstall Script
# Removes systemd services and cleans up the modular monitoring system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="modular-monitor"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}🗑️  MODULAR MONITOR UNINSTALL${NC}"
    echo -e "${BLUE}   Removing monitoring system components${NC}"
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
    
    return 0
}

stop_and_disable_service() {
    print_info "Stopping and disabling monitoring service..."
    
    # Stop the timer if it's running
    if systemctl is-active --quiet "${SERVICE_NAME}.timer" 2>/dev/null; then
        print_status "Stopping ${SERVICE_NAME}.timer..."
        systemctl stop "${SERVICE_NAME}.timer"
    else
        print_info "${SERVICE_NAME}.timer is not running"
    fi
    
    # Stop the service if it's running
    if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
        print_status "Stopping ${SERVICE_NAME}.service..."
        systemctl stop "${SERVICE_NAME}.service"
    else
        print_info "${SERVICE_NAME}.service is not running"
    fi
    
    # Disable the timer if it's enabled
    if systemctl is-enabled --quiet "${SERVICE_NAME}.timer" 2>/dev/null; then
        print_status "Disabling ${SERVICE_NAME}.timer..."
        systemctl disable "${SERVICE_NAME}.timer"
    else
        print_info "${SERVICE_NAME}.timer is not enabled"
    fi
    
    # Disable the service if it's enabled
    if systemctl is-enabled --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
        print_status "Disabling ${SERVICE_NAME}.service..."
        systemctl disable "${SERVICE_NAME}.service"
    else
        print_info "${SERVICE_NAME}.service is not enabled"
    fi
}

remove_systemd_files() {
    print_info "Removing systemd service files..."
    
    # Remove service file
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        print_status "Removed ${SERVICE_NAME}.service"
    else
        print_info "${SERVICE_NAME}.service file not found"
    fi
    
    # Remove timer file
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.timer" ]]; then
        rm -f "/etc/systemd/system/${SERVICE_NAME}.timer"
        print_status "Removed ${SERVICE_NAME}.timer"
    else
        print_info "${SERVICE_NAME}.timer file not found"
    fi
    
    # Reload systemd daemon
    print_status "Reloading systemd daemon..."
    systemctl daemon-reload
}

cleanup_state() {
    print_info "Cleaning up state and configuration..."
    
    # Load system configuration to get state directory
    if [[ -f "$SCRIPT_DIR/config/SYSTEM.conf" ]]; then
        source "$SCRIPT_DIR/config/SYSTEM.conf"
    fi
    
    # Set default state directory if not defined
    STATE_DIR="${STATE_DIR:-/var/tmp/modular-monitor-state}"
    
    # Ask user if they want to remove state directory
    if [[ -d "$STATE_DIR" ]]; then
        echo -e "${YELLOW}State directory found: $STATE_DIR${NC}"
        echo -n "Remove state directory and all monitoring data? [y/N]: "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "$STATE_DIR"
            print_status "Removed state directory: $STATE_DIR"
        else
            print_info "Keeping state directory: $STATE_DIR"
        fi
    else
        print_info "No state directory found at: $STATE_DIR"
    fi
    
    # Ask user if they want to remove enabled module configurations
    if [[ -d "$SCRIPT_DIR/config" ]]; then
        local enabled_modules=$(find "$SCRIPT_DIR/config" -name "*.enabled" 2>/dev/null | wc -l)
        if [[ $enabled_modules -gt 0 ]]; then
            echo -e "${YELLOW}Found $enabled_modules enabled module configuration(s)${NC}"
            echo -n "Remove module enable/disable configurations? [y/N]: "
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                rm -f "$SCRIPT_DIR/config"/*.enabled
                print_status "Removed module configurations"
            else
                print_info "Keeping module configurations"
            fi
        fi
    fi
}

verify_removal() {
    print_info "Verifying service removal..."
    
    local issues_found=false
    
    # Check if services are still running
    if systemctl is-active --quiet "${SERVICE_NAME}.timer" 2>/dev/null; then
        print_error "${SERVICE_NAME}.timer is still running"
        issues_found=true
    fi
    
    if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
        print_error "${SERVICE_NAME}.service is still running"
        issues_found=true
    fi
    
    # Check if service files still exist
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        print_error "Service file still exists: /etc/systemd/system/${SERVICE_NAME}.service"
        issues_found=true
    fi
    
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.timer" ]]; then
        print_error "Timer file still exists: /etc/systemd/system/${SERVICE_NAME}.timer"
        issues_found=true
    fi
    
    if [[ "$issues_found" == "true" ]]; then
        print_error "Some issues found during removal"
        return 1
    else
        print_status "Service successfully removed"
        return 0
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                echo "Modular Monitor Uninstall Script"
                echo ""
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --help, -h       Show this help message"
                echo ""
                echo "This script will:"
                echo "  • Stop and disable the monitoring service"
                echo "  • Remove systemd service files"
                echo "  • Optionally clean up state and configuration files"
                echo ""
                echo "Note: This script must be run with sudo privileges"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Check if we have root privileges
    check_requirements
    
    print_header
    echo ""
    print_info "This will remove the modular monitoring system from your computer."
    echo -n "Are you sure you want to continue? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Uninstall cancelled"
        exit 0
    fi
    
    echo ""
    print_info "Beginning uninstall process..."
    echo ""
    
    # Stop and disable services
    stop_and_disable_service
    echo ""
    
    # Remove systemd files
    remove_systemd_files
    echo ""
    
    # Optional cleanup
    cleanup_state
    echo ""
    
    # Verify removal
    if verify_removal; then
        print_header
        echo -e "${GREEN}🎉 UNINSTALL COMPLETE!${NC}"
        echo ""
        echo -e "${GREEN}The modular monitoring system has been successfully removed.${NC}"
        echo ""
        echo -e "${BLUE}📋 What was removed:${NC}"
        echo -e "  • Systemd service and timer files"
        echo -e "  • Service registrations and enablements"
        echo -e "  • Optionally: state data and module configurations"
        echo ""
        echo -e "${CYAN}The project files in $SCRIPT_DIR remain untouched.${NC}"
        echo -e "${CYAN}You can reinstall anytime by running: sudo ./setup.sh${NC}"
    else
        print_header
        echo -e "${RED}❌ UNINSTALL INCOMPLETE${NC}"
        echo ""
        echo -e "${YELLOW}Some issues were encountered during removal.${NC}"
        echo -e "${YELLOW}You may need to manually clean up remaining components.${NC}"
        exit 1
    fi
}

main "$@"
