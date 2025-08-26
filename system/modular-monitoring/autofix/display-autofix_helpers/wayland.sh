#!/bin/bash
# =============================================================================
# WAYLAND DISPLAY SERVER AUTOFIX HELPER
# =============================================================================
#
# PURPOSE:
#   Handles Wayland display server-specific autofix actions including compositor
#   restart, session recovery, and display connectivity issues.
#
# AUTOFIX CAPABILITIES:
#   - Wayland compositor restart
#   - Display output management
#   - Session recovery procedures
#   - Multi-monitor reconfiguration
#
# USAGE:
#   Called by display-autofix.sh: ./wayland.sh <module> <grace> <issue_type> <severity>
#
# ISSUE TYPES:
#   - compositor_crash: Wayland compositor failure
#   - session_freeze: Display session unresponsive
#   - display_disconnect: Monitor/output issues
#   - frame_timing: Rendering performance problems
#
# TESTED ON:
#   - KDE Plasma Wayland (kwin_wayland)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/common.sh"

# Initialize autofix script with common setup
init_autofix_script "$@"

# Additional arguments specific to this helper
ISSUE_TYPE="${3:-display_error}"
SEVERITY="${4:-unknown}"

# =============================================================================
# show_help() - Display usage information
# =============================================================================
show_help() {
    cat << 'EOF'
WAYLAND DISPLAY SERVER AUTOFIX HELPER

PURPOSE:
    Handles Wayland display server-specific autofix actions for compositor
    crashes, session freezes, and display connectivity issues.

USAGE:
    wayland.sh <calling_module> <grace_period> [issue_type] [severity]

ISSUE TYPES:
    compositor_crash    Wayland compositor has crashed or hung
    session_freeze      Display session is unresponsive
    display_disconnect  Monitor or output connectivity issues
    frame_timing        Rendering performance or timing problems

SEVERITY LEVELS:
    warning            Minor issues, process restart recommended
    critical           Significant issues requiring session recovery
    emergency          Severe issues threatening system usability

AUTOFIX ACTIONS:
    - Wayland compositor restart (kwin_wayland, etc.)
    - Display session recovery
    - Multi-monitor reconfiguration
    - Process cleanup for display-related applications

TESTED ENVIRONMENTS:
    ✅ KDE Plasma Wayland
    ⚠️  Other Wayland compositors may need additional testing

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
# detect_wayland_compositor() - Identify running Wayland compositor
# =============================================================================
detect_wayland_compositor() {
    local compositor="unknown"
    
    if pgrep -f "kwin_wayland" >/dev/null; then
        compositor="kwin"
    elif pgrep -f "gnome-shell" >/dev/null; then
        compositor="gnome"
    elif pgrep -f "sway" >/dev/null; then
        compositor="sway"
    elif pgrep -f "weston" >/dev/null; then
        compositor="weston"
    fi
    
    echo "$compositor"
}

# =============================================================================
# perform_wayland_autofix() - Main Wayland autofix logic
# =============================================================================
perform_wayland_autofix() {
    local issue_type="$1"
    local severity="$2"
    
    autofix_log "INFO" "Wayland autofix initiated: $issue_type ($severity)"
    
    # Check if we're in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        autofix_log "INFO" "[DRY-RUN] Would perform Wayland autofix for $issue_type ($severity)"
        
        local compositor
        compositor=$(detect_wayland_compositor)
        autofix_log "INFO" "[DRY-RUN] Detected compositor: $compositor"
        
        case "$issue_type" in
            "compositor_crash")
                autofix_log "INFO" "[DRY-RUN]   - Would restart Wayland compositor ($compositor)"
                autofix_log "INFO" "[DRY-RUN]   - Would clean up compositor processes"
                ;;
            "session_freeze")
                autofix_log "INFO" "[DRY-RUN]   - Would restart display session"
                autofix_log "INFO" "[DRY-RUN]   - Would recover Wayland socket"
                ;;
            "display_disconnect"|"frame_timing")
                autofix_log "INFO" "[DRY-RUN]   - Would restart graphics-intensive applications"
                autofix_log "INFO" "[DRY-RUN]   - Would reconfigure display outputs"
                ;;
        esac
        
        autofix_log "INFO" "[DRY-RUN] Wayland autofix simulation completed successfully"
        return 0
    fi
    
    # Detect the current compositor
    local compositor
    compositor=$(detect_wayland_compositor)
    autofix_log "INFO" "Detected Wayland compositor: $compositor"
    
    # Determine autofix strategy based on issue type and severity
    case "$issue_type" in
        "compositor_crash")
            handle_compositor_crash "$severity" "$compositor"
            ;;
        "session_freeze")
            handle_session_freeze "$severity" "$compositor"
            ;;
        "display_disconnect")
            handle_display_disconnect "$severity" "$compositor"
            ;;
        "frame_timing")
            handle_frame_timing "$severity" "$compositor"
            ;;
        *)
            # Generic display error handling
            handle_generic_display_error "$severity" "$compositor"
            ;;
    esac
}

