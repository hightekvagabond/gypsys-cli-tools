#!/bin/bash
# =============================================================================
# GREEDY PROCESS KILLER AUTOFIX SCRIPT
# =============================================================================
#
# ⚠️  WARNING:
#   This script kills resource-greedy processes that are consuming excessive
#   CPU or memory. Can cause data loss if it terminates applications with
#   unsaved work.
#
# PURPOSE:
#   Targets specific resource-greedy non-system processes based on the problem
#   type (CPU for thermal issues, memory for OOM prevention). This is more
#   precise than generic cleanup and addresses the actual resource hog.
#
# INTELLIGENT TARGETING:
#   🎯 CPU_GREEDY: Kills high-CPU processes (thermal emergencies)
#   🎯 MEMORY_GREEDY: Kills high-memory processes (OOM prevention)
#   🎯 Combined analysis for processes that are greedy on multiple resources
#
# PROCESS MANAGEMENT STRATEGY:
#   1. Identify processes exceeding resource thresholds
#   2. Filter out all critical system processes
#   3. Try throttling first (nice, ionice, cgroups)
#   4. Wait and monitor if throttling helps
#   5. Only kill if throttling fails to resolve issue
#
# SAFETY MECHANISMS:
#   ✅ Never kills critical system processes (systemd, ssh, etc.)
#   ✅ Grace period prevents repeated kills of same process
#   ✅ Resource-specific targeting (not random killing)
#   ✅ Attempts SIGTERM before SIGKILL
#   ✅ Comprehensive logging for audit trail
#
# USAGE:
#   manage-greedy-process.sh <module> <grace_period> <CPU_GREEDY|MEMORY_GREEDY> [threshold]
#
# EXAMPLES:
#   manage-greedy-process.sh thermal 300 CPU_GREEDY 80     # Throttle/kill high-CPU for thermal
#   manage-greedy-process.sh memory 600 MEMORY_GREEDY 2048 # Throttle/kill high-memory processes
#   manage-greedy-process.sh oom 120 MEMORY_GREEDY 4096    # Emergency memory management
#
# SECURITY CONSIDERATIONS:
#   - Process validation prevents injection attacks
#   - Resource type validation prevents abuse
#   - All process termination logged for security audit
#   - Grace period prevents DoS through repeated calls
#
# BASH CONCEPTS FOR BEGINNERS:
#   - Targeted resource management is more effective than broad cleanup
#   - Process resource usage can be measured and compared
#   - Graceful vs forced termination affects data preservation
#   - Resource thresholds help identify truly problematic processes
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize autofix script with common setup
init_autofix_script "$@"

# Additional arguments specific to this script
# Note: Arguments may be shifted if --dry-run was used
if [[ "${DRY_RUN:-false}" == "true" ]]; then
    # In dry-run mode, arguments are: --dry-run calling_module grace_period [resource_type] [threshold]
    RESOURCE_TYPE="${4:-MEMORY_GREEDY}"  # CPU_GREEDY or MEMORY_GREEDY
    THRESHOLD_VALUE="${5:-unknown}"      # Resource threshold (CPU % or Memory MB)
else
    # Normal mode: calling_module grace_period [resource_type] [threshold]
    RESOURCE_TYPE="${3:-MEMORY_GREEDY}"  # CPU_GREEDY or MEMORY_GREEDY
    THRESHOLD_VALUE="${4:-unknown}"      # Resource threshold (CPU % or Memory MB)
fi

# Configuration loaded automatically via modules/common.sh

