#!/bin/bash
# =============================================================================
# ROOT COMMON FUNCTIONS - CENTRALIZED CONFIGURATION MANAGEMENT
# =============================================================================
#
# PURPOSE:
#   Provides centralized configuration loading with proper priority hierarchy
#   and common functions used across all monitoring scripts, modules, and
#   autofix scripts. This ensures consistent behavior and DRY principles.
#
# CONFIGURATION HIERARCHY (highest to lowest priority):
#   1. Environment Variables (export VARIABLE=value)
#   2. Machine-Specific System Config (config/SYSTEM.conf)
#   3. Module-Specific Config (modules/<MODULE>/config.conf)
#   4. System Default Config (system_default.conf)
#
# USAGE:
#   Source this file from any script that needs configuration:
#   source "$(dirname "$0")/common.sh"           # From root scripts
#   source "$SCRIPT_DIR/../../common.sh"        # From modules/autofix
#
# KEY FEATURES:
#   - Proper configuration hierarchy enforcement
#   - Environment variable override support
#   - Module-specific configuration loading
#   - Logging and debugging support
#   - Standardized path resolution
#
# =============================================================================

# Determine the project root directory
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    # Try to find project root by looking for marker files
    CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # If we're already in root (has system_default.conf), use current dir
    if [[ -f "$CURRENT_DIR/system_default.conf" ]]; then
        PROJECT_ROOT="$CURRENT_DIR"
    # If we're in modules/ or autofix/, go up two levels
    elif [[ "$CURRENT_DIR" =~ .*/modules/.* ]] || [[ "$CURRENT_DIR" =~ .*/autofix.* ]]; then
        PROJECT_ROOT="$(cd "$CURRENT_DIR/../.." && pwd)"
    # If we're in modules or autofix, go up one level
    elif [[ "$(basename "$CURRENT_DIR")" == "modules" ]] || [[ "$(basename "$CURRENT_DIR")" == "autofix" ]]; then
        PROJECT_ROOT="$(cd "$CURRENT_DIR/.." && pwd)"
    else
        # Fallback: search upward for system_default.conf
        SEARCH_DIR="$CURRENT_DIR"
        while [[ "$SEARCH_DIR" != "/" ]]; do
            if [[ -f "$SEARCH_DIR/system_default.conf" ]]; then
                PROJECT_ROOT="$SEARCH_DIR"
                break
            fi
            SEARCH_DIR="$(dirname "$SEARCH_DIR")"
        done
        
        # If still not found, use current directory as fallback
        if [[ -z "${PROJECT_ROOT:-}" ]]; then
            PROJECT_ROOT="$CURRENT_DIR"
        fi
    fi
fi

# Export PROJECT_ROOT for use by other scripts
export PROJECT_ROOT

# =============================================================================
# log_config() - Unified logging function for configuration scripts
# =============================================================================
log_config() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Only log if debugging is enabled or it's an error/warning
    if [[ "${DEBUG_CONFIG:-false}" == "true" ]] || [[ "$level" =~ ^(ERROR|WARN)$ ]]; then
        echo "[$timestamp] [CONFIG] [$level] $message" >&2
    fi
}

# =============================================================================
# load_system_defaults() - Load system default configuration
# =============================================================================
load_system_defaults() {
    local defaults_file="$PROJECT_ROOT/system_default.conf"
    
    if [[ -f "$defaults_file" ]]; then
        log_config "DEBUG" "Loading system defaults from: $defaults_file"
        log_config "DEBUG" "AUTOFIX before loading defaults: '${AUTOFIX:-<unset>}'"
        # Use a subshell to avoid polluting current environment
        source "$defaults_file"
        log_config "DEBUG" "AUTOFIX after loading defaults: '${AUTOFIX:-<unset>}'"
        log_config "DEBUG" "System defaults loaded successfully"
    else
        log_config "WARN" "System defaults file not found: $defaults_file"
    fi
}

# =============================================================================
# load_system_config() - Load machine-specific system configuration
# =============================================================================
load_system_config() {
    local system_config="$PROJECT_ROOT/config/SYSTEM.conf"
    
    if [[ -f "$system_config" ]]; then
        log_config "DEBUG" "Loading system config from: $system_config"
        log_config "DEBUG" "AUTOFIX before loading system config: '${AUTOFIX:-<unset>}'"
        source "$system_config"
        log_config "DEBUG" "AUTOFIX after loading system config: '${AUTOFIX:-<unset>}'"
        log_config "DEBUG" "System config loaded successfully"
    else
        log_config "DEBUG" "System config file not found: $system_config (this is optional)"
    fi
}

