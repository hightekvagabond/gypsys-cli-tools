#!/bin/bash
# =============================================================================
# TEST CONFIG DUMMY AUTOFIX SCRIPT
# =============================================================================
#
# PURPOSE:
#   Safe dummy autofix script for testing configuration hierarchy and environment
#   variable overrides. This script performs NO system changes and only creates
#   temporary test files for verification.
#
# AUTOFIX CAPABILITIES:
#   - Creates harmless temporary test files
#   - Shows configuration values in logs
#   - Tests grace period functionality
#   - Validates environment variable overrides
#
# USAGE:
#   test-config-dummy.sh <calling_module> <grace_period> [test_type] [message]
#
# EXAMPLES:
#   test-config-dummy.sh test 60 basic "hello world"
#   test-config-dummy.sh --dry-run test 60 basic "hello world"
#
# SAFETY:
#   - Creates files only in /tmp/modular-monitor-test/
#   - No system modifications
#   - No dangerous operations
#   - Safe for repeated testing
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize autofix script with common setup
init_autofix_script "$@"

# Additional arguments specific to this script
TEST_TYPE="${3:-basic}"
TEST_MESSAGE="${4:-Configuration test}"

# =============================================================================
# show_help() - Display usage information
# =============================================================================
show_help() {
    cat << 'EOF'
TEST CONFIG DUMMY AUTOFIX SCRIPT

PURPOSE:
    Safe dummy autofix script for testing configuration hierarchy and environment
    variable overrides. Performs NO dangerous operations.

USAGE:
    test-config-dummy.sh <calling_module> <grace_period> [test_type] [message]

ARGUMENTS:
    calling_module   - Name of module requesting autofix (e.g., "test")
    grace_period     - Seconds to wait before allowing autofix again
    test_type        - Type of test (basic, config, env-vars)
    message         - Test message to include in output

EXAMPLES:
    # Basic configuration test
    test-config-dummy.sh test 60 basic "hello world"

    # Environment variable override test
    AUTOFIX=true DISABLE_AUTOFIX="" test-config-dummy.sh test 60 env-vars "override test"

    # Dry run mode
    test-config-dummy.sh --dry-run test 60 basic "dry run test"

SAFETY:
    - Creates files only in /tmp/modular-monitor-test/
    - No system modifications whatsoever
    - Safe for repeated testing
    - All files are timestamped and harmless

EXIT CODES:
    0 - Test completed successfully
    1 - Error occurred (check logs)
    2 - Skipped due to grace period
EOF
}

# Validate arguments
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1
fi

CALLING_MODULE="$1"
GRACE_PERIOD="$2"

