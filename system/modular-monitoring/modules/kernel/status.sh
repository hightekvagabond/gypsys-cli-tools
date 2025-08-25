#!/bin/bash
# Kernel module status script - simplified to use monitor.sh --status

MODULE_NAME="kernel"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments and pass them to monitor.sh
if [[ $# -eq 0 ]]; then
    # Default: use default time range
    "$SCRIPT_DIR/monitor.sh" --status
elif [[ $# -eq 1 ]]; then
    # One argument: start time
    "$SCRIPT_DIR/monitor.sh" --status --start-time "$1"
elif [[ $# -eq 2 ]]; then
    # Two arguments: start and end time
    "$SCRIPT_DIR/monitor.sh" --status --start-time "$1" --end-time "$2"
else
    echo "Usage: $0 [start_time] [end_time]"
    echo "Examples:"
    echo "  $0                           # Default time range"
    echo "  $0 '1 hour ago'              # Last hour"
    echo "  $0 '10:00' '11:00'           # Specific time range"
    echo ""
    echo "This script is a simplified wrapper around monitor.sh --status"
    echo "For more options, use: $SCRIPT_DIR/monitor.sh --help"
    exit 1
fi
