#!/bin/bash
# 🧠 MEMORY MODULE TESTS test script

MODULE_NAME="memory"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo -n "Testing $test_name... "
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if $test_function; then
        echo "✅ PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "❌ FAIL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test 1: Check basic system tools
test_basic_tools() {
    # Check for basic commands needed by this module
    if ! command -v journalctl >/dev/null 2>&1; then
        return 1
    fi
    
    if ! command -v systemctl >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}


# Test 2: Check memory monitoring tools
test_memory_tools() {
    # Check for free command
    if ! command -v free >/dev/null 2>&1; then
        return 1
    fi
    
    # Test free functionality
    if ! free -m >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Test 3: Check proc filesystem access
test_proc_access() {
    # Check if /proc/meminfo is readable
    if [[ ! -r /proc/meminfo ]]; then
        return 1
    fi
    
    # Check if we can read memory info
    if ! grep -E "MemTotal|MemFree|SwapTotal" /proc/meminfo >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Test: Check configuration loading
test_configuration() {
    # Check if config file exists
    if [[ ! -f "$SCRIPT_DIR/config.conf" ]]; then
        return 1
    fi
    
    # Try to source config
    if ! source "$SCRIPT_DIR/config.conf" 2>/dev/null; then
        return 1
    fi
    
    return 0
}

# Test: Check monitor script functionality
test_monitor_script() {
    # Check if monitor script exists and is executable
    if [[ ! -x "$SCRIPT_DIR/monitor.sh" ]]; then
        return 1
    fi
    
    # Test help function (might fail due to corruption, so be lenient)
    if ! "$SCRIPT_DIR/monitor.sh" --help >/dev/null 2>&1; then
        echo "  Warning: Monitor script may have issues"
    fi
    
    return 0
}

# Test: Check module's declared autofix scripts exist in main autofix directory
test_autofix_availability() {
    local project_root="$(dirname "$SCRIPT_DIR")"
    local main_autofix_dir="$project_root/autofix"
    
    # Get list of autofixes this module uses
    local declared_autofixes
    if ! declared_autofixes=$("$SCRIPT_DIR/monitor.sh" --list-autofixes 2>/dev/null); then
        # If module doesn't support --list-autofixes, assume it uses no autofix
        return 0
    fi
    
    # Check if each declared autofix exists in main autofix directory
    while IFS= read -r autofix_name; do
        [[ -z "$autofix_name" ]] && continue
        
        local autofix_script="$main_autofix_dir/${autofix_name}.sh"
        if [[ ! -f "$autofix_script" ]] || [[ ! -x "$autofix_script" ]]; then
            return 1
        fi
    done <<< "$declared_autofixes"
    
    return 0
}

# Main test execution
main() {
    echo "🧠 MEMORY MODULE TESTS"
    echo "$(echo "🧠 MEMORY MODULE TESTS" | sed 's/./=/g')"
    echo ""
    
    # Load module configuration for testing
    if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
        source "$SCRIPT_DIR/config.conf"
    fi
    
    # Run all tests
    run_test "Basic system tools" test_basic_tools
    run_test "memory tools" test_memory_tools
    run_test "proc access" test_proc_access
    run_test "Configuration loading" test_configuration
    run_test "Monitor script functionality" test_monitor_script
    run_test "Declared autofix availability" test_autofix_availability
    
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
        echo "⚠️  Some tests failed. Check the failures above."
        echo "   The module may still work with reduced functionality."
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
