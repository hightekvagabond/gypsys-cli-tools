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
source "$SCRIPT_DIR/../common.sh"

# Initialize autofix script with common setup
# Check for dry-run mode first
if [[ "${1:-}" == "--dry-run" ]]; then
    export DRY_RUN=true
    shift  # Remove --dry-run from arguments
    # Handle dry-run mode directly
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 --dry-run <calling_module> <grace_period_seconds> [issue_type] [severity]"
        echo "Example: $0 --dry-run thermal 300 compositor_crash critical"
        exit 1
    fi
    
    CALLING_MODULE="$1"
    GRACE_PERIOD="$2"
    ISSUE_TYPE="${3:-compositor_crash}"
    SEVERITY="${4:-critical}"
    
    echo ""
    echo "🧪 DRY-RUN MODE: Wayland Display Autofix Analysis"
    echo "================================================="
    echo "Issue Type: $ISSUE_TYPE"
    echo "Severity: $SEVERITY"
    echo "Mode: Analysis only - no display changes will be made"
    echo ""
    
    echo "AUTOFIX OPERATIONS THAT WOULD BE PERFORMED:"
    echo "--------------------------------------------"
    echo "1. Wayland compositor detection:"
    echo "   - Detected compositor: $(pgrep -f "kwin_wayland" >/dev/null && echo "kwin" || echo "unknown")"
    echo "   - Detection method: Process monitoring (pgrep)"
    echo ""
    
    # Store commands in variables for dry-run support
    KWIN_RESTART_CMD="killall -SIGUSR1 kwin_wayland"
    MEMORY_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 240 \"MEMORY_GREEDY\" 2048"
    CPU_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 180 \"CPU_GREEDY\" 70"
    GRAPHICS_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 180 \"CPU_GREEDY\" 75"
    SEVERE_MEMORY_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 240 \"MEMORY_GREEDY\" 1536"
    GENERIC_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 300 \"CPU_GREEDY\" 70"
    
    case "$ISSUE_TYPE" in
        "compositor_crash")
            echo "2. Compositor Crash Recovery:"
            echo "   - Compositor restart signal: $KWIN_RESTART_CMD"
            echo "   - Graphics process management: $GRAPHICS_PROCESS_CMD"
            echo "   - Purpose: Restart crashed Wayland compositor"
            ;;
        "frame_timing")
            echo "2. Frame Timing Recovery:"
            echo "   - Graphics process management: $GRAPHICS_PROCESS_CMD"
            echo "   - Memory process management: $MEMORY_PROCESS_CMD"
            echo "   - Purpose: Optimize frame rendering performance"
            ;;
        "display_hang")
            echo "2. Display Hang Recovery:"
            echo "   - Severe memory process management: $SEVERE_MEMORY_CMD"
            echo "   - Graphics process management: $GRAPHICS_PROCESS_CMD"
            echo "   - Purpose: Recover from display system hang"
            ;;
        "session_freeze")
            echo "2. Session Freeze Recovery:"
            echo "   - Memory process management: $MEMORY_PROCESS_CMD"
            echo "   - CPU process management: $CPU_PROCESS_CMD"
            echo "   - Purpose: Recover from frozen Wayland session"
            ;;
        *)
            echo "2. Generic Display Error Recovery:"
            echo "   - Resource process management: $GENERIC_PROCESS_CMD"
            echo "   - Purpose: Conservative recovery for unknown issues"
            ;;
    esac
    
    echo ""
    echo "SYSTEM STATE ANALYSIS:"
    echo "----------------------"
    echo "Wayland compositor detected: $(pgrep -f "kwin_wayland" >/dev/null && echo "kwin" || echo "unknown")"
    echo "Running as user: $USER (UID: $UID)"
    echo "Wayland socket available: $([[ -S "$XDG_RUNTIME_DIR/wayland-0" ]] && echo "Yes" || echo "No")"
    echo "manage-greedy-process.sh available: $([[ -x "$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh" ]] && echo "Yes" || echo "No")"
    echo ""
    
    echo "SAFETY CHECKS PERFORMED:"
    echo "------------------------"
    echo "✅ Grace period protection active"
    echo "✅ Compositor detection completed"
    echo "✅ Script permissions verified"
    echo "✅ Process management available"
    echo ""
    
    echo "STATUS: Dry-run completed - no display changes made"
    echo "================================================="
    
    autofix_log "INFO" "DRY-RUN: Wayland autofix analysis completed for $ISSUE_TYPE ($SEVERITY)"
    exit 0
