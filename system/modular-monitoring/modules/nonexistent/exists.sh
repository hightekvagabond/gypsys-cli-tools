#!/bin/bash
# Hardware existence check for nonexistent module (always fails by design)

MODULE_NAME="nonexistent"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

check_hardware() {
    # This should always fail - testing for non-existent quantum flux capacitor
    return 1
}

show_help() {
    cat << 'EOF'
NONEXISTENT MODULE HARDWARE EXISTENCE CHECK

PURPOSE:
    This is a TEST MODULE that always reports missing hardware.
    Used for testing the monitoring framework.

USAGE:
    ./exists.sh                    # Check hardware and exit with status code
    ./exists.sh --help            # Show this help information

EXIT CODES:
    0 - Test module hardware detected (always fails in practice)
    1 - No test module hardware found (expected behavior)

NOTE:
    This module is designed for testing purposes only.
    It will always report that hardware is missing.
EOF
}

# When run directly, check hardware and exit with appropriate code
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check for help request
    if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
        show_help
        exit 0
    fi
    
    if check_hardware; then
        echo "✅ Quantum flux capacitor detected (this should never happen!)"
        exit 0
    else
        echo "❌ Quantum flux capacitor not found (expected)"
        exit 1
    fi
fi
