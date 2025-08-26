#!/bin/bash
# =============================================================================
# NETWORK MODULE HARDWARE SCAN SCRIPT
# =============================================================================
#
# PURPOSE:
#   Detect network hardware and generate appropriate configuration for the
#   network monitoring module.
#
# CAPABILITIES:
#   - Network interface detection
#   - Network card identification
#   - Connection type analysis (wired/wireless)
#   - Network configuration discovery
#
# USAGE:
#   ./scan.sh                    # Human-readable scan results
#   ./scan.sh --config          # Machine-readable config format
#   ./scan.sh --help            # Show help information
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="network"

show_help() {
    cat << 'EOF'
NETWORK HARDWARE SCAN SCRIPT

PURPOSE:
    Detect network hardware and generate configuration for the network
    monitoring module.

USAGE:
    ./scan.sh                    # Human-readable scan results
    ./scan.sh --config          # Machine-readable config format for SYSTEM.conf
    ./scan.sh --help            # Show this help information

OUTPUT MODES:
    Default Mode:
        Human-readable hardware detection results with explanations
        
    Config Mode (--config):
        Shell variable assignments suitable for SYSTEM.conf

EXIT CODES:
    0 - Network hardware detected and configuration generated
    1 - No network hardware detected or scan failed
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

detect_network_hardware() {
    local config_mode=false
    if [[ "${1:-}" == "--config" ]]; then
        config_mode=true
    fi
    
    local interface_count=0
    local wired_count=0
    local wireless_count=0
    local active_interfaces=""
    local primary_interface=""
    
    # Get network interfaces (excluding loopback)
    if command -v ip >/dev/null 2>&1; then
        interface_count=$(ip link show 2>/dev/null | grep -c "^[0-9]*:" || echo "0")
        # Exclude loopback
        interface_count=$((interface_count - 1))
        
        # Count wired vs wireless interfaces
        for iface in $(ip link show 2>/dev/null | grep "^[0-9]*:" | grep -v "lo:" | awk -F': ' '{print $2}' | awk '{print $1}'); do
            if [[ -d "/sys/class/net/$iface/wireless" ]] || [[ -L "/sys/class/net/$iface/phy80211" ]]; then
                ((wireless_count++))
            else
                ((wired_count++))
            fi
            
            # Check if interface is up
            if ip link show "$iface" 2>/dev/null | grep -q "state UP"; then
                if [[ -z "$active_interfaces" ]]; then
                    active_interfaces="$iface"
                else
                    active_interfaces="$active_interfaces,$iface"
                fi
            fi
        done
        
        # Get primary interface (default route)
        primary_interface=$(ip route show default 2>/dev/null | head -1 | sed -n 's/.*dev \([^ ]*\).*/\1/p' || echo "")
    fi
    
    if [[ "$config_mode" == "true" ]]; then
        # Machine-readable config format
        if [[ $interface_count -gt 0 ]]; then
            echo "NETWORK_INTERFACE_COUNT=\"$interface_count\""
            echo "NETWORK_WIRED_COUNT=\"$wired_count\""
            echo "NETWORK_WIRELESS_COUNT=\"$wireless_count\""
            if [[ -n "$active_interfaces" ]]; then
                echo "NETWORK_ACTIVE_INTERFACES=\"$active_interfaces\""
            fi
            if [[ -n "$primary_interface" ]]; then
                echo "NETWORK_PRIMARY_INTERFACE=\"$primary_interface\""
            fi
            exit 0
        else
            exit 1
        fi
    else
        # Human-readable format
        if [[ $interface_count -eq 0 ]]; then
            echo "❌ No network hardware detected"
            exit 1
        fi
        
        echo "✅ Network hardware detected:"
        echo ""
        echo "🔧 Hardware Details:"
        echo "  Total interfaces: $interface_count"
        echo "  Wired interfaces: $wired_count"
        echo "  Wireless interfaces: $wireless_count"
        
        if [[ -n "$active_interfaces" ]]; then
            echo "  Active interfaces: $active_interfaces"
        fi
        
        if [[ -n "$primary_interface" ]]; then
            echo "  Primary interface: $primary_interface"
        fi
        
        # Show interface details
        if command -v ip >/dev/null 2>&1; then
            echo ""
            echo "🌐 Interface Status:"
            ip -brief addr show | grep -v "lo " | sed 's/^/  /' || echo "  No interface details available"
        fi
        
        # Show network cards from lspci if available
        if command -v lspci >/dev/null 2>&1; then
            local network_cards
            network_cards=$(lspci | grep -i "network\|ethernet\|wireless" | head -3)
            if [[ -n "$network_cards" ]]; then
                echo ""
                echo "🔌 Network Hardware:"
                echo "$network_cards" | sed 's/^/  /'
            fi
        fi
        
        echo ""
        echo "⚙️  Configuration Recommendations:"
        echo "  NETWORK_INTERFACE_COUNT=\"$interface_count\""
        if [[ -n "$primary_interface" ]]; then
            echo "  NETWORK_PRIMARY_INTERFACE=\"$primary_interface\""
        fi
        
        exit 0
    fi
}

# Execute detection
detect_network_hardware "$@"
