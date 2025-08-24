#!/bin/bash
# Intel i915 GPU monitoring module

MODULE_NAME="i915"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# i915-specific thresholds
I915_WARN_THRESHOLD=5
I915_FIX_THRESHOLD=15
I915_CRITICAL_THRESHOLD=50

check_status() {
    local error_count
    error_count=$(count_i915_errors)
    
    if [[ $error_count -ge $I915_CRITICAL_THRESHOLD ]]; then
        send_alert "critical" "🎮 Critical: $error_count i915 GPU errors detected - manual intervention required"
        return 1
    elif [[ $error_count -ge $I915_FIX_THRESHOLD ]]; then
        send_alert "warning" "🎮 Warning: $error_count i915 GPU errors - attempting automatic fix"
        attempt_i915_fix
        return 1
    elif [[ $error_count -ge $I915_WARN_THRESHOLD ]]; then
        send_alert "warning" "🎮 Notice: $error_count i915 GPU errors detected"
        return 1
    fi
    
    log "i915 GPU status normal: $error_count errors since boot"
    return 0
}

count_i915_errors() {
    local error_count=0
    
    # Error patterns from original i915-watch.sh
    local patterns=(
        "i915.*ERROR"
        "workqueue: i915_hpd"
        "i915.*gpu hang"
        "i915.*reset"
    )
    
    for pattern in "${patterns[@]}"; do
        # Use journalctl to check for i915 errors
        local count
        count=$(journalctl --since "1 hour ago" --no-pager 2>/dev/null | grep -c "$pattern" 2>/dev/null || true)
        
        # Simple validation - if count is empty or not a number, default to 0
        if [[ -z "$count" ]] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
            count=0
        fi
        
        error_count=$((error_count + count))
    done
    
    echo "$error_count"
}

attempt_i915_fix() {
    log "Attempting i915 GPU fixes..."
    
    # Check cooldown periods
    local dkms_cooldown_file="$STATE_DIR/i915_dkms_last_fix"
    local grub_cooldown_file="$STATE_DIR/i915_grub_last_fix"
    local current_time=$(date +%s)
    
    # Try DKMS fix if not in cooldown
    if should_attempt_dkms_fix "$dkms_cooldown_file" "$current_time"; then
        log "Attempting DKMS rebuild..."
        if attempt_dkms_fix_action; then
            echo "$current_time" > "$dkms_cooldown_file"
            log "DKMS fix attempted - monitor for improvement"
            return 0
        fi
    fi
    
    # Try GRUB flags if DKMS not available/failed and not in cooldown
    if should_attempt_grub_fix "$grub_cooldown_file" "$current_time"; then
        log "Attempting GRUB flags fix..."
        if attempt_grub_fix_action; then
            echo "$current_time" > "$grub_cooldown_file"
            log "GRUB flags fix attempted - reboot may be required"
            return 0
        fi
    fi
    
    log "No i915 fixes available or all in cooldown"
    return 1
}

should_attempt_dkms_fix() {
    local cooldown_file="$1"
    local current_time="$2"
    local cooldown_hours=6
    
    if [[ ! -f "$cooldown_file" ]]; then
        return 0  # No previous fix
    fi
    
    local last_fix
    last_fix=$(cat "$cooldown_file" 2>/dev/null || echo "0")
    local time_diff=$(( (current_time - last_fix) / 3600 ))
    
    [[ $time_diff -ge $cooldown_hours ]]
}

should_attempt_grub_fix() {
    local cooldown_file="$1"
    local current_time="$2"
    local cooldown_hours=24
    
    if [[ ! -f "$cooldown_file" ]]; then
        return 0  # No previous fix
    fi
    
    local last_fix
    last_fix=$(cat "$cooldown_file" 2>/dev/null || echo "0")
    local time_diff=$(( (current_time - last_fix) / 3600 ))
    
    [[ $time_diff -ge $cooldown_hours ]]
}

attempt_dkms_fix_action() {
    # Check if DKMS modules exist
    if ! command -v dkms >/dev/null 2>&1; then
        log "DKMS not available"
        return 1
    fi
    
    # List i915-related DKMS modules
    local dkms_modules
    dkms_modules=$(dkms status 2>/dev/null | grep -i "i915\|intel" || echo "")
    
    if [[ -z "$dkms_modules" ]]; then
        log "No i915 DKMS modules found"
        return 1
    fi
    
    log "Found DKMS modules: $dkms_modules"
    
    # This would need root privileges - log the recommendation
    log "DKMS rebuild recommended - requires root privileges"
    send_alert "warning" "🔧 i915 fix: DKMS rebuild recommended (run as root: dkms autoinstall)"
    
    return 0
}

attempt_grub_fix_action() {
    # Check current GRUB configuration
    local grub_file="/etc/default/grub"
    if [[ ! -f "$grub_file" ]]; then
        log "GRUB configuration not found"
        return 1
    fi
    
    # Check if i915 flags are already set
    if grep -q "i915.enable_psr=0" "$grub_file" 2>/dev/null; then
        log "i915 GRUB flags already present"
        return 1
    fi
    
    log "GRUB flags fix recommended - requires root privileges"
    send_alert "warning" "🔧 i915 fix: GRUB flags needed (i915.enable_psr=0 i915.enable_fbc=0)"
    
    return 0
}

# Module validation
validate_module "$MODULE_NAME"

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_status
fi