#!/bin/bash
# =============================================================================
# UBUNTU KERNEL HELPER FUNCTIONS
# =============================================================================
#
# PURPOSE:
#   Ubuntu-specific kernel detection, management, and compatibility functions.
#   Provides Ubuntu kernel track detection and management capabilities.
#
# UBUNTU KERNEL TRACKS:
#   - GA: General Availability (original release kernel)
#   - HWE: Hardware Enablement (newer kernel for LTS)
#   - LTS: Long Term Support (kernel.org LTS)
#   - OEM: Original Equipment Manufacturer (vendor hardware)
#   - lowlatency: Low-latency (audio/video/realtime)
#   - mainline: Mainline development (testing only)
#
# FUNCTIONS PROVIDED:
#   - detect_ubuntu_kernel_track()
#   - get_ubuntu_release()
#   - check_kernel_track_compliance()
#   - get_recommended_track()
#
# =============================================================================

# =============================================================================
# get_ubuntu_release() - Get current Ubuntu release version
# =============================================================================
get_ubuntu_release() {
    if command -v lsb_release >/dev/null 2>&1; then
        lsb_release -rs 2>/dev/null || echo "22.04"
    else
        # Fallback to /etc/os-release
        if [[ -f /etc/os-release ]]; then
            grep "^VERSION_ID=" /etc/os-release | cut -d'"' -f2 || echo "22.04"
        else
            echo "22.04"  # Safe fallback
        fi
    fi
}

# =============================================================================
# detect_ubuntu_kernel_track() - Detect current Ubuntu kernel track
# =============================================================================
detect_ubuntu_kernel_track() {
    local kernel_version="$1"
    local ubuntu_release
    ubuntu_release=$(get_ubuntu_release)
    
    # Remove any architecture suffix (e.g., -generic, -lowlatency)
    local base_version
    base_version=$(echo "$kernel_version" | sed 's/-[^-]*$//')
    
    # Detect kernel track based on package and version patterns
    if [[ "$kernel_version" =~ -lowlatency ]]; then
        echo "lowlatency"
    elif [[ "$kernel_version" =~ -oem ]]; then
        echo "OEM"
    elif [[ "$kernel_version" =~ -hwe ]]; then
        echo "HWE"
    elif dpkg -l | grep -q "linux-image.*hwe.*$ubuntu_release"; then
        echo "HWE"
    elif [[ "$base_version" =~ ^6\.[0-9]+\.[0-9]+$ ]]; then
        # 6.x.y pattern - likely mainline or linux-next
        local major_minor
        major_minor=$(echo "$base_version" | cut -d. -f1-2)
        
        # Check if this is a very recent kernel (likely mainline/linux-next)
        if [[ "$major_minor" > "6.6" ]]; then
            echo "mainline"  # Cutting edge kernel
        else
            echo "LTS"  # Stable 6.x LTS kernel
        fi
    elif [[ "$base_version" =~ ^5\.[0-9]+\.[0-9]+$ ]]; then
        # 5.x.y pattern - determine if LTS or GA
        local minor_version
        minor_version=$(echo "$base_version" | cut -d. -f2)
        
        # 5.4, 5.10, 5.15 are LTS kernels
        if [[ "$minor_version" == "4" || "$minor_version" == "10" || "$minor_version" == "15" ]]; then
            echo "LTS"
        else
            echo "GA"
        fi
    else
        # Default to GA for unknown patterns
        echo "GA"
    fi
}

# =============================================================================
# check_kernel_track_compliance() - Check if current kernel matches preferred track
# =============================================================================
check_kernel_track_compliance() {
    local preferred_track="$1"
    local current_kernel="$2"
    
    local current_track
    current_track=$(detect_ubuntu_kernel_track "$current_kernel")
    
    # Handle legacy track names
    case "$preferred_track" in
        "stable")
            preferred_track="LTS"
            ;;
        "longterm")
            preferred_track="LTS"
            ;;
        "linux-next")
            preferred_track="mainline"
            ;;
    esac
    
    if [[ "$current_track" == "$preferred_track" ]]; then
        echo "compliant"
        return 0
    else
        echo "non-compliant"
        return 1
    fi
}

# =============================================================================
# get_recommended_track() - Get recommended kernel track for hardware
# =============================================================================
get_recommended_track() {
    local hardware_type="${HARDWARE_TYPE:-unknown}"
    local graphics_chipset="${GRAPHICS_CHIPSET:-unknown}"
    local ubuntu_release
    ubuntu_release=$(get_ubuntu_release)
    
    # Hardware-specific recommendations
    case "$graphics_chipset" in
        "i915")
            # Intel integrated graphics - prefer stable kernels
            if [[ "$ubuntu_release" =~ ^(18.04|20.04|22.04)$ ]]; then
                echo "LTS"  # LTS kernel for Intel graphics stability
            else
                echo "GA"   # GA kernel for non-LTS releases
            fi
            ;;
        "nvidia")
            # NVIDIA graphics - HWE often has better driver support
            if [[ "$ubuntu_release" =~ ^(18.04|20.04|22.04)$ ]]; then
                echo "HWE"  # HWE kernel for newer NVIDIA driver support
            else
                echo "GA"   # GA kernel for non-LTS releases
            fi
            ;;
        "amdgpu")
            # AMD graphics - HWE for newer hardware support
            echo "HWE"
            ;;
        *)
            # Default recommendation based on Ubuntu release
            if [[ "$ubuntu_release" =~ ^(18.04|20.04|22.04)$ ]]; then
                echo "LTS"  # Conservative choice for LTS releases
            else
                echo "GA"   # Standard choice for regular releases
            fi
            ;;
    esac
}

# =============================================================================
# get_track_description() - Get human-readable description of kernel track
# =============================================================================
get_track_description() {
    local track="$1"
    
    case "$track" in
        "GA")
            echo "General Availability (original release kernel)"
            ;;
        "HWE")
            echo "Hardware Enablement (newer kernel for better hardware support)"
            ;;
        "LTS")
            echo "Long Term Support (stable kernel.org LTS kernel)"
            ;;
        "OEM")
            echo "Original Equipment Manufacturer (vendor-specific optimizations)"
            ;;
        "lowlatency")
            echo "Low-latency (optimized for audio/video/realtime workloads)"
            ;;
        "mainline")
            echo "Mainline development (cutting-edge, testing only)"
            ;;
        # Legacy compatibility
        "stable")
            echo "Stable (legacy - maps to LTS)"
            ;;
        "longterm")
            echo "Long-term (legacy - maps to LTS)"
            ;;
        "linux-next")
            echo "Linux-next (legacy - maps to mainline)"
            ;;
        *)
            echo "Unknown kernel track"
            ;;
    esac
}

# Export functions for use by other scripts
export -f get_ubuntu_release
export -f detect_ubuntu_kernel_track
export -f check_kernel_track_compliance
export -f get_recommended_track
export -f get_track_description
