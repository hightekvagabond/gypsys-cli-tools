# Network Monitoring Module

Monitors network connectivity, interface health, and identifies network-related system issues.

## 🎯 **Purpose**

Monitors network connectivity, interface health, and identifies network-related system issues.

## ⚙️ **Configuration**

Edit `config.conf` or create `config/network.conf` override:

```bash
# See config.conf for all available settings
# Key configuration options are documented in the file
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

## 🔧 **Features**

- **Connectivity analysis**: Monitor network interfaces and connection health
- **DHCP issue detection**: Identify DHCP server problems and timeouts
- **WiFi SSID tracking**: Identify problematic networks and connection issues
- **Interface error analysis**: Map network errors to specific devices and networks

## 📋 **Status Information**

The status display includes relevant network monitoring information for the specified time period.

## 🔍 **Monitoring Integration**

This module integrates with:
- **System logs**: All actions logged to journalctl with `modular-monitor` tag
- **Alert system**: Uses common alerting framework with cooldowns
- **Configuration system**: Supports system/module/override configuration hierarchy

## ⚠️ **Important Notes**

See the module's `config.conf` file for detailed configuration options and explanations.

## 🎛️ **Tuning Guidelines**

Adjust thresholds and settings in the configuration file based on your system's characteristics and monitoring needs.

This module can be enabled/disabled by managing the symlink in `config/network.enabled`.