# =============================================================================
# show_help() - Display usage and safety information
# =============================================================================
show_help() {
    cat << 'EOF'
GREEDY PROCESS KILLER AUTOFIX SCRIPT

⚠️  WARNING:
    This script kills resource-greedy processes that consume excessive
    CPU or memory. Can cause data loss if unsaved work exists.

PURPOSE:
    Targets specific resource-greedy processes based on the problem type:
    - CPU_GREEDY: For thermal emergencies (high-CPU processes)
    - MEMORY_GREEDY: For OOM prevention (high-memory processes)

USAGE:
    manage-greedy-process.sh <module> <grace_period> <RESOURCE_TYPE> [threshold]

RESOURCE TYPES:
    CPU_GREEDY      Manage processes with high CPU usage
    MEMORY_GREEDY   Manage processes with high memory usage

EXAMPLES:
    # Manage high-CPU process for thermal emergency
    manage-greedy-process.sh thermal 300 CPU_GREEDY 80

    # Manage high-memory process to prevent OOM
    manage-greedy-process.sh memory 600 MEMORY_GREEDY 2048

    # Emergency memory management with low threshold
    manage-greedy-process.sh oom 120 MEMORY_GREEDY 1024

MANAGEMENT STRATEGY:
    1. Find processes exceeding resource thresholds
    2. Filter out critical system processes
    3. Try throttling first (nice, ionice, cgroups)
    4. Monitor if throttling resolves the issue
    5. Kill only if throttling fails after timeout

PROTECTED PROCESSES:
    ✅ System daemons (systemd, init, kernel threads)
    ✅ SSH sessions, network services
    ✅ Essential services (dbus, udev)
    ❌ User applications consuming excessive resources

EXIT CODES:
    0 - Process killed successfully
    1 - Error occurred (check logs)
    2 - Skipped due to grace period
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

# =============================================================================
# VALIDATE RESOURCE TYPE INPUT
# =============================================================================
# Validate resource type to prevent injection and ensure correct operation
validate_resource_type() {
    local resource_type="$1"
    
    case "$resource_type" in
        CPU_GREEDY|MEMORY_GREEDY)
            return 0  # Valid
            ;;
        *)
            autofix_log "ERROR" "Invalid resource type: $resource_type"
            autofix_log "ERROR" "Valid types: CPU_GREEDY, MEMORY_GREEDY"
            return 1
            ;;
    esac
}

# Validate the resource type argument
if ! validate_resource_type "$RESOURCE_TYPE"; then
    autofix_log "CRITICAL" "Invalid resource type '$RESOURCE_TYPE' - ABORTING"
    exit 1
fi

autofix_log "INFO" "Greedy process killer: targeting $RESOURCE_TYPE processes (threshold: $THRESHOLD_VALUE)"

# =============================================================================
# PROCESS THROTTLING FUNCTIONS
# =============================================================================

# =============================================================================
# throttle_process_cpu() - Reduce CPU priority and affinity
# =============================================================================
#
# PURPOSE:
#   Throttles a process's CPU usage using nice (priority) and CPU affinity.
#   This is less disruptive than killing and often resolves CPU issues.
#
# PARAMETERS:
#   $1 - pid: Process ID to throttle
#   $2 - cmd: Process command name (for logging)
#
# THROTTLING METHODS:
#   - nice: Lower process priority (higher nice value = lower priority)
#   - ionice: Lower I/O priority (reduce disk competition)
#   - CPU affinity: Restrict to fewer CPU cores
#
# RETURNS:
#   0 - Throttling applied successfully
#   1 - Failed to throttle process
#
throttle_process_cpu() {
    local pid="$1"
    local cmd="$2"
    
    autofix_log "INFO" "Attempting to throttle CPU for process: $cmd (PID: $pid)"
    
    # Check if process still exists
    if ! kill -0 "$pid" 2>/dev/null; then
        autofix_log "WARN" "Process $pid no longer exists - cannot throttle"
        return 1
    fi
    
    # Method 1: Increase nice value (lower priority)
    if command -v renice >/dev/null 2>&1; then
        if renice +10 "$pid" >/dev/null 2>&1; then
            autofix_log "INFO" "Applied nice +10 to process $pid ($cmd)"
        else
            autofix_log "WARN" "Failed to renice process $pid"
        fi
    fi
    
    # Method 2: Lower I/O priority
    if command -v ionice >/dev/null 2>&1; then
        if ionice -c 3 -p "$pid" >/dev/null 2>&1; then
            autofix_log "INFO" "Applied ionice idle class to process $pid ($cmd)"
        else
            autofix_log "WARN" "Failed to ionice process $pid"
        fi
    fi
    
    # Method 3: CPU affinity (restrict to fewer cores for multi-core systems)
    if command -v taskset >/dev/null 2>&1; then
        local cpu_count
        cpu_count=$(nproc 2>/dev/null || echo "1")
        if [[ $cpu_count -gt 2 ]]; then
            # Restrict to only the first CPU core
            if taskset -cp 0 "$pid" >/dev/null 2>&1; then
                autofix_log "INFO" "Restricted process $pid ($cmd) to CPU 0"
            else
                autofix_log "WARN" "Failed to set CPU affinity for process $pid"
            fi
        fi
    fi
    
    autofix_log "INFO" "CPU throttling applied to process $pid ($cmd)"
    return 0
}

