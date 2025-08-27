# Autofix Scripts Directory

This directory contains all automated fix scripts for the modular monitoring system.

## 📋 **Autofix Script Requirements**

### **Mandatory Parameters**
Every autofix script **MUST** accept these parameters in order:

1. **`calling_module`** - Which module requested the autofix (e.g., "thermal", "memory", "disk")
2. **`grace_period_seconds`** - How long to wait before allowing this action again
3. **Additional parameters** - Script-specific arguments

### **Example Usage**
```bash
# Production usage
./manage-greedy-process.sh thermal 45 CPU_GREEDY 80
./disk-cleanup.sh disk 300 "/var/log"
./emergency-shutdown.sh thermal 120 "thermal_emergency"

# REQUIRED: Dry-run testing (see Testing Requirements below)
./manage-greedy-process.sh --dry-run thermal 45 CPU_GREEDY 80
./disk-cleanup.sh --dry-run disk 300 "/var/log"
./emergency-shutdown.sh --dry-run thermal 120 "thermal_emergency"
```

## 🕐 **Grace Period Management**

### **How It Works**
- **Centralized Tracking**: All grace periods are managed in `/tmp/modular-monitor-grace/`
- **Cross-Module Coordination**: If thermal and memory both call `emergency-process-kill.sh`, the grace period applies to BOTH
- **Frequency-Aware**: Grace period = configured_grace + monitor_frequency (typically +120s)
- **Automatic Cleanup**: Expired grace files are automatically cleaned up

### **Grace Period Logic**
```bash
# Example: thermal monitor calls emergency-process-kill with 45s grace
# If monitor runs every 120s, total grace = 45 + 120 = 165s
# Within 165s, ANY module calling emergency-process-kill will be blocked
```

## 🏗️ **Implementation Guide**

### **Step 1: Source Common Functions**
```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
```

### **Step 2: Validate Arguments and Handle Help**
```bash
# Handle help and dry-run options
if ! validate_autofix_args "$(basename "$0")" "$@"; then
    exit 1
fi

# Arguments are now validated and adjusted for dry-run
CALLING_MODULE="$1"
GRACE_PERIOD="$2"
# Additional args as needed (e.g., REASON="${3:-default}")
```

### **Step 3: Define Your Action Function**
```bash
perform_emergency_action() {
    local reason="$1"
    
    autofix_log "INFO" "Performing emergency action: $reason"
    
    # Your actual action logic here
    # Use autofix_log for all output instead of echo/log
    # Example: autofix_log "WARN" "Something needs attention"
    # Example: autofix_log "ERROR" "Action failed"
    
    return 0  # Success
}
```

### **Step 4: Use Grace Period Wrapper**
```bash
# Execute with grace period management
autofix_log "INFO" "Action requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "action-name" "$CALLING_MODULE" "$GRACE_PERIOD" \
    "perform_emergency_action" "$3"  # Pass additional args to your function
```

## 🔧 **Common Functions Reference**

### **Logging Functions**
```bash
# Use instead of echo, log, or logger
autofix_log "DEBUG" "Debug information"    # Development info
autofix_log "INFO"  "Normal operation"     # Standard messages  
autofix_log "WARN"  "Warning condition"    # Potential issues
autofix_log "ERROR" "Error occurred"       # Failures
```

### **Grace Period Management**
```bash
# Automatic grace period handling (use run_autofix_with_grace)
run_autofix_with_grace "action-name" "$CALLING_MODULE" "$GRACE_PERIOD" "function_name" [args...]

# Manual grace period checking (advanced use only)
if check_grace_period "action-name" "$grace_seconds" "$module"; then
    autofix_log "INFO" "Still in grace period, skipping"
    exit 2
fi
start_grace_period "action-name" "$grace_seconds" "$module"
```

### **Argument Validation**
```bash
# Validate calling module and grace period arguments
if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1  # Function prints error message and usage
fi
```

## 📁 **Discovery and Documentation**

### **Script Self-Documentation**
All autofix scripts are self-documented. Use `--help` to see their specific purpose, parameters, and usage:

```bash
# Get detailed help for any script
./manage-greedy-process.sh --help
./emergency-shutdown.sh --help
./disk-cleanup.sh --help

# List all available scripts
ls -1 *.sh | grep -v common.sh | head -10
```

### **Dynamic Discovery**
The test system automatically discovers all autofix scripts:

```bash
# Test all autofix scripts
./test.sh --autofix-only

# See what scripts were discovered
./test.sh --list --include-autofix
```

## 🏛️ **Autofix Helper Architecture**

### **Helper Folder Pattern**
For autofix scripts that need chipset/vendor-specific logic, use the helper folder pattern:

```
autofix/
├── main-autofix-script.sh           # Main orchestrator script
├── main-autofix-script_helpers/     # Helper folder (note the _helpers suffix)
│   ├── chipset1.sh                  # Specific implementation (e.g., i915.sh)
│   ├── chipset2.sh                  # Another implementation (e.g., nvidia.sh)
│   └── chipset3.sh                  # Stub implementation (e.g., amdgpu.sh)
└── other-simple-autofix.sh          # Scripts without helpers
```

