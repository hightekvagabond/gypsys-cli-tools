#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#  i915-watch.sh – Self-healing watchdog for Intel-i915 GPU error storms
#
#  DEVELOPER NOTES
#  ---------------
#  Enhanced version of the original simple error-counting watchdog.
#  Now includes automatic fix capabilities with intelligent escalation.
#
#  ARCHITECTURE
#  ------------
#  - Error pattern detection via journalctl + grep
#  - Three-tier escalation: warn → attempt fixes → critical alert
#  - Cooldown periods prevent fix loops (6h DKMS, 24h GRUB flags)
#  - State tracking in /var/tmp/i915-watch-state
#  - Integration with i915-fix-all.sh for actual fix operations
#
#  ESCALATION LOGIC
#  ----------------
#  - WARN_THRESHOLD (5): Desktop notification only
#  - FIX_THRESHOLD (15): Attempt DKMS fix, then GRUB flags if needed
#  - CRITICAL_THRESHOLD (50): Manual intervention required alert
#
#  ERROR PATTERNS DETECTED
#  -----------------------
#  - "i915.*ERROR" - General i915 driver errors
#  - "workqueue: i915_hpd" - Hot-plug detection workqueue issues
#
#  DEPLOYMENT
#  ----------
#  Designed for cron execution (hourly recommended).
#  Use i915-install.sh for automated deployment.
#
# -----------------------------------------------------------------------------

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX_SCRIPT="$SCRIPT_DIR/i915-fix-all.sh"
STATE_FILE="/var/tmp/i915-watch-state"

# Thresholds for escalation
WARN_THRESHOLD=5      # Start warning at this error count
FIX_THRESHOLD=15      # Attempt automatic fixes at this count  
CRITICAL_THRESHOLD=50 # Critical alert threshold

# Cooldown periods (in hours) to prevent fix loops
DKMS_COOLDOWN=6       # Wait 6 hours before trying DKMS fix again
FLAGS_COOLDOWN=24     # Wait 24 hours before trying GRUB flags fix again

# Logging function
log() {
    echo "[i915-watch] $*"
    logger -t "i915-watch" "$*"
}

# Get current error count
get_error_count() {
    journalctl -b | grep -cE "i915.*ERROR|workqueue: i915_hpd" || echo "0"
}