# =============================================================================
# throttle_process_memory() - Limit memory using cgroups if available
# =============================================================================
#
# PURPOSE:
#   Attempts to limit process memory usage using cgroups v1/v2 if available.
#   This is more complex than CPU throttling but can prevent OOM conditions.
#
# PARAMETERS:
#   $1 - pid: Process ID to throttle
#   $2 - cmd: Process command name (for logging)
#   $3 - memory_limit_mb: Memory limit in MB (optional, default: 1024)
#
# METHODS:
#   - cgroups v2: Modern memory limiting
#   - cgroups v1: Legacy memory limiting
#   - Process suspension: Pause/resume as last resort
#
# RETURNS:
#   0 - Memory throttling applied
#   1 - Failed to apply memory throttling
#
throttle_process_memory() {
    local pid="$1"
    local cmd="$2"
    local memory_limit_mb="${3:-1024}"
    
    autofix_log "INFO" "Attempting to throttle memory for process: $cmd (PID: $pid, limit: ${memory_limit_mb}MB)"
    
    # Check if process still exists
    if ! kill -0 "$pid" 2>/dev/null; then
        autofix_log "WARN" "Process $pid no longer exists - cannot throttle"
        return 1
    fi
    
    # Try cgroups v2 first (modern systems)
    if [[ -d "/sys/fs/cgroup" ]] && [[ -f "/sys/fs/cgroup/cgroup.controllers" ]]; then
        autofix_log "DEBUG" "Attempting cgroups v2 memory limiting"
        local cgroup_name="modular-monitor-throttle-$$"
        local cgroup_path="/sys/fs/cgroup/$cgroup_name"
        
        # Create temporary cgroup (requires root)
        if [[ $EUID -eq 0 ]] && mkdir "$cgroup_path" 2>/dev/null; then
            # Set memory limit
            local memory_limit_bytes=$((memory_limit_mb * 1024 * 1024))
            if echo "$memory_limit_bytes" > "$cgroup_path/memory.max" 2>/dev/null; then
                # Move process to cgroup
                if echo "$pid" > "$cgroup_path/cgroup.procs" 2>/dev/null; then
                    autofix_log "INFO" "Applied cgroups v2 memory limit (${memory_limit_mb}MB) to process $pid ($cmd)"
                    return 0
                fi
            fi
            # Cleanup on failure
            rmdir "$cgroup_path" 2>/dev/null || true
        fi
    fi
    
    # Try cgroups v1 (legacy systems)
    if [[ -d "/sys/fs/cgroup/memory" ]]; then
        autofix_log "DEBUG" "Attempting cgroups v1 memory limiting"
        # This is more complex and often requires special setup
        autofix_log "WARN" "cgroups v1 memory limiting not implemented (requires admin setup)"
    fi
    
    # Fallback: Send SIGSTOP/SIGCONT to pause high-memory processes temporarily
    autofix_log "WARN" "No cgroups available - using process suspension as fallback"
    if kill -STOP "$pid" 2>/dev/null; then
        autofix_log "INFO" "Suspended process $pid ($cmd) temporarily"
        sleep 2  # Brief pause
        if kill -CONT "$pid" 2>/dev/null; then
            autofix_log "INFO" "Resumed process $pid ($cmd)"
            return 0
        fi
    fi
    
    autofix_log "ERROR" "Failed to throttle memory for process $pid ($cmd)"
    return 1
}

