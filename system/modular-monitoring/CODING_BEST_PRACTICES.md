# CODING BEST PRACTICES
## Security, Safety, and Quality Guidelines for Bash Scripts

---

## 🔒 SECURITY PRACTICES

### Injection Attack Prevention
- **NEVER** pass user input directly to shell commands
- **ALWAYS** validate and sanitize inputs before using them
- **AVOID** `eval`, `exec`, or dynamic command construction
- **USE** parameter expansion `${var}` instead of `$var` in complex contexts
- **VALIDATE** file paths to prevent directory traversal (`../` attacks)
- **RESTRICT** allowed characters in identifiers (alphanumeric, hyphens, underscores only)

#### Examples:
```bash
# ❌ DANGEROUS - injection risk
rm -rf "$user_input"

# ✅ SAFE - validated input
if [[ "$user_input" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    rm -rf "/safe/path/$user_input"
fi
```

### Logging Security
- **SANITIZE** log messages to prevent command injection in log content
- **AVOID** logging sensitive information (passwords, keys, personal data)
- **VALIDATE** log inputs before writing to prevent log injection

---

## ⚠️ SAFETY PRACTICES

### System Safety (Critical for Emergency Scripts)
- **NEVER** delete current system logs (`*.log` files)
- **NEVER** touch critical directories: `/boot`, `/bin`, `/sbin`, `/etc`, `/dev`, `/proc`, `/sys`, `/run`
- **NEVER** kill critical processes: init, systemd, kernel threads, SSH sessions
- **ALWAYS** validate filesystem paths before any destructive operations
- **PROTECT** user data and configuration files
- **IMPLEMENT** grace periods for emergency actions to prevent rapid repeated execution

#### Protected Process Types:
```bash
# ❌ NEVER KILL THESE
- Kernel threads: [kworker], [ksoftirqd], [migration]
- System daemons: systemd, init, dbus, NetworkManager
- SSH services: sshd (would lock out remote users)
- Low PIDs (1-100): Usually system-critical processes
```

#### Protected File Patterns:
```bash
# ❌ NEVER DELETE THESE
- Current logs: *.log (without rotation suffix)
- Configuration: /etc/*
- System binaries: /bin/*, /sbin/*, /usr/bin/*, /usr/sbin/*
- Kernel files: /boot/*, /lib/modules/*
- User data: /home/*
```

### Safe Cleanup Operations:
```bash
# ✅ SAFE to clean
find /tmp -type f -mtime +7 -delete           # Old temp files
find /var/log -name "*.log.[0-9]*" -delete    # Rotated logs only
apt-get clean                                  # Package cache
journalctl --vacuum-time=30d                  # Old journal entries
```

---

## 🛡️ ERROR HANDLING

### Script Robustness
- **ALWAYS** use `set -euo pipefail` for safer execution
- **VALIDATE** all function arguments before use
- **CHECK** command success with explicit conditions
- **PROVIDE** meaningful error messages with context
- **LOG** both successful actions and failures

#### Error Handling Pattern:
```bash
set -euo pipefail

function_name() {
    local param1="$1"
    local param2="$2"
    
    # Validate inputs
    if [[ -z "$param1" ]]; then
        log_error "Missing required parameter"
        return 1
    fi
    
    # Safe operation with error checking
    if ! some_command "$param1"; then
        log_error "Failed to execute command for $param1"
        return 1
    fi
    
    log_info "Successfully processed $param1"
    return 0
}
```

---

## 📝 DOCUMENTATION STANDARDS

### Script Headers
Every script MUST have:
- **Purpose**: What the script does and why it exists
- **Safety warnings**: For dangerous operations
- **Usage examples**: Clear command-line examples
- **Security considerations**: Known risks and mitigations
- **Bash concepts**: Explanations for beginners

### Function Documentation
Every function MUST have:
- **Purpose**: What the function accomplishes
- **Parameters**: Each parameter with type and description
- **Returns**: Return values and their meanings
- **Behavior**: Step-by-step description of what happens
- **Security notes**: Injection risks, validation needs
- **Examples**: How to call the function

