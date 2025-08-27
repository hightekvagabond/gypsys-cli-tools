#!/bin/bash
# Graphics Module Status Script
# Provides detailed status information for graphics hardware monitoring

MODULE_NAME="graphics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common functions
source "$(dirname "$SCRIPT_DIR")/common.sh"

show_help() {
    cat << 'EOF'
GRAPHICS MODULE STATUS SCRIPT

PURPOSE:
    Provides detailed status information for graphics hardware monitoring.

USAGE:
    ./status.sh                    # Show status for last hour
    ./status.sh [start_time]       # Show status from start_time to now
    ./status.sh [start] [end]      # Show status for specific time range
    ./status.sh --help             # Show this help information

EXAMPLES:
    ./status.sh                    # Last hour
    ./status.sh "2 hours ago"      # Last 2 hours
    ./status.sh "10:00" "11:00"   # Specific time range

TIME FORMATS:
    • "1 hour ago", "2 days ago"
    • "10:00", "14:30"
    • "yesterday", "today"
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

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
