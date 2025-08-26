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