# =============================================================================
# load_module_config() - Load module-specific configuration
# =============================================================================
load_module_config() {
    local module_name="$1"
    
    if [[ -z "$module_name" ]]; then
        log_config "DEBUG" "No module name provided, skipping module config"
        return 0
    fi
    
    # Load module's default config first
    local module_config="$PROJECT_ROOT/modules/$module_name/config.conf"
    if [[ -f "$module_config" ]]; then
        log_config "DEBUG" "Loading module config from: $module_config"
        source "$module_config"
        log_config "DEBUG" "Module config loaded for: $module_name"
    else
        log_config "DEBUG" "Module config not found: $module_config (this is optional)"
    fi
    
    # Load any override config (in config directory)
    local override_config="$PROJECT_ROOT/config/$module_name.conf"
    if [[ -f "$override_config" ]]; then
        log_config "DEBUG" "Loading module override from: $override_config"
        source "$override_config"
        log_config "INFO" "Applied override config for $module_name"
    fi
}

# =============================================================================
# preserve_environment_vars() - Save environment variables before config loading
# =============================================================================
preserve_environment_vars() {
    # Save critical environment variables that should override config files
    local env_vars=("AUTOFIX" "DISABLE_AUTOFIX" "PREFERRED_KERNEL_BRANCH" "GRAPHICS_CHIPSET" "USE_MODULES" "IGNORE_MODULES")
    
    log_config "DEBUG" "=== PRESERVE ENVIRONMENT VARS START ==="
    for var in "${env_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            # Save the environment variable value with a special prefix
            eval "ENV_OVERRIDE_${var}=\"${!var}\""
            log_config "DEBUG" "Preserved environment variable: $var=${!var}"
        else
            log_config "DEBUG" "Environment variable not set: $var"
        fi
    done
    log_config "DEBUG" "=== PRESERVE ENVIRONMENT VARS END ==="
}

# =============================================================================
# restore_environment_vars() - Restore environment variables after config loading
# =============================================================================
restore_environment_vars() {
    # Restore environment variables (highest priority)
    local env_vars=("AUTOFIX" "DISABLE_AUTOFIX" "PREFERRED_KERNEL_BRANCH" "GRAPHICS_CHIPSET" "USE_MODULES" "IGNORE_MODULES")
    
    log_config "DEBUG" "=== RESTORE ENVIRONMENT VARS START ==="
    for var in "${env_vars[@]}"; do
        local env_override_var="ENV_OVERRIDE_${var}"
        if [[ -n "${!env_override_var:-}" ]]; then
            # Restore the environment variable value (overriding config files)
            log_config "DEBUG" "$var before restore: '${!var:-<unset>}'"
            eval "${var}=\"${!env_override_var}\""
            log_config "DEBUG" "$var after restore: '${!var:-<unset>}'"
            log_config "DEBUG" "Restored environment variable override: $var=${!env_override_var}"
        else
            log_config "DEBUG" "No environment override for: $var (current value: '${!var:-<unset>}')"
        fi
    done
    log_config "DEBUG" "=== RESTORE ENVIRONMENT VARS END ==="
}

# =============================================================================
# load_all_configs() - Load all configurations in proper hierarchy
# =============================================================================
#
# This function loads configurations in the correct priority order:
# 1. Preserve environment variables (highest priority)
# 2. System defaults (lowest priority)
# 3. Module-specific configs 
# 4. Machine-specific system config
# 5. Restore environment variables (ensure they override everything)
#
# Parameters:
#   $1 - module_name (optional): Load module-specific config
#
load_all_configs() {
    local module_name="${1:-}"
    
    log_config "DEBUG" "Starting configuration loading (PROJECT_ROOT: $PROJECT_ROOT)"
    
    # Step 1: Preserve environment variables (they have highest priority)
    preserve_environment_vars
    
    # Step 2: Load system defaults (lowest priority)
    load_system_defaults
    
    # Step 3: Load module-specific config (if provided)
    if [[ -n "$module_name" ]]; then
        load_module_config "$module_name"
    fi
    
    # Step 4: Load machine-specific system config (higher priority)
    load_system_config
    
    # Step 5: Restore environment variables (highest priority - override everything)
    restore_environment_vars
    
    log_config "DEBUG" "Configuration loading complete"
    
    # Debug output if requested
    if [[ "${DEBUG_CONFIG:-false}" == "true" ]]; then
        log_config "DEBUG" "Final configuration values:"
        log_config "DEBUG" "  AUTOFIX=${AUTOFIX:-<not set>}"
        log_config "DEBUG" "  DISABLE_AUTOFIX=${DISABLE_AUTOFIX:-<not set>}"
        log_config "DEBUG" "  PREFERRED_KERNEL_BRANCH=${PREFERRED_KERNEL_BRANCH:-<not set>}"
        log_config "DEBUG" "  GRAPHICS_CHIPSET=${GRAPHICS_CHIPSET:-<not set>}"
        log_config "DEBUG" "  USE_MODULES=${USE_MODULES:-<not set>}"
    fi
}

# =============================================================================
# get_config_value() - Get configuration value with hierarchy support
# =============================================================================
#
# This function provides a standardized way to retrieve configuration values
# with proper fallback hierarchy and debugging support.
#
# Parameters:
#   $1 - variable_name: Name of the configuration variable
#   $2 - default_value: Default value if not found anywhere
#   $3 - module_name (optional): Module context for debugging
#
# Returns:
#   The configuration value following the priority hierarchy
#
get_config_value() {
    local var_name="$1"
    local default_value="$2"
    local module_context="${3:-global}"
    
    # Use parameter expansion with fallback to default
    local value="${!var_name:-$default_value}"
    
    log_config "DEBUG" "[$module_context] $var_name = '$value'"
    
    echo "$value"
}

