#!/bin/bash
# Modular Monitor Installer
# Creates systemd service that runs orchestrator.sh to call all monitoring modules

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="modular-monitor"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}🛡️  MODULAR MONITOR INSTALLER${NC}"
    echo -e "${BLUE}   (systemd service → orchestrator → modules)${NC}"
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
    
    print_status "Requirements check complete"
    return 0
}

install_systemd_service() {
    print_status "Creating systemd service..."
    
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
    print_status "Systemd service and timer created from templates"
}

enable_and_start() {
    systemctl enable "${SERVICE_NAME}.timer"
    systemctl start "${SERVICE_NAME}.timer"
    print_status "Service enabled and started"
}

create_state_directories() {
    mkdir -p "/var/tmp/modular-monitor-state"
    chmod 755 "/var/tmp/modular-monitor-state"
    print_status "State directories created"
}

main() {
    case "${1:-}" in
        -h|--help)
            echo "Usage: $0 [--uninstall]"
            exit 0
            ;;
        --uninstall)
            systemctl stop "${SERVICE_NAME}.timer" 2>/dev/null || true
            systemctl disable "${SERVICE_NAME}.timer" 2>/dev/null || true
            rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
            rm -f "/etc/systemd/system/${SERVICE_NAME}.timer"
            systemctl daemon-reload
            rm -rf "/var/tmp/modular-monitor-state"
            print_status "Uninstall complete"
            exit 0
            ;;
    esac
    
    print_header
    check_requirements
    create_state_directories
    install_systemd_service
    enable_and_start
    
    echo -e "\n${GREEN}🎉 INSTALLATION COMPLETE!${NC}"
    echo "Monitor logs: journalctl -t modular-monitor -f"
}

main "$@"