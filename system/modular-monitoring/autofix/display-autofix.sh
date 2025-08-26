#!/bin/bash
# =============================================================================
# DISPLAY AUTOFIX SCRIPT WITH HELPER ARCHITECTURE
# =============================================================================
#
# PURPOSE:
#   Main display autofix orchestrator that routes to display system-specific helpers.
#   This script detects the display server/compositor and calls the appropriate helper
#   script to handle display-related issues and compositor crashes.
#
# HELPER ARCHITECTURE:
#   This script uses the autofix helper pattern:
#   - display-autofix_helpers/wayland.sh    - Wayland display server autofix (TESTED for KDE)
#   - display-autofix_helpers/x11.sh        - X11 display server autofix (STUB)
#   - display-autofix_helpers/kwin.sh       - KDE KWin compositor autofix (TESTED)
#   - display-autofix_helpers/gnome.sh      - GNOME Shell compositor autofix (STUB)
#
#   Helpers are selected based on DISPLAY_SERVER and DISPLAY_COMPOSITOR in config/SYSTEM.conf
#
# AUTOFIX CAPABILITIES:
#   - Compositor crashes and hangs
#   - Display server connectivity issues
#   - Window manager freezes
#   - Multi-monitor configuration problems
#   - Frame timing and rendering issues
#
# USAGE:
#   display-autofix.sh <calling_module> <grace_period> [issue_type] [severity]
#
# EXAMPLES:
#   display-autofix.sh display 300 compositor_crash critical
#   display-autofix.sh graphics 180 frame_timing warning
#
# SECURITY CONSIDERATIONS:
#   - Helper validation prevents arbitrary script execution
#   - Display system detection prevents wrong autofix application
#   - All actions logged for security audit
#   - Grace period prevents DoS through repeated calls
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize autofix script with common setup
init_autofix_script "$@"

# Additional arguments specific to this script
ISSUE_TYPE="${3:-display_error}"
SEVERITY="${4:-unknown}"

# Load system configuration to determine display setup
DISPLAY_SERVER="${DISPLAY_SERVER:-auto}"
DISPLAY_COMPOSITOR="${DISPLAY_COMPOSITOR:-auto}"

# =============================================================================
# show_help() - Display usage information
# =============================================================================
show_help() {
    cat << 'EOF'
DISPLAY AUTOFIX SCRIPT

PURPOSE:
    Routes display autofix actions to appropriate display system-specific helpers.
    Automatically detects display server and compositor for correct fixes.

USAGE:
    display-autofix.sh <calling_module> <grace_period> [issue_type] [severity]

ARGUMENTS:
    calling_module   - Name of module requesting autofix (e.g., "display")
    grace_period     - Seconds to wait before allowing autofix again
    issue_type       - Type of display issue (compositor_crash, frame_timing, etc.)
    severity         - Issue severity (warning, critical, emergency)

EXAMPLES:
    # Compositor crash detected by display module
    display-autofix.sh display 300 compositor_crash critical

    # Frame timing issues detected
    display-autofix.sh display 180 frame_timing warning

SUPPORTED DISPLAY SYSTEMS:
    ✅ Wayland/KDE    - Tested and supported
    ⚠️  X11           - Stub implementation, needs testing
    ⚠️  GNOME Shell  - Stub implementation, needs testing

HELPER SCRIPTS:
    display-autofix_helpers/wayland.sh    - Wayland display server autofix
    display-autofix_helpers/x11.sh        - X11 display server autofix (STUB)
    display-autofix_helpers/kwin.sh       - KDE KWin compositor autofix  
    display-autofix_helpers/gnome.sh      - GNOME Shell compositor autofix (STUB)

CONFIGURATION:
    Set display system in config/SYSTEM.conf:
    DISPLAY_SERVER="wayland"        # or "x11"
    DISPLAY_COMPOSITOR="kwin"       # or "gnome", "sway", etc.

EXIT CODES:
    0 - Autofix completed successfully
    1 - Error occurred (check logs)
    2 - Skipped due to grace period
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

# =============================================================================
# detect_display_system() - Auto-detect display server and compositor
# =============================================================================
detect_display_system() {
    local detected_server="unknown"
    local detected_compositor="unknown"
    
    # Detect display server
    if [[ -n "${WAYLAND_DISPLAY:-}" ]] || pgrep -f "wayland" >/dev/null; then
        detected_server="wayland"
    elif [[ -n "${DISPLAY:-}" ]] || pgrep -f "Xorg\|X11" >/dev/null; then
        detected_server="x11"
    fi
    
    # Detect compositor (only check if we have Wayland)
    if [[ "$detected_server" == "wayland" ]]; then
        if pgrep -f "kwin_wayland" >/dev/null; then
            detected_compositor="kwin"
        elif pgrep -f "gnome-shell" >/dev/null; then
            detected_compositor="gnome"
        elif pgrep -f "sway" >/dev/null; then
            detected_compositor="sway"
        fi
    fi
    
    autofix_log "DEBUG" "Auto-detected display: server=$detected_server, compositor=$detected_compositor"
    echo "$detected_server|$detected_compositor"
}

# =============================================================================
# perform_display_autofix() - Main autofix function with helper routing
# =============================================================================
perform_display_autofix() {
    local issue_type="$1"
    local severity="$2"
    local display_server="$DISPLAY_SERVER"
    local display_compositor="$DISPLAY_COMPOSITOR"
    
    autofix_log "INFO" "Display autofix requested: $issue_type ($severity)"
    
    # Auto-detect display system if not configured
    if [[ "$display_server" == "auto" || -z "$display_server" ]]; then
        local detection_result
        detection_result=$(detect_display_system)
        display_server="${detection_result%%|*}"
        display_compositor="${detection_result#*|}"
        autofix_log "INFO" "Auto-detected display system: $display_server/$display_compositor"
    fi
    
    # Validate we have a supported display system
    if [[ "$display_server" == "unknown" ]]; then
        autofix_log "ERROR" "Unable to detect display server - no autofix available"
        return 1
    fi
    
    # Try compositor-specific helper first (more specific)
    if [[ "$display_compositor" != "unknown" && -n "$display_compositor" ]]; then
        local compositor_helper="$SCRIPT_DIR/display-autofix_helpers/${display_compositor}.sh"
        if [[ -x "$compositor_helper" ]]; then
            autofix_log "INFO" "Using compositor-specific helper: $display_compositor"
            if "$compositor_helper" "$CALLING_MODULE" "$GRACE_PERIOD" "$issue_type" "$severity"; then
                autofix_log "INFO" "Compositor autofix completed successfully: $display_compositor"
                return 0
            else
                autofix_log "WARN" "Compositor autofix failed, trying display server helper"
            fi
        fi
    fi
    
    # Fall back to display server helper
    local server_helper="$SCRIPT_DIR/display-autofix_helpers/${display_server}.sh"
    if [[ -x "$server_helper" ]]; then
        autofix_log "INFO" "Using display server helper: $display_server"
        if "$server_helper" "$CALLING_MODULE" "$GRACE_PERIOD" "$issue_type" "$severity"; then
            autofix_log "INFO" "Display server autofix completed successfully: $display_server"
            return 0
        else
            autofix_log "ERROR" "Display server autofix failed: $display_server"
            return 1
        fi
    else
        autofix_log "ERROR" "No display autofix helper available for: $display_server"
        return 1
    fi
}

# Execute with grace period management
autofix_log "INFO" "Display autofix requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "display-autofix" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_display_autofix" "$ISSUE_TYPE" "$SEVERITY"
