#!/bin/bash
# =============================================================================
# KDE KWIN COMPOSITOR AUTOFIX HELPER
# =============================================================================
#
# PURPOSE:
#   Handles KDE KWin compositor-specific autofix actions including KWin restart,
#   window management recovery, and KDE-specific display issues.
#
# AUTOFIX CAPABILITIES:
#   - KWin Wayland compositor restart
#   - Window management recovery
#   - KDE desktop effect management
#   - Multi-workspace recovery
#
# USAGE:
#   Called by display-autofix.sh: ./kwin.sh <module> <grace> <issue_type> <severity>
#
# ISSUE TYPES:
#   - compositor_crash: KWin compositor failure
#   - window_freeze: Window management unresponsive
#   - effect_hang: Desktop effects causing issues
#   - workspace_error: Multi-workspace problems
#
# TESTED ON:
#   - KDE Plasma 5.x/6.x with Wayland
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
KDE KWIN COMPOSITOR AUTOFIX HELPER

PURPOSE:
    Handles KDE KWin compositor-specific autofix actions for compositor
    crashes, window management issues, and KDE desktop effects.

USAGE:
    kwin.sh <calling_module> <grace_period> [issue_type] [severity]

ISSUE TYPES:
    compositor_crash   KWin compositor has crashed or hung
    window_freeze      Window management is unresponsive
    effect_hang        Desktop effects causing performance issues
    workspace_error    Multi-workspace or activity problems

SEVERITY LEVELS:
    warning           Minor issues, process restart recommended
    critical          Significant issues requiring KWin restart
    emergency         Severe issues threatening desktop usability

AUTOFIX ACTIONS:
    - KWin Wayland compositor restart (SIGUSR1)
    - Desktop effects disable/re-enable
    - Window management recovery
    - Process cleanup for KDE applications

TESTED ENVIRONMENTS:
    ✅ KDE Plasma 5.x/6.x Wayland
    ⚠️  KDE X11 may need additional testing

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
# check_kwin_status() - Check if KWin is running and responsive
# =============================================================================
check_kwin_status() {
    local kwin_pid
    kwin_pid=$(pgrep -f "kwin_wayland" 2>/dev/null || echo "")
    
    if [[ -n "$kwin_pid" ]]; then
        autofix_log "DEBUG" "KWin Wayland running (PID: $kwin_pid)"
        return 0
    else
        autofix_log "DEBUG" "KWin Wayland not detected"
        return 1
    fi
}

# =============================================================================
# perform_kwin_autofix() - Main KWin autofix logic
# =============================================================================
perform_kwin_autofix() {
    local issue_type="$1"
    local severity="$2"
    
    autofix_log "INFO" "KWin autofix initiated: $issue_type ($severity)"
    
    # Check if we're in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        autofix_log "INFO" "[DRY-RUN] Would perform KWin autofix for $issue_type ($severity)"
        
        if check_kwin_status; then
            autofix_log "INFO" "[DRY-RUN] KWin Wayland is running"
        else
            autofix_log "INFO" "[DRY-RUN] KWin Wayland not detected"
        fi
        
        case "$issue_type" in
            "compositor_crash")
                autofix_log "INFO" "[DRY-RUN]   - Would restart KWin compositor (SIGUSR1)"
                autofix_log "INFO" "[DRY-RUN]   - Would clean up KDE processes"
                ;;
            "window_freeze")
                autofix_log "INFO" "[DRY-RUN]   - Would refresh KWin window management"
                autofix_log "INFO" "[DRY-RUN]   - Would reset workspace state"
                ;;
            "effect_hang")
                autofix_log "INFO" "[DRY-RUN]   - Would disable/re-enable desktop effects"
                autofix_log "INFO" "[DRY-RUN]   - Would restart compositor for effect reset"
                ;;
        esac
        
        autofix_log "INFO" "[DRY-RUN] KWin autofix simulation completed successfully"
        return 0
    fi
    
    # Check KWin status
    if ! check_kwin_status; then
        autofix_log "WARN" "KWin Wayland not running - limited autofix options available"
    fi
    
    # Determine autofix strategy based on issue type and severity
    case "$issue_type" in
        "compositor_crash")
            handle_compositor_crash "$severity"
            ;;
        "window_freeze")
            handle_window_freeze "$severity"
            ;;
        "effect_hang")
            handle_effect_hang "$severity"
            ;;
        "workspace_error")
            handle_workspace_error "$severity"
            ;;
        *)
            # Generic KWin error handling
            handle_generic_kwin_error "$severity"
            ;;
    esac
}

