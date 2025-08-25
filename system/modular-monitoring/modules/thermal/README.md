# Thermal Monitoring Module

Intelligent CPU temperature monitoring with emergency protection and automated process management.

## 🎯 **Purpose**

Prevents system thermal damage and thermal throttling by monitoring CPU temperatures and taking graduated emergency actions when temperatures exceed safe thresholds.

## 🌡️ **Features**

### **Smart Temperature Monitoring**
- **Real-time CPU package temperature tracking**
- **Graduated response levels**: Warning (85°C) → Critical (90°C) → Emergency (95°C)
- **Hardware-specific optimizations** for laptop thermal design

### **Emergency Protection**
- **Surgical process targeting**: Identifies and kills only the highest CPU-consuming process
- **Grace period protection**: 60-second boot protection + 60-second new process protection
- **Sustained monitoring**: Prevents killing processes with legitimate short CPU spikes
- **Emergency shutdown**: Clean system shutdown if no killable processes during thermal crisis

### **Intelligent Process Management**
- **Context-aware targeting**: Considers process age, CPU usage patterns, and system state
- **System-critical process protection**: Never kills essential system processes
- **User notification**: Wall messages and logging for all emergency actions
- **Diagnostic dumps**: Comprehensive system state capture during emergencies

## ⚙️ **Configuration**

Edit `config.conf` or create `config/thermal.conf` override:

```bash
# Temperature thresholds (°C)
TEMP_WARNING=85
TEMP_CRITICAL=90
TEMP_EMERGENCY=95

# Temperature monitoring interval (seconds)
TEMP_CHECK_INTERVAL=10

# Process management
PROCESS_CPU_THRESHOLD=10        # Minimum CPU % to consider for emergency killing
GRACE_PERIOD_SECONDS=60         # Grace period for new processes after boot
SUSTAINED_HIGH_CPU_SECONDS=30   # How long high CPU must be sustained

# Emergency actions
ENABLE_THERMAL_AUTOFIX=true
ENABLE_EMERGENCY_KILL=true
ENABLE_EMERGENCY_SHUTDOWN=true

# Process kill settings
KILL_PROCESS_WAIT_TIME=2        # seconds to wait after SIGTERM before SIGKILL

# Alert cooldowns (seconds)
WARNING_COOLDOWN=600            # 10 minutes
CRITICAL_COOLDOWN=180           # 3 minutes  
EMERGENCY_COOLDOWN=60           # 1 minute
```

## 📊 **Usage**

### **Status Checking**
```bash
# Current status with default time range
./status.sh

# Status for specific time period
./status.sh "2 hours ago" "now"

# Detailed status information
./monitor.sh --status

# Status for custom time range
./monitor.sh --status --start-time "10:00" --end-time "11:00"
```

### **Monitoring Operations**
```bash
# Normal monitoring with autofix enabled
./monitor.sh

# Monitor without taking any automatic actions
./monitor.sh --no-auto-fix

# Monitor specific time range (for analysis)
./monitor.sh --start-time "1 hour ago" --end-time "now"

# Get help
./monitor.sh --help
```

## 🔧 **Autofix Actions**

### **Emergency Process Kill** (`autofix/emergency-process-kill.sh`)
**Triggered**: When CPU temperature reaches emergency threshold
**Action**: 
1. Identifies highest CPU-consuming non-critical process
2. Checks process age and grace periods
3. Sends SIGTERM, waits, then SIGKILL if necessary
4. Logs action and notifies user via wall message

### **Emergency Shutdown** (`autofix/emergency-shutdown.sh`)
**Triggered**: When no killable processes are found during thermal emergency
**Action**:
1. Creates comprehensive diagnostic dump
2. Captures hardware error logs
3. Initiates clean system shutdown
4. Preserves diagnostic information for analysis

## 📋 **Status Information**

The status display includes:
- **Current CPU temperature** with status indicator (NORMAL/ELEVATED/HIGH)
- **Thermal alerts** in specified time period
- **Emergency actions taken** (process kills, shutdowns)
- **Current configuration** values
- **Historical thermal events**

## 🚨 **Alert Examples**

```
🌡️ Warning: CPU temperature 87°C exceeds warning threshold 85°C
🌡️ Critical: CPU temperature 92°C - emergency process management active
🚨 Emergency: Thermal monitor killed 'chrome' (23.4% CPU) at 96°C
💥 Emergency: Thermal shutdown initiated - no killable processes found at 97°C
```

## 🔍 **Monitoring Integration**

This module integrates with:
- **System logs**: All actions logged to journalctl with `modular-monitor` tag
- **Wall messages**: Critical actions broadcast to all users
- **Alert system**: Uses common alerting framework with cooldowns
- **Diagnostic system**: Creates emergency dumps when needed

## ⚠️ **Important Notes**

1. **Hardware Protection**: This module prioritizes hardware protection over process preservation
2. **Grace Periods**: New processes and system boot get protection periods
3. **System Critical**: Essential system processes are never killed
4. **Clean Shutdown**: Emergency shutdown is clean, not a hard power-off
5. **Logging**: All actions are comprehensively logged for analysis

## 🎛️ **Tuning Guidelines**

### **For Gaming Laptops**
- Lower warning threshold (80°C) for early notification
- Shorter grace periods if thermal design is poor
- Enable all autofix options

### **For Workstations**
- Higher thresholds if thermal design is good
- Longer grace periods for legitimate high-CPU work
- Consider disabling emergency kill for critical processes

### **For Servers**
- Conservative thresholds
- Longer monitoring intervals to reduce overhead
- Enable emergency shutdown for hardware protection

## 🔬 **Technical Details**

### **Temperature Reading**
- Uses `sensors` command for accurate package temperature
- Falls back to thermal zone readings if sensors unavailable
- Validates temperature readings for sanity

### **Process Analysis**
- Uses `/proc/stat` for CPU usage calculation
- Analyzes process start time and age
- Excludes kernel threads and system processes
- Considers sustained CPU usage patterns

### **Emergency Response**
- Implements graduated response escalation
- Uses cooldowns to prevent response spam
- Creates diagnostic snapshots for analysis
- Maintains state between monitoring cycles

This module is the primary defense against thermal damage and should be enabled on all systems with thermal management concerns.
