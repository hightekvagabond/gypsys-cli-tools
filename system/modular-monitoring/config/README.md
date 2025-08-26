# Machine-Specific Configuration Directory

## 📁 Purpose

This directory serves as a **placeholder** for machine-specific configuration files that will override the system defaults. Eventually, this will likely be moved to a more appropriate location (e.g., `/etc/modular-monitor/`, `~/.config/modular-monitor/`, or similar).

## 🔄 Configuration Hierarchy

The modular monitoring system uses a **4-tier configuration precedence** (most important to least important):

1. **Environment Variables** 🌍
   - `export TEMP_WARNING=75` (overrides everything)
   - Highest precedence for runtime overrides

2. **Machine-Specific System Config** 🖥️
   - `config/SYSTEM.conf` (this directory - when it exists)
   - Per-machine overrides for system-wide settings

3. **Module-Specific Config** 📦
   - `modules/<MODULE_NAME>/config.conf`
   - Module-specific settings and overrides

4. **System Default Config** 🎯
   - `system_default.conf` (project root)
   - Fallback defaults shipped with the project

## 📋 Current Files

- `modules.conf` - Module-specific configuration settings
- `*.backup` - Backup files from configuration consolidation
- `SYSTEM.conf` - **Will be moved to become system_default.conf**

## 🚀 Future Location

This `config/` directory is temporary. In a production deployment, machine-specific configs would likely be placed in:

- `/etc/modular-monitor/` (system-wide)
- `~/.config/modular-monitor/` (user-specific)
- Or another appropriate system configuration location

The exact location will be determined during deployment planning.

## 🔧 Usage Examples

### Setting Machine-Specific Overrides

Create `config/SYSTEM.conf` to override defaults:
```bash
# Machine-specific overrides
USE_MODULES="thermal memory i915"  # Only enable critical modules on this machine
IGNORE_MODULES=""                  # Don't ignore any modules
DEFAULT_MONITOR_INTERVAL=120       # Check every 2 minutes on this machine
```

### Runtime Environment Overrides

```bash
# Temporary override for testing
export TEMP_EMERGENCY=80
./monitor.sh --test thermal

# Override module selection for this run
export USE_MODULES="thermal only"
./monitor.sh
```

### Module-Specific Overrides

Each module can have machine-specific settings in `modules/<MODULE>/config.conf`.

## 📖 Configuration Loading

The configuration loading happens in `modules/common.sh` with this priority:

1. Load system defaults (`system_default.conf`)
2. Load module defaults (`modules/<MODULE>/config.conf`) 
3. Load machine-specific system config (`config/SYSTEM.conf`)
4. Apply environment variable overrides

This ensures that more specific configurations always take precedence over general defaults.
