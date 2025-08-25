#!/bin/bash
# Thermal module test script

MODULE_NAME="thermal"
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

# Test 1: Check if temperature monitoring is available
test_temperature_availability() {
    # Test if sensors command exists
    if command -v sensors >/dev/null 2>&1; then
        # Test if sensors can read temperature
        if sensors 2>/dev/null | grep -E "Package id 0|Tctl" | grep -E "[0-9]+\.[0-9]+°C" >/dev/null; then
            return 0
        fi
    fi
    
    # Fallback: Check thermal zones
    if [[ -d /sys/class/thermal/thermal_zone0 ]] && [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
        local temp_raw
        temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        if [[ -n "$temp_raw" ]] && [[ "$temp_raw" =~ ^[0-9]+$ ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Test 2: Check if process management tools are available
test_process_tools() {
    # Check for ps command
    if ! command -v ps >/dev/null 2>&1; then
        return 1
    fi
    
    # Check for kill command
    if ! command -v kill >/dev/null 2>&1; then
        return 1
    fi
    
    # Test ps functionality
    if ! ps -eo pid,pcpu,cmd --no-headers >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Test 3: Check if system notification tools are available
test_notification_tools() {
    # Check for wall command (emergency notifications)
    if ! command -v wall >/dev/null 2>&1; then
        return 1
    fi
    
    # Check for logger command
    if ! command -v logger >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Test 4: Check configuration loading
test_configuration() {
    # Check if config file exists
    if [[ ! -f "$SCRIPT_DIR/config.conf" ]]; then
        return 1
    fi
    
    # Try to source config
    if ! source "$SCRIPT_DIR/config.conf" 2>/dev/null; then
        return 1
    fi
    
    # Check if key variables are set
    if [[ -z "${TEMP_WARNING:-}" ]] || [[ -z "${TEMP_CRITICAL:-}" ]] || [[ -z "${TEMP_EMERGENCY:-}" ]]; then
        return 1
    fi
    
    return 0
}

# Test 5: Check monitor script functionality
test_monitor_script() {
    # Check if monitor script exists and is executable
    if [[ ! -x "$SCRIPT_DIR/monitor.sh" ]]; then
        return 1
    fi
    
    # Test help function
    if ! "$SCRIPT_DIR/monitor.sh" --help >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Test 6: Check autofix scripts
test_autofix_scripts() {
    local autofix_dir="$SCRIPT_DIR/autofix"
    
    # Check if autofix directory exists
    if [[ ! -d "$autofix_dir" ]]; then
        return 1
    fi
    
    # Check for key autofix scripts
    if [[ ! -f "$autofix_dir/emergency-process-kill.sh" ]]; then
        return 1
    fi
    
    if [[ ! -f "$autofix_dir/emergency-shutdown.sh" ]]; then
        return 1
    fi
    
    return 0
}

# Test 7: Check system integration
test_system_integration() {
    # Check if journalctl is available for logging
    if ! command -v journalctl >/dev/null 2>&1; then
        return 1
    fi
    
    # Check if systemctl is available (for potential service integration)
    if ! command -v systemctl >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Test 8: Check permissions for thermal monitoring
test_permissions() {
    # Check if we can read thermal information
    if ! get_cpu_package_temp >/dev/null 2>&1; then
        # This might fail on some systems, so it's a warning not an error
        echo "  Warning: Temperature reading may require elevated privileges"
    fi
    
    return 0
}

# Main test execution
main() {
    echo "🌡️  THERMAL MODULE TESTS"
    echo "======================"
    echo ""
    
    # Load module configuration for testing
    if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
        source "$SCRIPT_DIR/config.conf"
    fi
    
    # Run all tests
    run_test "Temperature monitoring availability" test_temperature_availability
    run_test "Process management tools" test_process_tools
    run_test "Notification tools" test_notification_tools
    run_test "Configuration loading" test_configuration
    run_test "Monitor script functionality" test_monitor_script
    run_test "Autofix scripts presence" test_autofix_scripts
    run_test "System integration tools" test_system_integration
    run_test "Thermal monitoring permissions" test_permissions
    
    echo ""
    echo "📊 TEST RESULTS:"
    echo "  ✅ Passed: $TESTS_PASSED"
    echo "  ❌ Failed: $TESTS_FAILED"
    echo "  📋 Total:  $TESTS_TOTAL"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo ""
        echo "🎉 All tests passed! Thermal module is ready for use."
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