### **Example: Graphics Autofix with Helpers**
```
autofix/
├── graphics.sh                    # Main graphics autofix orchestrator
├── graphics_helpers/              # Graphics chipset helpers
│   ├── i915.sh                           # Intel graphics autofix (TESTED)
│   ├── nvidia.sh                         # NVIDIA graphics autofix (STUB)
│   └── amdgpu.sh                         # AMD graphics autofix (STUB)
├── display-autofix.sh                     # Main display autofix orchestrator  
├── display-autofix_helpers/               # Display system helpers
│   ├── wayland.sh                        # Wayland display server (TESTED)
│   ├── kwin.sh                           # KDE KWin compositor (TESTED)
│   ├── x11.sh                            # X11 display server (STUB)
│   └── gnome.sh                          # GNOME Shell compositor (STUB)
└── emergency-shutdown.sh                  # Simple script (no helpers needed)
```

### **Helper Script Requirements**
Helper scripts follow the same autofix conventions:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/common.sh"

# Initialize autofix script with common setup
init_autofix_script "$@"

# Additional arguments specific to this helper
ISSUE_TYPE="${3:-graphics_error}"
SEVERITY="${4:-unknown}"

# Helper-specific autofix logic
perform_helper_autofix() {
    local issue_type="$1"
    local severity="$2"
    
    # Implement chipset/vendor-specific logic here
    autofix_log "INFO" "Helper autofix: $issue_type ($severity)"
    
    # Use existing autofix scripts when possible
    # Example: "$autofix_dir/i915-dkms-rebuild.sh" "$CALLING_MODULE" 300
}

# Execute with grace period management
run_autofix_with_grace "helper-autofix" "$CALLING_MODULE" "$GRACE_PERIOD" \
    "perform_helper_autofix" "$ISSUE_TYPE" "$SEVERITY"
```

### **Main Script Architecture**
Main autofix scripts detect hardware/configuration and route to helpers:

```bash
#!/bin/bash
# graphics.sh example

# Auto-detect or use config
GRAPHICS_CHIPSET="${GRAPHICS_CHIPSET:-auto}"
if [[ "$GRAPHICS_CHIPSET" == "auto" ]]; then
    # Detection logic here
    if lsmod | grep -q "i915"; then
        GRAPHICS_CHIPSET="i915"
    elif lsmod | grep -q "nvidia"; then
        GRAPHICS_CHIPSET="nvidia"
    fi
fi

# Route to appropriate helper
helper_script="$SCRIPT_DIR/graphics_helpers/${GRAPHICS_CHIPSET}.sh"
if [[ -x "$helper_script" ]]; then
    "$helper_script" "$CALLING_MODULE" "$GRACE_PERIOD" "$ISSUE_TYPE" "$SEVERITY"
else
    autofix_log "ERROR" "No helper available for: $GRAPHICS_CHIPSET"
    exit 1
fi
```

### **When to Use Helpers**
Use the helper pattern when:
- **Hardware-specific logic**: Different chipsets need different approaches
- **Vendor-specific tools**: Intel vs NVIDIA vs AMD require different commands
- **Multiple implementations**: Wayland vs X11, different compositors
- **Future extensibility**: Want to support new hardware/software variants

**Don't use helpers for:**
- Simple, universal scripts (disk cleanup, process management)
- Single-purpose tools that work the same everywhere
- Scripts with only one implementation

### **Stub Implementation Guidelines**
When creating stubs for untested hardware/software:

1. **Clear warnings**: Mark as STUB in filename, comments, and logs
2. **Implementation roadmap**: Document what needs to be implemented
3. **Required tools**: List the tools/commands needed for real implementation
4. **Safe defaults**: Return success to avoid breaking the autofix chain
5. **Helpful errors**: Log informative messages about the missing implementation

## 🔧 **Converting Existing Scripts**

### **Before (Old Style)**
```bash
#!/bin/bash
# emergency-process-kill.sh
kill_process() {
    # Direct action
    killall high_cpu_process
}
kill_process
```

### **After (New Style)**
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Validate arguments
if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1
fi

CALLING_MODULE="$1"
GRACE_PERIOD="$2"
REASON="${3:-emergency}"

kill_process() {
    local reason="$1"
    autofix_log "INFO" "Killing processes: $reason"
    killall high_cpu_process
    return $?
}

# Execute with grace period
run_autofix_with_grace "emergency-process-kill" "$CALLING_MODULE" "$GRACE_PERIOD" \
    "kill_process" "$REASON"
```

## 📊 **Monitoring Grace Periods**

### **Check Active Grace Periods**
```bash
ls -la /tmp/modular-monitor-grace/
```

### **View Grace Period Details**
```bash
cat /tmp/modular-monitor-grace/emergency-process-kill.grace
# Output: 1693056000|thermal|45
# Format: timestamp|calling_module|grace_period_seconds
```

### **View Autofix Logs**
```bash
tail -f /var/log/modular-monitor-autofix.log
```

## ⚠️ **Important Notes**

1. **Backwards Compatibility**: Old autofix scripts will continue to work but won't have grace period protection
2. **Module Independence**: Each module can configure different grace periods for the same action
3. **System Frequency**: Default monitor frequency is 120s - adjust `DEFAULT_MONITOR_FREQUENCY_SECONDS` if changed
4. **Grace File Cleanup**: Files older than 24 hours are automatically cleaned up
5. **Log Rotation**: Ensure `/var/log/modular-monitor-autofix.log` is included in log rotation

---

**Remember**: Grace periods protect against rapid-fire autofix execution while allowing different modules to coordinate their emergency responses effectively.
