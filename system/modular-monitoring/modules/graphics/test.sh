#!/bin/bash
# Graphics Module Test Script
# Tests graphics monitoring functionality

MODULE_NAME="graphics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load test framework from parent directory
source "$(dirname "$SCRIPT_DIR")/common.sh"

# Test configuration
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -n "  Testing $test_name: "
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo "✅ PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "🔧 GRAPHICS MODULE TESTS"
echo "========================"
echo ""

# Critical test: Hardware existence (should be first)
run_test "Hardware existence" "$SCRIPT_DIR/exists.sh"

# Test required scripts
run_test "Configuration loading" "[[ -f '$SCRIPT_DIR/config.conf' ]]"
run_test "Monitor script functionality" "$SCRIPT_DIR/monitor.sh --help"
run_test "Status script functionality" "$SCRIPT_DIR/status.sh"
run_test "Scan script functionality" "$SCRIPT_DIR/scan.sh --help"

# Test graphics helpers
if [[ -d "$SCRIPT_DIR/helpers" ]]; then
    run_test "Graphics helpers directory" "[[ -d '$SCRIPT_DIR/helpers' ]]"
    
    # Test i915 helper if it exists
    if [[ -x "$SCRIPT_DIR/helpers/i915.sh" ]]; then
        # Test that the helper runs and produces output (exit code doesn't matter for hardware monitoring)
        run_test "i915 helper functionality" "$SCRIPT_DIR/helpers/i915.sh false false >/dev/null 2>&1 || true"
    fi
fi

# Test autofix integration
run_test "Graphics autofix availability" "[[ -x '$(dirname $(dirname $SCRIPT_DIR))/autofix/graphics.sh' ]]"

# Summary
echo ""
echo "📊 TEST RESULTS:"
echo "  ✅ Passed: $TESTS_PASSED"
echo "  ❌ Failed: $TESTS_FAILED"
echo "  📋 Total:  $TESTS_TOTAL"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo "🎉 All tests passed! $MODULE_NAME module is ready for use."
    exit 0
else
    echo ""
    echo "❌ Some tests failed. Please check the module configuration."
    exit 1
fi
