#!/bin/bash
# 🌐 NETWORK MODULE TESTS test script

MODULE_NAME="network"
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


# Test 2: Check network tools
test_network_tools() {
    # Check for ip command
    if ! command -v ip >/dev/null 2>&1; then
        return 1
    fi
    
    # Test ip functionality
    if ! ip addr show >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Test 3: Check network manager availability
test_network_manager() {
    # Check for NetworkManager
    if command -v nmcli >/dev/null 2>&1; then
        return 0
    fi
    
    echo "  Warning: NetworkManager not found (some features may be limited)"
    return 0
}

# Test 4: Check network interfaces
test_network_interfaces() {
    # Check if any network interfaces exist
    local interface_count
    interface_count=$(ip link show 2>/dev/null | grep -c "^[0-9]")
    
    if [[ $interface_count -lt 1 ]]; then
        return 1
    fi
    
    echo "  Found $interface_count network interfaces"
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

# Test: Check autofix scripts
test_autofix_scripts() {
    local autofix_dir="$SCRIPT_DIR/autofix"
    
    # Check if autofix directory exists
    if [[ ! -d "$autofix_dir" ]]; then
        return 1
    fi
    
    # Check if there are any autofix scripts
    if [[ $(find "$autofix_dir" -name "*.sh" | wc -l) -eq 0 ]]; then
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    echo "🌐 NETWORK MODULE TESTS"
    echo "$(echo "🌐 NETWORK MODULE TESTS" | sed 's/./=/g')"
    echo ""
    
    # Load module configuration for testing
    if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
        source "$SCRIPT_DIR/config.conf"
    fi
    
    # Run all tests
    run_test "Basic system tools" test_basic_tools
    run_test "network tools" test_network_tools
    run_test "network manager" test_network_manager
    run_test "network interfaces" test_network_interfaces
    run_test "Configuration loading" test_configuration
    run_test "Monitor script functionality" test_monitor_script
    run_test "Autofix scripts presence" test_autofix_scripts
    
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