### Documentation Template:
```bash
#!/bin/bash
# =============================================================================
# SCRIPT_NAME - Brief description
# =============================================================================
#
# PURPOSE:
#   Detailed explanation of what this script does and why it exists.
#
# ⚠️  SAFETY WARNING: (if applicable)
#   Specific warnings about dangerous operations.
#
# USAGE:
#   script_name <required_args> [optional_args]
#
# SECURITY CONSIDERATIONS:
#   - List of security risks and mitigations
#
# BASH CONCEPTS FOR BEGINNERS:
#   - Explanations of bash-specific concepts used
#
# =============================================================================

# =============================================================================
# function_name() - Brief function description
# =============================================================================
#
# PURPOSE:
#   What this function does.
#
# PARAMETERS:
#   $1 - param_name: Description and type
#   $2 - param_name: Description and type
#
# RETURNS:
#   0 - Success condition
#   1 - Error condition
#
# SECURITY CONSIDERATIONS:
#   - Specific security concerns for this function
#
# EXAMPLE:
#   function_name "arg1" "arg2"
#
function_name() {
    # Implementation
}
```

---

## 🖥️ COMMAND-LINE INTERFACE STANDARDS

### Required Flags
Every script MUST implement:
- **`--help`**: Display comprehensive usage information and exit
- **`--dry-run`**: Show what would be executed without making changes

### Help Flag Implementation
The `--help` flag should:
- Display script purpose and description
- Show all available options and arguments
- Provide usage examples
- List any safety warnings or prerequisites
- Exit with status 0 after displaying help

### Dry-Run Flag Implementation
The `--dry-run` flag should:

#### Core Requirements
- **Set maximum debug level** for maximum output verbosity
- **Echo all commands** that would be executed (not just descriptions)
- **Show actual command variables** before execution
- **Prevent any system changes** outside of temporary files
- **Provide comprehensive logging** of what would happen

#### Implementation Pattern
```bash
#!/bin/bash

# Global variables for commands
SHUTDOWN_CMD=""
CLEANUP_CMD=""
RESTART_CMD=""

# Parse command line arguments
DRY_RUN=false
DEBUG_LEVEL=1

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            DEBUG_LEVEL=10  # Maximum debug level
            shift
            ;;
        # ... other options
    esac
done

# Function to execute commands safely
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $cmd"
        echo "[DRY-RUN] Description: $description"
        return 0
    else
        echo "Executing: $cmd"
        eval "$cmd"
        return $?
    fi
}

# Example usage in script
SHUTDOWN_CMD="systemctl poweroff"
execute_command "$SHUTDOWN_CMD" "Shutdown system"
```

#### Key Implementation Rules
1. **Store commands in variables** before execution
2. **Echo the actual variable content** in dry-run mode, not hardcoded descriptions
3. **Use the same variable** for both dry-run display and actual execution
4. **Set debug level to maximum** when `--dry-run` is active
5. **Echo all log messages** to stdout during dry-run
6. **Never execute system-changing commands** during dry-run
7. **Show complete command context** including all arguments and options

#### Example Output During Dry-Run
```bash
$ ./emergency-script.sh --dry-run
[DRY-RUN] DEBUG: Script started in dry-run mode
[DRY-RUN] DEBUG: Maximum debug level enabled
[DRY-RUN] Would execute: systemctl poweroff
[DRY-RUN] Description: Shutdown system
[DRY-RUN] Would execute: rm -rf /tmp/emergency-cache/*
[DRY-RUN] Description: Clean emergency cache files
[DRY-RUN] DEBUG: Dry-run completed - no changes made
```

---

## 📚 COMMON.SH USAGE REQUIREMENTS

### Mandatory Common.sh Usage
Every script MUST source the appropriate `common.sh` file for its component:

- **Autofix Scripts**: Must source `autofix/common.sh`
- **Monitoring Modules**: Must source `modules/common.sh`

### Why Common.sh is Required
Common.sh files provide:
- **Standardized initialization** and argument validation
- **Shared utility functions** (logging, configuration, etc.)
- **Safety mechanisms** (grace periods, dry-run support)
- **Consistent behavior** across all scripts in the component
- **Centralized configuration** management
- **Cross-script coordination** and state management

### Implementation Pattern for Autofix Scripts
```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize autofix script with common setup
init_autofix_script "$@"

# Use common functions
autofix_log "INFO" "Starting autofix action"
run_autofix_with_grace "action-name" "$CALLING_MODULE" "$GRACE_PERIOD" "action_function" "$@"
```

