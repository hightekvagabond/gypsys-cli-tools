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

# When run directly, check hardware and exit with appropriate code
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if check_hardware; then
        echo "✅ Quantum flux capacitor detected (this should never happen!)"
        exit 0
    else
        echo "❌ Quantum flux capacitor not found (expected)"
        exit 1
    fi
fi
