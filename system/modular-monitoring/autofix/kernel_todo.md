# Kernel Autofix Enhancement TODO

## Overview
This document captures kernel management features that should be automated based on manual operations performed during monitor issue resolution. These enhancements will make kernel branch management more complete and robust.

## Current State
- Basic kernel branch switching exists in `autofix/kernel_helpers/ubuntu.sh`
- Only handles installing preferred kernel packages
- Missing comprehensive track management and cleanup

## Required Enhancements

### 1. Conflicting Kernel Track Removal
**Priority: HIGH**  
**Function:** `remove_conflicting_kernel_tracks()`

**What it should do:**
- Detect installed kernel track packages (HWE, OEM, GA, etc.)
- Remove packages that conflict with target track
- Example: When switching to LTS, remove `linux-image-generic-hwe-*` and `linux-image-oem-*`

**Manual commands we used:**
```bash
sudo apt remove linux-image-generic-hwe-24.04 linux-image-oem-24.04b
```

**Implementation notes:**
- Should support dry-run mode
- Require confirmation for destructive operations
- Log all package removals

### 2. APT Preferences Management
**Priority: HIGH**  
**Function:** `set_apt_kernel_preferences()`

**What it should do:**
- Create `/etc/apt/preferences.d/kernel-lts-preference` (or similar)
- Set high priority for preferred kernel track
- Set negative priority for conflicting tracks
- Prevent automatic upgrades to unwanted kernel tracks

**Manual commands we used:**
```bash
sudo tee /etc/apt/preferences.d/kernel-lts-preference > /dev/null << 'EOF'
Package: linux-image-generic-hwe-*
Pin: release *
Pin-Priority: -1

Package: linux-image-oem-*
Pin: release *
Pin-Priority: -1

Package: linux-image-generic
Pin: release *
Pin-Priority: 1001
EOF
```

**Implementation notes:**
- Template-based preference generation
- Track-specific preference files
- Backup existing preferences before modification

### 3. Old Kernel Cleanup
**Priority: MEDIUM**  
**Function:** `cleanup_old_kernels()`

**What it should do:**
- Remove automatically installed but no longer needed kernel images
- Clean up old kernel modules (DKMS cleanup)
- Free up `/boot` space

**Manual commands we used:**
```bash
sudo apt autoremove
```

**Implementation notes:**
- Should preserve at least 2-3 recent kernels for safety
- Handle DKMS module cleanup gracefully
- Warn if `/boot` space is low

### 4. GRUB Default Management Enhancement
**Priority: HIGH**  
**Function:** `update_grub_default()` (enhance existing)

**What it should do:**
- Automatically set GRUB_DEFAULT to preferred kernel
- Remove conflicting saved_entry from GRUB environment
- Update GRUB configuration
- Verify GRUB entries exist before setting default

**Manual commands we used:**
```bash
# Set GRUB default to specific kernel
sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="1>gnulinux-6.8.0-79-generic-advanced-..."/' /etc/default/grub

# Remove saved_entry that overrides GRUB_DEFAULT
sudo grub-editenv /boot/grub/grubenv unset saved_entry

# Update GRUB configuration
sudo update-grub
```

**Implementation notes:**
- Parse GRUB menu entries dynamically to find correct entry ID
- Handle different GRUB naming conventions (Ubuntu vs Kubuntu)
- Clear GRUB saved_entry when it conflicts with desired default
- Backup GRUB configuration before changes
- Verify no saved_entry overrides are active

## Integration Points

### Enhanced perform_kernel_branch_switch() Flow
```bash
perform_kernel_branch_switch() {
    1. ensure_grace_period_permissions()     # NEW (setup)
    2. Validate target kernel track
    3. remove_conflicting_kernel_tracks()    # NEW
    4. set_apt_kernel_preferences()          # NEW  
    5. install_kernel_branch()               # EXISTING
    6. verify_kernel_installation()          # NEW (verification)
    7. get_grub_kernel_entry_id()            # NEW (dynamic GRUB parsing)
    8. update_grub_default()                 # ENHANCED (includes saved_entry fix)
    9. apply_graphics_stability_flags()      # NEW (i915 integration)
    10. cleanup_old_kernels()                # NEW
    11. update_grub()                        # ENHANCED (regenerate config)
    12. coordinate_reboot_requirements()     # NEW (reboot coordination)
}
```

### Safety Considerations
- All operations should support `--dry-run` mode
- Destructive operations require confirmation
- Always backup configurations before modification
- Preserve multiple kernel options for recovery
- Log all operations for audit trail

### Configuration Integration
Should respect configuration hierarchy:
- `PREFERRED_KERNEL_TRACK` from helper config
- `KERNEL_UPDATE_POLICY` from module config  
- `ALLOW_KERNEL_TRACK_CHANGES` from system config
- Environment variable overrides

## Testing Strategy
1. Test with dummy script first
2. Use `--dry-run` mode extensively
3. Test on non-production systems
4. Verify rollback procedures
5. Test with different Ubuntu versions/tracks

## Implementation Priority
1. **Phase 1:** APT preferences management (prevents future conflicts)
2. **Phase 2:** Conflicting track removal (cleans up existing conflicts)  
3. **Phase 3:** Enhanced GRUB management (improves boot reliability)
4. **Phase 4:** Automated cleanup (maintenance and space management)

