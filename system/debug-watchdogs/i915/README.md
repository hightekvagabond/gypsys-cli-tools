# i915 Self-Healing System

This folder contains a unified system for preventing Intel i915 GPU freezes on hybrid-GPU laptops. It automatically monitors for i915 driver errors and applies fixes when problems are detected, preventing the infamous *Atomic update failure* and *workqueue hogged CPU* freezes.

## System Components

- **`i915-fix-all.sh`** - Unified fix script that handles GRUB flags, DKMS modules, and system checks
- **`i915-watch.sh`** - Comprehensive watchdog that monitors both errors and system health, triggering automatic fixes  
- **`i915-install.sh`** - System installer that sets up cron jobs, APT hooks, and systemd services

## Quick Start

```bash
cd /path/to/gypsys-cli-tools/system/debug-watchdogs/i915
sudo ./i915-install.sh
```

This creates a complete self-healing system with hourly monitoring, automatic DKMS rebuilding after package updates, and boot-time health checks.

## How It Works

The system applies proven i915 stability flags (`enable_psr=0`, `enable_dc=0`, `enable_fbc=0`, `disable_power_well=0`) and provides comprehensive monitoring through:

- **Error monitoring**: Tracks i915 driver errors in systemd journal
- **System health checks**: Verifies GRUB flags, kernel headers, and DKMS modules  
- **Proactive fixes**: Automatically applies repairs when issues are detected
- **Smart escalation**: 5+ errors = warning, 15+ errors OR system issues = auto-fix, 50+ errors = critical alert
- **Cooldown periods**: Prevents fix loops with intelligent timing (6h DKMS, 24h GRUB flags)

## Tested On

* **Kubuntu 24.04** (kernel 6.11+) with Intel UHD 630 + NVIDIA RTX 2060
* **Hybrid GPU laptops** with DisplayLink/USB-C external displays
* **Any systemd-based distro** with GRUB bootloader

Use `--help` on any script for detailed usage information.


