#!/bin/bash
# Modular Monitor Centralized Configuration
# This file is sourced by the monitor framework to set system-wide defaults

# ========================================
# TEMPERATURE MONITORING
# ========================================

# Temperature thresholds (°C)
TEMP_WARNING=${TEMP_WARNING:-85}
TEMP_CRITICAL=${TEMP_CRITICAL:-90}  
TEMP_EMERGENCY=${TEMP_EMERGENCY:-95}

# Temperature monitoring interval (seconds)
TEMP_CHECK_INTERVAL=${TEMP_CHECK_INTERVAL:-10}

# ========================================
# MEMORY MONITORING  
# ========================================

# Memory thresholds (percentage)
MEMORY_WARNING=${MEMORY_WARNING:-85}
MEMORY_CRITICAL=${MEMORY_CRITICAL:-95}

# Memory check interval (seconds)
MEMORY_CHECK_INTERVAL=${MEMORY_CHECK_INTERVAL:-15}

# ========================================
# USB MONITORING
# ========================================

# USB reset thresholds (resets per time window)
USB_RESET_WARNING=${USB_RESET_WARNING:-10}
USB_RESET_CRITICAL=${USB_RESET_CRITICAL:-20}

# USB monitoring interval (seconds)
USB_CHECK_INTERVAL=${USB_CHECK_INTERVAL:-5}

# ========================================
# GPU/i915 MONITORING
# ========================================

# GPU error thresholds
GPU_ERROR_WARNING=${GPU_ERROR_WARNING:-5}
GPU_ERROR_CRITICAL=${GPU_ERROR_CRITICAL:-15}

# GPU check interval (seconds)
GPU_CHECK_INTERVAL=${GPU_CHECK_INTERVAL:-10}

# ========================================
# SYSTEM MONITORING
# ========================================

# System monitoring interval (seconds)
SYSTEM_CHECK_INTERVAL=${SYSTEM_CHECK_INTERVAL:-30}

# Network timeout settings
NETWORK_TIMEOUT=${NETWORK_TIMEOUT:-5}
NETWORK_RETRY_COUNT=${NETWORK_RETRY_COUNT:-3}

# ========================================
# EMERGENCY RESPONSE
# ========================================

# Process management
PROCESS_CPU_THRESHOLD=${PROCESS_CPU_THRESHOLD:-10}  # Minimum CPU % to consider for emergency killing
GRACE_PERIOD_SECONDS=${GRACE_PERIOD_SECONDS:-60}   # Grace period for new processes after boot
SUSTAINED_HIGH_CPU_SECONDS=${SUSTAINED_HIGH_CPU_SECONDS:-30}  # How long high CPU must be sustained

# Emergency actions
ENABLE_EMERGENCY_KILL=${ENABLE_EMERGENCY_KILL:-true}
ENABLE_EMERGENCY_SHUTDOWN=${ENABLE_EMERGENCY_SHUTDOWN:-true}

# ========================================
# ALERTING & NOTIFICATIONS
# ========================================

# Alert cooldowns (seconds)
WARNING_COOLDOWN=${WARNING_COOLDOWN:-600}      # 10 minutes
CRITICAL_COOLDOWN=${CRITICAL_COOLDOWN:-180}    # 3 minutes  
EMERGENCY_COOLDOWN=${EMERGENCY_COOLDOWN:-60}   # 1 minute

# Desktop notifications
ENABLE_DESKTOP_NOTIFICATIONS=${ENABLE_DESKTOP_NOTIFICATIONS:-true}
NOTIFICATION_TIMEOUT=${NOTIFICATION_TIMEOUT:-10000}  # milliseconds

# ========================================
# LOGGING & DEBUGGING
# ========================================

# Logging
LOG_LEVEL=${LOG_LEVEL:-info}  # debug, info, warning, error
ENABLE_DIAGNOSTIC_DUMPS=${ENABLE_DIAGNOSTIC_DUMPS:-true}

# Debug mode (enables more verbose logging)
DEBUG_MODE=${DEBUG_MODE:-false}

# ========================================
# DIRECTORY PATHS
# ========================================

# Override default paths if needed
# STATE_DIR is set in monitor-framework.sh
# LOG_DIR is set in common.sh

# ========================================
# MODULE ENABLE/DISABLE
# ========================================

# Individual module toggles (sourced from modules.conf if it exists)
ENABLE_THERMAL_MONITOR=${ENABLE_THERMAL_MONITOR:-true}
ENABLE_USB_MONITOR=${ENABLE_USB_MONITOR:-true}
ENABLE_MEMORY_MONITOR=${ENABLE_MEMORY_MONITOR:-true}
ENABLE_I915_MONITOR=${ENABLE_I915_MONITOR:-true}
ENABLE_SYSTEM_MONITOR=${ENABLE_SYSTEM_MONITOR:-true}

# Load module-specific configuration if available
if [[ -f "$MONITOR_ROOT/config/modules.conf" ]]; then
    source "$MONITOR_ROOT/config/modules.conf"
fi
