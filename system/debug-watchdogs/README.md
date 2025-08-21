# Debug Watchdogs - Hybrid Monitoring System

A comprehensive system freeze prevention and monitoring solution designed for Ubuntu/Kubuntu on Acer Predator hardware.

## 🛡️ **Protection Strategy**

This system uses a **hybrid approach** combining real-time critical monitoring with comprehensive periodic health checks:

### **⚡ Real-time Protection (2-minute intervals)**
- **`critical-monitor.service`** - Systemd service detecting immediate freeze risks:
  - **Thermal monitoring**: >75°C warning, >85°C critical alerts
  - **USB storage resets**: Detects patterns that cause system hangs
  - **Memory pressure**: >90% warning, >95% critical alerts
  - **Automatic fixes**: Emergency USB storage repairs

### **🔍 Comprehensive Monitoring (6-hour intervals)**
- **`debug-watch.sh`** - Full system health analysis via cron:
  - Performance issues, hardware errors, service failures
  - Network connectivity, DNS resolution
  - System stability analysis
- **`i915-watch.sh`** - Intel GPU specific monitoring via cron:
  - i915 driver errors, DKMS module health
  - GRUB flag verification, automatic repairs

## 📁 **Directory Structure**

```
debug-watchdogs/
├── critical-monitor.sh        # Real-time critical monitoring script
├── critical-monitor.service   # Systemd service definition
├── critical-monitor.timer     # Systemd timer (every 2 minutes)
├── debug-watch.sh            # Comprehensive system monitoring
├── debug-fix-all.sh          # Unified diagnostic and repair tool
├── hybrid-install.sh         # Main installer for the hybrid system
├── i915/                     # Intel GPU monitoring subsystem
│   ├── i915-watch.sh         # GPU-specific monitoring
│   ├── i915-fix-all.sh       # GPU fixes and diagnostics
│   └── i915-install.sh       # GPU monitoring installer
└── README.md                 # This file
```

## 🚀 **Quick Installation**

```bash
# Install the complete hybrid monitoring system
sudo ./hybrid-install.sh

# Monitor real-time critical alerts
journalctl -t critical-monitor -f

# Monitor comprehensive system health
journalctl -t debug-watch -t i915-watch -f

# Check service status
systemctl status critical-monitor.timer
```

## 📊 **Monitoring Overview**

| Component | Frequency | Purpose | Technology |
|-----------|-----------|---------|------------|
| Critical Monitor | 2 minutes | Freeze prevention | systemd service |
| Debug Watch | 6 hours | System health | cron job |
| i915 Watch | 6 hours | GPU monitoring | cron job |
| System Cleanup | Weekly | Maintenance | cron job |

## 🛠️ **Manual Operations**

### **Diagnostic Commands**
```bash
# Run immediate critical check
./critical-monitor.sh

# Test specific monitoring
./critical-monitor.sh --test-thermal
./critical-monitor.sh --test-usb
./critical-monitor.sh --test-memory

# Full system health check
./debug-fix-all.sh --health-check

# GPU-specific diagnostics
./i915/i915-fix-all.sh --check-only
```

### **Fix Commands**
```bash
# Fix USB storage issues (freeze prevention)
sudo ./debug-fix-all.sh --usb-fix

# Fix network connectivity
sudo ./debug-fix-all.sh --network-fix

# Restart failed services
sudo ./debug-fix-all.sh --service-fix

# GPU fixes
sudo ./i915/i915-fix-all.sh
```

## 📈 **System Requirements**

- **OS**: Ubuntu/Kubuntu 24.04 LTS
- **Hardware**: Optimized for Acer Predator laptops
- **Dependencies**: `sensors`, `systemd`, `cron`
- **Privileges**: Root access required for installation and fixes

## 🔧 **Configuration**

### **Critical Monitor Thresholds**
- **Temperature**: 75°C warning, 85°C critical
- **USB Resets**: 10 warning, 20 critical
- **Memory**: 90% warning, 95% critical

### **Cooldown Periods** (prevent alert spam)
- **Thermal critical**: 5 minutes
- **Thermal warning**: 10 minutes  
- **USB critical**: 15 minutes
- **Memory critical**: 5 minutes

## 🚨 **Troubleshooting**

### **Service Issues**
```bash
# Check service logs
journalctl -t critical-monitor --since "1 hour ago"

# Restart services
sudo systemctl restart critical-monitor.timer

# Test service manually
sudo ./critical-monitor.sh
```

### **High CPU Temperatures**
If you're seeing persistent thermal warnings:

1. **Check current temps**: `sensors`
2. **Clean laptop vents**: Physical cleaning
3. **Adjust CPU governor**: `cpupower frequency-info`
4. **Check thermal paste**: May need replacement

### **USB Storage Issues**
If getting USB reset warnings:

1. **Try different USB port**: Prefer USB 3.0 ports
2. **Check USB cable**: Replace if damaged
3. **Update USB drivers**: `sudo apt update && sudo apt upgrade`
4. **Manually fix**: `sudo ./debug-fix-all.sh --usb-fix`

## 📝 **Logs and Monitoring**

### **Real-time Monitoring**
```bash
# Critical alerts
journalctl -t critical-monitor -f

# All monitoring
journalctl -t critical-monitor -t debug-watch -t i915-watch -f

# System status
systemctl list-timers | grep critical
```

### **Log Locations**
- **Critical Monitor**: `journalctl -t critical-monitor`
- **Debug Watch**: `journalctl -t debug-watch`
- **i915 Watch**: `journalctl -t i915-watch`
- **State Files**: `/var/tmp/critical-monitor-state/`

## ⚙️ **Advanced Options**

### **Selective Installation**
```bash
# Install only critical monitoring
sudo ./hybrid-install.sh --service-only

# Install only comprehensive monitoring
sudo ./hybrid-install.sh --cron-only

# Skip GPU monitoring
sudo ./hybrid-install.sh --no-i915
```

### **Uninstallation**
```bash
# Remove entire system
sudo ./hybrid-install.sh --uninstall
```

## 🎯 **Why This System Works**

1. **Fast Response**: 2-minute critical monitoring catches issues before they cause freezes
2. **Comprehensive Coverage**: 6-hour monitoring ensures nothing is missed long-term
3. **Automatic Fixes**: Self-healing reduces manual intervention
4. **Smart Alerting**: Cooldown periods prevent notification spam
5. **Hardware Optimized**: Specifically tuned for Predator laptop hardware

---

**For technical support or to report issues, check the script headers for detailed developer documentation.**