### Implementation Pattern for Monitoring Modules
```bash
#!/bin/bash
set -euo pipefail

MODULE_NAME="disk"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Load module configuration
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

# Use common functions
log_message "INFO" "Starting disk monitoring"
check_thresholds "$DISK_WARNING" "$DISK_CRITICAL"
```

### Implementation Pattern for Helper Scripts
```bash
#!/bin/bash
set -euo pipefail

# Helper scripts source the parent directory's common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"  # Parent directory's common.sh

# Initialize autofix script with common setup
init_autofix_script "$@"

# Helper-specific logic
perform_helper_action() {
    local issue_type="$1"
    local severity="$2"
    
    autofix_log "INFO" "Helper action: $issue_type ($severity)"
    # Implementation here
}

# Execute with grace period management
run_autofix_with_grace "helper-action" "$CALLING_MODULE" "$GRACE_PERIOD" \
    "perform_helper_action" "$ISSUE_TYPE" "$SEVERITY"
```

### Helper Script Directory Structure
```
autofix/
├── common.sh                    # Main autofix common library
├── graphics_helpers/
│   ├── i915.sh                 # Sources ../common.sh
│   ├── nvidia.sh               # Sources ../common.sh
│   └── amdgpu.sh               # Sources ../common.sh
└── display_helpers/
    ├── wayland.sh              # Sources ../common.sh
    ├── kwin.sh                 # Sources ../common.sh
    └── x11.sh                  # Sources ../common.sh
```

**CRITICAL**: Helper scripts in subfolders MUST source `../common.sh`, NOT `./common.sh`

### What Common.sh Provides

#### Autofix Common.sh Functions
- `init_autofix_script()` - Standardized initialization
- `autofix_log()` - Centralized logging with syslog integration
- `check_grace_period()` - Prevent repeated actions
- `start_grace_period()` - Track action execution
- `run_autofix_with_grace()` - Execute with safety wrapper
- `execute_command()` - Safe command execution with dry-run
- `validate_autofix_args()` - Argument validation
- `send_autofix_notification()` - Desktop notifications

#### Modules Common.sh Functions
- `load_configuration()` - 4-tier configuration hierarchy
- `log_message()` - Standardized logging
- `check_thresholds()` - Threshold validation
- `get_module_status()` - Module state management
- `hardware_detection()` - Automatic hardware detection
- `module_discovery()` - Dynamic module enablement

### Benefits of Using Common.sh
1. **Consistency**: All scripts behave the same way
2. **Maintainability**: Changes in one place affect all scripts
3. **Safety**: Built-in safety mechanisms and validation
4. **Debugging**: Standardized logging and error handling
5. **Configuration**: Centralized settings management
6. **Testing**: Common testing patterns and dry-run support

### Common Mistakes to Avoid
- **Don't duplicate** common.sh functionality in individual scripts
- **Don't skip** common.sh sourcing - it's not optional
- **Don't override** common.sh functions without good reason
- **Don't hardcode** values that common.sh provides
- **Don't bypass** safety mechanisms provided by common.sh
- **Don't create** separate common.sh files in helper directories - use parent directory's common.sh

---

## 🚨 DETAILED ERROR AND WARNING MESSAGES

### Mandatory Detailed Messaging
Every script MUST provide detailed, actionable error and warning messages instead of generic instructions like "check manually".

### Why Detailed Messages Are Required
Generic messages like "check manually" are insufficient because they:
- **Don't help users** understand what went wrong
- **Don't provide guidance** on how to resolve issues
- **Don't enable automation** or scripted responses
- **Don't improve debugging** or troubleshooting
- **Don't meet professional standards** for system administration tools

### Message Quality Standards

#### ✅ GOOD - Specific and Actionable
```bash
# Instead of: "check manually"
echo "⚠️  USB module: 15 device resets detected in last hour"
echo "   - 8 resets from USB storage device on bus 1-1.2"
echo "   - 7 resets from network adapter on bus 1-1.3"
echo "   - Threshold exceeded: 10 resets/hour"
echo "   - Recommended: Check USB cable connections and power supply"
echo "   - Run: journalctl -k --since '1 hour ago' | grep 'usb.*reset'"
```