# =============================================================================
# handle_compositor_crash() - Handle KWin compositor crashes
# =============================================================================
handle_compositor_crash() {
    local severity="$1"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling KWin compositor crash (severity: $severity)"
    
    # For critical/emergency crashes, attempt KWin restart
    if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
        if check_kwin_status; then
            autofix_log "INFO" "Attempting KWin compositor restart (SIGUSR1)"
            if killall -SIGUSR1 kwin_wayland 2>/dev/null; then
                autofix_log "INFO" "Sent restart signal to KWin Wayland"
                sleep 2  # Allow time for restart
            else
                autofix_log "WARN" "Could not send restart signal to KWin"
            fi
        else
            autofix_log "ERROR" "KWin not running - cannot restart compositor"
        fi
    fi
    
    # Manage KDE and graphics-intensive processes
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing graphics processes for KWin recovery"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 180 "CPU_GREEDY" 75 || \
            autofix_log "WARN" "Graphics process management failed"
    fi
}

# =============================================================================
# handle_window_freeze() - Handle window management freezes
# =============================================================================
handle_window_freeze() {
    local severity="$1"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling KWin window freeze (severity: $severity)"
    
    # Try to refresh KWin's window management
    if check_kwin_status && [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
        autofix_log "INFO" "Attempting KWin window management refresh"
        if killall -SIGUSR1 kwin_wayland 2>/dev/null; then
            autofix_log "INFO" "Sent refresh signal to KWin for window management"
        else
            autofix_log "WARN" "Could not refresh KWin window management"
        fi
    fi
    
    # Manage memory-intensive processes that might affect window management
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing memory processes for window management recovery"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 240 "MEMORY_GREEDY" 1536 || \
            autofix_log "WARN" "Memory process management failed"
    fi
}

# =============================================================================
# handle_effect_hang() - Handle desktop effects issues
# =============================================================================
handle_effect_hang() {
    local severity="$1"
    
    autofix_log "INFO" "Handling KWin desktop effects hang (severity: $severity)"
    
    # For effects issues, restart compositor to reset effects
    if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
        if check_kwin_status; then
            autofix_log "INFO" "Restarting KWin to reset desktop effects"
            if killall -SIGUSR1 kwin_wayland 2>/dev/null; then
                autofix_log "INFO" "KWin restarted for desktop effects reset"
            else
                autofix_log "WARN" "Could not restart KWin for effects reset"
            fi
        fi
    fi
    
    # Effects issues often correlate with high GPU usage
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing graphics processes for effects recovery"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 180 "CPU_GREEDY" 80 || \
            autofix_log "WARN" "Graphics process management failed"
    fi
}

# =============================================================================
# handle_workspace_error() - Handle workspace/activity issues
# =============================================================================
handle_workspace_error() {
    local severity="$1"
    
    autofix_log "INFO" "Handling KWin workspace error (severity: $severity)"
    
    # Workspace issues usually require compositor refresh
    if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
        if check_kwin_status; then
            autofix_log "INFO" "Refreshing KWin for workspace recovery"
            if killall -SIGUSR1 kwin_wayland 2>/dev/null; then
                autofix_log "INFO" "KWin refreshed for workspace recovery"
            else
                autofix_log "WARN" "Could not refresh KWin for workspace recovery"
            fi
        fi
    fi
}

# =============================================================================
# handle_generic_kwin_error() - Handle unspecified KWin errors
# =============================================================================
handle_generic_kwin_error() {
    local severity="$1"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling generic KWin error (severity: $severity)"
    
    # Conservative approach - just manage processes
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing resource-intensive processes for generic KWin error"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 300 "CPU_GREEDY" 70 || \
            autofix_log "WARN" "Generic process management failed"
    fi
    
    # Only restart for emergency situations
    if [[ "$severity" == "emergency" ]]; then
        if check_kwin_status; then
            autofix_log "INFO" "Emergency KWin restart for generic error"
            if killall -SIGUSR1 kwin_wayland 2>/dev/null; then
                autofix_log "INFO" "Emergency KWin restart completed"
            else
                autofix_log "WARN" "Emergency KWin restart failed"
            fi
        fi
    fi
}

# Execute with grace period management
autofix_log "INFO" "KWin compositor autofix requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "kwin-compositor-autofix" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_kwin_autofix" "$ISSUE_TYPE" "$SEVERITY"
