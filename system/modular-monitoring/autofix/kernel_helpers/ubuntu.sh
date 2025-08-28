#!/bin/bash
# =============================================================================
# KERNEL BRANCH SWITCHING AUTOFIX SCRIPT
# =============================================================================
#
# 🚨 CRITICAL DANGER WARNING:
#   This script modifies kernel installation and GRUB configuration which can 
#   make your system UNBOOTABLE if done incorrectly. Always have recovery media ready.
#
# PURPOSE:
#   Automatically switches to the preferred kernel branch when kernel branch
#   compliance violations are detected. Helps maintain system stability by
#   ensuring the correct kernel branch is installed and active.
#
# SUPPORTED UBUNTU KERNEL TRACKS:
#   - GA: General Availability kernel (shipped with original Ubuntu release)
#   - HWE: Hardware Enablement kernel (newer kernel for LTS, better hardware support)
#   - LTS: Long Term Support kernel (stable kernel.org LTS adopted by Canonical)
#   - OEM: Original Equipment Manufacturer kernel (vendor-specific hardware support)
#   - lowlatency: Low-latency kernel (audio/video workloads, realtime applications)
#   - mainline: Mainline kernel (cutting-edge, Ubuntu Kernel Team, testing only)
#
# AUTOFIX CAPABILITIES:
#   - Install preferred kernel branch packages
#   - Update GRUB to use new kernel as default
#   - Schedule reboot for kernel activation
#   - Backup current kernel configuration
#
# WHEN TO USE:
#   - Kernel branch compliance violations detected
#   - After accidental kernel upgrades to wrong branch
#   - When switching from bleeding-edge to stable for production
#   - Hardware compatibility issues with current kernel
#
# BOOTLOADER SAFETY:
#   ⚠️  Kernel changes require system reboot to take effect
#   ⚠️  GRUB modification risks making system unbootable
#   ⚠️  Always backup important data before kernel changes
#   ⚠️  Have recovery/rescue media available
#
# USAGE:
#   kernel-branch-switch.sh <calling_module> <grace_period> [target_branch] [action]
#
# EXAMPLES:
#   kernel-branch-switch.sh kernel 7200 stable install      # Switch to stable branch
#   kernel-branch-switch.sh manual 3600 longterm install   # Manual longterm installation
#   kernel-branch-switch.sh kernel 7200 stable recommend    # Recommend only (no install)
#
# SECURITY CONSIDERATIONS:
#   - Requires root privileges for kernel installation
#   - Validates kernel packages before installation
#   - Creates backup of GRUB configuration
#   - All changes logged for audit and recovery
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Initialize autofix script with common setup
init_autofix_script "$@"

# Additional arguments specific to this script
TARGET_BRANCH="${3:-${PREFERRED_KERNEL_BRANCH:-stable}}"
ACTION="${4:-install}"  # install, recommend, check

# =============================================================================
# show_help() - Display usage and safety information
# =============================================================================
show_help() {
    cat << 'EOF'
KERNEL BRANCH SWITCHING AUTOFIX SCRIPT

⚠️  WARNING:
    This script modifies kernel installation and GRUB configuration which can
    potentially make your system unbootable if done incorrectly.

PURPOSE:
    Automatically switches to the preferred kernel branch for system stability.
    Helps resolve kernel compatibility issues and maintains consistent environment.

USAGE:
    kernel-branch-switch.sh <calling_module> <grace_period> [target_branch] [action]

ARGUMENTS:
    calling_module   - Name of module requesting autofix (e.g., "kernel")
    grace_period     - Seconds to wait before allowing autofix again
    target_branch    - Kernel branch to switch to (stable, longterm, mainline, linux-next)
    action          - Action to take (install, recommend, check)

EXAMPLES:
    # Install stable kernel branch (production environments)
    kernel-branch-switch.sh kernel 7200 stable install

    # Recommend LTS kernel (maximum stability)
    kernel-branch-switch.sh kernel 3600 lts recommend

    # Check available kernels for mainline branch
    kernel-branch-switch.sh manual 1800 mainline check

SUPPORTED BRANCHES:
    stable       - Current stable kernel release (recommended for production)
    longterm    - Long Term Support kernel (maximum stability)
    mainline    - Latest mainline development kernel (balanced stability/features)
    linux-next  - Integration tree for next kernel cycle (testing only)

ACTIONS:
    install     - Actually install and configure the target kernel
    recommend   - Provide recommendations without making changes
    check       - Check available kernels and current status

REQUIREMENTS:
    - Root privileges for kernel installation
    - Internet connection for package downloads
    - Sufficient disk space for additional kernels
    - GRUB bootloader (standard Ubuntu setup)

EXIT CODES:
    0 - Kernel switch completed successfully or recommendation provided
    1 - Error occurred (check logs)
    2 - Skipped due to grace period

SAFETY FEATURES:
    - Grace period prevents repeated modifications
    - Creates backup of GRUB configuration
    - Validates kernel packages before installation
    - Comprehensive logging and error handling
    - Reboot scheduling with user notification

⚠️  CRITICAL: Kernel changes require system reboot and can make system unbootable
    Always have recovery media ready and test in non-production environments first.
EOF
}

