#!/bin/bash
# =============================================================================
# AUTOFIX COMMON FUNCTIONS
# =============================================================================

# Source root common.sh for centralized configuration management
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../common.sh" ]]; then
    source "$SCRIPT_DIR/../common.sh"
elif [[ -f "$(dirname "$SCRIPT_DIR")/common.sh" ]]; then
    source "$(dirname "$SCRIPT_DIR")/common.sh"
else
    echo "ERROR: Cannot find root common.sh from autofix/common.sh" >&2
    exit 1
fi
#
# PURPOSE:
#   Provides centralized grace period management, logging, and initialization
#   for all autofix scripts. This prevents autofix actions from being executed
#   too frequently and ensures consistent behavior across all emergency response
#   scripts. The grace period system tracks when actions were last taken and
#   prevents duplicate actions within configured timeframes.
#
# KEY FEATURES:
#   - Grace period coordination across multiple monitoring modules
#   - Centralized logging with timestamps and severity levels
#   - Standardized autofix script initialization
#   - Cross-module action tracking to prevent conflicts
#   - Configurable cooldown periods per action type
#
# USAGE:
#   This file is sourced by all autofix scripts. Individual scripts should
#   call init_autofix_script() for standardized setup, then use the provided
#   grace period and logging functions.
#
# GRACE PERIOD LOGIC:
#   When multiple modules detect issues requiring the same autofix action,
#   this system ensures the action is only taken once within the grace period.
#   For example, if both thermal and memory modules want to kill a high-CPU
#   process, only the first request will execute immediately; subsequent
#   requests within the grace period will be logged but not executed.
#
# =============================================================================

# show_autofix_help() - Display help information for autofix scripts
# =============================================================================
#
# PURPOSE:
#   Provides standardized help information for all autofix scripts, showing
#   common usage patterns and safety information.
#
# PARAMETERS:
#   $1 - script_name: Name of the autofix script
#
# send_autofix_notification() - Send desktop notification for autofix events
# =============================================================================
#
# PURPOSE:
#   Sends desktop notifications to inform users about autofix actions,
#   especially when actions are disabled or prevented.
#
# PARAMETERS:
#   $1 - title: Notification title
#   $2 - message: Notification message
#   $3 - urgency: low, normal, or critical (optional, defaults to normal)
#
send_autofix_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    
    # Try to send desktop notification if notify-send is available
    if command -v notify-send >/dev/null 2>&1; then
        notify-send --urgency="$urgency" --icon=dialog-warning --app-name="Modular Monitor" "$title" "$message" 2>/dev/null || true
    fi
    
    # Also log the notification attempt
    autofix_log "INFO" "NOTIFICATION: $title - $message"
}

show_autofix_help() {
    local script_name="$1"
    
    cat << EOF
AUTOFIX SCRIPT: $script_name

PURPOSE:
    Automated system remediation script called by monitoring modules
    when critical issues are detected.

USAGE:
    $script_name <calling_module> <grace_period_seconds> [additional_args...]
    $script_name --dry-run [additional_args...]
    $script_name --force [additional_args...]
    $script_name --help

ARGUMENTS:
    calling_module        Name of monitoring module triggering this autofix
    grace_period_seconds  Minimum seconds between autofix executions
    additional_args       Script-specific arguments (varies by script)

OPTIONS:
    --dry-run            Test mode - logs actions but doesn't execute them
    --force              Bypass grace period checks (manual override)
    --help               Show this help information

SAFETY FEATURES:
    • Grace period prevents rapid repeated execution
    • Dry-run mode for safe testing
    • Comprehensive logging of all actions
    • Input validation and sanity checks

EXAMPLES:
    $script_name thermal 300 cpu_temp 95C     # Called by thermal module
    $script_name --dry-run thermal 300        # Test mode
    $script_name --force thermal 300          # Force execution (bypass grace)
    $script_name --help                        # Show help

For script-specific usage and parameters, see the script's header comments.

SECURITY WARNING:
    Autofix scripts perform potentially dangerous system operations.
    Always test with --dry-run first and understand what the script does.
EOF
}

# Configuration
# Use local log file if /var/log is not writable (for testing)
if [[ -w "/var/log" ]]; then
    AUTOFIX_LOG_FILE="/var/log/modular-monitor-autofix.log"
