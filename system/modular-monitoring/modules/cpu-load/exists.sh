#!/bin/bash
# Hardware existence check for cpu-load monitoring module

MODULE_NAME="cpu-load"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

check_hardware() {
    # TODO: Add specific hardware checks for cpu-load module
    # For now, assume hardware exists
    return 0
}

# When run directly, check hardware and exit with appropriate code
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if check_hardware; then
        echo "✅ cpu-load monitoring hardware detected"
        exit 0
    else
        echo "❌ No cpu-load monitoring hardware found"
        exit 1
    fi
fi
