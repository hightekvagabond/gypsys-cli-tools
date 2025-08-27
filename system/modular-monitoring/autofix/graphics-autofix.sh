#!/bin/bash
# =============================================================================
# GRAPHICS AUTOFIX SCRIPT WITH HELPER ARCHITECTURE
# =============================================================================
#
# PURPOSE:
#   Main graphics autofix orchestrator that routes to chipset-specific helpers.
#   This script detects the graphics hardware and calls the appropriate helper
#   script to handle graphics-specific issues and emergencies.
#
# HELPER ARCHITECTURE:
#   This script uses the autofix helper pattern:
#   - graphics_helpers/i915.sh     - Intel graphics autofix (TESTED)
#   - graphics_helpers/nvidia.sh   - NVIDIA graphics autofix (STUB)
#   - graphics_helpers/amdgpu.sh   - AMD graphics autofix (STUB)
#
#   Helpers are selected based on GRAPHICS_CHIPSET in config/SYSTEM.conf
#
# AUTOFIX CAPABILITIES:
#   - GPU driver crashes and hangs
#   - Graphics memory issues
#   - Display pipeline errors
#   - GPU thermal throttling
#   - Hardware acceleration problems
#
# USAGE:
#   graphics.sh <calling_module> <grace_period> [issue_type] [severity]
#
# EXAMPLES:
#   graphics.sh graphics 300 gpu_hang critical
#   graphics.sh display 180 driver_error warning
#
# SECURITY CONSIDERATIONS:
#   - Helper validation prevents arbitrary script execution
#   - Chipset detection prevents wrong autofix application
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
ISSUE_TYPE="${3:-graphics_error}"
SEVERITY="${4:-unknown}"

# Load system configuration to determine graphics chipset
GRAPHICS_CHIPSET="${GRAPHICS_CHIPSET:-auto}"