#### ❌ BAD - Generic and Unhelpful
```bash
# Don't do this:
echo "⚠️  usb status had issues (check manually)"
echo "⚠️  $module: UNKNOWN (check manually)"
echo "Error occurred - investigate further"
```

### Required Message Components

#### 1. **Issue Summary** (What happened)
- Clear description of the problem
- Quantified impact (numbers, percentages, counts)
- Time context (when it happened)

#### 2. **Root Cause Analysis** (Why it happened)
- Specific error codes or messages
- Threshold violations with actual values
- System state at time of failure

#### 3. **Actionable Guidance** (How to fix it)
- Specific commands to run for diagnosis
- Configuration changes needed
- Manual steps required

#### 4. **Automation Hints** (For scripted responses)
- Environment variables to check
- Configuration files to examine
- Log locations to monitor

### Implementation Patterns

#### For Status Scripts
```bash
show_detailed_status() {
    local module="$1"
    local status_script="$SCRIPT_DIR/modules/$module/status.sh"
    
    if [[ -f "$status_script" && -x "$status_script" ]]; then
        echo -e "\n${BLUE}--- $module Module ---${NC}"
        
        # Capture both stdout and stderr for detailed analysis
        local output
        local exit_code
        output=$(bash "$status_script" "$since_time" "$end_time" 2>&1)
        exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}✅ $module status completed${NC}"
            echo "$output"
        else
            echo -e "${YELLOW}⚠️  $module status had issues:${NC}"
            
            # Provide specific error analysis instead of generic message
            if [[ -n "$output" ]]; then
                echo "   Error details:"
                echo "$output" | sed 's/^/   /'
            else
                echo "   No error output available"
                echo "   Run manually: $status_script --help"
                echo "   Check logs: tail -f /var/log/modular-monitor-$module.log"
            fi
            
            # Suggest specific troubleshooting steps
            echo "   Troubleshooting:"
            echo "   - Check module configuration: cat modules/$module/config.conf"
            echo "   - Verify dependencies: modules/$module/exists.sh"
            echo "   - Test module: modules/$module/test.sh"
        fi
    else
        echo -e "\n${YELLOW}⚠️  $module: No status script available${NC}"
        echo "   Expected location: $status_script"
        echo "   Create with: modules/$module/status.sh"
    fi
}
```

#### For Error Handling Functions
```bash
handle_module_error() {
    local module="$1"
    local error_code="$2"
    local error_output="$3"
    
    case $error_code in
        1)
            echo "⚠️  $module: Configuration error detected"
            echo "   - Check config file: modules/$module/config.conf"
            echo "   - Verify environment variables"
            echo "   - Run validation: modules/$module/exists.sh"
            ;;
        2)
            echo "⚠️  $module: Dependency missing"
            echo "   - Required tool not found"
            echo "   - Install missing package or verify PATH"
            echo "   - Check: modules/$module/exists.sh"
            ;;
        3)
            echo "⚠️  $module: Permission denied"
            echo "   - Script not executable: chmod +x modules/$module/*.sh"
            echo "   - Insufficient privileges for operation"
            echo "   - Check file ownership and permissions"
            ;;
        *)
            echo "⚠️  $module: Unknown error (code: $error_code)"
            if [[ -n "$error_output" ]]; then
                echo "   Error details: $error_output"
            fi
            echo "   - Check module logs for details"
            echo "   - Run with --debug for verbose output"
            ;;
    esac
}
```

#### For Threshold Violations
```bash
report_threshold_violation() {
    local metric="$1"
    local current_value="$2"
    local threshold="$3"
    local unit="$4"
    local severity="$5"
    
    echo "🚨 $severity: $metric threshold exceeded"
    echo "   Current: $current_value$unit"
    echo "   Threshold: $threshold$unit"
    echo "   Exceeded by: $((current_value - threshold))$unit"
    
    # Provide specific context
    case $metric in
        "CPU_TEMP")
            echo "   Impact: Thermal throttling may occur"
            echo "   Check: sensors, thermal zones, cooling system"
            echo "   Command: watch -n 1 'sensors | grep temp'"
            ;;
        "MEMORY_USAGE")
            echo "   Impact: System may become unresponsive"
            echo "   Check: memory-hungry processes, swap usage"
            echo "   Command: ps aux --sort=-%mem | head -10"
            ;;
        "DISK_USAGE")
            echo "   Impact: System may become unbootable"
            echo "   Check: large files, log rotation, temp files"
            echo "   Command: du -sh /* 2>/dev/null | sort -hr | head -10"
            ;;
    esac
}
```

