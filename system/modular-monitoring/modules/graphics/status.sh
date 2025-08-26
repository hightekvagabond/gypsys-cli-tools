#!/bin/bash
# Graphics Module Status Script
# Provides detailed status information for graphics hardware monitoring

MODULE_NAME="graphics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common functions
source "$(dirname "$SCRIPT_DIR")/common.sh"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

# Show graphics hardware status
echo "=== GRAPHICS MODULE STATUS ==="
echo "Time range: ${1:-1 hour ago} to ${2:-now}"
echo ""

# Check if graphics hardware exists
if ! "$SCRIPT_DIR/exists.sh" >/dev/null 2>&1; then
    echo "❌ No graphics hardware detected on this system"
    exit 0
fi

echo "✅ Graphics hardware detected"

# Show graphics helpers configuration
echo ""
echo "📋 GRAPHICS HELPERS CONFIGURATION:"
if [[ -n "${GRAPHICS_HELPERS_ENABLED:-}" ]]; then
    echo "  Enabled helpers: ${GRAPHICS_HELPERS_ENABLED}"
else
    echo "  No graphics helpers enabled"
    echo "  Check GRAPHICS_HELPERS_ENABLED in config/SYSTEM.conf"
fi

# Run the monitor in status mode
echo ""
AUTO_FIX_ENABLED=false "$SCRIPT_DIR/monitor.sh" --status

echo ""
echo "✅ Graphics status completed"
