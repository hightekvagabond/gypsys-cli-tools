# Modular System Monitoring Suite

A comprehensive, modular monitoring and autofix system for Linux systems with hardware-specific optimizations and intelligent problem detection.

## 🎯 **Mission**

Prevent system freezes, hardware issues, and performance problems through intelligent monitoring with automated fixes - designed to be your system's intelligent assistant that knows your hardware and keeps things running smoothly.

## 🚀 **Quick Start**

```bash
# Install the complete monitoring system
sudo ./setup.sh

# Check overall system status
./status.sh

# List available modules
./monitor.sh --list

# View real-time monitoring logs
journalctl -t modular-monitor -f
```

## 📁 **Architecture Overview**

```
modular-monitoring/
├── setup.sh                   # System installer & reconfiguration
├── monitor.sh                 # Central module coordinator  
├── status.sh                  # System-wide status reporter
├── README.md                  # This file
├── FUTURE_SCOPE.md           # Roadmap and AI integration plans
├── system_default.conf        # Default system configuration
├── config/                    # Machine-specific configuration (placeholder)
│   ├── README.md             # Configuration system guide
│   └── SYSTEM.conf           # Machine-specific overrides (optional)
│                             # NOTE: In production, this will be /etc/modular-monitor/ or similar
├── modules/                   # Modular monitoring components
│   ├── MODULE_BEST_PRACTICES.md  # Development guide
│   ├── common.sh             # Shared framework functions
│   └── */                    # Individual modules (see below)
└── systemd/                   # Service definitions
    ├── modular-monitor.service
    └── modular-monitor.timer
```

## 🔍 **Discovering Modules**

The system is designed to be completely modular. To see what monitoring capabilities are available:

```bash
# List all enabled modules
./monitor.sh --list

# Browse available modules
ls modules/*/README.md

# Check what modules are available but not enabled
ls modules/ | grep -v common.sh | grep -v MODULE_BEST_PRACTICES.md
```

Each module in the `modules/` directory has its own README.md explaining its purpose, configuration options, and usage.

## ⚙️ **Configuration System**

### **4-Tier Configuration Hierarchy** 
The system uses a sophisticated configuration precedence system (most → least important):

1. **🌍 Environment Variables** - Runtime overrides
   ```bash
   export USE_MODULES="thermal memory"
   export TEMP_EMERGENCY=75
   ./monitor.sh
   ```

2. **🖥️ Machine-Specific Config** - Per-machine overrides
   ```bash
   # config/SYSTEM.conf (when it exists)
   USE_MODULES="thermal memory i915 usb"
   DEFAULT_MONITOR_INTERVAL=180
   ```

3. **📦 Module-Specific Config** - Module settings
   ```bash
   # modules/thermal/config.conf
   TEMP_WARNING=85
   TEMP_CRITICAL=90
   ```

4. **🎯 System Default Config** - Project defaults
   ```bash
   # system_default.conf
   USE_MODULES="ALL"
   IGNORE_MODULES="nonexistent"
   ```

### **Module Management**
Modules are controlled via configuration, not symlinks:

```bash
# Enable specific modules
USE_MODULES="thermal memory i915 usb"

# Enable all except some
USE_MODULES="ALL"
IGNORE_MODULES="nonexistent kernel"

# Disable all modules  
USE_MODULES="NONE"

# List enabled modules
./monitor.sh --list
```

### **Configuration Deployment**
- **Development**: `config/` directory serves as a placeholder
- **Production**: Machine-specific configs will be deployed to:
  - `/etc/modular-monitor/` (system-wide)
  - `~/.config/modular-monitor/` (user-specific)
  - Or other appropriate system configuration location

See `config/README.md` for detailed configuration documentation and deployment scenarios.

## 📊 **Usage Patterns**

### **System-Wide Operations**
```bash
# Quick system overview
./status.sh

# Status for specific time range
./status.sh "2 hours ago" "1 hour ago"

# Complete historical analysis
./status.sh --all
```

### **Module-Specific Operations**
```bash
# Each module supports standard arguments:
./modules/MODULE_NAME/monitor.sh --help
./modules/MODULE_NAME/monitor.sh --status
./modules/MODULE_NAME/monitor.sh --no-auto-fix
./modules/MODULE_NAME/monitor.sh --start-time "1 hour ago"

# Module status (simplified wrapper)
./modules/MODULE_NAME/status.sh [start_time] [end_time]
```

