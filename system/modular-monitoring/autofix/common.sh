#!/bin/bash
# Autofix Common Functions
# Centralized grace period management and logging for all autofix scripts

# Configuration
AUTOFIX_LOG_FILE="/var/log/modular-monitor-autofix.log"
GRACE_TRACKING_DIR="/tmp/modular-monitor-grace"
DEFAULT_MONITOR_FREQUENCY_SECONDS=120  # 2 minutes default

# Ensure grace tracking directory exists
mkdir -p "$GRACE_TRACKING_DIR"

# Logging function
autofix_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$AUTOFIX_LOG_FILE"
    logger -t "modular-monitor-autofix" "[$level] $message"
}

# Get the time in seconds since epoch
get_timestamp() {
    date +%s
}

# Check if we're within the grace period for a specific action
# Args: $1=action_name, $2=grace_period_seconds, $3=calling_module
check_grace_period() {
    local action_name="$1"
    local grace_period_seconds="$2"
    local calling_module="$3"
    local monitor_frequency_seconds="${4:-$DEFAULT_MONITOR_FREQUENCY_SECONDS}"
    
    local grace_file="$GRACE_TRACKING_DIR/${action_name}.grace"
    local current_time=$(get_timestamp)
    
    autofix_log "DEBUG" "Checking grace period for $action_name (module: $calling_module, grace: ${grace_period_seconds}s, freq: ${monitor_frequency_seconds}s)"
    
    # If no grace file exists, we're not in a grace period
    if [[ ! -f "$grace_file" ]]; then
        autofix_log "DEBUG" "No existing grace file for $action_name - proceeding"
        return 1  # Not in grace period
    fi
    
    # Read the grace file: timestamp|module|grace_period
    local grace_data
    if ! grace_data=$(cat "$grace_file" 2>/dev/null); then
        autofix_log "WARN" "Could not read grace file for $action_name - proceeding"
        return 1
    fi
    
    local recorded_time="${grace_data%%|*}"
    local recorded_module="${grace_data#*|}"
    recorded_module="${recorded_module%%|*}"
    local recorded_grace="${grace_data##*|}"
    
    # Validate the recorded timestamp
    if ! [[ "$recorded_time" =~ ^[0-9]+$ ]]; then
        autofix_log "WARN" "Invalid timestamp in grace file for $action_name - proceeding"
        return 1
    fi
    
    # Calculate total grace period (grace period + monitor frequency)
    # This ensures we don't run autofix more frequently than it can be detected
    local total_grace_period=$((grace_period_seconds + monitor_frequency_seconds))
    local elapsed_time=$((current_time - recorded_time))
    
    autofix_log "DEBUG" "Grace period check: elapsed=${elapsed_time}s, total_grace=${total_grace_period}s, recorded_module=$recorded_module"
    
    if [[ $elapsed_time -lt $total_grace_period ]]; then
        local remaining_time=$((total_grace_period - elapsed_time))
        autofix_log "INFO" "Action $action_name is in grace period (${remaining_time}s remaining, originally requested by $recorded_module)"
        return 0  # Still in grace period
    else
        autofix_log "DEBUG" "Grace period expired for $action_name - proceeding"
        return 1  # Grace period expired
    fi
}

# Start a grace period for a specific action
# Args: $1=action_name, $2=grace_period_seconds, $3=calling_module
start_grace_period() {
    local action_name="$1"
    local grace_period_seconds="$2"
    local calling_module="$3"
    
    local grace_file="$GRACE_TRACKING_DIR/${action_name}.grace"
    local current_time=$(get_timestamp)
    
    # Record: timestamp|module|grace_period
    echo "${current_time}|${calling_module}|${grace_period_seconds}" > "$grace_file"
    
    autofix_log "INFO" "Started ${grace_period_seconds}s grace period for $action_name (requested by $calling_module)"
}

# Clean up expired grace files (housekeeping)
cleanup_expired_grace_files() {
    local current_time=$(get_timestamp)
    local cleaned=0
    
    for grace_file in "$GRACE_TRACKING_DIR"/*.grace; do
        [[ ! -f "$grace_file" ]] && continue
        
        local grace_data
        if ! grace_data=$(cat "$grace_file" 2>/dev/null); then
            continue
        fi
        
        local recorded_time="${grace_data%%|*}"
        local recorded_grace="${grace_data##*|}"
        
        # If grace file is older than 24 hours, remove it (safety cleanup)
        if [[ "$recorded_time" =~ ^[0-9]+$ ]] && [[ $((current_time - recorded_time)) -gt 86400 ]]; then
            rm -f "$grace_file"
            ((cleaned++))
        fi
    done
    
    if [[ $cleaned -gt 0 ]]; then
        autofix_log "DEBUG" "Cleaned up $cleaned expired grace files"
    fi
}

# Standard autofix wrapper function
# This should be called by all autofix scripts to ensure proper grace period management
# Args: $1=action_name, $2=calling_module, $3=grace_period_seconds, $4=actual_action_function, $5...$n=action_function_args
run_autofix_with_grace() {
    local action_name="$1"
    local calling_module="$2"
    local grace_period_seconds="$3"
    local action_function="$4"
    shift 4  # Remove the first 4 args, leaving only function args
    
    autofix_log "INFO" "Autofix request: $action_name from module $calling_module with ${grace_period_seconds}s grace period"
    
    # Cleanup expired grace files
    cleanup_expired_grace_files
    
    # Check if we're in a grace period
    if check_grace_period "$action_name" "$grace_period_seconds" "$calling_module"; then
        autofix_log "INFO" "Skipping $action_name - still in grace period"
        return 2  # Grace period active
    fi
    
    # Start grace period
    start_grace_period "$action_name" "$grace_period_seconds" "$calling_module"
    
    # Execute the action
    autofix_log "INFO" "Executing $action_name (called by $calling_module)"
    if "$action_function" "$@"; then
        autofix_log "INFO" "Successfully executed $action_name"
        return 0
    else
        local exit_code=$?
        autofix_log "ERROR" "Failed to execute $action_name (exit code: $exit_code)"
        return $exit_code
    fi
}

# Helper function to validate autofix script arguments
# All autofix scripts should call this to ensure they received proper arguments
validate_autofix_args() {
    local script_name="$1"
    local calling_module="$2"
    local grace_period="$3"
    
    if [[ -z "$calling_module" ]]; then
        autofix_log "ERROR" "$script_name: Missing required argument - calling module"
        echo "Usage: $script_name <calling_module> <grace_period_seconds> [additional_args...]"
        echo "Example: $script_name thermal 45 emergency"
        return 1
    fi
    
    if [[ -z "$grace_period" ]] || ! [[ "$grace_period" =~ ^[0-9]+$ ]]; then
        autofix_log "ERROR" "$script_name: Invalid grace period '$grace_period' (must be numeric seconds)"
        echo "Usage: $script_name <calling_module> <grace_period_seconds> [additional_args...]"
        echo "Example: $script_name thermal 45 emergency"
        return 1
    fi
    
    autofix_log "DEBUG" "$script_name: Valid arguments - module=$calling_module, grace=${grace_period}s"
    return 0
}

# Initialize autofix logging
autofix_log "DEBUG" "Autofix common functions loaded"
