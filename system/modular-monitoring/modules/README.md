# Monitoring Modules

This directory contains all the monitoring modules for the modular monitoring system. Each module is responsible for monitoring a specific aspect of the system (hardware, software, or system component) and can operate independently.

## 📁 What This Folder Contains

### Module Types
- **Hardware Monitors**: Check physical components (thermal, i915 GPU, USB devices, etc.)
- **System Monitors**: Monitor OS-level resources (memory, disk, network, kernel)
- **Service Monitors**: Monitor running services and processes
- **Special Modules**: Testing and validation modules (nonexistent)

### Common Files
- **`common.sh`**: Shared functions and framework used by all modules
- **Individual Module Folders**: Each contains a complete monitoring module

## 🧩 Available Modules

To see all available modules and their status:
```bash
# List all modules and their enabled status
../monitor.sh --list

# See individual module documentation
ls */README.md

# Test individual module hardware detection
./MODULE_NAME/exists.sh
```

## 🏗️ Module Architecture

Each module follows a standardized structure:

```
modules/MODULE_NAME/
├── exists.sh           # Hardware/software existence check (REQUIRED)
├── monitor.sh          # Main monitoring script
├── status.sh           # Status reporting script
├── test.sh             # Module testing script
├── config.conf         # Module-specific configuration
├── README.md           # Module documentation
└── autofix/            # Automated fix scripts directory
    ├── action1.sh
    ├── action2.sh
    └── ...
```

### Script Execution Flow
1. **`exists.sh`** - First check: Does required hardware/software exist?
2. **`monitor.sh`** - Main monitoring: Check status, apply fixes if needed
3. **`status.sh`** - Reporting: Show detailed status information
4. **`test.sh`** - Validation: Test module functionality

## 🔧 Creating New Modules

### Step 1: Create Module Directory
```bash
mkdir modules/NEW_MODULE_NAME
cd modules/NEW_MODULE_NAME
```

### Step 2: Create exists.sh (CRITICAL FIRST STEP)
This script must determine if the hardware/software this module monitors actually exists on the system.

```bash
#!/bin/bash
# Hardware existence check for NEW_MODULE_NAME monitoring module

MODULE_NAME="new_module_name"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

check_hardware() {
    # Add specific checks for your module's requirements
    # Examples:
    # - Hardware devices: lspci | grep -i "device_name"
    # - Kernel modules: lsmod | grep "module_name"
    # - System files: [[ -r "/sys/class/something" ]]
    # - Commands: command -v tool_name >/dev/null
    # - Services: systemctl is-active service_name
    
    # Return 0 if hardware exists, 1 if not found
    return 0
}

# When run directly, check hardware and exit with appropriate code
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if check_hardware; then
        echo "✅ NEW_MODULE_NAME hardware detected"
        exit 0
    else
        echo "❌ NEW_MODULE_NAME hardware not found"
        exit 1
    fi
fi
```

### Step 3: Create monitor.sh
Main monitoring script with standardized interface:

```bash
#!/bin/bash
# NEW_MODULE_NAME monitoring module

MODULE_NAME="new_module_name"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

# Parse command line arguments
parse_args() {
    AUTO_FIX_ENABLED=true
    STATUS_MODE=false
    START_TIME=""
    END_TIME=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-auto-fix)
                AUTO_FIX_ENABLED=false
                shift
                ;;
            --start-time)
                START_TIME="$2"
                shift 2
                ;;
            --end-time)
                END_TIME="$2"
                shift 2
                ;;
            --status)
                STATUS_MODE=true
                AUTO_FIX_ENABLED=false
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << 'EOH'
NEW_MODULE_NAME Monitor Module

USAGE:
    ./monitor.sh [OPTIONS]

OPTIONS:
    --no-auto-fix       Disable automatic fix actions
    --start-time TIME   Set monitoring start time for analysis
    --end-time TIME     Set monitoring end time for analysis
    --status            Show detailed status information instead of monitoring
    --help              Show this help message

EXAMPLES:
    ./monitor.sh                                    # Normal monitoring with autofix
    ./monitor.sh --no-auto-fix                     # Monitor only, no autofix
    ./monitor.sh --start-time "1 hour ago"         # Analyze last hour
    ./monitor.sh --status --start-time "1 hour ago" # Show status for last hour

EOH
}

# Main monitoring logic
check_status() {
    log "Checking NEW_MODULE_NAME status..."
    
    # Add your monitoring logic here
    # Examples:
    # - Check hardware status
    # - Parse log files
    # - Test functionality
    # - Check thresholds
    
    # Use send_alert for notifications:
    # send_alert "warning" "Issue detected"
    # send_alert "critical" "Critical issue"
    
    log "NEW_MODULE_NAME status check complete"
    return 0
}

show_status() {
    local start_time="${START_TIME:-${DEFAULT_STATUS_START_TIME:-1 hour ago}}"
    local end_time="${END_TIME:-${DEFAULT_STATUS_END_TIME:-now}}"
    
    echo "=== NEW_MODULE_NAME MODULE STATUS ==="
    echo "Time range: $start_time to $end_time"
    echo ""
    
    # Call monitoring function in status mode
    AUTO_FIX_ENABLED=false
    check_status
}

# Initialize framework
init_framework "$MODULE_NAME"
make_autofix_executable

# Parse arguments
parse_args "$@"

# Module validation
validate_module "$MODULE_NAME"

# Check if required hardware exists
if ! "$SCRIPT_DIR/exists.sh" >/dev/null 2>&1; then
    log "Required hardware not detected - skipping $MODULE_NAME monitoring"
    exit 0
fi

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$STATUS_MODE" == "true" ]]; then
        show_status
    else
        check_status
    fi
fi
```