### **Monitor Management**
```bash
# List all enabled modules with status
./monitor.sh --list

# Run monitor once manually
./monitor.sh

# Test monitor with verbose output
./monitor.sh --debug
```

## 🔧 **Key Features**

### **True Modularity**
- **Independent modules**: Each module is completely self-contained
- **Dynamic discovery**: System automatically finds and uses available modules
- **Flexible enabling**: Enable/disable modules without code changes
- **Standardized interface**: All modules follow the same command patterns

### **Intelligent Configuration**
- **No hardcoded values**: All timeouts, limits, and thresholds are configurable
- **Override system**: Easily customize any module's behavior
- **Time range flexibility**: Analyze any time period with natural language
- **Hierarchical settings**: System → Module → User override precedence

### **Smart Automation**
- **Context-aware fixes**: Automated fixes consider system state
- **Cooldown management**: Prevent excessive fix attempts
- **Graduated responses**: Try gentle fixes before aggressive ones
- **User transparency**: Clear notifications of automatic actions

## 🔍 **Monitoring & Debugging**

### **Real-time Monitoring**
```bash
# Watch all monitoring activity
journalctl -t modular-monitor -f

# Filter by specific modules (discovered dynamically)
journalctl -t modular-monitor -f | grep MODULE_NAME
```

### **Service Management**
```bash
# Check service status
systemctl status modular-monitor.timer
systemctl status modular-monitor.service

# Restart monitoring
sudo systemctl restart modular-monitor.timer

# View service logs
journalctl -u modular-monitor.service --no-pager
```

## 📋 **Development & Customization**

### **Adding New Modules**
1. Read `modules/MODULE_BEST_PRACTICES.md` for complete guidelines
2. Create module directory: `modules/new_module/`
3. Implement required files: `monitor.sh`, `config.conf`, `status.sh`, `README.md`
4. Add autofix scripts in `autofix/` subdirectory
5. Enable module: Add to `USE_MODULES` in `system_default.conf` or machine config

### **Module Standards**
- **Standardized interface**: All modules support `--help`, `--status`, `--no-auto-fix`, `--start-time`, `--end-time`
- **Configuration integration**: Use `common.sh` framework and config hierarchy
- **Documentation**: Each module includes its own README.md
- **Self-contained**: Modules should not depend on specific other modules

## 🌟 **Design Philosophy**

### **Modularity First**
- **No hardcoded module lists**: System discovers modules dynamically
- **Plugin architecture**: Add/remove capabilities without touching core code
- **Standard interfaces**: Consistent command patterns across all modules
- **Independent operation**: Each module can function standalone

### **Configuration Flexibility**
- **Everything configurable**: No hardcoded values anywhere in the system
- **User override capability**: Easy customization without editing source
- **Profile support**: Different configurations for different use cases
- **Documentation embedded**: Configuration files are self-documenting

### **Intelligent Operation**
- **Context awareness**: System understands hardware and usage patterns
- **Predictive capabilities**: Identify problems before they cause issues
- **Adaptive behavior**: Learn from system patterns and user preferences
- **Transparent automation**: Users always know what the system is doing

## 🚀 **Future Development**

See `FUTURE_SCOPE.md` for detailed roadmap including:
- **AI Integration**: Local and cloud AI assistants for intelligent analysis
- **Advanced Analytics**: Predictive maintenance and trend analysis  
- **Enhanced Interfaces**: Web dashboard and mobile monitoring
- **Ecosystem Integration**: Third-party service integrations

The modular architecture ensures that new capabilities can be added without disrupting existing functionality.

## 🎯 **Success Philosophy**

This system is designed on the principle that **intelligent monitoring should fade into the background** - preventing problems before they occur, fixing issues automatically when possible, and providing clear, actionable information when human intervention is needed.

The modular design ensures the system can grow and adapt to new hardware, new problems, and new monitoring needs without requiring architectural changes.

## 📜 **License**

Open source - use, modify, and distribute freely. Designed for educational and personal use.

---

**Built for reliability, designed for modularity, optimized for extensibility.**