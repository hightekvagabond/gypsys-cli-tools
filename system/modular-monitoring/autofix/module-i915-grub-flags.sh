#!/bin/bash
# i915 GRUB Flags Autofix
# Attempts to apply GRUB flags for i915 GPU stability

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Source module config
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

should_attempt_grub_fix() {
    local cooldown_file="$1"
    local current_time="$2"
    local cooldown_hours="${GRUB_COOLDOWN_HOURS:-24}"
    
    if [[ ! -f "$cooldown_file" ]]; then
        return 0  # No previous fix
    fi
    
    local last_fix
    last_fix=$(cat "$cooldown_file" 2>/dev/null || echo "0")
    local time_diff=$(( (current_time - last_fix) / 3600 ))
    
    [[ $time_diff -ge $cooldown_hours ]]
}

attempt_grub_flags() {
    local grub_cooldown_file="$STATE_DIR/i915_grub_last_fix"
    local current_time=$(date +%s)
    
    # Check cooldown
    if ! should_attempt_grub_fix "$grub_cooldown_file" "$current_time"; then
        log "AUTOFIX: GRUB fix still in cooldown period"
        return 1
    fi
    
    # Check current GRUB configuration
    local grub_file="/etc/default/grub"
    if [[ ! -f "$grub_file" ]]; then
        log "AUTOFIX: GRUB configuration not found"
        return 1
    fi
    
    # Check if i915 flags are already set
    if grep -q "i915.enable_psr=0" "$grub_file" 2>/dev/null; then
        log "AUTOFIX: i915 GRUB flags already present"
        return 1
    fi
    
    log "AUTOFIX: GRUB flags fix recommended - requires root privileges"
    send_alert "warning" "🔧 i915 fix: GRUB flags needed (i915.enable_psr=0 i915.enable_fbc=0)"
    
    # Record the attempt
    echo "$current_time" > "$grub_cooldown_file"
    log "AUTOFIX: GRUB flags fix attempt recorded"
    
    return 0
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    attempt_grub_flags
fi