### Step 4: Create status.sh
Simplified wrapper that calls monitor.sh in status mode:

```bash
#!/bin/bash
# Module status script - simplified to use monitor.sh --status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Call the monitor script in status mode
"$SCRIPT_DIR/monitor.sh" --status --start-time "$1" --end-time "$2"
```

### Step 5: Create test.sh
Comprehensive testing script:

```bash
#!/bin/bash
# NEW_MODULE_NAME module tests

MODULE_NAME="new_module_name"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test configuration
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test functions
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -n "Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo "✅ PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "❌ FAIL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

echo "🔧 NEW_MODULE_NAME MODULE TESTS"
echo "==============================="
echo ""

# Critical test: Hardware existence (should be first)
run_test "Hardware existence" "$SCRIPT_DIR/exists.sh"

# Add module-specific tests
run_test "Configuration loading" "[[ -f '$SCRIPT_DIR/config.conf' ]]"
run_test "Monitor script functionality" "$SCRIPT_DIR/monitor.sh --help"
run_test "Status script functionality" "$SCRIPT_DIR/status.sh"

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
```

### Step 6: Create config.conf
Module-specific configuration:

```bash
# NEW_MODULE_NAME Module Configuration

# Enable/disable autofix for this module
ENABLE_NEW_MODULE_AUTOFIX=true

# Module-specific thresholds and settings
# (Add your configuration variables here)

# Time ranges for analysis
DEFAULT_ANALYSIS_TIMESPAN="1 hour ago"
DEFAULT_STATUS_START_TIME="1 hour ago"
DEFAULT_STATUS_END_TIME="now"
```

### Step 7: Create README.md
Document your module:

```markdown
# NEW_MODULE_NAME Monitoring Module

## Purpose
Brief description of what this module monitors.

## Features
- List key monitoring capabilities
- Autofix actions available
- Alert conditions

## Configuration
Key configuration options in config.conf.

## Usage
How to run and test the module.

## Hardware Requirements
What hardware/software must be present.
```

### Step 8: Enable the Module
```bash
# Create symlink to enable the module
cd ../../config
ln -sf ../modules/NEW_MODULE_NAME/config.conf NEW_MODULE_NAME.enabled
```

## 📋 Development Best Practices

### Code Standards
- **Bash Best Practices**: Use `set -euo pipefail`, quote variables, check return codes
- **Error Handling**: Always use the `log` and `error` functions from common.sh
- **Hardware Checks**: ALWAYS check if hardware exists before monitoring
- **Configuration**: Make everything configurable, avoid hardcoded values
- **Testing**: Test both positive and negative cases

### Naming Conventions
- **Module Names**: Use lowercase with hyphens (e.g., `cpu-load`, `gpu-nvidia`)
- **Function Names**: Use snake_case (e.g., `check_temperature`, `send_notification`)
- **Variables**: Use UPPER_CASE for configuration, lower_case for local variables
- **File Names**: Follow the standard structure exactly

### Integration Requirements
- **Framework Integration**: Always source `../common.sh` and use provided functions
- **Argument Parsing**: Support all standard flags (`--help`, `--status`, `--no-auto-fix`, etc.)
- **Exit Codes**: Use appropriate exit codes (0 = success, 1 = failure, 2 = skipped)
- **Logging**: Use systemd journal via `logger` (handled by common.sh)

### Testing Guidelines
1. **Hardware Existence**: First test should always be "does the hardware exist?"
2. **Functionality**: Test that monitoring logic works correctly
3. **Configuration**: Verify all config options are respected
4. **Error Conditions**: Test what happens when things go wrong
5. **Integration**: Test with the main orchestrator

### Autofix Guidelines
- **Separate Scripts**: Each autofix action gets its own script in `autofix/`
- **Idempotent**: Autofix scripts should be safe to run multiple times
- **Configurable**: Always check if autofix is enabled before running
- **Logging**: Log all autofix actions clearly
- **Conservative**: Better to alert than to break something

### Security Considerations
- **Privileges**: Run with minimum required privileges
- **Input Validation**: Validate all inputs and time ranges
- **File Permissions**: Ensure scripts are not world-writable
- **Sensitive Data**: Never log sensitive information

## 🚀 Future Migration Notes

When migrating to Python (planned):
- The module structure and interface will remain the same
- `exists.py`, `monitor.py`, `status.py`, `test.py` will replace bash scripts
- Configuration will move to YAML/TOML format
- All modules will be updated simultaneously to maintain compatibility

---

**Remember**: The `exists.sh` script is the foundation of every module. If you can't detect the hardware, the module shouldn't run!