# Check if we're in a cooldown period for a specific fix type
is_in_cooldown() {
    local fix_type="$1"
    local cooldown_hours="$2"
    local state_key="last_${fix_type}_fix"
    
    if [[ ! -f "$STATE_FILE" ]]; then
        return 1  # No state file = no cooldown
    fi
    
    local last_fix_time
    last_fix_time=$(grep "^$state_key=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2 || echo "0")
    
    local current_time
    current_time=$(date +%s)
    
    local cooldown_seconds=$((cooldown_hours * 3600))
    local time_since_fix=$((current_time - last_fix_time))
    
    if [[ $time_since_fix -lt $cooldown_seconds ]]; then
        return 0  # Still in cooldown
    else
        return 1  # Cooldown expired
    fi
}

# Record that we performed a fix
record_fix() {
    local fix_type="$1"
    local state_key="last_${fix_type}_fix"
    local current_time
    current_time=$(date +%s)
    
    # Create state file if it doesn't exist
    touch "$STATE_FILE"
    
    # Update or add the fix timestamp
    if grep -q "^$state_key=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s/^$state_key=.*/$state_key=$current_time/" "$STATE_FILE"
    else
        echo "$state_key=$current_time" >> "$STATE_FILE"
    fi
}

# Check if fix script exists and is executable
check_fix_script() {
    if [[ ! -x "$FIX_SCRIPT" ]]; then
        log "WARNING: Fix script not found or not executable: $FIX_SCRIPT"
        return 1
    fi
    return 0
}

# Attempt DKMS module fix
attempt_dkms_fix() {
    if is_in_cooldown "dkms" "$DKMS_COOLDOWN"; then
        log "DKMS fix in cooldown period, skipping"
        return 1
    fi
    
    log "ATTEMPTING: DKMS module fix for i915 issues"
    
    local fix_output
    fix_output=$("$FIX_SCRIPT" --quiet --dkms-only 2>&1)
    local fix_result=$?
    
    if [[ $fix_result -eq 0 ]]; then
        record_fix "dkms"
        log "DKMS FIX SUCCESS: DKMS modules processed successfully"
        
        # Check if kernel headers are now present
        local kernel=$(uname -r)
        if [[ -e "/lib/modules/$kernel/build" ]]; then
            log "RESULT: Kernel headers now present for $kernel"
        else
            log "WARNING: Kernel headers still missing after DKMS fix"
        fi
        
        notify-send -u normal "i915-watch: Applied DKMS fix for GPU errors" 2>/dev/null || true
        return 0
    else
        log "DKMS FIX FAILED: DKMS operations failed (exit code: $fix_result)"
        log "FIX OUTPUT: $fix_output"
        
        notify-send -u critical "i915-watch: DKMS fix failed" \
            "Check journalctl -t i915-watch for details" 2>/dev/null || true
        
        error "DKMS fix failed - manual intervention may be required"
        return 1
    fi
}

# Attempt GRUB flags fix
attempt_flags_fix() {
    if is_in_cooldown "flags" "$FLAGS_COOLDOWN"; then
        log "GRUB flags fix in cooldown period, skipping"
        return 1
    fi
    
    log "ATTEMPTING: GRUB flags fix for i915 stability"
    
    local fix_output
    fix_output=$("$FIX_SCRIPT" --quiet --flags-only 2>&1)
    local fix_result=$?
    
    if [[ $fix_result -eq 0 ]]; then
        record_fix "flags"
        log "GRUB FLAGS FIX SUCCESS: i915 stability flags applied to GRUB"
        
        # Check if flags are active in current boot
        if grep -q "i915.enable_psr=0" /proc/cmdline; then
            log "RESULT: i915 flags already active in current boot"
        else
            log "RESULT: i915 flags applied to GRUB - reboot required for activation"
            # Trigger KDE reboot notification
            "$FIX_SCRIPT" --help >/dev/null 2>&1 && {
                # Create reboot-required flag for KDE
                touch /var/run/reboot-required 2>/dev/null || true
                echo "i915-watch: GPU stability flags updated" > /var/run/reboot-required.pkgs 2>/dev/null || true
            }
        fi
        
        notify-send -u normal "i915-watch: Applied GRUB flags fix - reboot recommended" 2>/dev/null || true
        return 0
    else
        log "GRUB FLAGS FIX FAILED: GRUB configuration update failed (exit code: $fix_result)"
        log "FIX OUTPUT: $fix_output"
        
        notify-send -u critical "i915-watch: GRUB flags fix failed" \
            "Check journalctl -t i915-watch for details" 2>/dev/null || true
        
        error "GRUB flags fix failed - manual GRUB configuration may be required"
        return 1
    fi
}

# Send notification and log message
send_alert() {
    local urgency="$1"
    local message="$2"
    
    log "$message"
    notify-send -u "$urgency" "i915-watch: $message" 2>/dev/null || true
}

# Show help
show_help() {
    cat << 'EOF'
i915-watch.sh - Self-healing watchdog for Intel i915 GPU errors

DESCRIPTION:
    Comprehensive monitoring and self-healing system for Intel i915 GPU issues.
    Monitors both error logs and system configuration, automatically attempting
    fixes when problems are detected. Designed for hybrid GPU laptops.

USAGE:
    ./i915-watch.sh [OPTIONS]

OPTIONS:
    --help, -h            Show this help message

OPERATION:
    This script runs automatically via cron (typically hourly) and performs:
    
    • Error count monitoring via systemd journal
    • Comprehensive system health checks (GRUB flags, kernel headers, DKMS)
    • Escalating automatic fixes based on severity

    Escalation levels:
    • 5+ errors:  Desktop warning notification
    • 15+ errors OR system issues: Attempt automatic fixes
    • 50+ errors: Critical alert requiring manual intervention

AUTOMATIC FIXES:
    • Missing kernel headers installation
    • DKMS module rebuilding (nvidia, evdi, virtualbox)
    • GRUB kernel flag application (cooldown periods prevent loops)
    • Integration with i915-fix-all.sh for comprehensive repairs

INSTALLATION:
    Use i915-install.sh for proper system integration, or manually add to cron:
    @reboot /path/to/i915-watch.sh
    0 */6 * * * /path/to/i915-watch.sh

MONITORING:
    View watchdog activity: sudo journalctl -t i915-watch -f
    Check error counts: journalctl -b | grep -E "i915.*ERROR|workqueue: i915_hpd" | wc -l

EOF
}

# Run system check and return any issues found
run_system_check() {
    local issues_found=0
    
    log "Running comprehensive system check..."
    
    # Check if fix script is available
    if ! check_fix_script; then
        log "WARNING: Fix script unavailable, limited checking possible"
        return 0
    fi
    
    # Run the full system check (this works without root)
    if "$FIX_SCRIPT" --check-only --quiet >/dev/null 2>&1; then
        log "System check completed successfully"
    else
        log "System check detected potential issues"
        issues_found=1
    fi
    
    # Check for missing kernel headers (common issue)
    local kernel=$(uname -r)
    if [[ ! -e "/lib/modules/$kernel/build" ]]; then
        log "WARNING: Kernel headers missing for $kernel"
        issues_found=1
    fi
    
    # Check if GRUB flags are active
    if ! grep -q "i915.enable_psr=0" /proc/cmdline; then
        log "WARNING: Required i915 flags not active in current boot"
        issues_found=1
    fi
    
    return $issues_found
}

# Main watchdog logic
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done
    
    local errors
    errors=$(get_error_count)
    
    # Always log the current count for monitoring
    if [[ $errors -gt 0 ]]; then
        log "Current boot i915 errors: $errors"
    fi
    
    # Run comprehensive system check
    local system_issues=0
    run_system_check || system_issues=1
    
    # Escalation logic - consider both error count and system issues
    local needs_attention=false
    local fix_attempted=false
    
    if [[ $errors -gt $CRITICAL_THRESHOLD ]]; then
        send_alert "critical" "CRITICAL: $errors i915 errors detected - manual intervention required"
        needs_attention=true
        
    elif [[ $errors -gt $FIX_THRESHOLD ]] || [[ $system_issues -eq 1 ]]; then
        if [[ $errors -gt $FIX_THRESHOLD ]]; then
            log "Error count ($errors) exceeds fix threshold ($FIX_THRESHOLD)"
        fi
        if [[ $system_issues -eq 1 ]]; then
            log "System check detected issues requiring attention"
        fi
        
        if ! check_fix_script; then
            send_alert "critical" "Issues detected but fix script unavailable"
            exit 1
        fi
        
        # Try fixes in order of likelihood to help
        # If system check found missing headers, try DKMS fix first
        if [[ $system_issues -eq 1 ]] && [[ ! -e "/lib/modules/$(uname -r)/build" ]]; then
            log "Missing kernel headers detected, prioritizing DKMS fix"
            if attempt_dkms_fix; then
                fix_attempted=true
            fi
        fi
        
        # If no fix attempted yet or DKMS didn't work, try other fixes
        if [[ $fix_attempted == false ]]; then
            if attempt_dkms_fix; then
                fix_attempted=true
            elif attempt_flags_fix; then
                fix_attempted=true
            fi
        fi
        
        if [[ $fix_attempted == false ]]; then
            if [[ $errors -gt $FIX_THRESHOLD ]]; then
                send_alert "critical" "High i915 errors ($errors) but all fixes in cooldown"
            else
                send_alert "normal" "System issues detected but fixes in cooldown"
            fi
        fi
        
    elif [[ $errors -gt $WARN_THRESHOLD ]]; then
        send_alert "normal" "Warning: $errors i915 errors detected (threshold: $WARN_THRESHOLD)"
    fi
    
    # Emergency thermal check (redundant protection)
    if command -v sensors >/dev/null 2>&1; then
        local max_temp
        max_temp=$(sensors 2>/dev/null | grep -E "Core|Package" | grep -oE "\+[0-9]+\.[0-9]+°C" | sed 's/+//;s/°C//' | sort -n | tail -1)
        if [[ -n "$max_temp" ]] && (( $(echo "$max_temp > 95" | bc -l 2>/dev/null || echo 0) )); then
            log "EMERGENCY: Thermal crisis detected during i915 check - ${max_temp}°C"
            notify-send -u critical "THERMAL EMERGENCY" "i915-watch detected ${max_temp}°C - Check system immediately!" 2>/dev/null || true
        fi
    fi
    
    exit 0
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

