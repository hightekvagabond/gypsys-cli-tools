# USB Device Monitoring Module

Advanced USB device monitoring with intelligent device identification and automated problem resolution.

## 🎯 **Purpose**

Detects and resolves USB-related system instability by monitoring device resets, connection issues, and identifying problematic hardware that can cause system freezes.

## 🔌 **Features**

### **Enhanced Device Identification**
- **Human-readable device names**: "🖱️ Logitech Mouse" instead of "usb 2-1:1.0"
- **Device categorization**: Automatic emoji assignment based on device type
- **Port mapping**: Correlate USB addresses to specific connected devices
- **Real-time device listing**: Current device inventory with enhanced details

### **Problem Detection**
- **Reset loop monitoring**: Identify devices causing excessive USB resets
- **Connection stability tracking**: Monitor disconnect/reconnect patterns
- **Port-specific analysis**: Map problems to specific USB ports
- **Docking station failure detection**: Identify network adapter issues in docks

### **Intelligent Resolution**
- **USB storage reset**: Restart USB storage drivers for problematic devices
- **Network adapter disconnect**: Temporarily disable problematic network adapters
- **Targeted fixes**: Address specific device categories differently

## ⚙️ **Configuration**

Edit `config.conf` or create `config/usb.conf` override:

```bash
# USB reset thresholds (resets per monitoring period)
USB_RESET_WARNING=10
USB_RESET_CRITICAL=20

# USB check interval (seconds)
USB_CHECK_INTERVAL=30

# Alert cooldowns (seconds)
WARNING_COOLDOWN=600            # 10 minutes
CRITICAL_COOLDOWN=180           # 3 minutes  
EMERGENCY_COOLDOWN=60           # 1 minute

# Autofix settings
ENABLE_USB_AUTOFIX=true
ENABLE_USB_STORAGE_RESET=true
ENABLE_USB_NETWORK_DISCONNECT=true

# Network/docking station settings
DOCK_FAILURE_THRESHOLD=20       # Docking station ethernet failure threshold

# Analysis time ranges and limits
DEFAULT_ANALYSIS_TIMESPAN="1 hour ago"
USB_DETAIL_ANALYSIS_TIMESPAN="1 hour ago"
PROBLEMATIC_DEVICE_TIMESPAN="1 hour ago"

# Log analysis limits
MAX_RECENT_USB_RESETS=3
MAX_RECENT_DISCONNECTS=3
MAX_RECENT_ISSUES=5
MAX_DEVICE_DETAILS=3

# Hardware-specific settings
PREDATOR_USB_QUIRKS=true        # Enable USB quirks for Predator hardware
```

## 📊 **Usage**

### **Status Checking**
```bash
# Current USB device status
./status.sh

# USB status for specific time period
./status.sh "2 hours ago" "now"

# Detailed status with device identification
./monitor.sh --status

# Analyze specific time range
./monitor.sh --status --start-time "10:00" --end-time "11:00"
```

### **Monitoring Operations**
```bash
# Normal monitoring with autofix enabled
./monitor.sh

# Monitor without taking automatic actions
./monitor.sh --no-auto-fix

# Monitor specific time range for analysis
./monitor.sh --start-time "1 hour ago" --end-time "now"

# Get help and usage examples
./monitor.sh --help
```

## 🔧 **Device Identification Features**

### **Enhanced Device Names**
The module automatically identifies and categorizes USB devices:

```
🖱️ Logitech G Pro Wireless Gaming Mouse
⌨️ Corsair K95 RGB Platinum Mechanical Keyboard  
🔌 Anker 7-Port USB 3.0 Hub
📷 Logitech HD Pro Webcam C920
🌐 Realtek USB Ethernet Adapter
💾 SanDisk Ultra USB 3.0 Flash Drive
📡 Intel Wireless Bluetooth Adapter
🔊 Blue Yeti USB Microphone
🎮 Xbox Wireless Controller
📱 Unknown Device (Vendor:Product ID)
```

### **Problem Correlation**
When issues occur, you get contextual information:
```
🚨 USB Reset Alert: 🖱️ Logitech Mouse on port usb 2-1 (15 resets in last hour)
⚠️ USB Issues: Multiple devices affected - likely hub problem
🌐 Network Fix: Disconnected 🌐 Dock Ethernet Adapter (temporary - resets at reboot)
```