# =============================================================================
# perform_test_config_actions() - Main test function (completely safe)
# =============================================================================
perform_test_config_actions() {
    local epoch_time
    epoch_time=$(date +%s)
    local test_dir="/tmp/modular-monitor-test"
    local test_file="$test_dir/config-test-${epoch_time}.txt"
    
    autofix_log "INFO" "Starting configuration test: $TEST_TYPE"
    autofix_log "INFO" "Test message: $TEST_MESSAGE"
    autofix_log "INFO" "Called by: $CALLING_MODULE"
    autofix_log "INFO" "Grace period: ${GRACE_PERIOD}s"
    
    # Create test directory if it doesn't exist
    if ! mkdir -p "$test_dir" 2>/dev/null; then
        autofix_log "WARN" "Could not create test directory: $test_dir"
        autofix_log "INFO" "Continuing without file creation..."
    else
        autofix_log "INFO" "Created test directory: $test_dir"
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🧪 DRY-RUN MODE: Test Config Dummy Analysis"
        echo "=========================================="
        echo "Mode: Analysis only - no test files will be created"
        echo ""
        
        echo "TEST OPERATIONS THAT WOULD BE PERFORMED:"
        echo "----------------------------------------"
        echo "1. Create test file: $test_file"
        echo "2. Write configuration values to file"
        echo "3. Log current settings"
        echo "4. Display environment variable status"
        echo ""
        
        echo "CONFIGURATION ANALYSIS:"
        echo "----------------------"
        echo "OS: ${OS:-<not set>}"
        echo "AUTOFIX: ${AUTOFIX:-<not set>}"
        echo "DISABLE_AUTOFIX: ${DISABLE_AUTOFIX:-<not set>}"
        echo "PREFERRED_KERNEL_BRANCH: ${PREFERRED_KERNEL_BRANCH:-<not set>}"
        echo "PREFERRED_KERNEL_TRACK: ${PREFERRED_KERNEL_TRACK:-<not set>}"
        echo "GRAPHICS_CHIPSET: ${GRAPHICS_CHIPSET:-<not set>}"
        echo "USE_MODULES: ${USE_MODULES:-<not set>}"
        echo ""
        
        echo "MODULE CONFIGURATION (if called from module):"
        echo "--------------------------------------------"
        echo "Calling Module: ${CALLING_MODULE}"
        if [[ "${CALLING_MODULE}" == "kernel" && "${OS:-}" == "ubuntu" ]]; then
            echo "Helper Config Path: modules/kernel/helpers/ubuntu.conf"
            echo "UBUNTU_RELEASE_DETECTION: ${UBUNTU_RELEASE_DETECTION:-<not set>}"
            echo "ENFORCE_TRACK_COMPLIANCE: ${ENFORCE_TRACK_COMPLIANCE:-<not set>}"
            echo "INTEL_GRAPHICS_PREFERRED_TRACK: ${INTEL_GRAPHICS_PREFERRED_TRACK:-<not set>}"
        fi
        echo ""
        
        echo "ENVIRONMENT VARIABLE ANALYSIS:"
        echo "-----------------------------"
        if [[ -n "${ENV_OVERRIDE_AUTOFIX:-}" ]]; then
            echo "ENV_OVERRIDE_AUTOFIX: ${ENV_OVERRIDE_AUTOFIX}"
        else
            echo "ENV_OVERRIDE_AUTOFIX: <not preserved>"
        fi
        
        if [[ -n "${ENV_OVERRIDE_DISABLE_AUTOFIX:-}" ]]; then
            echo "ENV_OVERRIDE_DISABLE_AUTOFIX: ${ENV_OVERRIDE_DISABLE_AUTOFIX}"
        else
            echo "ENV_OVERRIDE_DISABLE_AUTOFIX: <not preserved>"
        fi
        echo ""
        
        echo "STATUS: Dry-run completed - no test files created"
        echo "=========================================="
        
        autofix_log "INFO" "DRY-RUN: Test config dummy analysis completed"
        return 0
    fi
    
    # Live mode - create actual test file
    autofix_log "INFO" "Creating test file: $test_file"
    
    # Create test file with configuration information
    cat > "$test_file" << EOF
# Modular Monitor Configuration Test
# Generated: $(date)
# Epoch: $epoch_time
# Test Type: $TEST_TYPE
# Test Message: $TEST_MESSAGE
# Called By: $CALLING_MODULE
# Grace Period: ${GRACE_PERIOD}s

# Configuration Values
OS=${OS:-<not set>}
AUTOFIX=${AUTOFIX:-<not set>}
DISABLE_AUTOFIX=${DISABLE_AUTOFIX:-<not set>}
PREFERRED_KERNEL_BRANCH=${PREFERRED_KERNEL_BRANCH:-<not set>}
PREFERRED_KERNEL_TRACK=${PREFERRED_KERNEL_TRACK:-<not set>}
GRAPHICS_CHIPSET=${GRAPHICS_CHIPSET:-<not set>}
USE_MODULES=${USE_MODULES:-<not set>}

# Helper Configuration (if applicable)
UBUNTU_RELEASE_DETECTION=${UBUNTU_RELEASE_DETECTION:-<not set>}
ENFORCE_TRACK_COMPLIANCE=${ENFORCE_TRACK_COMPLIANCE:-<not set>}
INTEL_GRAPHICS_PREFERRED_TRACK=${INTEL_GRAPHICS_PREFERRED_TRACK:-<not set>}

# Environment Variable Overrides (if any)
ENV_OVERRIDE_AUTOFIX=${ENV_OVERRIDE_AUTOFIX:-<not preserved>}
ENV_OVERRIDE_DISABLE_AUTOFIX=${ENV_OVERRIDE_DISABLE_AUTOFIX:-<not preserved>}

# Test Results
Test completed successfully at $(date)
Configuration hierarchy working: YES
Environment variable preservation: $(if [[ -n "${ENV_OVERRIDE_AUTOFIX:-}" ]]; then echo "YES"; else echo "NO"; fi)
EOF
    
    if [[ -f "$test_file" ]]; then
        autofix_log "INFO" "Test file created successfully: $test_file"
        autofix_log "INFO" "File contents:"
        while IFS= read -r line; do
            autofix_log "INFO" "  $line"
        done < "$test_file"
        
        # Also output to console for immediate visibility
        echo "✅ TEST SUCCESSFUL: Configuration test completed"
        echo "📁 Test file created: $test_file"
        echo "📋 Configuration summary:"
        echo "   AUTOFIX: ${AUTOFIX:-<not set>}"
        echo "   DISABLE_AUTOFIX: ${DISABLE_AUTOFIX:-<not set>}"
        echo "   Environment overrides preserved: $(if [[ -n "${ENV_OVERRIDE_AUTOFIX:-}" ]]; then echo "YES"; else echo "NO"; fi)"
        
        return 0
    else
        autofix_log "ERROR" "Failed to create test file: $test_file"
        return 1
    fi
}

# Execute with grace period management
autofix_log "INFO" "Test config dummy requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "test-config-dummy" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_test_config_actions"