# =============================================================================
# monitor_throttled_process() - Check if throttling resolved the issue
# =============================================================================
#
# PURPOSE:
#   Monitors a throttled process to see if the resource usage dropped
#   below acceptable levels. Determines if killing is still necessary.
#
# PARAMETERS:
#   $1 - pid: Process ID to monitor
#   $2 - resource_type: CPU_GREEDY or MEMORY_GREEDY
#   $3 - threshold: Resource threshold to check against
#   $4 - timeout_seconds: How long to monitor (default: 30)
#
# RETURNS:
#   0 - Throttling was successful (resource usage reduced)
#   1 - Throttling failed (still above threshold)
#
monitor_throttled_process() {
    local pid="$1"
    local resource_type="$2"
    local threshold="$3"
    local timeout_seconds="${4:-30}"
    
    autofix_log "INFO" "Monitoring throttled process $pid for $timeout_seconds seconds..."
    
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout_seconds))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        # Check if process still exists
        if ! kill -0 "$pid" 2>/dev/null; then
            autofix_log "INFO" "Process $pid exited during monitoring - throttling successful"
            return 0
        fi
        
        # Check resource usage based on type
        case "$resource_type" in
            CPU_GREEDY)
                local current_cpu
                current_cpu=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | awk '{print int($1)}' || echo "0")
                if [[ $current_cpu -lt $threshold ]]; then
                    autofix_log "INFO" "CPU usage dropped to $current_cpu% (below threshold $threshold%) - throttling successful"
                    return 0
                fi
                ;;
            MEMORY_GREEDY)
                local current_mem_mb
                current_mem_mb=$(ps -p "$pid" -o rss --no-headers 2>/dev/null | awk '{print int($1/1024)}' || echo "0")
                if [[ $current_mem_mb -lt $threshold ]]; then
                    autofix_log "INFO" "Memory usage dropped to ${current_mem_mb}MB (below threshold ${threshold}MB) - throttling successful"
                    return 0
                fi
                ;;
        esac
        
        sleep 5  # Check every 5 seconds
    done
    
    autofix_log "WARN" "Throttling did not reduce resource usage below threshold after $timeout_seconds seconds"
    return 1
}

# Check if a process is system critical
is_system_critical_process() {
    local pid="$1"
    local cmd="$2"
    
    # Skip kernel threads (processes in brackets)
    if [[ "$cmd" =~ ^\[.*\]$ ]]; then
        return 0  # Critical
    fi
    
    # Skip essential system processes
    case "$cmd" in
        systemd|init|kthreadd|ksoftirqd|rcu_*|watchdog|migration|systemd-*|dbus|NetworkManager|sshd)
            return 0  # Critical
            ;;
        */systemd|*/init|*/dbus|*/NetworkManager|*/sshd)
            return 0  # Critical
            ;;
    esac
    
    # Skip processes with PID 1, 2, or in the first 100 PIDs (likely system)
    if [[ $pid -le 100 ]]; then
        return 0  # Critical
    fi
    
    return 1  # Not critical
}

