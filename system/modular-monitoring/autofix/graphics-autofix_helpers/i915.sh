#!/bin/bash
# =============================================================================
# INTEL i915 GRAPHICS AUTOFIX HELPER
# =============================================================================
#
# PURPOSE:
#   Handles Intel i915 graphics-specific autofix actions including driver
#   rebuilds, GRUB parameter adjustments, and GPU hang recovery.
#
# AUTOFIX CAPABILITIES:
#   - DKMS module rebuild for driver corruption
#   - GRUB parameter application for stability
#   - GPU hang recovery and process management
#   - Display pipeline error recovery
#
# USAGE:
#   Called by graphics-autofix.sh: ./i915.sh <module> <grace> <issue_type> <severity>
#
# ISSUE TYPES:
#   - gpu_hang: GPU lockup requiring reset
#   - driver_error: i915 driver malfunction  
#   - memory_error: Graphics memory issues
#   - display_error: Display pipeline problems
#
# SECURITY CONSIDERATIONS:
#   - Uses existing validated autofix scripts
#   - No direct hardware manipulation
#   - All actions logged for audit
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/common.sh"

# Initialize autofix script with common setup
init_autofix_script "$@"

# Additional arguments specific to this helper
ISSUE_TYPE="${3:-graphics_error}"
SEVERITY="${4:-unknown}"

# Intel i915 specific thresholds
I915_WARN_THRESHOLD="${I915_WARN_THRESHOLD:-5}"
I915_FIX_THRESHOLD="${I915_FIX_THRESHOLD:-15}" 
I915_CRITICAL_THRESHOLD="${I915_CRITICAL_THRESHOLD:-50}"

# =============================================================================
# show_help() - Display usage information
# =============================================================================
show_help() {
    cat << 'EOF'
INTEL i915 GRAPHICS AUTOFIX HELPER

PURPOSE:
    Handles Intel graphics-specific autofix actions for GPU hangs,
    driver errors, and display issues.

USAGE:
    i915.sh <calling_module> <grace_period> [issue_type] [severity]

ISSUE TYPES:
    gpu_hang        GPU lockup requiring reset/recovery
    driver_error    i915 driver malfunction or corruption
    memory_error    Graphics memory allocation issues
    display_error   Display pipeline or output problems

SEVERITY LEVELS:
    warning         Minor issues, monitoring recommended
    critical        Significant issues requiring intervention
    emergency       Severe issues threatening system stability

AUTOFIX ACTIONS:
    - DKMS module rebuild (for driver corruption)
    - GRUB stability parameters (for persistent issues)
    - Process management (for GPU-intensive applications)
    - Display pipeline recovery

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
# perform_i915_autofix() - Main Intel graphics autofix logic
# =============================================================================
perform_i915_autofix() {
    local issue_type="$1"
    local severity="$2"
    
    autofix_log "INFO" "Intel i915 autofix initiated: $issue_type ($severity)"
    
    # Check if we're in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        autofix_log "INFO" "[DRY-RUN] Would perform Intel i915 autofix for $issue_type ($severity)"
        autofix_log "INFO" "[DRY-RUN] Available actions based on issue type:"
        
        case "$issue_type" in
            "gpu_hang")
                autofix_log "INFO" "[DRY-RUN]   - Would manage GPU-intensive processes"
                autofix_log "INFO" "[DRY-RUN]   - Would apply GRUB stability parameters if critical"
                ;;
            "driver_error")
                autofix_log "INFO" "[DRY-RUN]   - Would rebuild i915 DKMS modules if critical"
                autofix_log "INFO" "[DRY-RUN]   - Would apply GRUB driver parameters"
                ;;
            "memory_error"|"display_error")
                autofix_log "INFO" "[DRY-RUN]   - Would restart graphics-intensive processes"
                autofix_log "INFO" "[DRY-RUN]   - Would check for memory pressure"
                ;;
        esac
        
        autofix_log "INFO" "[DRY-RUN] Severity '$severity' would determine action intensity"
        autofix_log "INFO" "[DRY-RUN] Intel i915 autofix simulation completed successfully"
        return 0
    fi
    
    # Determine autofix strategy based on issue type and severity
    case "$issue_type" in
        "gpu_hang")
            handle_gpu_hang "$severity"
            ;;
        "driver_error")
            handle_driver_error "$severity"
            ;;
        "memory_error")
            handle_memory_error "$severity"
            ;;
        "display_error")
            handle_display_error "$severity"
            ;;
        *)
            # Generic graphics error handling
            handle_generic_error "$severity"
            ;;
    esac
}

