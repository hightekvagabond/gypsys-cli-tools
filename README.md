# Modular System Monitoring Suite

A comprehensive, self-healing monitoring system designed to prevent system freezes and hardware damage on high-performance laptops (specifically tested on Acer Predator series).

## 🎯 **Project Purpose**

This monitoring suite was created to solve critical system stability issues:
- **System freezes** requiring hard reboots
- **CPU thermal emergencies** (temperatures reaching 100°C+)
- **USB device instability** causing system hangs
- **Docking station ethernet failures** creating thermal stress
- **Intel i915 GPU driver issues** causing lockups

## 🏗️ **Architecture**

**Modular Design**: Each monitoring function is a separate, independent module coordinated by a central orchestrator.

```
modular-monitoring/
├── orchestrator.sh         # Central coordinator (runs every 1 minute via systemd)
├── install.sh             # System installer
├── status.sh              # Health checker
├── README.md              # This documentation
├── modules/               # Individual monitoring modules
│   ├── common.sh          # Shared utilities (logging, alerts, cooldowns)
│   ├── thermal-monitor.sh # CPU/GPU temperature + emergency protection
│   ├── usb-monitor.sh     # USB resets + network adapter management
│   ├── i915-monitor.sh    # Intel GPU driver issues + fixes
│   ├── memory-monitor.sh  # RAM/swap pressure monitoring
│   └── system-monitor.sh  # General system health
├── config/
│   └── thresholds.conf    # Centralized configuration
├── systemd/
│   ├── modular-monitor.service  # Service definition
│   └── modular-monitor.timer    # Timer (every 1 minute)
├── logs/                  # Local logs (if needed)
└── state/                 # Runtime state tracking
```

## 🚨 **Critical Features**

### **Emergency Thermal Protection**
- **Smart Process Targeting**: Only kills the highest CPU offender (non-system processes)
- **Grace Periods**: 60-second startup grace period to prevent false kills
- **Temperature Thresholds**: 85°C warning / 90°C critical / 95°C emergency
- **Diagnostic Dumps**: Complete system state capture before emergency shutdown
- **Prevents Hardware Damage**: Clean shutdown if no killable processes found

### **Network Adapter Management** 
- **Docking Station Protection**: Automatically disables failing ethernet adapters
- **Thermal Overload Prevention**: Stops DHCP failure loops that cause CPU stress
- **Ephemeral Disabling**: Auto-restores at reboot (no permanent config changes)
- **Desktop Notifications**: User awareness of adapter changes

### **Intel GPU Driver Fixes**
- **DKMS Rebuild**: Automatic detection and rebuild recommendations
- **GRUB Parameter Management**: i915 flag recommendations for stability
- **Fix Cooldowns**: 6-hour DKMS / 24-hour GRUB cooldown periods
- **Error Pattern Detection**: Monitors for i915 GPU hangs and resets

### **USB Stability Management**
- **USB Reset Detection**: Monitors for device instability
- **Driver Restart**: Automatic USB storage module cycling
- **Controller Reset**: USB power management resets

## 📊 **Monitoring Thresholds**

### Temperature (CPU Package)
- **Warning**: 85°C (desktop notification)
- **Critical**: 90°C (process analysis + alerts)
- **Emergency**: 95°C (kill top CPU offender or shutdown)

### USB Device Resets
- **Warning**: 10 resets since boot
- **Critical**: 20 resets since boot (attempt fixes)

### Memory Pressure
- **Warning**: 90% RAM usage
- **Critical**: 95% RAM usage

### Network Failures
- **Critical**: 20+ docking station DHCP failures (disable adapter)

### i915 GPU Errors
- **Notice**: 5+ errors (monitoring alert)
- **Fix Attempt**: 15+ errors (automatic fixes)
- **Critical**: 50+ errors (manual intervention required)

## 🔧 **Installation & Usage**

### Install
```bash
cd /path/to/modular-monitoring
sudo ./install.sh
```

### Check Status
```bash
./status.sh
```

### Manual Testing
```bash
# Test individual modules
./modules/thermal-monitor.sh
./modules/usb-monitor.sh
./modules/i915-monitor.sh

# Test orchestrator
./orchestrator.sh
```

### View Logs
```bash
# Live monitoring
journalctl -t modular-monitor -f

# Recent activity
journalctl -t modular-monitor --since '1 hour ago'

# Errors only
journalctl -t modular-monitor -p err

# Check emergency dumps
ls -la /var/log/emergency-thermal-dump-*
```

## 📁 **Log & State Locations**

### Logs
- **Primary**: SystemD journal (`journalctl -t modular-monitor`)
- **Emergency Dumps**: `/var/log/emergency-thermal-dump-YYYYMMDD-HHMMSS.log`