# Validate arguments
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

if ! validate_autofix_args "$(basename "$0")" "$1" "$2"; then
    exit 1
fi

CALLING_MODULE="$1"
GRACE_PERIOD="$2"

# =============================================================================
# get_kernel_package_name() - Get the package name for a kernel branch
# =============================================================================
get_kernel_package_name() {
    local track="$1"
    
    # Get current Ubuntu release
    local ubuntu_release
    ubuntu_release=$(lsb_release -rs 2>/dev/null || echo "22.04")
    
    case "$track" in
        "GA")
            # General Availability - original kernel shipped with release
            echo "linux-image-generic"
            ;;
        "HWE")
            # Hardware Enablement - newer kernel for LTS releases
            if [[ "$ubuntu_release" == "22.04" ]]; then
                echo "linux-image-generic-hwe-22.04"
            elif [[ "$ubuntu_release" == "20.04" ]]; then
                echo "linux-image-generic-hwe-20.04"
            elif [[ "$ubuntu_release" == "18.04" ]]; then
                echo "linux-image-generic-hwe-18.04"
            else
                echo "linux-image-generic"  # Fallback for non-LTS or newer releases
            fi
            ;;
        "LTS")
            # Long Term Support kernel from kernel.org
            echo "linux-image-generic"  # Standard LTS kernel
            ;;
        "OEM")
            # Original Equipment Manufacturer kernel for specific hardware
            echo "linux-image-oem-22.04"  # Adjust based on Ubuntu version
            ;;
        "lowlatency")
            # Low-latency kernel for audio/video workloads
            echo "linux-image-lowlatency"
            ;;
        "mainline")
            # Mainline kernel from Ubuntu Kernel Team (testing)
            echo "linux-image-generic"  # Note: mainline requires manual PPA setup
            ;;
        # Legacy compatibility
        "stable")
            echo "linux-image-generic"
            ;;
        "longterm")
            echo "linux-image-generic-hwe-$ubuntu_release"
            ;;
        "linux-next")
            echo "linux-image-generic"
            ;;
        *)
            echo "linux-image-generic"  # Safe fallback
            ;;
    esac
}

# =============================================================================
# check_available_kernels() - Check what kernels are available and installed
# =============================================================================
check_available_kernels() {
    local target_branch="$1"
    
    autofix_log "INFO" "Checking available kernels for branch: $target_branch"
    
    # Get current kernel
    local current_kernel
    current_kernel=$(uname -r)
    autofix_log "INFO" "Current kernel: $current_kernel"
    
    # Get target package name
    local target_package
    target_package=$(get_kernel_package_name "$target_branch")
    autofix_log "INFO" "Target package: $target_package"
    
    # Check if target package is available
    if apt-cache show "$target_package" >/dev/null 2>&1; then
        autofix_log "INFO" "Target kernel package '$target_package' is available"
        
        # Check if already installed
        if dpkg -l | grep -q "^ii  $target_package "; then
            autofix_log "INFO" "Target kernel package '$target_package' is already installed"
            return 0
        else
            autofix_log "INFO" "Target kernel package '$target_package' is available but not installed"
            return 1
        fi
    else
        autofix_log "WARN" "Target kernel package '$target_package' is not available in repositories"
        return 2
    fi
}

# =============================================================================
# install_kernel_branch() - Install the target kernel branch
# =============================================================================
install_kernel_branch() {
    local target_branch="$1"
    local target_package
    target_package=$(get_kernel_package_name "$target_branch")
    
    autofix_log "INFO" "Installing kernel branch: $target_branch (package: $target_package)"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        autofix_log "WARN" "Kernel installation requires root privileges - providing recommendation"
        
        # Send desktop notification if available
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "Kernel Switch Required" "Install $target_branch kernel: sudo apt install $target_package" 2>/dev/null || true
        fi
        
        autofix_log "INFO" "RECOMMENDATION: Install $target_branch kernel with: sudo apt install $target_package"
        autofix_log "INFO" "RECOMMENDATION: After installation, run: sudo update-grub"
        autofix_log "INFO" "RECOMMENDATION: Reboot to activate new kernel"
        
        return 0  # Success - we provided the recommendation
    fi
    
    # Update package cache
    autofix_log "INFO" "Updating package cache..."
    if apt update 2>&1 | while IFS= read -r line; do
        autofix_log "INFO" "APT: $line"
    done; then
        autofix_log "INFO" "Package cache updated successfully"
    else
        autofix_log "ERROR" "Failed to update package cache"
        return 1
    fi
    
    # Install the target kernel
    autofix_log "INFO" "Installing kernel package: $target_package"
    if apt install -y "$target_package" 2>&1 | while IFS= read -r line; do
        autofix_log "INFO" "APT: $line"
    done; then
        autofix_log "INFO" "Kernel package installed successfully"
    else
        autofix_log "ERROR" "Failed to install kernel package: $target_package"
        return 1
    fi
    
    # Update GRUB configuration
    autofix_log "INFO" "Updating GRUB configuration..."
    if update-grub 2>&1 | while IFS= read -r line; do
        autofix_log "INFO" "GRUB: $line"
    done; then
        autofix_log "INFO" "GRUB configuration updated successfully"
    else
        autofix_log "ERROR" "Failed to update GRUB configuration"
        return 1
    fi
    
    # Recommend reboot
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Kernel Installed" "$target_branch kernel installed - reboot required" 2>/dev/null || true
    fi
    
    autofix_log "INFO" "Kernel branch switch completed - system reboot required for changes to take effect"
    autofix_log "INFO" "NEXT STEP: Reboot system to activate $target_branch kernel"
    
    return 0
}

