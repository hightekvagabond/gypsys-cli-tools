#!/bin/bash
# =============================================================================
# NONEXISTENT MODULE HARDWARE SCAN SCRIPT
# =============================================================================
#
# PURPOSE:
#   This is a test module that always fails hardware detection.
#   Used for testing module framework behavior with missing hardware.
#
# CAPABILITIES:
#   - Always reports no hardware found (by design)
#   - Tests error handling in scan system
#   - Validates module framework robustness
#
# USAGE:
#   ./scan.sh                    # Human-readable scan results (always fails)
#   ./scan.sh --config          # Machine-readable config format (always fails)
#   ./scan.sh --help            # Show help information
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="nonexistent"

show_help() {
    cat << 'EOF'
NONEXISTENT HARDWARE SCAN SCRIPT

PURPOSE:
    This is a test module that always fails hardware detection.
    Used for testing module framework behavior with missing hardware.

USAGE:
    ./scan.sh                    # Human-readable scan results (always fails)
    ./scan.sh --config          # Machine-readable config format (always fails)
    ./scan.sh --help            # Show this help information

OUTPUT MODES:
    Default Mode:
        Human-readable hardware detection results (always reports failure)
        
    Config Mode (--config):
        Always exits with code 1 (no configuration generated)

EXIT CODES:
    1 - Always fails (by design - this module tests missing hardware)
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

detect_nonexistent_hardware() {
    local config_mode=false
    if [[ "${1:-}" == "--config" ]]; then
        config_mode=true
    fi
    
    if [[ "$config_mode" == "true" ]]; then
        # Machine-readable config format - always fail
        exit 1
    else
        # Human-readable format - always fail
        echo "❌ No nonexistent hardware detected (as expected)"
        echo ""
        echo "This is a test module designed to always fail hardware detection."
        echo "It's used to test the monitoring framework's behavior when"
        echo "required hardware is not present on the system."
        echo ""
        echo "Expected behavior:"
        echo "  • Module should be skipped during monitoring"
        echo "  • Tests should handle missing hardware gracefully"
        echo "  • Framework should continue with other modules"
        
        exit 1
    fi
}

# Execute detection
detect_nonexistent_hardware "$@"