### State Files
- **Directory**: `/var/tmp/modular-monitor-state/`
- **Alert Cooldowns**: `{module}_{level}_last_alert`
- **Fix Cooldowns**: `i915_dkms_last_fix`, `i915_grub_last_fix`
- **Network Markers**: `/tmp/network_disabled_{adapter}`

## 🛠️ **Technical Implementation**

### Systemd Integration
- **Service**: `modular-monitor.service` (runs orchestrator)
- **Timer**: `modular-monitor.timer` (every 1 minute)
- **Logging**: Integrated with systemd journal

### Module Communication
- **Shared Library**: `modules/common.sh` provides utilities
- **Alert System**: Desktop notifications + system logging
- **Cooldown Management**: Prevents alert spam
- **State Persistence**: Survives reboots and service restarts

### Safety Features
- **System Process Protection**: Never kills essential system processes
- **Graceful Degradation**: Continues monitoring even if individual modules fail
- **Non-Destructive**: All fixes are recommendations or temporary changes
- **Rollback Capability**: Network changes auto-restore at reboot

## 🎛️ **Configuration**

### Main Config: `config/thresholds.conf`
```bash
# Temperature thresholds (°C)
TEMP_WARNING=85
TEMP_CRITICAL=90
TEMP_EMERGENCY=95

# USB reset thresholds
USB_RESET_WARNING=10
USB_RESET_CRITICAL=20

# Memory thresholds (%)
MEMORY_WARNING=90
MEMORY_CRITICAL=95

# i915 error thresholds
I915_WARN_THRESHOLD=5
I915_FIX_THRESHOLD=15
I915_CRITICAL_THRESHOLD=50
```

## 🧪 **Development & Testing**

### Module Development
- Each module is a standalone bash script
- Must source `common.sh` for shared utilities
- Must implement `check_status()` function
- Should use `validate_module()` for consistency

### Testing Individual Modules
```bash
# Test with debug output
DEBUG=1 ./modules/thermal-monitor.sh

# Test orchestrator with specific module
./orchestrator.sh thermal-monitor
```

## 🔄 **Migration from debug-watchdogs**

This modular system replaces the previous monolithic `debug-watchdogs` scripts:
- **critical-monitor.sh** → `thermal-monitor.sh` + `usb-monitor.sh`
- **debug-watch.sh** → `system-monitor.sh`
- **i915-watch.sh** → `i915-monitor.sh`
- **debug-fix-all.sh** → Integrated fix functions in respective modules

### Before Installing
Run the old uninstaller to clean up previous system:
```bash
# From parent directory
cd ../debug-watchdogs
sudo ./uninstall.sh  # If it exists
```

## 🚧 **Known Issues & Limitations**

1. **Root Privileges**: Most fix actions require root (systemd provides this)
2. **Hardware Specific**: Tuned for Acer Predator with Intel i915 GPU
3. **DKMS Dependency**: i915 fixes require DKMS to be installed
4. **Network Manager**: Network fixes require NetworkManager (nmcli)

## 🎯 **Future Enhancements**

- [ ] **Web Dashboard**: Real-time monitoring interface
- [ ] **Email Alerts**: Critical issue notifications
- [ ] **Historical Analytics**: Trend analysis and reporting
- [ ] **Custom Thresholds**: Per-system configuration tuning
- [ ] **Plugin System**: Easy addition of new monitoring modules
- [ ] **Hardware Profiles**: Support for different laptop models
- [ ] **Predictive Monitoring**: ML-based failure prediction
- [ ] **Remote Monitoring**: Multi-system management

## 📞 **Troubleshooting**

### Service Not Starting
```bash
# Check service status
systemctl status modular-monitor.service

# Check service logs
journalctl -u modular-monitor.service

# Restart service
sudo systemctl restart modular-monitor.service
```

### Module Errors
```bash
# Test individual module
./modules/problematic-module.sh

# Check permissions
ls -la modules/

# Validate module
bash -n modules/problematic-module.sh
```

### Missing Dependencies
```bash
# Check required commands
command -v sensors    # lm-sensors
command -v nmcli      # NetworkManager
command -v dkms       # Dynamic Kernel Module Support
command -v notify-send # libnotify-bin
```

## 🏆 **Success Metrics**

Since deployment, this system has:
- **Prevented Hardware Damage**: Multiple 100°C thermal events safely handled
- **Eliminated Hard Reboots**: System freezes resolved before critical failure
- **Improved Stability**: Proactive USB and GPU driver management
- **Enhanced Awareness**: Real-time alerts for developing issues

---

**⚠️ Important**: This system is designed for high-performance laptops prone to thermal and stability issues. Always test thoroughly in your specific environment before relying on automated emergency actions.