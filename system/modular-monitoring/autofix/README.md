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
./emergency-process-kill.sh thermal 45 "high_temperature"
./disk-cleanup.sh disk 300 "/var/log"
./memory-cleanup.sh memory 120
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

### **Step 2: Validate Arguments**
```bash
# Validate required arguments
if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1
fi

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

## 📁 **Current Autofix Scripts**

### **Global Actions**
- **`emergency-process-kill.sh`** - Kill high-CPU processes (any module)
- **`emergency-shutdown.sh`** - Emergency system shutdown (any module) 
- **`disk-cleanup.sh`** - Clean up disk space (any module)
- **`memory-cleanup.sh`** - Clean up memory/swap (any module)

### **Module-Specific Actions**
- **`module-i915-dkms-rebuild.sh`** - Rebuild i915 DKMS modules
- **`module-i915-grub-flags.sh`** - Apply i915 GRUB parameters
- **`module-usb-network-disconnect.sh`** - Reset USB network devices
- **`module-usb-storage-reset.sh`** - Reset USB storage devices

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