# =============================================================================
# is_autofix_enabled() - Check if autofix is enabled with proper hierarchy
# =============================================================================
#
# This function checks if autofix is enabled, following the configuration
# hierarchy and respecting selective disable lists.
#
# Parameters:
#   $1 - action_name (optional): Specific autofix action to check
#
# Returns:
#   0 - Autofix is enabled for this action
#   1 - Autofix is disabled (globally or selectively)
#
is_autofix_enabled() {
    local action_name="${1:-}"
    
    # Check global AUTOFIX flag first (use current variable value, not get_config_value)
    local autofix_enabled="${AUTOFIX:-true}"
    
    # Debug: Show what we're actually checking
    log_config "DEBUG" "is_autofix_enabled called with AUTOFIX='$autofix_enabled' (raw AUTOFIX='${AUTOFIX:-<unset>}')"
    
    if [[ "$autofix_enabled" != "true" ]]; then
        log_config "DEBUG" "Autofix globally disabled (AUTOFIX=$autofix_enabled)"
        return 1
    fi
    
    # If action name provided, check selective disable list
    if [[ -n "$action_name" ]]; then
        local disable_list="${DISABLE_AUTOFIX:-}"
        
        if [[ -n "$disable_list" ]]; then
            # Remove .sh extension for matching
            local action_basename="${action_name%.sh}"
            
            # Check if action is in the disable list (space-separated)
            if [[ " $disable_list " =~ " $action_basename " ]] || [[ " $disable_list " =~ " ${action_basename}.sh " ]]; then
                log_config "DEBUG" "Autofix selectively disabled for: $action_name (DISABLE_AUTOFIX=$disable_list)"
                return 1
            fi
        fi
    fi
    
    log_config "DEBUG" "Autofix enabled for: ${action_name:-all actions}"
    return 0
}

# =============================================================================
# get_modules_list() - Get list of enabled modules with proper hierarchy
# =============================================================================
get_modules_list() {
    local use_modules
    local ignore_modules
    
    use_modules=$(get_config_value "USE_MODULES" "ALL")
    ignore_modules=$(get_config_value "IGNORE_MODULES" "")
    
    # Implementation would go here to process the module lists
    # For now, just return the raw values for backward compatibility
    echo "USE_MODULES='$use_modules' IGNORE_MODULES='$ignore_modules'"
}

# =============================================================================
# validate_project_structure() - Validate that we're in a valid project
# =============================================================================
validate_project_structure() {
    local required_files=("system_default.conf" "modules" "autofix")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ ! -e "$PROJECT_ROOT/$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_config "ERROR" "Invalid project structure. Missing: ${missing_files[*]}"
        log_config "ERROR" "PROJECT_ROOT: $PROJECT_ROOT"
        return 1
    fi
    
    log_config "DEBUG" "Project structure validation passed"
    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Validate project structure
if ! validate_project_structure; then
    echo "ERROR: Invalid project structure detected. Cannot continue." >&2
    exit 1
fi

# Auto-load configurations when this file is sourced
# Only do full loading if not already done (avoid recursive loading)
log_config "DEBUG" "common.sh sourced - CONFIG_LOADED='${CONFIG_LOADED:-<unset>}'"
if [[ -z "${CONFIG_LOADED:-}" ]]; then
    # Enable debug mode if requested
    if [[ "${DEBUG:-false}" == "true" ]] || [[ "${DEBUG_CONFIG:-false}" == "true" ]]; then
        export DEBUG_CONFIG=true
    fi
    
    log_config "DEBUG" "Initializing root common.sh (first time)"
    log_config "DEBUG" "AUTOFIX at start of initialization: '${AUTOFIX:-<unset>}'"
    
    # Load all configs except module-specific (that's loaded per-module)
    load_all_configs
    
    log_config "DEBUG" "AUTOFIX after load_all_configs: '${AUTOFIX:-<unset>}'"
    
    # Mark configuration as loaded to prevent recursion
    export CONFIG_LOADED=true
    
    log_config "DEBUG" "Root common.sh initialization complete - CONFIG_LOADED set to true"
    log_config "DEBUG" "AUTOFIX at end of initialization: '${AUTOFIX:-<unset>}'"
else
    log_config "DEBUG" "Skipping config loading - already loaded (CONFIG_LOADED='${CONFIG_LOADED}')"
    log_config "DEBUG" "Current AUTOFIX value: '${AUTOFIX:-<unset>}'"
fi

# Export commonly used paths for convenience
export MODULES_DIR="${PROJECT_ROOT}/modules"
export AUTOFIX_DIR="${PROJECT_ROOT}/autofix"
export CONFIG_DIR="${PROJECT_ROOT}/config"
export STATE_DIR="${STATE_DIR:-/var/tmp/modular-monitor-state}"

# Ensure state directory exists
if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR" 2>/dev/null || true
fi