# =============================================================================
# handle_gpu_hang() - Handle GPU lockup and hang situations
# =============================================================================
handle_gpu_hang() {
    local severity="$1"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling Intel GPU hang (severity: $severity)"
    
    # Always try to manage GPU-intensive processes first
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing GPU-intensive processes for hang recovery"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 180 "CPU_GREEDY" 80 || \
            autofix_log "WARN" "Process management failed during GPU hang recovery"
    fi
    
    # For critical/emergency hangs, apply stability parameters
    if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
        if [[ -x "$SCRIPT_DIR/i915-grub-flags.sh" ]]; then
            autofix_log "INFO" "Applying i915 GRUB stability flags for critical GPU hang"
            "$SCRIPT_DIR/i915-grub-flags.sh" "$CALLING_MODULE" 600 || \
                autofix_log "ERROR" "Failed to apply GRUB stability flags"
        fi
    fi
}

# =============================================================================
# handle_driver_error() - Handle i915 driver malfunction
# =============================================================================
handle_driver_error() {
    local severity="$1"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling Intel driver error (severity: $severity)"
    
    # For critical driver errors, rebuild DKMS modules
    if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
        if [[ -x "$SCRIPT_DIR/i915-dkms-rebuild.sh" ]]; then
            autofix_log "INFO" "Rebuilding i915 DKMS modules for critical driver error"
            "$SCRIPT_DIR/i915-dkms-rebuild.sh" "$CALLING_MODULE" 300 || \
                autofix_log "ERROR" "Failed to rebuild i915 DKMS modules"
        fi
    fi
    
    # Apply GRUB parameters for driver stability
    if [[ -x "$SCRIPT_DIR/i915-grub-flags.sh" ]]; then
        autofix_log "INFO" "Applying i915 GRUB driver parameters"
        "$SCRIPT_DIR/i915-grub-flags.sh" "$CALLING_MODULE" 600 || \
            autofix_log "WARN" "Failed to apply GRUB driver parameters"
    fi
}

# =============================================================================
# handle_memory_error() - Handle graphics memory issues
# =============================================================================
handle_memory_error() {
    local severity="$1"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling Intel graphics memory error (severity: $severity)"
    
    # Manage memory-intensive processes
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing memory-intensive processes for graphics memory recovery"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 240 "MEMORY_GREEDY" 1024 || \
            autofix_log "WARN" "Memory process management failed"
    fi
    
    # For severe memory issues, consider GRUB parameters
    if [[ "$severity" == "emergency" ]]; then
        if [[ -x "$SCRIPT_DIR/i915-grub-flags.sh" ]]; then
            autofix_log "INFO" "Applying memory-related GRUB parameters for emergency"
            "$SCRIPT_DIR/i915-grub-flags.sh" "$CALLING_MODULE" 600 || \
                autofix_log "WARN" "Failed to apply memory-related GRUB parameters"
        fi
    fi
}

# =============================================================================
# handle_display_error() - Handle display pipeline issues
# =============================================================================
handle_display_error() {
    local severity="$1"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling Intel display error (severity: $severity)"
    
    # For display issues, focus on graphics-intensive process management
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing graphics processes for display recovery"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 180 "CPU_GREEDY" 70 || \
            autofix_log "WARN" "Graphics process management failed"
    fi
    
    # For critical display issues, apply stability measures
    if [[ "$severity" == "critical" || "$severity" == "emergency" ]]; then
        if [[ -x "$SCRIPT_DIR/i915-grub-flags.sh" ]]; then
            autofix_log "INFO" "Applying display stability GRUB flags"
            "$SCRIPT_DIR/i915-grub-flags.sh" "$CALLING_MODULE" 600 || \
                autofix_log "WARN" "Failed to apply display stability flags"
        fi
    fi
}

# =============================================================================
# handle_generic_error() - Handle unspecified graphics errors
# =============================================================================
handle_generic_error() {
    local severity="$1"
    local autofix_dir="$(dirname "$SCRIPT_DIR")"
    
    autofix_log "INFO" "Handling generic Intel graphics error (severity: $severity)"
    
    # Conservative approach for unknown issues
    if [[ -x "$autofix_dir/manage-greedy-process.sh" ]]; then
        autofix_log "INFO" "Managing resource-intensive processes for generic error"
        "$autofix_dir/manage-greedy-process.sh" "$CALLING_MODULE" 300 "CPU_GREEDY" 75 || \
            autofix_log "WARN" "Generic process management failed"
    fi
    
    # Only apply aggressive measures for emergency severity
    if [[ "$severity" == "emergency" ]]; then
        if [[ -x "$SCRIPT_DIR/i915-grub-flags.sh" ]]; then
            autofix_log "INFO" "Applying conservative GRUB flags for emergency"
            "$SCRIPT_DIR/i915-grub-flags.sh" "$CALLING_MODULE" 600 || \
                autofix_log "WARN" "Failed to apply emergency GRUB flags"
        fi
    fi
}

# Execute with grace period management
autofix_log "INFO" "Intel i915 graphics autofix requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "i915-graphics-autofix" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_i915_autofix" "$ISSUE_TYPE" "$SEVERITY"