## 🔧 **Autofix Actions**

### **USB Storage Reset** (`autofix/storage-reset.sh`)
**Triggered**: When USB storage devices show reset patterns
**Action**: 
1. Identifies affected USB storage drivers
2. Safely unmounts affected filesystems
3. Restarts USB storage drivers (`usb-storage`, `uas`)
4. Logs action and monitors for improvement

### **Network Adapter Disconnect** (`autofix/network-disconnect.sh`)
**Triggered**: When USB network adapters (especially in docks) fail repeatedly
**Action**:
1. Identifies problematic network adapters
2. Temporarily disables autoconnect for affected connections
3. Brings interface down safely
4. Logs action with reboot recovery note

## 📋 **Status Information**

The status display includes:
- **Currently connected USB devices** with enhanced identification
- **Recent USB resets** with device names and timestamps
- **USB disconnections** with device identification
- **Problem summary** highlighting devices with issues
- **Docking station status** and network adapter health
- **Autofix actions taken** in the specified time period

## 🚨 **Alert Examples**

```
🔌 USB device issues detected: 15 resets, 3 dock failures since boot
🖱️ USB Reset: Logitech Mouse (usb 2-1) reset 5 times in last hour
🌐 Dock Issues: Network adapter experiencing timeouts - temporary disconnect applied
⚠️ USB Hub Problem: Multiple connected devices showing reset patterns
```

## 🔍 **Problem Analysis**

### **Reset Loop Detection**
- Monitors kernel logs for USB reset messages
- Correlates resets to specific devices and ports
- Identifies patterns suggesting hardware problems
- Distinguishes between normal reconnects and problematic resets

### **Docking Station Monitoring**
- Tracks network adapter failures in USB docks
- Monitors ethernet timeout and link-down events
- Identifies dock-specific vs device-specific problems
- Provides targeted fixes for dock connectivity issues

### **Port-Level Analysis**
- Maps USB topology to identify problematic ports
- Tracks issues by physical USB port location
- Helps identify failing USB controllers or hubs
- Provides data for hardware replacement decisions

## ⚠️ **Important Notes**

1. **Hardware Diagnosis**: This module helps identify failing USB hardware
2. **Temporary Fixes**: Network disconnects are temporary and reset at reboot
3. **Data Safety**: Storage resets only occur after safe unmounting
4. **System Stability**: Addresses USB issues that can cause system freezes
5. **Vendor Specific**: Includes optimizations for known hardware quirks

## 🎛️ **Tuning Guidelines**

### **For Desktop Systems**
- Higher reset thresholds (USB hubs more common)
- Enable storage reset autofix
- Monitor for specific problematic devices

### **For Laptops with Docks**
- Lower dock failure thresholds
- Enable network adapter disconnect
- Focus on dock-related connectivity issues

### **For Gaming Systems**
- Monitor gaming peripherals specifically
- Lower thresholds for input devices
- Track performance impact of USB issues

## 🔬 **Technical Details**

### **Device Identification Process**
1. **USB Address Parsing**: Extract bus and device numbers from kernel logs
2. **lsusb Integration**: Map addresses to vendor/product information
3. **usb-devices Parsing**: Get detailed device information
4. **Categorization**: Apply emoji and friendly names based on device class
5. **Caching**: Maintain device list for correlation across monitoring cycles

### **Reset Detection Algorithm**
1. **Log Analysis**: Parse kernel USB subsystem logs
2. **Pattern Recognition**: Identify reset vs normal disconnect patterns  
3. **Time Correlation**: Group related events within time windows
4. **Device Mapping**: Correlate events to specific connected devices
5. **Threshold Evaluation**: Compare against configured limits

### **Autofix Decision Logic**
1. **Problem Classification**: Determine if issue is storage, network, or general USB
2. **Impact Assessment**: Evaluate severity and system impact
3. **Cooldown Check**: Ensure sufficient time has passed since last fix attempt
4. **Safety Validation**: Confirm fix can be applied safely
5. **Execution and Monitoring**: Apply fix and monitor for improvement

This module is essential for systems using USB hubs, docking stations, or experiencing unexplained system instability that might be USB-related.
