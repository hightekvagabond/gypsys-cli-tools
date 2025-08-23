#!/bin/bash
# Status Script - Use the proven check-monitoring-status.sh
exec "$(dirname "$0")/framework/check-monitoring-status.sh" "$@"