else
    AUTOFIX_LOG_FILE="$(dirname "${BASH_SOURCE[0]}")/../autofix.log"
fi
GRACE_TRACKING_DIR="/tmp/modular-monitor-grace"
DEFAULT_MONITOR_FREQUENCY_SECONDS=120  # 2 minutes default

# Ensure grace tracking directory exists
mkdir -p "$GRACE_TRACKING_DIR"

# =============================================================================
# init_autofix_script() - Standardized autofix script initialization
# =============================================================================
#
# PURPOSE:
#   Performs common initialization tasks for all autofix scripts, eliminating
#   boilerplate code and ensuring consistent setup across all emergency response
#   actions.
#
# PARAMETERS:
#   $@ - All arguments passed to the autofix script
#        Expected format: <calling_module> <grace_period_seconds> [additional_args...]
#
# SETS GLOBAL VARIABLES:
#   CALLING_MODULE - Name of the monitoring module that triggered this autofix
#   GRACE_PERIOD   - Grace period in seconds for this specific action
#
# BEHAVIOR:
#   1. Loads modules/common.sh for access to helper functions
#   2. Validates that required arguments are present and properly formatted
#   3. Sets standard variables used by all autofix scripts
#   4. Logs initialization for debugging and audit purposes
#   5. Exits with error code 1 if validation fails
#
# EXAMPLE:
#   init_autofix_script "$@"  # Call from autofix script with all arguments
#
init_autofix_script() {
    local script_name
    script_name="$(basename "${BASH_SOURCE[1]}")"  # Get calling script name
    
    # Check for help request BEFORE argument validation
    if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
        show_autofix_help "$script_name"
        exit 0
    fi
    
    # Load modules common.sh for helper functions
    local project_root
    project_root="$(dirname "$SCRIPT_DIR")"
    if [[ -f "$project_root/modules/common.sh" ]]; then
        autofix_log "INFO" "About to source modules/common.sh - AUTOFIX='${AUTOFIX:-<unset>}'"
        source "$project_root/modules/common.sh"
        autofix_log "INFO" "After sourcing modules/common.sh - AUTOFIX='${AUTOFIX:-<unset>}'"
    fi
    
    # Validate arguments (now safe since help was already handled)
    if ! validate_autofix_args "$script_name" "$1" "$2"; then
        exit 1
    fi
    
    # Set standard autofix variables - handle dry-run mode argument shifting
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        # In dry-run mode, arguments were shifted by validate_autofix_args
        CALLING_MODULE="$2"  # Second argument after --dry-run
        GRACE_PERIOD="$3"    # Third argument after --dry-run
    else
        # Normal mode
        CALLING_MODULE="$1"
        GRACE_PERIOD="$2"
    fi
    
    # Load module and helper configs if we know the calling module
    if [[ -n "${CALLING_MODULE:-}" && "${CALLING_MODULE}" != "--dry-run" && "${CALLING_MODULE}" != "--force" ]]; then
        autofix_log "DEBUG" "Loading module and helper configs for: $CALLING_MODULE"
        load_all_configs "$CALLING_MODULE"
        autofix_log "DEBUG" "Module and helper configs loaded for: $CALLING_MODULE"
    fi
    
    # Export for use by autofix script
    export CALLING_MODULE GRACE_PERIOD
    
    autofix_log "INFO" "Initialized $script_name: module=$CALLING_MODULE, grace=$GRACE_PERIOD"
}

# =============================================================================
# autofix_log() - Centralized logging with timestamp and syslog integration
# =============================================================================
#
# PURPOSE:
#   Provides consistent logging across all autofix scripts with both file
#   and syslog output. Critical for debugging and audit trails.
#
# PARAMETERS:
#   $1 - Log level (INFO, WARN, ERROR, CRITICAL)
#   $2 - Log message (should be descriptive and include context)
#
# SECURITY CONSIDERATIONS:
#   - Message content is NOT validated for injection attacks
#   - Could be vulnerable if $2 contains command substitution like $(rm -rf /)
#   - Should validate/sanitize message content before logging
#
# BASH CONCEPTS FOR BEGINNERS:
#   - 'local' creates variables that only exist inside this function
#   - '$()' is command substitution - runs the command and uses its output
#   - 'tee -a' writes to both stdout AND appends to a file
#   - 'logger' sends messages to the system log (journald/syslog)
#
# EXAMPLE:
#   autofix_log "ERROR" "Failed to kill process PID 1234"
#
autofix_log() {
    local level="$1"
    local message="$2"
    
    # SECURITY ISSUE: Should validate/sanitize message to prevent injection
    # TODO: Add message validation to prevent command injection
    
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"  # Quoted to prevent word splitting
    
    echo "[$timestamp] [$level] $message" | tee -a "$AUTOFIX_LOG_FILE"
    logger -t "modular-monitor-autofix" "[$level] $message"
}