## Related Files
- `autofix/kernel_helpers/ubuntu.sh` - Main implementation
- `modules/kernel/monitor.sh` - Detection and triggering
- `modules/kernel/config.conf` - Module configuration
- `modules/kernel/helpers/ubuntu.conf` - Helper configuration
- `config/SYSTEM.conf` - System overrides

## Real-World Trigger
This enhancement was prompted by a monitor issue where:
- System was on bleeding-edge kernel (`6.14.0-29-generic`)
- HDMI monitor not detected after kernel update
- Manual switch to LTS kernel (`6.8.0-79-generic`) resolved issue
- Required manual cleanup of conflicting kernel tracks
- APT preferences needed to prevent future conflicts
- **GRUB `saved_entry=0` was overriding `GRUB_DEFAULT` setting**
- Manual removal of `saved_entry` was needed for proper boot default

**The autofix should handle this entire scenario automatically.**

## Critical GRUB Issue Discovered
During implementation, we found that:
1. `GRUB_DEFAULT` was correctly set to LTS kernel entry
2. `saved_entry=0` in GRUB environment was overriding this setting
3. Entry 0 ("Kubuntu") boots the newest kernel (bleeding-edge)
4. This caused system to boot wrong kernel despite correct configuration

**Fix:** `sudo grub-editenv /boot/grub/grubenv unset saved_entry`

This is a critical automation requirement - the system must check for and remove conflicting `saved_entry` values when setting kernel defaults.

## Missing Manual Activities Analysis

### **5. Grace Period Directory Permissions Fix**
**Priority: MEDIUM**  
**Function:** `ensure_grace_period_permissions()`

**What it should do:**
- Ensure `/tmp/modular-monitor-grace/` directory exists with proper permissions
- Create directory if missing and set write permissions for all users

**Manual commands we used:**
```bash
sudo mkdir -p /tmp/modular-monitor-grace 
sudo chmod 777 /tmp/modular-monitor-grace
```

**Implementation notes:**
- Should be part of autofix initialization
- Check and fix permissions before grace period operations
- Handle different temp directory scenarios

### **6. GRUB Configuration Parsing and Entry ID Detection**
**Priority: HIGH**  
**Function:** `get_grub_kernel_entry_id()`

**What it should do:**
- Parse `/boot/grub/grub.cfg` to find correct kernel entry IDs
- Handle Ubuntu vs Kubuntu naming conventions
- Find specific kernel version entries dynamically

**Manual commands we used:**
```bash
# We manually found the correct entry ID for LTS kernel:
# "1>gnulinux-6.8.0-79-generic-advanced-a544a064-509e-4d5b-8f40-3385dc6dd28a"
```

**Implementation notes:**
- Must parse GRUB menu structure correctly
- Handle advanced submenu entries (1>submenu>entry format)
- Verify entry exists before setting as default
- Account for different distribution naming

### **7. I915 Graphics Driver GRUB Flags Integration**
**Priority: HIGH**  
**Function:** Enhanced kernel switching should include graphics stability flags

**What it should do:**
- Apply i915 stability flags when switching to/from kernel tracks
- Ensure graphics stability flags are preserved across kernel changes
- Coordinate with graphics autofix helpers

**Manual commands we used:**
```bash
# i915 GRUB flags were applied during display troubleshooting
# These should be coordinated with kernel track switching
```

**Implementation notes:**
- Kernel track switching should call graphics helpers
- Ensure i915 flags are applied for Intel systems on LTS kernels
- Integration point between kernel and graphics autofix

### **8. Kernel Version Verification After Installation**
**Priority: MEDIUM**  
**Function:** `verify_kernel_installation()`

**What it should do:**
- Verify target kernel package was installed successfully
- Check that kernel files exist in `/boot/`
- Confirm GRUB detected the new kernel

**Manual verification we did:**
```bash
uname -r                    # Check active kernel after reboot
ls /boot/vmlinuz-*         # Verify kernel files present
update-grub                # Regenerate GRUB config to detect new kernels
```

**Implementation notes:**
- Should be called after kernel installation
- Provide clear success/failure feedback
- Suggest troubleshooting steps if verification fails

### **9. System Reboot Coordination**
**Priority: MEDIUM**  
**Function:** `coordinate_reboot_requirements()`

**What it should do:**
- Track which autofix operations require reboot
- Coordinate multiple reboot requirements into single reboot
- Provide clear reboot instructions with verification steps

**Manual coordination we did:**
```bash
# Multiple reboots were needed for:
# 1. Kernel changes
# 2. Graphics driver changes  
# 3. GRUB configuration changes
# These should be coordinated into fewer reboots
```

**Implementation notes:**
- Batch reboot-requiring operations
- Clear pre/post reboot verification steps
- Handle failed reboots and recovery

### **10. Environment Variable Configuration Override Testing**
**Priority: LOW**  
**Function:** Already covered by dummy script, but needs integration testing

**What we manually tested:**
```bash
export AUTOFIX=true
export DRY_RUN=true  
export OVERRIDE_GRACE=true
```

**Implementation notes:**
- Comprehensive testing framework for config hierarchy
- Environment variable override verification
- Integration testing across all autofix scripts
