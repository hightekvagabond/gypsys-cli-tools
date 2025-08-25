#!/bin/bash
# USB module test script

MODULE_NAME="usb"
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

# Test 1: Check if USB monitoring tools exist
test_usb_tools() {
    # Check for lsusb command
    if ! command -v lsusb >/dev/null 2>&1; then
        return 1
    fi
    
    # Test lsusb functionality
    if ! lsusb >/dev/null 2>&1; then
        return 1
    fi
    
    # Check for usb-devices (optional but helpful)
    if ! command -v usb-devices >/dev/null 2>&1; then
        echo "  Warning: usb-devices not found (device identification will be limited)"
    fi
    
    return 0
}

# Test 2: Check if kernel USB logs are accessible
test_usb_logs() {
    # Check if journalctl can access kernel logs
    if ! command -v journalctl >/dev/null 2>&1; then
        return 1
    fi
    
    # Test if we can read kernel logs (may need privileges)
    if ! journalctl -k --no-pager -n 1 >/dev/null 2>&1; then
        echo "  Warning: Cannot access kernel logs (may need elevated privileges)"
        # Don't fail the test as this might work when run properly
    fi
    
    return 0
}

# Test 3: Check USB device detection
test_usb_detection() {
    # Check if any USB devices are connected
    local device_count
    device_count=$(lsusb 2>/dev/null | wc -l)
    
    if [[ $device_count -lt 1 ]]; then
        return 1
    fi
    
    echo "  Found $device_count USB devices"
    return 0
}

# Test 4: Check network management tools (for autofix)
test_network_tools() {
    # Check for nmcli (NetworkManager)
    if command -v nmcli >/dev/null 2>&1; then
        return 0
    fi
    
    # Check for ip command (fallback)
    if command -v ip >/dev/null 2>&1; then
        return 0
    fi
    
    echo "  Warning: No network management tools found (autofix may be limited)"
    return 1
}

# Test 5: Check configuration loading
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
    if [[ -z "${USB_RESET_WARNING:-}" ]] || [[ -z "${USB_RESET_CRITICAL:-}" ]]; then
        return 1
    fi
    
    return 0
}

# Test 6: Check monitor script functionality
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

# Test 7: Check autofix scripts
test_autofix_scripts() {
    local autofix_dir="$SCRIPT_DIR/autofix"
    
    # Check if autofix directory exists
    if [[ ! -d "$autofix_dir" ]]; then
        return 1
    fi
    
    # Check for key autofix scripts
    if [[ ! -f "$autofix_dir/storage-reset.sh" ]]; then
        return 1
    fi
    
    if [[ ! -f "$autofix_dir/network-disconnect.sh" ]]; then
        return 1
    fi
    
    return 0
}

# Test 8: Check USB device identification functionality
test_device_identification() {
    # Test if we can parse USB device information
    local test_output
    test_output=$(lsusb 2>/dev/null | head -1)
    
    if [[ -z "$test_output" ]]; then
        return 1
    fi
    
    # Test if we can extract bus and device numbers
    local bus_dev
    bus_dev=$(echo "$test_output" | grep -o "Bus [0-9]* Device [0-9]*")
    
    if [[ -z "$bus_dev" ]]; then
        return 1
    fi
    
    return 0
}

# Test 9: Check USB subsystem accessibility
test_usb_subsystem() {
    # Check if USB sysfs is accessible
    if [[ ! -d /sys/bus/usb ]]; then
        return 1
    fi
    
    # Check if we can list USB devices via sysfs
    if [[ ! -r /sys/bus/usb/devices ]]; then
        echo "  Warning: USB sysfs may not be fully accessible"
    fi
    
    return 0
}

# Main test execution
main() {
    echo "🔌 USB MODULE TESTS"
    echo "=================="
    echo ""
    
    # Load module configuration for testing
    if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
        source "$SCRIPT_DIR/config.conf"
    fi
    
    # Run all tests
    run_test "USB monitoring tools" test_usb_tools
    run_test "USB kernel log access" test_usb_logs
    run_test "USB device detection" test_usb_detection
    run_test "Network management tools" test_network_tools
    run_test "Configuration loading" test_configuration
    run_test "Monitor script functionality" test_monitor_script
    run_test "Autofix scripts presence" test_autofix_scripts
    run_test "Device identification" test_device_identification
    run_test "USB subsystem access" test_usb_subsystem
    
    echo ""
    echo "📊 TEST RESULTS:"
    echo "  ✅ Passed: $TESTS_PASSED"
    echo "  ❌ Failed: $TESTS_FAILED"
    echo "  📋 Total:  $TESTS_TOTAL"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo ""
        echo "🎉 All tests passed! USB module is ready for use."
        echo ""
        echo "💡 TIP: Run with elevated privileges to access all USB monitoring features."
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