# =============================================================================
# get_timestamp() - Get current time as Unix epoch seconds
# =============================================================================
#
# PURPOSE:
#   Returns the current time as seconds since Unix epoch (1970-01-01).
#   Used for grace period calculations and time-based comparisons.
#
# RETURNS:
#   Integer representing seconds since epoch (e.g., 1693123456)
#
# BASH CONCEPTS FOR BEGINNERS:
#   - Unix epoch is the standard way computers measure time
#   - 'date +%s' outputs current time as a number
#   - This number increases by 1 every second
#   - Easy to do math with (current_time - old_time = seconds_elapsed)
#
# PERFORMANCE:
#   - Very fast operation, safe to call frequently
#   - No external dependencies beyond basic 'date' command
#
get_timestamp() {
    date +%s
}

# =============================================================================
# check_grace_period() - Prevent repeated autofix actions within timeframe
# =============================================================================
#
# PURPOSE:
#   Checks if a specific autofix action was recently performed and should be
#   skipped to prevent dangerous repeated actions (like multiple shutdowns).
#   This is the core safety mechanism of the autofix system.
#
# PARAMETERS:
#   $1 - action_name: Unique identifier for the action (e.g., "emergency_shutdown")
#   $2 - grace_period_seconds: How long to wait before allowing action again
#   $3 - calling_module: Which monitoring module is requesting this action
#   $4 - monitor_frequency_seconds: How often the monitor runs (optional)
#
# RETURNS:
#   0 - We ARE in grace period (don't execute action)
#   1 - We are NOT in grace period (safe to execute action)
#
# SECURITY CONSIDERATIONS:
#   - Uses $GRACE_TRACKING_DIR which could be manipulated by other processes
#   - Grace files in /tmp could be deleted by system cleanup or attackers
#   - action_name should be validated to prevent directory traversal (../)
#   - File parsing could be vulnerable if grace file is corrupted maliciously
#
# BASH CONCEPTS FOR BEGINNERS:
#   - 'local' variables only exist inside this function
#   - '${var:-default}' uses 'default' if 'var' is empty
#   - '${var%%pattern}' removes longest match of pattern from the end
#   - '${var##pattern}' removes longest match of pattern from the start
#   - '[[ ]]' is bash's advanced test command (better than [ ])
#   - '=~' does regular expression matching
#   - '^[0-9]+$' means "only digits from start to end"
#
# SAFETY MECHANISM:
#   This prevents disasters like:
#   - Multiple emergency shutdowns in quick succession
#   - Repeatedly killing the same critical process
#   - Rapid-fire disk cleanups that could corrupt filesystems
#
# EXAMPLE:
#   if check_grace_period "emergency_shutdown" 300 "thermal"; then
#       echo "Recently shut down, skipping"
#   else 
#       echo "Safe to shutdown"
#   fi
#
check_grace_period() {
    local action_name="$1"
    local grace_period_seconds="$2"
    local calling_module="$3"
    local monitor_frequency_seconds="${4:-$DEFAULT_MONITOR_FREQUENCY_SECONDS}"
    
    # SECURITY: Validate action_name to prevent directory traversal attacks
    # Only allow alphanumeric, hyphens, and underscores
    if [[ ! "$action_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        autofix_log "ERROR" "Invalid action_name '$action_name' - security violation"
        return 1  # Treat as not in grace period but log the security issue
    fi
    
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

# =============================================================================
# start_grace_period() - Begin tracking grace period for an action
# =============================================================================
#
# PURPOSE:
#   Records that an autofix action has been taken and should not be repeated
#   for a specified time period. Called AFTER successfully executing an action.
#
# PARAMETERS:
#   $1 - action_name: Unique identifier for the action
#   $2 - grace_period_seconds: How long to prevent repeating this action
#   $3 - calling_module: Which module executed this action
#
# SECURITY CONSIDERATIONS:
#   - Should validate action_name to prevent directory traversal
#   - Creates files in /tmp which could be manipulated by other processes
#   - File creation could fail due to permissions or disk space
#
# BASH CONCEPTS FOR BEGINNERS:
#   - '>' redirects output to a file (overwrites existing content)
#   - This creates a simple text file with the timestamp and metadata
#   - The file acts as a "lock" to prevent repeated actions
#
# EXAMPLE:
#   start_grace_period "emergency_shutdown" 300 "thermal"
#
start_grace_period() {
    local action_name="$1"
    local grace_period_seconds="$2"
    local calling_module="$3"
    
    # SECURITY: Validate action_name to prevent directory traversal attacks
    if [[ ! "$action_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        autofix_log "ERROR" "Invalid action_name '$action_name' - security violation"
        return 1
    fi
    
    local grace_file="$GRACE_TRACKING_DIR/${action_name}.grace"
    local current_time=$(get_timestamp)
    
    # Record: timestamp|module|grace_period
    echo "${current_time}|${calling_module}|${grace_period_seconds}" > "$grace_file"
    
    autofix_log "INFO" "Started ${grace_period_seconds}s grace period for $action_name (requested by $calling_module)"
}

# =============================================================================
# cleanup_expired_grace_files() - Remove old grace tracking files
# =============================================================================
#
# PURPOSE:
#   Removes grace files older than 24 hours to prevent /tmp from filling up
#   with stale tracking files. This is maintenance to keep the system clean.
#
# SECURITY CONSIDERATIONS:
#   - Uses 'rm -f' which could be dangerous if GRACE_TRACKING_DIR is wrong
#   - Glob expansion with *.grace could match unexpected files
#   - Should validate paths before deletion
#
# BASH CONCEPTS FOR BEGINNERS:
#   - 'for file in pattern' loops through matching files
#   - '[[ ! -f "$file" ]] && continue' skips if file doesn't exist
#   - '&&' means "and" - only run second command if first succeeds
#   - '(( ))' is arithmetic context for math operations
#   - '86400' is seconds in 24 hours (60*60*24)
#
# PERFORMANCE:
#   - Only runs cleanup when needed
#   - Uses efficient file operations
#   - Logs cleanup activity for debugging
#
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

# =============================================================================
# run_autofix_with_grace() - Execute autofix action with grace period protection
# =============================================================================
#
# PURPOSE:
#   High-level wrapper that combines grace period checking, action execution,
#   and cleanup. This is the recommended way to run any autofix action.
#
# PARAMETERS:
#   $1 - action_name: Unique identifier for this action
#   $2 - calling_module: Module requesting the action
#   $3 - grace_period_seconds: Cooldown time before action can repeat
#   $4 - action_function: Name of function to execute
#   $5+ - Additional arguments passed to the action function
#
# RETURNS:
#   0 - Action executed successfully
#   1 - Action failed (check logs for details)
#   2 - Action skipped due to grace period
#
# SECURITY CONSIDERATIONS:
#   - Action function name should be validated to prevent injection
#   - Function execution uses "$action_function" which could be exploited
#   - Should restrict allowed function names or use safer execution method
#
# BASH CONCEPTS FOR BEGINNERS:
#   - 'shift 4' removes first 4 arguments, leaving remaining ones for function
#   - '"$@"' passes all remaining arguments exactly as they were received
#   - 'if "$action_function" "$@"' calls the function by name with arguments
#   - '$?' captures the exit code of the last command
#
# EXAMPLE:
#   run_autofix_with_grace "disk_cleanup" "disk" 300 cleanup_logs "/var/log"
#
run_autofix_with_grace() {
    local action_name="$1"
    local calling_module="$2"
    local grace_period_seconds="$3"
    local action_function="$4"
    shift 4  # Remove the first 4 args, leaving only function args
    
    autofix_log "INFO" "Autofix request: $action_name from module $calling_module with ${grace_period_seconds}s grace period"
    
    # Check if autofix is enabled using centralized configuration logic
    autofix_log "INFO" "About to call is_autofix_enabled() - AUTOFIX='${AUTOFIX:-<unset>}'"
    if ! is_autofix_enabled; then
        autofix_log "INFO" "AUTOFIX DISABLED - Log-only mode active"
        autofix_log "INFO" "Would execute: $action_name"
        autofix_log "INFO" "Called by: $calling_module"
        autofix_log "INFO" "Grace period: ${grace_period_seconds}s"
        autofix_log "INFO" "Function: $action_function"
        autofix_log "INFO" "Arguments: $*"
        autofix_log "INFO" "AUTOFIX is disabled in system configuration - no action taken"
        
        # Extract device information from arguments for better visibility
        local device_info
        device_info=$(extract_device_info "$@")
        
        # Send desktop notification with device info if available
        local notification_msg="Action '$action_name' was requested by '$calling_module'"
        if [[ -n "$device_info" ]]; then
            notification_msg="$notification_msg for device: $device_info"
        fi
        notification_msg="$notification_msg but autofix is globally disabled. Enable in config/SYSTEM.conf"
        
        send_autofix_notification "🚫 Autofix Disabled" "$notification_msg" "low"
        
        echo "🚫 AUTOFIX DISABLED: $action_name would be executed but AUTOFIX=false in configuration"
        echo "   Called by: $calling_module"
        if [[ -n "$device_info" ]]; then
            echo "   Device: $device_info"
        fi
        echo "   Function: $action_function"
        echo "   Arguments: $*"
        echo "   To enable: Set AUTOFIX=true in config/SYSTEM.conf"
        return 0  # Success (logged the action)
    fi
    
    # Check if this specific autofix action is enabled using centralized logic
    autofix_log "INFO" "About to call is_autofix_enabled('$action_name') - AUTOFIX='${AUTOFIX:-<unset>}'"
    if ! is_autofix_enabled "$action_name"; then
        autofix_log "INFO" "AUTOFIX SELECTIVELY DISABLED - $action_name is disabled by configuration"
        autofix_log "INFO" "Would execute: $action_name"
        autofix_log "INFO" "Called by: $calling_module"
        autofix_log "INFO" "Grace period: ${grace_period_seconds}s"
        autofix_log "INFO" "Function: $action_function"
        autofix_log "INFO" "Arguments: $*"
        
        # Extract device information from arguments for better visibility
        local device_info
        device_info=$(extract_device_info "$@")
        
        # Send desktop notification with device info if available
        local notification_msg="Action '$action_name' was requested by '$calling_module'"
        if [[ -n "$device_info" ]]; then
            notification_msg="$notification_msg for device: $device_info"
        fi
        notification_msg="$notification_msg but is disabled by configuration. Set AUTOFIX=true environment variable to override"
        
        send_autofix_notification "🚫 Autofix Disabled" "$notification_msg" "low"
        
        echo "🚫 AUTOFIX DISABLED: $action_name is disabled by configuration"
        echo "   Called by: $calling_module"
        if [[ -n "$device_info" ]]; then
            echo "   Device: $device_info"
        fi
        echo "   Function: $action_function"
        echo "   Arguments: $*"
        echo "   To enable: Set AUTOFIX=true environment variable or modify configuration"
        return 0  # Success (logged the action)
    fi
    
    # Cleanup expired grace files
    cleanup_expired_grace_files
    
    # Check if we're in a grace period (unless force override is enabled)
    if [[ "${OVERRIDE_GRACE:-false}" == "true" ]]; then
        autofix_log "WARN" "Grace period check bypassed due to --force flag"
    elif check_grace_period "$action_name" "$grace_period_seconds" "$calling_module"; then
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

# =============================================================================
# validate_autofix_args() - Validate arguments passed to autofix scripts
# =============================================================================
#
# PURPOSE:
#   Ensures autofix scripts receive properly formatted arguments before
#   proceeding with potentially dangerous operations. Supports dry-run mode
#   and grace period override for safe testing of autofix operations.
#
# PARAMETERS:
#   $1 - script_name: Name of script for error messages
#   $2 - calling_module: Module name (must not be empty, or "--dry-run", or "--force")
#   $3 - grace_period: Grace period in seconds (must be a positive number)
#
# RETURNS:
#   0 - Arguments are valid
#   1 - Arguments are invalid (error logged)
#
# SPECIAL FLAGS SUPPORT:
#   --dry-run: Sets DRY_RUN=true for safe testing without execution
#   --force: Sets OVERRIDE_GRACE=true to bypass grace period checks
#   --override-grace: Alternative syntax for --force
#
# SECURITY CONSIDERATIONS:
#   - Should validate calling_module format to prevent injection
#   - Grace period should be bounded to prevent DoS attacks
#   - Dry-run mode must be clearly logged to prevent confusion
#   - Grace override should be logged for security audit
#
validate_autofix_args() {
    local script_name="$1"
    local calling_module="${2:-}"
    local grace_period="${3:-}"
    
    # Check for help request first
    if [[ "$calling_module" =~ ^(-h|--help|help)$ ]]; then
        show_autofix_help "$script_name"
        return 1  # Signal to exit
    fi
    
    # Check for special flags
    if [[ "$calling_module" == "--dry-run" ]]; then
        export DRY_RUN=true
        autofix_log "INFO" "$script_name: DRY-RUN MODE ENABLED - No dangerous operations will be performed"
        
        # Shift arguments for dry-run mode
        calling_module="$grace_period"
        grace_period="${4:-60}"  # Default grace period for dry-run
        
        if [[ -z "$calling_module" ]]; then
            autofix_log "ERROR" "$script_name: Missing calling module in dry-run mode"
            echo "Usage: $script_name --dry-run <calling_module> [grace_period_seconds] [additional_args...]"
            echo "Example: $script_name --dry-run thermal 45 emergency"
            return 1
        fi
    elif [[ "$calling_module" == "--force" ]]; then
        export OVERRIDE_GRACE=true
        autofix_log "WARN" "$script_name: FORCE MODE ENABLED - Bypassing grace period checks"
        
        # Shift arguments for force mode
        calling_module="$grace_period"
        grace_period="${4:-60}"  # Default grace period for force mode
        
        if [[ -z "$calling_module" ]]; then
            autofix_log "ERROR" "$script_name: Missing calling module in force mode"
            echo "Usage: $script_name --force <calling_module> [grace_period_seconds] [additional_args...]"
            echo "Example: $script_name --force thermal 45 emergency"
            return 1
        fi
    else
        export DRY_RUN=false
        export OVERRIDE_GRACE=false
    fi
    
    if [[ -z "$calling_module" ]]; then
        autofix_log "ERROR" "$script_name: Missing required argument - calling module"
        echo "Usage: $script_name [--dry-run|--force] <calling_module> <grace_period_seconds> [additional_args...]"
        echo "Example: $script_name thermal 45 emergency"
        echo "Example: $script_name --dry-run thermal 45 emergency"
        echo "Example: $script_name --force thermal 45 emergency"
        return 1
    fi
    
    if [[ -z "$grace_period" ]] || ! [[ "$grace_period" =~ ^[0-9]+$ ]]; then
        autofix_log "ERROR" "$script_name: Invalid grace period '$grace_period' (must be numeric seconds)"
        echo "Usage: $script_name [--dry-run|--force] <calling_module> <grace_period_seconds> [additional_args...]"
        echo "Example: $script_name thermal 45 emergency"
        echo "Example: $script_name --dry-run thermal 45 emergency"
        echo "Example: $script_name --force thermal 45 emergency"
        return 1
    fi
    
    # SECURITY: Validate calling_module format to prevent injection
    if [[ ! "$calling_module" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        autofix_log "ERROR" "$script_name: Invalid calling module name '$calling_module' - security violation"
        return 1
    fi
    
    local mode_info="LIVE MODE"
    if [[ "$DRY_RUN" == "true" ]]; then
        mode_info="DRY-RUN MODE"
    fi
    
    autofix_log "DEBUG" "$script_name: Valid arguments - module=$calling_module, grace=${grace_period}s, mode=$mode_info"
    return 0
}

# =============================================================================
# extract_device_info() - Extract device information from autofix arguments
# =============================================================================
#
# PURPOSE:
#   Centralized function to extract device information from autofix arguments
#   for better logging and notifications. Used by both globally disabled and
#   selectively disabled message handlers.
#
# PARAMETERS:
#   $@ - All arguments passed to the autofix function
#
# RETURNS:
#   Device information string (empty if none found)
#
extract_device_info() {
    local device_info=""
    
    # Simple approach: if arguments contain device-related keywords, use the full arguments
    if [[ "$*" =~ Device|device|Mouse|Keyboard|Hub|Storage|Ethernet|Adapter|Camera|Audio|Controller|USB|usb ]]; then
        # Just use the full arguments string as it contains the device information
        device_info="$*"
    fi
    
    echo "$device_info"
}

# =============================================================================
# dry_run_execute() - Execute command only if not in dry-run mode
# =============================================================================
#
# PURPOSE:
#   Performs all analysis and detection in both modes, but only executes the
#   actual corrective action in live mode. In dry-run mode, reports exactly
#   what corrective action would be taken and why.
#
# PARAMETERS:
#   $1 - description: Human-readable description of the operation
#   $@ - command and arguments that would be executed
#
# RETURNS:
#   0 - Command executed successfully (or dry-run completed)
#   1 - Command failed (only in live mode)
#
# DRY-RUN BEHAVIOR:
#   - Performs all diagnostic checks and analysis
#   - Reports detected issues and their severity
#   - Shows exactly what corrective action would be taken
#   - Explains why this action is needed
#   - Does NOT execute the actual corrective command
#
# EXAMPLES:
#   dry_run_execute "Kill greedy process firefox (PID 1234) using 4GB RAM" kill -TERM 1234
#   dry_run_execute "Emergency shutdown due to thermal overload (CPU: 95°C)" shutdown -h now
#
dry_run_execute() {
    local description="$1"
    shift  # Remove description, leaving only the command
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🧪 DRY-RUN ANALYSIS COMPLETE"
        echo "================================"
        echo "DETECTED ISSUE: Analysis performed successfully"
        echo "RECOMMENDED ACTION: $description"
        echo "COMMAND THAT WOULD BE EXECUTED: $*"
        echo "STATUS: Action NOT executed (dry-run mode)"
        echo "================================"
        autofix_log "INFO" "DRY-RUN: Analysis complete - would execute: $description"
        autofix_log "DEBUG" "DRY-RUN: Command would be: $*"
        return 0
    else
        autofix_log "INFO" "Analysis complete - executing: $description"
        autofix_log "DEBUG" "Command: $*"
        "$@"
        return $?
    fi
}

# =============================================================================
# dry_run_file_operation() - Safely perform file operations in dry-run mode
# =============================================================================
#
# PURPOSE:
#   Handles file operations (create, modify, delete) safely in dry-run mode.
#   Shows what would happen without actually modifying files.
#
# PARAMETERS:
#   $1 - operation: "create", "modify", "delete", "backup"
#   $2 - target_file: File that would be affected
#   $3 - description: Human-readable description
#
# EXAMPLES:
#   dry_run_file_operation "delete" "/tmp/cache" "Clear temporary cache"
#   dry_run_file_operation "modify" "/etc/default/grub" "Update GRUB parameters"
#
# =============================================================================
# dry_run_report_analysis() - Report analysis results in structured format
# =============================================================================
#
# PURPOSE:
#   Provides structured reporting of what the autofix script discovered and
#   what actions it would take. Should be called after all analysis is complete
#   but before any corrective actions.
#
# PARAMETERS:
#   $1 - issue_type: Type of issue detected (e.g., "HIGH_CPU", "DISK_FULL")
#   $2 - severity: "LOW", "MEDIUM", "HIGH", "CRITICAL"  
#   $3 - details: Specific details about what was detected
#   $4 - proposed_action: What action would be taken
#   $5 - reasoning: Why this action is recommended
#
# EXAMPLE:
#   dry_run_report_analysis "HIGH_MEMORY" "HIGH" "firefox using 4.2GB RAM (85% of system)" \
#                           "kill -TERM 1234" "Process exceeds 2GB threshold and is non-critical"
#
dry_run_report_analysis() {
    local issue_type="$1"
    local severity="$2" 
    local details="$3"
    local proposed_action="$4"
    local reasoning="$5"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "🔍 AUTOFIX ANALYSIS RESULTS"
        echo "============================"
        echo "ISSUE TYPE: $issue_type"
        echo "SEVERITY: $severity"
        echo "DETAILS: $details"
        echo "PROPOSED ACTION: $proposed_action"
        echo "REASONING: $reasoning"
        echo "STATUS: Analysis only - no action taken (dry-run mode)"
        echo "============================"
        echo ""
        autofix_log "INFO" "DRY-RUN Analysis: $issue_type ($severity) - $details"
        autofix_log "INFO" "DRY-RUN Proposed: $proposed_action - $reasoning"
    else
        autofix_log "INFO" "Analysis: $issue_type ($severity) - $details"
        autofix_log "INFO" "Action needed: $proposed_action - $reasoning"
    fi
}

dry_run_file_operation() {
    local operation="$1"
    local target_file="$2"
    local description="$3"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "📁 FILE OPERATION ANALYSIS:"
        echo "  Operation: $operation"
        echo "  Target: $target_file"
        echo "  Purpose: $description"
        case "$operation" in
            "delete")
                if [[ -f "$target_file" ]]; then
                    local file_size=$(du -sh "$target_file" 2>/dev/null | cut -f1 || echo "unknown")
                    echo "  Current state: File exists ($file_size)"
                    echo "  Result: File would be deleted"
                else
                    echo "  Current state: File does not exist"
                    echo "  Result: No operation needed"
                fi
                ;;
            "create"|"modify")
                if [[ -f "$target_file" ]]; then
                    echo "  Current state: File exists, would be modified"
                else
                    echo "  Current state: File does not exist, would be created"
                fi
                ;;
            "backup")
                echo "  Current state: Backup would be created as ${target_file}.backup"
                ;;
        esac
        echo ""
        autofix_log "INFO" "DRY-RUN: Would $operation file: $target_file ($description)"
        return 0
    else
        autofix_log "INFO" "File operation: $operation $target_file ($description)"
        return 0  # Actual file operations handled by calling script
    fi
}

# =============================================================================
# execute_command() - Execute command with dry-run support and logging
# =============================================================================
#
# PURPOSE:
#   Executes commands safely with comprehensive dry-run support. In dry-run mode,
#   shows exactly what command would be executed. In live mode, executes the
#   command and logs the result. This function ensures commands are stored in
#   variables and echoed exactly as they would be executed.
#
# PARAMETERS:
#   $1 - cmd: The command to execute (should be a variable containing the command)
#   $2 - description: Human-readable description of what the command does
#
# RETURNS:
#   0 - Command executed successfully (or dry-run completed)
#   1 - Command failed (only in live mode)
#
# DRY-RUN BEHAVIOR:
#   - Echoes the exact command that would be executed
#   - Shows the description of what the command does
#   - Logs the dry-run action for audit purposes
#   - Does NOT execute the actual command
#
# IMPLEMENTATION NOTES:
#   - Commands should be stored in variables before calling this function
#   - The same variable is used for both display and execution
#   - This prevents maintaining commands in two places
#   - Ensures dry-run output shows exactly what would be executed
#
# EXAMPLES:
#   SHUTDOWN_CMD="systemctl poweroff"
#   execute_command "$SHUTDOWN_CMD" "Shutdown system"
#
#   CLEANUP_CMD="rm -rf /tmp/emergency-cache/*"
#   execute_command "$CLEANUP_CMD" "Clean emergency cache files"
#
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $cmd"
        echo "[DRY-RUN] Description: $description"
        autofix_log "INFO" "DRY-RUN: Would execute command - $description"
        autofix_log "DEBUG" "DRY-RUN: Command would be: $cmd"
        return 0
    else
        echo "Executing: $cmd"
        autofix_log "INFO" "Executing command: $description"
        autofix_log "DEBUG" "Command: $cmd"
        eval "$cmd"
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            autofix_log "INFO" "Command executed successfully: $description"
        else
            autofix_log "ERROR" "Command failed (exit code: $exit_code): $description"
        fi
        return $exit_code
    fi
}

# Initialize autofix logging
autofix_log "DEBUG" "Autofix common functions loaded"
