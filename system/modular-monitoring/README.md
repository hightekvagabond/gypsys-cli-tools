# Modular System Monitoring Suite

A comprehensive, lightweight monitoring and freeze prevention system designed for Linux laptops with hardware-specific quirks.

## 🎯 **Mission**

Prevent system freezes that require hard reboots by monitoring and automatically fixing the specific causes that standard monitoring tools miss.

## 🚀 **Quick Start**

```bash
# Install the complete monitoring system
sudo ./install.sh

# Check system status
./status.sh

# View real-time monitoring
journalctl -t modular-monitor -f
```

## 📁 **Structure**

```
modular-monitoring/
├── install.sh              # Main installer script
├── status.sh               # System status checker  
├── README.md               # This file
├── modules/                # Individual monitoring modules
│   ├── thermal-monitor.sh  # CPU/GPU temperature monitoring
│   ├── usb-monitor.sh      # USB device reset detection
│   ├── memory-monitor.sh   # RAM pressure monitoring
│   ├── gpu-monitor.sh      # i915 driver monitoring
│   ├── network-monitor.sh  # Network adapter management
│   └── system-monitor.sh   # System stability monitoring
├── framework/              # Common functions and configuration
│   ├── monitor-framework.sh # Shared logging, alerting, state management
│   └── monitor-config.sh   # Centralized configuration
├── systemd/                # Service definitions
│   ├── modular-monitor.service
│   └── modular-monitor.timer
└── config/                 # Runtime configuration
    └── modules.conf        # Module enable/disable settings
```

## 🛡️ **Current Features**

### **Real-time Monitoring (Systemd Service)**
- **🌡️ Thermal Protection**: Smart CPU temperature monitoring with surgical process targeting
- **🔌 USB Monitoring**: Detects USB reset loops that cause system hangs  
- **🧠 Memory Monitoring**: RAM/swap pressure detection
- **🎮 GPU Monitoring**: Intel i915 driver stability monitoring
- **🌐 Network Monitoring**: Docking station failure management
- **🔧 System Monitoring**: Hardware errors and stability checks

### **Emergency Protection**
- **Surgical Process Targeting**: Kills only the top CPU offender, not multiple processes
- **Grace Periods**: 60s boot + 60s startup protection for new processes  
- **Sustained Monitoring**: Prevents killing legitimate short CPU spikes
- **Emergency Shutdown**: Clean shutdown if no killable processes during thermal crisis

### **Smart Intelligence**
- **Hardware-Specific**: Optimized for Acer Predator and similar laptops
- **Predictive**: Detects patterns that lead to freezes before they happen
- **Learning**: Adapts to normal vs abnormal process behavior
- **Context-Aware**: Considers system state, uptime, and process age

## ⚙️ **Configuration**

Edit `framework/monitor-config.sh` to customize:
- Temperature thresholds (default: 85°C/90°C/95°C)
- Monitoring intervals  
- Alert preferences
- Emergency action settings
- Module enable/disable

## 📊 **Monitoring**

```bash
# Check overall status
./status.sh

# View real-time logs
journalctl -t modular-monitor -f

# Check specific module logs
journalctl -t thermal-monitor -f
journalctl -t usb-monitor -f

# View diagnostic dumps
ls -la logs/emergency-diagnostic-dump-*.log
```

## 🔧 **Troubleshooting**

```bash
# Validate installation
sudo ./install.sh --validate

# Test modules individually
./modules/thermal-monitor.sh --test
./modules/usb-monitor.sh --check

# Debug mode
sudo systemctl edit modular-monitor.service
# Add: Environment="DEBUG_MODE=true"
```

## 📋 **Roadmap**

### **Phase 1: Enhanced Intelligence**
- [ ] Machine learning pattern recognition for freeze prediction
- [ ] Application behavior learning and anomaly detection  
- [ ] Thermal correlation analysis across hardware components
- [ ] Graduated response levels before emergency actions

### **Phase 2: Hardware Expansion**  
- [ ] NVIDIA GPU monitoring beyond i915
- [ ] Battery health and thermal monitoring
- [ ] SMART disk health monitoring with predictive failure detection
- [ ] Dynamic fan curve optimization

### **Phase 3: User Experience**
- [ ] Optional lightweight web dashboard
- [ ] Mobile push notifications for critical alerts
- [ ] Automatic maintenance scheduling during idle periods
- [ ] Performance profiling and optimization suggestions

### **Phase 4: Advanced Features**
- [ ] Multi-machine monitoring for home networks
- [ ] Cloud backup integration for diagnostics
- [ ] Hardware-specific optimization presets
- [ ] Energy consumption monitoring and optimization

## 🏗️ **Architecture Philosophy**

### **Unified Service Model**
- Single systemd service handles all monitoring
- Modular design allows easy addition/removal of monitors
- Centralized logging and state management
- No cron job complexity or timing issues

### **Emergency Response Hierarchy**
1. **Monitor**: Continuous observation of system metrics
2. **Alert**: User notification when thresholds approached  
3. **Intervene**: Automatic fixes for known issues
4. **Protect**: Emergency actions to prevent system damage
5. **Document**: Comprehensive diagnostic dumps for analysis

### **Hardware-First Design**
- Built specifically for Linux laptop freeze prevention
- Targets actual hardware issues (i915 bugs, USB reset loops)
- Optimized for poor thermal design (gaming laptops)
- Handles manufacturer-specific quirks and driver problems

## 📜 **License**

Open source - use, modify, and distribute freely. Designed for educational and personal use.

---

**Built for stability, designed for laptops, optimized for real-world hardware problems.**