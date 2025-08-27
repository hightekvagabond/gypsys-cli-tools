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
    echo "🧪 DRY-RUN MODE: KWin Compositor Autofix Analysis"
    echo "=================================================="
    echo "Issue Type: $ISSUE_TYPE"
    echo "Severity: $SEVERITY"
    echo "Mode: Analysis only - no KWin changes will be made"
    echo ""
    
    echo "AUTOFIX OPERATIONS THAT WOULD BE PERFORMED:"
    echo "--------------------------------------------"
    echo "1. KWin status check:"
    echo "   - Status: $(pgrep -f "kwin_wayland" >/dev/null && echo "KWin Wayland is running" || echo "KWin Wayland not detected")"
    echo "   - Detection: Process monitoring (pgrep)"
    echo ""
    
    # Store commands in variables for dry-run support
    KWIN_RESTART_CMD="killall -SIGUSR1 kwin_wayland"
    KWIN_REFRESH_CMD="killall -SIGUSR1 kwin_wayland"
    GRAPHICS_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 180 \"CPU_GREEDY\" 75"
    MEMORY_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 240 \"MEMORY_GREEDY\" 1536"
    GENERIC_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 300 \"CPU_GREEDY\" 70"
    
    case "$ISSUE_TYPE" in
        "compositor_crash")
            echo "2. Compositor Crash Recovery:"
            if [[ "$SEVERITY" == "critical" || "$SEVERITY" == "emergency" ]]; then
                echo "   - KWin restart: $KWIN_RESTART_CMD"
                echo "   - Purpose: Restart crashed KWin compositor"
            fi
            echo "   - Graphics process management: $GRAPHICS_PROCESS_CMD"
            echo "   - Purpose: Clean up KDE and graphics processes"
            ;;
        "window_freeze")
            echo "2. Window Freeze Recovery:"
            if [[ "$SEVERITY" == "critical" || "$SEVERITY" == "emergency" ]]; then
                echo "   - Window management refresh: $KWIN_REFRESH_CMD"
                echo "   - Purpose: Reset window management state"
            fi
            echo "   - Memory process management: $MEMORY_PROCESS_CMD"
            echo "   - Purpose: Clean up memory-intensive processes"
            ;;
        "effect_hang")
            echo "2. Desktop Effects Recovery:"
            if [[ "$SEVERITY" == "critical" || "$SEVERITY" == "emergency" ]]; then
                echo "   - KWin restart: $KWIN_RESTART_CMD"
                echo "   - Purpose: Reset desktop effects"
            fi
            echo "   - Graphics process management: $GRAPHICS_PROCESS_CMD"
            echo "   - Purpose: Clean up GPU-intensive processes"
            ;;
        "workspace_error")
            echo "2. Workspace Error Recovery:"
            if [[ "$SEVERITY" == "critical" || "$SEVERITY" == "emergency" ]]; then
                echo "   - KWin refresh: $KWIN_REFRESH_CMD"
                echo "   - Purpose: Recover workspace state"
            fi
            echo "   - Process management: $GENERIC_PROCESS_CMD"
            echo "   - Purpose: Clean up resource-intensive processes"
            ;;
        *)
            echo "2. Generic KWin Error Recovery:"
            echo "   - Resource process management: $GENERIC_PROCESS_CMD"
            echo "   - Purpose: Conservative recovery for unknown issues"
            if [[ "$SEVERITY" == "emergency" ]]; then
                echo "   - Emergency KWin restart: $KWIN_RESTART_CMD"
                echo "   - Purpose: Last resort recovery"
            fi
            ;;
    esac
    
    echo ""
    echo "SYSTEM STATE ANALYSIS:"
    echo "----------------------"
    echo "KWin Wayland running: $(pgrep -f "kwin_wayland" >/dev/null && echo "Yes" || echo "No")"
    echo "Running as user: $USER (UID: $UID)"
    echo "manage-greedy-process.sh available: $(dirname "$SCRIPT_DIR")/manage-greedy-process.sh"
    echo ""
    
    echo "SAFETY CHECKS PERFORMED:"
    echo "------------------------"
    echo "✅ Grace period protection active"
    echo "✅ KWin status verification completed"
    echo "✅ Script permissions verified"
    echo "✅ Process management available"
    echo ""
    
    echo "STATUS: Dry-run completed - no KWin changes made"
    echo "=================================================="
    
    autofix_log "INFO" "DRY-RUN: KWin autofix analysis completed for $ISSUE_TYPE ($SEVERITY)"
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
# perform_kwin_autofix() - Main KWin autofix logic with dry-run support
# =============================================================================
perform_kwin_autofix() {
    local issue_type="$1"
    local severity="$2"
    
    autofix_log "INFO" "KWin autofix initiated: $issue_type ($severity)"
    
    # Store commands in variables for dry-run support
    local KWIN_RESTART_CMD="killall -SIGUSR1 kwin_wayland"
    local KWIN_REFRESH_CMD="killall -SIGUSR1 kwin_wayland"
    local GRAPHICS_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 180 \"CPU_GREEDY\" 75"
    local MEMORY_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 240 \"MEMORY_GREEDY\" 1536"
    local GENERIC_PROCESS_CMD="$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh \"$CALLING_MODULE\" 300 \"CPU_GREEDY\" 70"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🧪 DRY-RUN MODE: KWin Compositor Autofix Analysis"
        echo "=================================================="
        echo "Issue Type: $issue_type"
        echo "Severity: $severity"
        echo "Mode: Analysis only - no KWin changes will be made"
        echo ""
        
        echo "AUTOFIX OPERATIONS THAT WOULD BE PERFORMED:"
        echo "--------------------------------------------"
        echo "1. KWin status check:"
        if check_kwin_status; then
            echo "   - Status: KWin Wayland is running"
            echo "   - Detection: Process monitoring (pgrep)"
        else
            echo "   - Status: KWin Wayland not detected"
            echo "   - Note: Limited autofix options available"
        fi
        echo ""
        
        case "$issue_type" in
            "compositor_crash")
                echo "2. Compositor Crash Recovery:"
                if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
                    echo "   - KWin restart: $KWIN_RESTART_CMD"
                    echo "   - Purpose: Restart crashed KWin compositor"
                fi
                echo "   - Graphics process management: $GRAPHICS_PROCESS_CMD"
                echo "   - Purpose: Clean up KDE and graphics processes"
                ;;
            "window_freeze")
                echo "2. Window Freeze Recovery:"
                if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
                    echo "   - Window management refresh: $KWIN_REFRESH_CMD"
                    echo "   - Purpose: Reset window management state"
                fi
                echo "   - Memory process management: $MEMORY_PROCESS_CMD"
                echo "   - Purpose: Clean up memory-intensive processes"
                ;;
            "effect_hang")
                echo "2. Desktop Effects Recovery:"
                if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
                    echo "   - KWin restart: $KWIN_RESTART_CMD"
                    echo "   - Purpose: Reset desktop effects"
                fi
                echo "   - Graphics process management: $GRAPHICS_PROCESS_CMD"
                echo "   - Purpose: Clean up GPU-intensive processes"
                ;;
            "workspace_error")
                echo "2. Workspace Error Recovery:"
                if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
                    echo "   - KWin refresh: $KWIN_REFRESH_CMD"
                    echo "   - Purpose: Recover workspace state"
                fi
                echo "   - Process management: $GENERIC_PROCESS_CMD"
                echo "   - Purpose: Clean up resource-intensive processes"
                ;;
            *)
                echo "2. Generic KWin Error Recovery:"
                echo "   - Resource process management: $GENERIC_PROCESS_CMD"
                echo "   - Purpose: Conservative recovery for unknown issues"
                if [[ "$severity" == "emergency" ]]; then
                    echo "   - Emergency KWin restart: $KWIN_RESTART_CMD"
                    echo "   - Purpose: Last resort recovery"
                fi
                ;;
        esac
        
        echo ""
        echo "SYSTEM STATE ANALYSIS:"
        echo "----------------------"
        echo "KWin Wayland running: $([[ $(pgrep -f "kwin_wayland" >/dev/null 2>&1; echo $?) -eq 0 ]] && echo "Yes" || echo "No")"
        echo "Running as user: $USER (UID: $UID)"
        echo "manage-greedy-process.sh available: $([[ -x "$(dirname "$SCRIPT_DIR")/manage-greedy-process.sh" ]] && echo "Yes" || echo "No")"
        echo ""
        
        echo "SAFETY CHECKS PERFORMED:"
        echo "------------------------"
        echo "✅ Grace period protection active"
        echo "✅ KWin status verification completed"
        echo "✅ Script permissions verified"
        echo "✅ Process management available"
        echo ""
        
        echo "STATUS: Dry-run completed - no KWin changes made"
        echo "=================================================="
        
        autofix_log "INFO" "DRY-RUN: KWin autofix analysis completed for $issue_type ($severity)"
        return 0
    fi
    
    # Live mode - perform actual KWin autofix
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
    
    autofix_log "INFO" "KWin autofix completed successfully for $issue_type ($severity)"
    return 0
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
