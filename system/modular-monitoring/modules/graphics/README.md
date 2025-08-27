# Graphics Monitoring Module

## Purpose
Monitors graphics hardware health, GPU errors, and display issues to prevent graphics crashes and system freezes. The graphics module uses a helper-based architecture to support multiple graphics chipsets.

## Features
- **Multi-chipset Support**: Intel i915 (tested), NVIDIA (stub), AMD (stub)
- **GPU Error Detection**: Kernel log analysis for graphics driver errors
- **Helper Architecture**: Chipset-specific monitoring and autofix
- **Display Integration**: Works with display module for comprehensive coverage
- **Autofix Capabilities**: Automated recovery for GPU hangs and driver issues

## Hardware Requirements
- Graphics hardware (GPU or integrated graphics)
- Supported chipsets: Intel i915 (fully supported), NVIDIA/AMD (stubs available)

## Configuration

### Module Configuration (modules/graphics/config.conf)
```bash
# Graphics helpers to enable (comma-separated)
GRAPHICS_HELPERS_ENABLED="i915"

# Error thresholds for different chipsets
I915_WARN_THRESHOLD=5
I915_FIX_THRESHOLD=15
I915_CRITICAL_THRESHOLD=50
```

### System Configuration (config/SYSTEM.conf)
```bash
# Graphics chipset detection
GRAPHICS_CHIPSET="i915"        # Intel integrated graphics
GPU_VENDOR="intel"             # GPU vendor
GRAPHICS_DRIVER="i915"         # Graphics driver

# Graphics helpers to enable
GRAPHICS_HELPERS_ENABLED="i915"
```

## Helper Architecture

The graphics module uses a helper-based architecture for chipset-specific monitoring:

```
modules/graphics/
├── monitor.sh          # Main orchestrator
├── helpers/            # Chipset-specific helpers
│   ├── i915.sh        # Intel graphics (tested)
│   ├── nvidia.sh      # NVIDIA graphics (stub)
│   └── amdgpu.sh      # AMD graphics (stub)
└── scan.sh            # Hardware detection
```

### Supported Chipsets

- **✅ Intel i915**: Fully supported and tested
  - GPU hang detection and recovery
  - Driver error analysis
  - DKMS module rebuild capability
  - GRUB stability parameter application

- **⚠️ NVIDIA**: Stub implementation available
  - Requires testing on NVIDIA hardware
  - Framework ready for implementation

- **⚠️ AMD (amdgpu)**: Stub implementation available
  - Requires testing on AMD hardware
  - Framework ready for implementation

## Autofix Capabilities

The graphics module integrates with the graphics autofix system:

- **GPU Hangs**: Process management and driver parameter adjustment
- **Driver Errors**: DKMS module rebuild and GRUB flag application
- **Memory Issues**: Graphics memory cleanup and pressure relief
- **Display Errors**: Display pipeline recovery procedures

### Autofix Scripts
- `autofix/graphics.sh` - Main graphics autofix orchestrator
- `autofix/graphics_helpers/i915.sh` - Intel-specific autofix
- `autofix/graphics_helpers/i915-dkms-rebuild.sh` - DKMS rebuild
- `autofix/graphics_helpers/i915-grub-flags.sh` - GRUB parameters

## Usage

### Manual Testing
```bash
# Test hardware detection
./exists.sh

# Run hardware scan
./scan.sh

# Monitor graphics (with autofix)
./monitor.sh

# Monitor graphics (status only)
./monitor.sh --status

# Test module functionality
./test.sh
```

### Integration with Main System
The graphics module is automatically discovered and enabled when graphics hardware is detected. It integrates with:

- **Main monitor**: `./monitor.sh` includes graphics monitoring
- **Status reporting**: `./status.sh` includes graphics status
- **Hardware scanning**: `./setup.sh --scan` detects graphics hardware

## Monitoring Details

### Error Detection
- Analyzes kernel logs for graphics driver errors
- Tracks GPU hangs, resets, and display pipeline issues
- Monitors graphics memory pressure and allocation failures
- Detects thermal throttling and performance degradation

### Alert Thresholds
- **Warning**: 5+ graphics errors in monitoring period
- **Critical**: 15+ graphics errors (triggers autofix)
- **Emergency**: 50+ graphics errors (aggressive autofix)

### Autofix Triggers
- **GPU Hangs**: Process management and stability parameters
- **Driver Corruption**: DKMS module rebuild
- **Persistent Issues**: GRUB stability flag application
- **Memory Pressure**: Graphics application management

## Development

### Adding New Chipset Support
1. Create helper script: `helpers/CHIPSET.sh`
2. Implement monitoring logic following i915.sh pattern
3. Add autofix helper: `autofix/graphics_helpers/CHIPSET.sh`
4. Update configuration examples
5. Test thoroughly on target hardware

### Testing New Helpers
1. Set `AUTOFIX=false` in config/SYSTEM.conf for safe testing
2. Run helper directly: `./helpers/CHIPSET.sh false true`
3. Check autofix integration: `./autofix/graphics.sh`
4. Validate with module tests: `./test.sh`

## Security Considerations
- Read-only access to GPU sysfs interfaces
- Safe dmesg analysis without system modification
- Validated autofix script execution with grace periods
- All dangerous operations require explicit configuration

## Troubleshooting

### Common Issues
- **No hardware detected**: Check if graphics drivers are loaded
- **Helper not found**: Verify GRAPHICS_HELPERS_ENABLED configuration
- **Autofix not working**: Check AUTOFIX and DISABLE_AUTOFIX settings
- **High error counts**: Review recent graphics driver or hardware changes

### Debugging
```bash
# Check hardware detection
./exists.sh

# Test specific helper
./helpers/i915.sh false true

# Check autofix system
AUTOFIX=true ./autofix/graphics.sh graphics 300 gpu_hang warning

# Review logs
tail -f /var/log/modular-monitor-autofix.log
```

## Related Modules
- **Display Module**: Handles compositor and display server issues
- **Thermal Module**: Monitors GPU temperatures
- **Memory Module**: Tracks graphics memory usage