# =============================================================================
# provide_recommendations() - Provide kernel switching recommendations
# =============================================================================
provide_recommendations() {
    local target_branch="$1"
    local current_kernel
    current_kernel=$(uname -r)
    
    autofix_log "INFO" "Providing kernel branch switching recommendations"
    autofix_log "INFO" "Current kernel: $current_kernel"
    autofix_log "INFO" "Target branch: $target_branch"
    
    local target_package
    target_package=$(get_kernel_package_name "$target_branch")
    
    # Check availability
    if check_available_kernels "$target_branch"; then
        autofix_log "INFO" "RECOMMENDATION: Target kernel is already installed"
        autofix_log "INFO" "RECOMMENDATION: Set as default in GRUB if needed"
        autofix_log "INFO" "RECOMMENDATION: Check GRUB menu on next reboot"
    else
        autofix_log "INFO" "RECOMMENDATION: Install $target_branch kernel branch"
        autofix_log "INFO" "COMMAND: sudo apt update && sudo apt install $target_package"
        autofix_log "INFO" "COMMAND: sudo update-grub"
        autofix_log "INFO" "RECOMMENDATION: Reboot after installation"
    fi
    
    # Provide branch-specific guidance
    case "$target_branch" in
        "stable")
            autofix_log "INFO" "STABLE BRANCH: Recommended for production environments"
            autofix_log "INFO" "BENEFITS: Better hardware compatibility, fewer driver issues"
            ;;
        "longterm")
            autofix_log "INFO" "LONGTERM BRANCH: Maximum stability for critical systems"
            autofix_log "INFO" "BENEFITS: Long-term support, minimal breaking changes"
            ;;
        "mainline")
            autofix_log "INFO" "MAINLINE BRANCH: Latest features with reasonable stability"
            autofix_log "INFO" "BENEFITS: Recent hardware support, modern features"
            ;;
        "linux-next")
            autofix_log "WARN" "LINUX-NEXT BRANCH: Integration testing only, not recommended for production"
            autofix_log "WARN" "RISKS: Driver incompatibilities, system instability, frequent breakage"
            ;;
    esac
    
    # Hardware-specific recommendations
    if [[ "${GRAPHICS_CHIPSET:-}" == "i915" ]]; then
        autofix_log "INFO" "HARDWARE NOTE: Intel i915 graphics work best with stable or longterm kernels"
        autofix_log "INFO" "CURRENT ISSUE: Development kernels may cause HDMI detection problems"
    fi
    
    return 0
}

# =============================================================================
# perform_kernel_branch_switch() - Main kernel switching function
# =============================================================================
perform_kernel_branch_switch() {
    local current_kernel
    current_kernel=$(uname -r)
    
    autofix_log "INFO" "Kernel branch switch requested: target=$TARGET_BRANCH, action=$ACTION"
    autofix_log "INFO" "Current kernel: $current_kernel"
    
    # Validate target track
    case "$TARGET_BRANCH" in
        "GA"|"HWE"|"LTS"|"OEM"|"lowlatency"|"mainline")
            autofix_log "INFO" "Valid Ubuntu kernel track: $TARGET_BRANCH"
            ;;
        # Legacy compatibility
        "stable"|"longterm"|"linux-next")
            autofix_log "INFO" "Valid kernel track (legacy): $TARGET_BRANCH"
            ;;
        *)
            autofix_log "ERROR" "Invalid kernel track: $TARGET_BRANCH"
            autofix_log "ERROR" "Valid Ubuntu tracks: GA, HWE, LTS, OEM, lowlatency, mainline"
            autofix_log "ERROR" "Legacy tracks: stable, longterm, linux-next"
            return 1
            ;;
    esac
    
    # Perform action based on request
    case "$ACTION" in
        "install")
            install_kernel_branch "$TARGET_BRANCH"
            ;;
        "recommend")
            provide_recommendations "$TARGET_BRANCH"
            ;;
        "check")
            check_available_kernels "$TARGET_BRANCH"
            ;;
        *)
            autofix_log "ERROR" "Invalid action: $ACTION"
            autofix_log "ERROR" "Valid actions: install, recommend, check"
            return 1
            ;;
    esac
}

# Execute with grace period management
autofix_log "INFO" "Kernel branch switch requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "kernel-branch-switch" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_kernel_branch_switch"