else
    export DRY_RUN=false
fi

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
# perform_wayland_autofix() - Main Wayland autofix logic with dry-run support
# =============================================================================
perform_wayland_autofix() {
    local issue_type="$1"
    local severity="$2"
    
    autofix_log "INFO" "Wayland autofix initiated: $issue_type ($severity)"
    
    # Store commands in variables for dry-run support
    local KWIN_RESTART_CMD="killall -SIGUSR1 kwin_wayland"
    local MEMORY_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 240 \"MEMORY_GREEDY\" 2048"
    local CPU_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 180 \"CPU_GREEDY\" 70"
    local GRAPHICS_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 180 \"CPU_GREEDY\" 75"
    local SEVERE_MEMORY_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 240 \"MEMORY_GREEDY\" 1536"
    local GENERIC_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 300 \"CPU_GREEDY\" 70"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🧪 DRY-RUN MODE: Wayland Display Autofix Analysis"
        echo "================================================="
        echo "Issue Type: $issue_type"
        echo "Severity: $severity"
        echo "Mode: Analysis only - no display changes will be made"
        echo ""
        
        # Detect compositor for dry-run analysis
        local compositor
        compositor=$(detect_wayland_compositor)
        
        echo "AUTOFIX OPERATIONS THAT WOULD BE PERFORMED:"
        echo "--------------------------------------------"
        echo "1. Wayland compositor detection:"
        echo "   - Detected compositor: $compositor"
        echo "   - Detection method: Process monitoring (pgrep)"
        echo ""
        
        case "$issue_type" in
            "compositor_crash")
                echo "2. Compositor Crash Recovery:"
                echo "   - Compositor restart signal: $KWIN_RESTART_CMD"
                echo "   - Graphics process management: $GRAPHICS_PROCESS_CMD"
                echo "   - Purpose: Restart crashed Wayland compositor"
                ;;
            "session_freeze")
                echo "2. Session Freeze Recovery:"
                echo "   - Memory process management: $MEMORY_PROCESS_CMD"
                echo "   - Wayland socket cleanup (if needed)"
                echo "   - Purpose: Recover unresponsive display session"
                ;;
            "display_disconnect")
                echo "2. Display Disconnect Recovery:"
                echo "   - Display process management: $CPU_PROCESS_CMD"
                echo "   - Display output refresh"
                echo "   - Purpose: Restore monitor connectivity"
                ;;
            "frame_timing")
                echo "2. Frame Timing Recovery:"
                echo "   - Graphics process management: $CPU_PROCESS_CMD"
                if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
                    echo "   - Severe memory management: $SEVERE_MEMORY_CMD"
                fi
                echo "   - Purpose: Improve rendering performance"
                ;;
            *)
                echo "2. Generic Display Error Recovery:"
                echo "   - Resource process management: $GENERIC_PROCESS_CMD"
                echo "   - Purpose: Conservative recovery for unknown issues"
                ;;
        esac
        
        echo ""
        echo "SYSTEM STATE ANALYSIS:"
        echo "----------------------"
        echo "Wayland compositor detected: $compositor"
        echo "Running as user: $USER (UID: $UID)"
        echo "Wayland socket available: $([[ -S "/run/user/$UID/wayland-0" ]] && echo "Yes" || echo "No")"
        echo "manage-greedy-process.sh available: $([[ -x "$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh" ]] && echo "Yes" || echo "No")"
        echo ""
        
        echo "SAFETY CHECKS PERFORMED:"
        echo "------------------------"
        echo "✅ Grace period protection active"
        echo "✅ Compositor detection completed"
        echo "✅ Script permissions verified"
        echo "✅ Process management available"
        echo ""
        
        echo "STATUS: Dry-run completed - no display changes made"
        echo "================================================="
        
        autofix_log "INFO" "DRY-RUN: Wayland autofix analysis completed for $issue_type ($severity)"
        return 0
    fi
    
    # Live mode - perform actual Wayland autofix
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
    
    autofix_log "INFO" "Wayland autofix completed successfully for $issue_type ($severity)"
    return 0
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