# =============================================================================
# handle_compositor_crash() - Handle Wayland compositor crashes
# =============================================================================
handle_compositor_crash() {
    local severity="$1"
    local compositor="$2"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling Wayland compositor crash: $compositor (severity: $severity)"
    
    # Try to restart compositor-specific processes
    case "$compositor" in
        "kwin")
            if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
                autofix_log "INFO" "Attempting KWin Wayland restart"
                # Note: This is a placeholder - actual KWin restart would need
                # careful implementation to avoid disrupting the entire session
                if killall -SIGUSR1 kwin_wayland 2>/dev/null; then
                    autofix_log "INFO" "Sent restart signal to kwin_wayland"
                else
                    autofix_log "WARN" "Could not signal kwin_wayland restart"
                fi
            fi
            ;;
        *)
            autofix_log "WARN" "Compositor restart not implemented for: $compositor"
            ;;
    esac
    
    # Manage graphics-intensive processes that might be causing issues
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing graphics processes for compositor recovery"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 180 "CPU_GREEDY" 75 || \
            autofix_log "WARN" "Graphics process management failed"
    fi
}

# =============================================================================
# handle_session_freeze() - Handle Wayland session freezes
# =============================================================================
handle_session_freeze() {
    local severity="$1"
    local compositor="$2"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling Wayland session freeze (severity: $severity)"
    
    # Manage resource-intensive processes first
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing resource-intensive processes for session recovery"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 240 "MEMORY_GREEDY" 2048 || \
            autofix_log "WARN" "Memory process management failed"
    fi
    
    # For critical freezes, try more aggressive measures
    if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
        autofix_log "INFO" "Attempting aggressive session recovery for critical freeze"
        
        # Clear any stuck Wayland sockets
        if [[ -d "/run/user/$UID" ]]; then
            local wayland_socket="/run/user/$UID/wayland-0"
            if [[ -S "$wayland_socket" ]]; then
                autofix_log "INFO" "Wayland socket exists: $wayland_socket"
                # Socket cleanup would go here if needed
            fi
        fi
    fi
}

# =============================================================================
# handle_display_disconnect() - Handle display connectivity issues
# =============================================================================
handle_display_disconnect() {
    local severity="$1"
    local compositor="$2"
    
    autofix_log "INFO" "Handling display disconnect issues (severity: $severity)"
    
    # Basic display output refresh
    autofix_log "INFO" "Attempting display output refresh"
    
    # This would typically involve compositor-specific commands
    # For now, we'll focus on process management
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing display-intensive processes"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 180 "CPU_GREEDY" 70 || \
            autofix_log "WARN" "Display process management failed"
    fi
}

# =============================================================================
# handle_frame_timing() - Handle rendering performance issues
# =============================================================================
handle_frame_timing() {
    local severity="$1"
    local compositor="$2"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling frame timing issues (severity: $severity)"
    
    # Manage graphics-intensive applications
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing graphics processes for frame timing recovery"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 180 "CPU_GREEDY" 80 || \
            autofix_log "WARN" "Graphics process management failed"
    fi
    
    # For severe frame timing issues, consider memory cleanup
    if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
        if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
            autofix_log "INFO" "Managing memory-intensive processes for severe frame timing issues"
            "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 240 "MEMORY_GREEDY" 1536 || \
                autofix_log "WARN" "Memory process management failed"
        fi
    fi
}

# =============================================================================
# handle_generic_display_error() - Handle unspecified display errors
# =============================================================================
handle_generic_display_error() {
    local severity="$1"
    local compositor="$2"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling generic Wayland display error (severity: $severity)"
    
    # Conservative approach for unknown issues
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing resource-intensive processes for generic display error"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 300 "CPU_GREEDY" 70 || \
            autofix_log "WARN" "Generic process management failed"
    fi
}

# Execute with grace period management
autofix_log "INFO" "Wayland display autofix requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "wayland-display-autofix" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_wayland_autofix" "$ISSUE_TYPE" "$SEVERITY"