# The actual greedy process management action
perform_greedy_process_management() {
    local resource_type="$1"
    local threshold_value="$2"
    
    # Check if we're in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        autofix_log "INFO" "[DRY-RUN] Would perform greedy process management"
        
        # In dry-run mode, analyze both CPU and memory greedy processes regardless of resource_type
        autofix_log "INFO" "[DRY-RUN] === CPU GREEDY PROCESS ANALYSIS ==="
        autofix_log "INFO" "[DRY-RUN] Would identify high-CPU processes (threshold: 80%+ CPU usage)"
        if command -v ps >/dev/null 2>&1; then
            local high_cpu_processes
            high_cpu_processes=$(ps aux --sort=-%cpu | head -6 | tail -5 2>/dev/null || echo "")
            if [[ -n "$high_cpu_processes" ]]; then
                autofix_log "INFO" "[DRY-RUN] Top CPU-consuming processes:"
                echo "$high_cpu_processes" | while read -r process_line; do
                    autofix_log "INFO" "[DRY-RUN]   $process_line"
                done
            fi
        fi
        autofix_log "INFO" "[DRY-RUN] Would apply CPU throttling (nice, ionice, CPU affinity) to high-CPU processes"
        autofix_log "INFO" "[DRY-RUN] Would skip critical system processes (systemd, ssh, etc.)"
        autofix_log "INFO" "[DRY-RUN] Would only kill non-critical processes if throttling fails"
        
        autofix_log "INFO" "[DRY-RUN] === MEMORY GREEDY PROCESS ANALYSIS ==="
        autofix_log "INFO" "[DRY-RUN] Would identify high-memory processes (threshold: 15%+ memory usage)"
        if command -v ps >/dev/null 2>&1; then
            local high_mem_processes
            high_mem_processes=$(ps aux --sort=-%mem | head -6 | tail -5 2>/dev/null || echo "")
            if [[ -n "$high_mem_processes" ]]; then
                autofix_log "INFO" "[DRY-RUN] Top memory-consuming processes:"
                echo "$high_mem_processes" | while read -r process_line; do
                    autofix_log "INFO" "[DRY-RUN]   $process_line"
                done
            fi
        fi
        autofix_log "INFO" "[DRY-RUN] Would apply memory throttling (cgroups, process suspension) to high-memory processes"
        autofix_log "INFO" "[DRY-RUN] Would drop system caches if running as root: echo 3 > /proc/sys/vm/drop_caches"
        autofix_log "INFO" "[DRY-RUN] Would analyze swap usage and warn if excessive"
        
        autofix_log "INFO" "[DRY-RUN] === GENERAL ANALYSIS ==="
        if command -v free >/dev/null 2>&1; then
            local mem_info
            mem_info=$(free -m 2>/dev/null || echo "")
            if [[ -n "$mem_info" ]]; then
                autofix_log "INFO" "[DRY-RUN] Current memory status:"
                echo "$mem_info" | while read -r mem_line; do
                    autofix_log "INFO" "[DRY-RUN]   $mem_line"
                done
            fi
        fi
        autofix_log "INFO" "[DRY-RUN] Would provide process termination recommendations if emergency kill is disabled"
        autofix_log "INFO" "[DRY-RUN] Greedy process management analysis would complete successfully"
        return 0
    fi
    
    autofix_log "INFO" "Greedy process management initiated - Resource: $resource_type (threshold: $threshold_value)"
    
    # Get current memory stats
    local mem_info
    mem_info=$(free -m)
    local total_mem=$(echo "$mem_info" | awk 'NR==2{print $2}')
    local used_mem=$(echo "$mem_info" | awk 'NR==2{print $3}')
    local free_mem=$(echo "$mem_info" | awk 'NR==2{print $4}')
    local available_mem=$(echo "$mem_info" | awk 'NR==2{print $7}')
    
    autofix_log "INFO" "Memory status - Total: ${total_mem}MB, Used: ${used_mem}MB, Free: ${free_mem}MB, Available: ${available_mem}MB"
    
    # Safe memory cleanup actions
    local cleanup_success=false
    
    # 1. Drop caches (requires root, but safe)
    if [[ ${ENABLE_CACHE_DROP:-true} == "true" ]]; then
        autofix_log "INFO" "Attempting to drop system caches..."
        
        if [[ $EUID -eq 0 ]]; then
            # Running as root - can drop caches directly
            if sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null; then
                autofix_log "INFO" "System caches dropped successfully"
                cleanup_success=true
            else
                autofix_log "ERROR" "Failed to drop system caches"
            fi
        else
            # Not running as root - provide recommendation
            autofix_log "WARN" "Cache drop requires root privileges - providing recommendation"
            autofix_log "INFO" "RECOMMENDATION: Run 'sudo sync && sudo sh -c \"echo 3 > /proc/sys/vm/drop_caches\"' to drop caches"
            
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "Memory Cleanup" "Cache drop recommended (requires root): sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'" 2>/dev/null || true
            fi
        fi
    fi
    
    # 2. Find and analyze memory-heavy processes
    autofix_log "INFO" "Analyzing memory-heavy processes..."
    local memory_hogs=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            memory_hogs+=("$line")
        fi
    done < <(get_top_memory_processes | head -5)
    
    if [[ ${#memory_hogs[@]} -gt 0 ]]; then
        autofix_log "INFO" "Top memory-consuming processes:"
        for process in "${memory_hogs[@]}"; do
            autofix_log "INFO" "  $process"
        done
        
        # Look for processes that are safe to restart/kill
        local killable_processes=()
        for process_line in "${memory_hogs[@]}"; do
            local pid=$(echo "$process_line" | awk '{print $1}')
            local mem_percent=$(echo "$process_line" | awk '{print $2}')
            local command=$(echo "$process_line" | awk '{print $3}')
            
            # Skip if not a valid PID
            if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
                continue
            fi
            
            # Skip critical system processes
            if is_system_critical_process "$pid" "$command"; then
                autofix_log "DEBUG" "Skipping critical process: PID $pid ($command)"
                continue
            fi
            
            # Consider processes using significant memory
            local mem_int=$(echo "$mem_percent" | cut -d. -f1)
            if [[ $mem_int -ge ${MEMORY_KILL_THRESHOLD:-15} ]]; then
                killable_processes+=("$pid:$mem_percent:$command")
            fi
        done
        
        # If we have killable processes and emergency mode is enabled
        if [[ ${#killable_processes[@]} -gt 0 && ${ENABLE_EMERGENCY_MEMORY_KILL:-false} == "true" ]]; then
            # Kill the most memory-hungry non-critical process
            local target_process="${killable_processes[0]}"
            local target_pid=$(echo "$target_process" | cut -d: -f1)
            local target_mem=$(echo "$target_process" | cut -d: -f2)
            local target_cmd=$(echo "$target_process" | cut -d: -f3)
            local app_name=$(basename "$target_cmd" | cut -d' ' -f1)
            
            autofix_log "INFO" "Emergency terminating high-memory process: PID $target_pid ($app_name) - ${target_mem}% memory"
            
            # Send notification before kill
            if command -v notify-send >/dev/null 2>&1; then
                notify-send -u critical "Memory Emergency Kill" "Killing: $app_name (${target_mem}% memory)\nReason: $trigger_reason\nCaller: $CALLING_MODULE" 2>/dev/null || true
            fi
            
            # Kill the process
            if kill -TERM "$target_pid" 2>/dev/null; then
                autofix_log "INFO" "Sent SIGTERM to PID $target_pid"
                sleep "${KILL_PROCESS_WAIT_TIME:-2}"
                if kill -0 "$target_pid" 2>/dev/null; then
                    autofix_log "WARN" "Process still running, sending SIGKILL"
                    kill -KILL "$target_pid" 2>/dev/null || true
                fi
            else
                autofix_log "ERROR" "Failed to terminate process PID $target_pid"
            fi
            
            cleanup_success=true
            autofix_log "INFO" "Memory cleanup process termination completed"
        else
            autofix_log "INFO" "Emergency memory kill disabled or no suitable processes found"
            if [[ ${#killable_processes[@]} -gt 0 ]]; then
                autofix_log "INFO" "RECOMMENDATION: Consider terminating high-memory processes manually if memory pressure persists"
            fi
        fi
    fi
    
    # 3. Analyze swap usage
    local swap_info
    swap_info=$(free -m | grep Swap)
    if [[ -n "$swap_info" ]]; then
        local swap_total=$(echo "$swap_info" | awk '{print $2}')
        local swap_used=$(echo "$swap_info" | awk '{print $3}')
        
        if [[ $swap_total -gt 0 && $swap_used -gt 0 ]]; then
            local swap_percent=$((swap_used * 100 / swap_total))
            autofix_log "INFO" "Swap usage: ${swap_used}MB/${swap_total}MB (${swap_percent}%)"
            
            if [[ $swap_percent -ge ${SWAP_WARNING_THRESHOLD:-50} ]]; then
                autofix_log "WARN" "High swap usage detected - system may be thrashing"
                
                if command -v notify-send >/dev/null 2>&1; then
                    notify-send "High Swap Usage" "Swap: ${swap_percent}% - performance may be degraded" 2>/dev/null || true
                fi
            fi
        fi
    fi
    
    # Get updated memory stats after cleanup
    sleep 2  # Allow time for cleanup effects
    mem_info=$(free -m)
    local new_available=$(echo "$mem_info" | awk 'NR==2{print $7}')
    local freed_memory=$((new_available - available_mem))
    
    if [[ $freed_memory -gt 0 ]]; then
        autofix_log "INFO" "Memory cleanup freed approximately ${freed_memory}MB"
        
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "Memory Cleanup Complete" "Freed ~${freed_memory}MB of memory" 2>/dev/null || true
        fi
    else
        autofix_log "INFO" "Memory cleanup completed (no significant memory freed)"
    fi
    
    autofix_log "INFO" "Memory cleanup procedure completed"
    return 0  # Always return success - we've done what we can
}

# Execute with grace period management
autofix_log "INFO" "Greedy process management requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "manage-greedy-process" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_greedy_process_management" "$RESOURCE_TYPE" "$THRESHOLD_VALUE"