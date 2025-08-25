# Memory Monitoring Module

Monitors system memory usage, swap activity, and detects potential memory-related issues.

## 🎯 **Purpose**

Monitors system memory usage, swap activity, and detects potential memory-related issues.

## ⚙️ **Configuration**

Edit `config.conf` or create `config/memory.conf` override:

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

- **RAM usage tracking**: Monitor memory consumption and pressure
- **Swap monitoring**: Track swap usage and thrashing indicators
- **Memory leak detection**: Identify processes with growing memory usage  
- **Automatic cleanup**: Optional memory cleanup routines when thresholds exceeded

## 📋 **Status Information**

The status display includes relevant memory monitoring information for the specified time period.

## 🔍 **Monitoring Integration**

This module integrates with:
- **System logs**: All actions logged to journalctl with `modular-monitor` tag
- **Alert system**: Uses common alerting framework with cooldowns
- **Configuration system**: Supports system/module/override configuration hierarchy

## ⚠️ **Important Notes**

See the module's `config.conf` file for detailed configuration options and explanations.

## 🎛️ **Tuning Guidelines**

Adjust thresholds and settings in the configuration file based on your system's characteristics and monitoring needs.

This module can be enabled/disabled by managing the symlink in `config/memory.enabled`.
