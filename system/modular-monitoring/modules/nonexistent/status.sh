#!/bin/bash
# Module status script - simplified to use monitor.sh --status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Call the monitor script in status mode
"$SCRIPT_DIR/monitor.sh" --status --start-time "$1" --end-time "$2"