### Fallback Guidance for Unrecoverable Errors

When detailed analysis is impossible, provide specific manual checking instructions:

#### Instead of "check manually":
```bash
echo "⚠️  Unable to determine specific issue"
echo "   Manual investigation required:"
echo "   1. Check module logs: tail -f /var/log/modular-monitor-$module.log"
echo "   2. Verify configuration: cat modules/$module/config.conf"
echo "   3. Test module directly: modules/$module/test.sh"
echo "   4. Check system resources: free, df, top"
echo "   5. Review recent changes: journalctl --since '1 hour ago'"
```

### Testing Error Message Quality

#### Checklist for Error Messages
- [ ] **Specific**: Describes exactly what went wrong
- [ ] **Quantified**: Includes numbers, percentages, or counts
- [ ] **Actionable**: Provides specific steps to resolve
- [ ] **Contextual**: Explains when and why it happened
- [ ] **Automation-friendly**: Includes commands and file paths
- [ ] **User-friendly**: Clear language without technical jargon

#### Example Test Cases
```bash
# Test error message quality
test_error_messages() {
    local module="$1"
    
    echo "Testing $module error message quality..."
    
    # Test with invalid configuration
    if ! bash "modules/$module/monitor.sh" --invalid-flag 2>&1; then
        echo "✅ Error message provided for invalid flag"
    else
        echo "❌ No error message for invalid flag"
    fi
    
    # Test with missing dependencies
    if ! bash "modules/$module/exists.sh" 2>&1; then
        echo "✅ Error message provided for missing dependencies"
    else
        echo "❌ No error message for missing dependencies"
    fi
}
```

---

## 🔧 BASH BEST PRACTICES

### Variable Handling
- **ALWAYS** quote variables: `"$var"` not `$var`
- **USE** `local` for function variables
- **PREFER** `[[ ]]` over `[ ]` for tests
- **USE** parameter expansion for string manipulation
- **VALIDATE** numeric variables before arithmetic operations

### Performance Optimization
- **AVOID** calling external commands in loops when possible
- **USE** bash built-ins instead of external commands where applicable
- **CACHE** expensive operations (like `date` calls)
- **MINIMIZE** subshell creation

### Code Quality
- **CONSISTENT** indentation (4 spaces recommended)
- **DESCRIPTIVE** variable and function names
- **SEPARATE** concerns into different functions
- **AVOID** deeply nested code structures
- **COMMENT** complex logic and edge cases

---

## 🧪 TESTING REQUIREMENTS

### Validation Checks
- **SYNTAX** checking with `bash -n script_name`
- **SHELLCHECK** for static analysis (if available)
- **DRY RUN** modes for destructive operations
- **ARGUMENT** validation testing

### Safety Testing
- **NEVER** test destructive operations on production systems
- **ALWAYS** test with non-critical test data first
- **VERIFY** safety mechanisms work as expected
- **TEST** error conditions and edge cases

---

## 🚨 EMERGENCY SCRIPT SPECIFIC RULES

### Grace Period Management
- **IMPLEMENT** grace periods for all emergency actions
- **TRACK** actions across multiple modules
- **PREVENT** rapid repeated execution of dangerous operations
- **LOG** all grace period decisions for audit

### Emergency Actions Priority
1. **Validate** all inputs and conditions
2. **Check** grace period status
3. **Identify** safest action that solves the problem
4. **Execute** with comprehensive logging
5. **Start** grace period to prevent repeats

---

## 📋 PRE-COMMIT CHECKLIST

Before committing any script changes:

- [ ] All functions have comprehensive documentation
- [ ] Security vulnerabilities reviewed and addressed
- [ ] Safety mechanisms tested (especially for destructive operations)
- [ ] Error handling covers all failure modes
- [ ] Logging provides sufficient audit trail
- [ ] Code follows style guidelines
- [ ] No hardcoded sensitive information
- [ ] Help function provides clear usage guidance
- [ ] Script tested on non-production system

---

*This document should be reviewed before documenting or modifying any script in this project.*