# =============================================================================
# show_help() - Display usage information
# =============================================================================
show_help() {
    cat << 'EOF'
GRAPHICS AUTOFIX SCRIPT

PURPOSE:
    Routes graphics autofix actions to appropriate chipset-specific helpers.
    Automatically detects graphics hardware and applies correct fixes.

USAGE:
    graphics.sh <calling_module> <grace_period> [issue_type] [severity]

ARGUMENTS:
    calling_module   - Name of module requesting autofix (e.g., "graphics")
    grace_period     - Seconds to wait before allowing autofix again
    issue_type       - Type of graphics issue (gpu_hang, driver_error, memory_error)
    severity         - Issue severity (warning, critical, emergency)

EXAMPLES:
    # GPU hang detected by graphics module
    graphics.sh graphics 300 gpu_hang critical

    # Driver error detected
    graphics.sh graphics 180 driver_error warning

SUPPORTED CHIPSETS:
    ✅ Intel (i915)     - Fully supported and tested
    ⚠️  NVIDIA          - Stub implementation, needs testing
    ⚠️  AMD (amdgpu)    - Stub implementation, needs testing

HELPER SCRIPTS:
    graphics_helpers/i915.sh     - Intel graphics autofix
    graphics_helpers/nvidia.sh   - NVIDIA graphics autofix (STUB)
    graphics_helpers/amdgpu.sh   - AMD graphics autofix (STUB)

CONFIGURATION:
    Set GRAPHICS_CHIPSET in config/SYSTEM.conf:
    GRAPHICS_CHIPSET="i915"      # For Intel graphics
    GRAPHICS_CHIPSET="nvidia"    # For NVIDIA graphics  
    GRAPHICS_CHIPSET="amdgpu"    # For AMD graphics

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
# detect_graphics_chipset() - Auto-detect graphics hardware if not configured
# =============================================================================
detect_graphics_chipset() {
    local detected_chipset="unknown"
    
    # Check for Intel graphics
    if lsmod | grep -q "i915" || lspci | grep -qi "intel.*graphics"; then
        detected_chipset="i915"
    # Check for NVIDIA graphics  
    elif lsmod | grep -q "nvidia" || lspci | grep -qi "nvidia.*graphics"; then
        detected_chipset="nvidia"
    # Check for AMD graphics
    elif lsmod | grep -q "amdgpu\|radeon" || lspci | grep -qi "amd.*graphics"; then
        detected_chipset="amdgpu"
    fi
    
    autofix_log "DEBUG" "Auto-detected graphics chipset: $detected_chipset"
    echo "$detected_chipset"
}

# =============================================================================
# validate_helper() - Ensure helper script exists and is safe to execute
# =============================================================================
validate_helper() {
    local helper_script="$1"
    local chipset="$2"
    
    # Check if helper script exists
    if [[ ! -f "$helper_script" ]]; then
        autofix_log "ERROR" "Graphics helper script not found: $helper_script"
        return 1
    fi
    
    # Check if helper script is executable
    if [[ ! -x "$helper_script" ]]; then
        autofix_log "ERROR" "Graphics helper script not executable: $helper_script"
        return 1
    fi
    
    # Security: Validate helper script is in expected location
    local expected_dir="$SCRIPT_DIR/graphics_helpers"
    if [[ "$(dirname "$helper_script")" != "$expected_dir" ]]; then
        autofix_log "ERROR" "Security: Helper script outside expected directory: $helper_script"
        return 1
    fi
    
    # Security: Validate chipset name to prevent directory traversal
    if [[ ! "$chipset" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        autofix_log "ERROR" "Security: Invalid chipset name: $chipset"
        return 1
    fi
    
    autofix_log "DEBUG" "Graphics helper validation passed: $helper_script"
    return 0
}

# =============================================================================
# perform_graphics_autofix() - Main autofix function with helper routing and dry-run support
# =============================================================================
perform_graphics_autofix() {
    local issue_type="$1"
    local severity="$2"
    local chipset="$GRAPHICS_CHIPSET"
    
    autofix_log "INFO" "Graphics autofix requested: $issue_type ($severity) for chipset: $chipset"
    
    # Auto-detect chipset if not configured
    if [[ "$chipset" == "auto" || -z "$chipset" ]]; then
        chipset=$(detect_graphics_chipset)
        autofix_log "INFO" "Auto-detected graphics chipset: $chipset"
    fi
    
    # Validate we have a supported chipset
    if [[ "$chipset" == "unknown" ]]; then
        autofix_log "ERROR" "Unable to detect graphics chipset - no autofix available"
        return 1
    fi
    
    # Determine helper script path
    local helper_script="$SCRIPT_DIR/graphics_helpers/${chipset}.sh"
    
    # Validate helper script
    if ! validate_helper "$helper_script" "$chipset"; then
        autofix_log "ERROR" "Graphics helper validation failed for chipset: $chipset"
        return 1
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🧪 DRY-RUN MODE: Graphics Autofix Analysis"
        echo "==========================================="
        echo "Issue Type: $issue_type"
        echo "Severity: $severity"
        echo "Graphics Chipset: $chipset"
        echo "Mode: Analysis only - no changes will be made"
        echo ""
        
        echo "AUTOFIX OPERATIONS THAT WOULD BE PERFORMED:"
        echo "--------------------------------------------"
        echo "1. Graphics chipset detection:"
        echo "   - Current setting: $GRAPHICS_CHIPSET"
        echo "   - Auto-detected: $chipset"
        echo "   - Helper script: $helper_script"
        echo ""
        
        echo "2. Helper script validation:"
        echo "   - Script exists: $([[ -f "$helper_script" ]] && echo "Yes" || echo "No")"
        echo "   - Script executable: $([[ -x "$helper_script" ]] && echo "Yes" || echo "No")"
        echo "   - Security validation: Passed"
        echo ""
        
        echo "3. Helper script execution:"
        echo "   - Would call: $helper_script"
        echo "   - Arguments: $CALLING_MODULE $GRACE_PERIOD $issue_type $severity"
        echo "   - Grace period: ${GRACE_PERIOD}s"
        echo ""
        
        echo "4. Expected actions based on issue type:"
        case "$issue_type" in
            "gpu_hang")
                echo "   - GPU driver restart"
                echo "   - Graphics memory reset"
                echo "   - Display pipeline recovery"
                ;;
            "driver_error")
                echo "   - Driver module reload"
                echo "   - Graphics state reset"
                echo "   - Error log analysis"
                ;;
            "memory_error")
                echo "   - Graphics memory cleanup"
                echo "   - Buffer cache reset"
                echo "   - Memory allocation recovery"
                ;;
            *)
                echo "   - Generic graphics recovery procedures"
                echo "   - System state analysis"
                echo "   - Hardware health check"
                ;;
        esac
        echo ""
        
        echo "SAFETY CHECKS PERFORMED:"
        echo "------------------------"
        echo "✅ Helper script location validated"
        echo "✅ Chipset name security validated"
        echo "✅ Script permissions verified"
        echo "✅ Grace period protection active"
        echo ""
        
        echo "STATUS: Dry-run completed - no changes made"
        echo "==========================================="
        
        autofix_log "INFO" "DRY-RUN: Graphics autofix analysis completed for $chipset"
        return 0
    fi
    
    # Live mode - execute chipset-specific helper
    autofix_log "INFO" "Executing graphics autofix helper: $chipset"
    if "$helper_script" "$CALLING_MODULE" "$GRACE_PERIOD" "$issue_type" "$severity"; then
        autofix_log "INFO" "Graphics autofix helper completed successfully: $chipset"
        return 0
    else
        autofix_log "ERROR" "Graphics autofix helper failed: $chipset"
        return 1
    fi
}

# Execute with grace period management
autofix_log "INFO" "Graphics autofix requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "graphics" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_graphics_autofix" "$ISSUE_TYPE" "$SEVERITY"
