#!/bin/bash
# i915 DKMS Rebuild Autofix
# Attempts to rebuild DKMS modules for i915 GPU issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Source module config
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

should_attempt_dkms_fix() {
    local cooldown_file="$1"
    local current_time="$2"
    local cooldown_hours="${DKMS_COOLDOWN_HOURS:-6}"
    
    if [[ ! -f "$cooldown_file" ]]; then
        return 0  # No previous fix
    fi
    
    local last_fix
    last_fix=$(cat "$cooldown_file" 2>/dev/null || echo "0")
    local time_diff=$(( (current_time - last_fix) / 3600 ))
    
    [[ $time_diff -ge $cooldown_hours ]]
}

attempt_dkms_rebuild() {
    local dkms_cooldown_file="$STATE_DIR/i915_dkms_last_fix"
    local current_time=$(date +%s)
    
    # Check cooldown
    if ! should_attempt_dkms_fix "$dkms_cooldown_file" "$current_time"; then
        log "AUTOFIX: DKMS fix still in cooldown period"
        return 1
    fi
    
    # Check if DKMS modules exist
    if ! command -v dkms >/dev/null 2>&1; then
        log "AUTOFIX: DKMS not available"
        return 1
    fi
    
    # List i915-related DKMS modules
    local dkms_modules
    dkms_modules=$(dkms status 2>/dev/null | grep -i "i915\|intel" || echo "")
    
    if [[ -z "$dkms_modules" ]]; then
        log "AUTOFIX: No i915 DKMS modules found"
        return 1
    fi
    
    log "AUTOFIX: Found DKMS modules: $dkms_modules"
    
    # This would need root privileges - log the recommendation
    log "AUTOFIX: DKMS rebuild recommended - requires root privileges"
    send_alert "warning" "🔧 i915 fix: DKMS rebuild recommended (run as root: dkms autoinstall)"
    
    # Record the attempt
    echo "$current_time" > "$dkms_cooldown_file"
    log "AUTOFIX: DKMS rebuild attempt recorded"
    
    return 0
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    attempt_dkms_rebuild
fi
