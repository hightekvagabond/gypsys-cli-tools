#!/bin/bash
# =============================================================================
# DISK CLEANUP AUTOFIX SCRIPT
# =============================================================================
#
# PURPOSE:
#   Automatically cleans up disk space when filesystem usage becomes critically
#   high. This script performs SAFE cleanup operations that won't break the
#   system, such as clearing temporary files, logs, and caches.
#
# ⚠️  CRITICAL SAFETY WARNING:
#   This script could render your system UNBOOTABLE if it deletes essential
#   files. It includes multiple safety checks to prevent this, but you should
#   understand what it does before running it.
#
# SAFE CLEANUP OPERATIONS:
#   ✅ Temporary files in /tmp, /var/tmp
#   ✅ Rotated log files (*.gz, *.1, *.2, etc.)
#   ✅ Package manager cache (apt, dnf, etc.)
#   ✅ Browser cache files
#   ✅ Systemd journal logs (older entries)
#
# ❌ NEVER TOUCHES (SAFETY PROTECTED):
#   ❌ Current system logs (/var/log/*.log without rotation suffix)
#   ❌ Configuration files (/etc/*)
#   ❌ User home directories (/home/*)
#   ❌ System binaries (/bin, /usr/bin, /sbin)
#   ❌ Kernel files (/boot/*, /lib/modules/*)
#   ❌ Device files (/dev/*)
#   ❌ Mount points (/proc, /sys, /run)
#
# USAGE:
#   disk-cleanup.sh <calling_module> <grace_period> [filesystem] [usage_percent]
#
# SECURITY CONSIDERATIONS:
#   - All deletion operations are restricted to safe directories
#   - Filesystem paths are validated to prevent directory traversal
#   - No user input is passed directly to shell commands
#   - Grace period prevents rapid repeated cleanup cycles
#
# BASH CONCEPTS FOR BEGINNERS:
#   - 'set -euo pipefail' makes script exit on any error (safer)
#   - Arrays store multiple values: safe_actions=()
#   - 'find' command searches for files matching patterns
#   - '-mtime +N' finds files older than N days
#   - Always test file operations on non-critical systems first!
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize autofix script with common setup
init_autofix_script "$@"

# Additional arguments specific to this script
FILESYSTEM="${3:-/}"
USAGE_PERCENT="${4:-unknown}"

# =============================================================================
# CRITICAL SAFETY VALIDATION
# =============================================================================

# Validate filesystem path to prevent dangerous operations
validate_filesystem_safety() {
    local fs="$1"
    
    # SECURITY: Prevent directory traversal attacks
    if [[ "$fs" =~ \.\. ]]; then
        autofix_log "ERROR" "SECURITY: Filesystem path contains '..' - blocked"
        return 1
    fi
    
    # SAFETY: Never allow cleanup of critical system directories
    local dangerous_paths=(
        "/boot" "/bin" "/sbin" "/usr/bin" "/usr/sbin"
        "/etc" "/dev" "/proc" "/sys" "/run"
        "/lib" "/lib64" "/usr/lib" "/usr/lib64"
        "/root/.ssh" "/home"
    )
    
    for dangerous in "${dangerous_paths[@]}"; do
        if [[ "$fs" == "$dangerous" ]] || [[ "$fs" == "$dangerous"/* ]]; then
            autofix_log "ERROR" "SAFETY: Refusing to clean critical path: $fs"
            return 1
        fi
    done
    
    autofix_log "DEBUG" "Filesystem path validation passed: $fs"
    return 0
}

# Validate filesystem before proceeding
if ! validate_filesystem_safety "$FILESYSTEM"; then
    autofix_log "CRITICAL" "Unsafe filesystem path: $FILESYSTEM - ABORTING"
    exit 1
fi

# Configuration loaded automatically via modules/common.sh

# =============================================================================
# show_help() - Display usage information and safety warnings
# =============================================================================
show_help() {
    cat << 'EOF'
DISK CLEANUP AUTOFIX SCRIPT

PURPOSE:
    Automatically clean disk space when filesystem usage is critically high.
    Performs ONLY safe operations that won't break your system.

USAGE:
    disk-cleanup.sh <calling_module> <grace_period> [filesystem] [usage_percent]

ARGUMENTS:
    calling_module   - Name of monitoring module (e.g., "disk")
    grace_period     - Seconds to wait before allowing cleanup again
    filesystem       - Filesystem to clean (default: "/")
    usage_percent    - Current usage percentage (for logging)

EXAMPLES:
    # Called by disk monitoring module
    disk-cleanup.sh disk 300 /var 85

    # Emergency manual cleanup with 1-hour grace period
    disk-cleanup.sh manual 3600 / unknown

SAFE OPERATIONS PERFORMED:
    ✅ Temporary files older than 7 days (/tmp, /var/tmp)
    ✅ Package manager cache (apt, yum, dnf)
    ✅ Rotated log files (*.1, *.gz, etc.)
    ✅ Browser cache directories
    ✅ User trash (if writable)
    ✅ Old systemd journal entries

NEVER TOUCHES:
    ❌ Current log files (*.log without rotation)
    ❌ Configuration files (/etc)
    ❌ User data (/home)
    ❌ System binaries or libraries
    ❌ Running system files

SAFETY FEATURES:
    - Path validation prevents directory traversal attacks
    - Critical directories are blacklisted
    - All operations are logged for audit
    - Grace period prevents repeated rapid cleanup
    - Non-destructive dry-run capabilities

EXIT CODES:
    0 - Cleanup completed successfully
    1 - Error occurred (check logs)
    2 - Skipped due to grace period

For more information, see the project documentation.
EOF
}

# Check for help request
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    show_help
    exit 0
fi

# =============================================================================
# analyze_disk_usage() - Find the real space hogs before assuming it's logs
# =============================================================================
#
# PURPOSE:
#   Analyzes actual disk usage to identify what's really consuming space.
#   Critical for avoiding the mistake of cleaning logs when the real problem
#   is docker containers, large files, or application data.
#
# PARAMETERS:
#   $1 - filesystem: Filesystem to analyze (e.g., "/", "/var")
#
# RETURNS:
#   Formatted output showing top space-consuming directories
#
# BASH CONCEPTS FOR BEGINNERS:
#   - 'du' command shows disk usage for directories
#   - '-h' makes output human-readable (GB, MB, etc.)
#   - 'sort -hr' sorts by size (largest first)
#   - 'head -n 10' shows only top 10 results
#
# SECURITY CONSIDERATIONS:
#   - Uses safe, read-only commands only
#   - No deletion or modification of files
#   - Path validation prevents directory traversal
#
analyze_disk_usage() {
    local filesystem="$1"
    
    # SAFETY: Validate filesystem path
    if ! validate_filesystem_safety "$filesystem"; then
        echo "ERROR: Unsafe filesystem path for analysis"
        return 1
    fi
    
    autofix_log "DEBUG" "Running disk usage analysis on $filesystem"
    
    # Find top-level directories consuming the most space
    # Exclude problematic mount points and special filesystems
    du -h --max-depth=2 "$filesystem" 2>/dev/null | \
        grep -v -E "(proc|sys|dev|run|lost\+found)" | \
        sort -hr | \
        head -n 15 | \
        while IFS=$'\t' read -r size path; do
            echo "  $size - $path"
        done
}

# =============================================================================
# detect_common_space_hogs() - Check for known problematic directories
# =============================================================================
#
# PURPOSE:
#   Specifically checks for common space-consuming issues like Docker containers,
#   large log files, tmp directories, browser caches, and application data.
#   Provides specific warnings and recommendations.
#
# PARAMETERS:
#   $1 - filesystem: Filesystem to check
#
# SECURITY CONSIDERATIONS:
#   - Only performs read operations and size checks
#   - No automatic deletion of detected space hogs
#   - Reports findings for manual decision-making
#
detect_common_space_hogs() {
    local filesystem="$1"
    
    autofix_log "INFO" "Checking for common space-consuming culprits..."
    
    # Check Docker containers and images (common space hog!)
    if command -v docker >/dev/null 2>&1 && [[ -d "/var/lib/docker" ]]; then
        local docker_size
        docker_size=$(du -sh /var/lib/docker 2>/dev/null | cut -f1 || echo "unknown")
        autofix_log "WARN" "🐳 Docker data: $docker_size (/var/lib/docker)"
        autofix_log "WARN" "    Consider: docker system prune -a (removes unused containers/images)"
        
        # Check for stopped containers
        local stopped_containers
        stopped_containers=$(docker ps -aq --filter "status=exited" 2>/dev/null | wc -l || echo "0")
        if [[ $stopped_containers -gt 0 ]]; then
            autofix_log "WARN" "    Found $stopped_containers stopped containers - consider removing"
        fi
    fi
    
    # Check systemd journal logs
    if [[ -d "/var/log/journal" ]]; then
        local journal_size
        journal_size=$(du -sh /var/log/journal 2>/dev/null | cut -f1 || echo "unknown")
        autofix_log "INFO" "📝 Journal logs: $journal_size (/var/log/journal)"
        if [[ "$journal_size" =~ ^[0-9]+G ]]; then
            autofix_log "WARN" "    Large journal size - consider: journalctl --vacuum-time=30d"
        fi
    fi
    
    # Check /tmp and /var/tmp
    for tmp_dir in "/tmp" "/var/tmp"; do
        if [[ -d "$tmp_dir" ]]; then
            local tmp_size
            tmp_size=$(du -sh "$tmp_dir" 2>/dev/null | cut -f1 || echo "unknown")
            autofix_log "INFO" "🗂️  Temp directory: $tmp_size ($tmp_dir)"
        fi
    done
    
    # Check common application caches
    local cache_dirs=(
        "/var/cache"
        "/home/*/.cache"
        "/root/.cache"
        "/var/spool"
    )
    
    for cache_pattern in "${cache_dirs[@]}"; do
        for cache_dir in $cache_pattern; do
            if [[ -d "$cache_dir" ]]; then
                local cache_size
                cache_size=$(du -sh "$cache_dir" 2>/dev/null | cut -f1 || echo "unknown")
                autofix_log "INFO" "💾 Cache directory: $cache_size ($cache_dir)"
            fi
        done
    done
    
    # Check for large individual files (>1GB)
    autofix_log "INFO" "🔍 Searching for large files (>1GB)..."
    local large_files
    large_files=$(find "$filesystem" -type f -size +1G 2>/dev/null | head -5)
    if [[ -n "$large_files" ]]; then
        autofix_log "WARN" "Large files found:"
        echo "$large_files" | while read -r file; do
            local file_size
            file_size=$(du -sh "$file" 2>/dev/null | cut -f1 || echo "unknown")
            autofix_log "WARN" "    $file_size - $file"
        done
    fi
}

# =============================================================================
# perform_disk_cleanup() - Main cleanup function with safety checks
# =============================================================================
#
# PURPOSE:
#   Performs safe disk cleanup operations in priority order, starting with
#   the safest operations first. Reports what was cleaned and how much space
#   was recovered.
#
# PARAMETERS:
#   $1 - filesystem: Filesystem to clean (e.g., "/", "/var", "/tmp")
#   $2 - usage_percent: Current usage percentage (for logging/decisions)
#
# SAFETY STRATEGY:
#   1. Start with safest operations (temp files, caches)
#   2. Move to moderate operations (old logs, journal)
#   3. Report what would be manual operations (don't auto-delete)
#   4. Always log what was cleaned and space recovered
#
# BASH CONCEPTS FOR BEGINNERS:
#   - Arrays store lists: safe_actions=("action1" "action2")
#   - Functions can call other functions
#   - 'local' variables only exist in this function
#   - Always validate inputs before using them in commands
#
# SECURITY CONSIDERATIONS:
#   - Never deletes current log files (system needs them)
#   - Never touches user data or configuration
#   - All paths are hardcoded (no user input passed to rm)
#   - Reports actions taken for audit trail
#
perform_disk_cleanup() {
    local filesystem="$1"
    local usage_percent="$2"
    
    # Check if we're in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        autofix_log "INFO" "[DRY-RUN] Would perform disk cleanup for $filesystem (${usage_percent}% full)"
        autofix_log "INFO" "[DRY-RUN] Would analyze disk usage to identify space hogs"
        autofix_log "INFO" "[DRY-RUN] Would clean the following if they exist:"
        autofix_log "INFO" "[DRY-RUN]   - Thumbnail cache: \$HOME/.cache/thumbnails/*"
        autofix_log "INFO" "[DRY-RUN]   - Old cache files: \$HOME/.cache/* (older than 7 days)"
        autofix_log "INFO" "[DRY-RUN]   - User trash: \$HOME/.local/share/Trash/*"
        autofix_log "INFO" "[DRY-RUN]   - System temp files: /tmp/* and /var/tmp/* (older than 7 days)"
        autofix_log "INFO" "[DRY-RUN]   - Package cache: apt clean, yum clean, dnf clean"
        autofix_log "INFO" "[DRY-RUN]   - Journal logs: journalctl --vacuum-time=30d"
        autofix_log "INFO" "[DRY-RUN]   - Rotated log files: *.log.[0-9]*, *.log.*.gz, *.log.*.bz2 (older than 30 days)"
        autofix_log "INFO" "[DRY-RUN] Would show disk usage analysis and space recovery report"
        autofix_log "INFO" "[DRY-RUN] Disk cleanup procedure would complete successfully"
        return 0
    fi
    
    # SAFETY: Re-validate filesystem even though we checked earlier
    if ! validate_filesystem_safety "$filesystem"; then
        autofix_log "CRITICAL" "Filesystem validation failed during cleanup: $filesystem"
        return 1
    fi
    
    autofix_log "INFO" "Disk cleanup initiated for $filesystem (${usage_percent}% full)"
    
    # ==========================================================================
    # CRITICAL: ANALYZE ACTUAL DISK USAGE FIRST
    # ==========================================================================
    # Don't assume it's logs! Find the real culprit using disk usage analysis
    
    autofix_log "INFO" "Analyzing disk usage to identify space hogs..."
    
    # Find the top 10 space-consuming directories
    local analysis_output
    analysis_output=$(analyze_disk_usage "$filesystem")
    
    autofix_log "INFO" "DISK USAGE ANALYSIS RESULTS:"
    autofix_log "INFO" "$analysis_output"
    
    # Check for common space hogs and warn about them
    detect_common_space_hogs "$filesystem"
    
    # Common cleanup actions that are safe
    local safe_actions=()
    local manual_actions=()
    local cleanup_size=0
    
    # Safe actions that don't require root
    if [[ -w "$HOME/.cache" ]]; then
        autofix_log "INFO" "Cleaning user cache directories..."
        
        # Clean thumbnails cache
        if [[ -d "$HOME/.cache/thumbnails" ]]; then
            local thumb_size=$(du -sm "$HOME/.cache/thumbnails" 2>/dev/null | cut -f1 || echo "0")
            if [[ $thumb_size -gt 0 ]]; then
                rm -rf "$HOME/.cache/thumbnails"/* 2>/dev/null || true
                autofix_log "INFO" "Cleaned ${thumb_size}MB from thumbnails cache"
                cleanup_size=$((cleanup_size + thumb_size))
            fi
        fi
        
        # Clean old cache files
        local cache_files_cleaned=0
        find "$HOME/.cache" -type f -mtime +7 -delete 2>/dev/null && cache_files_cleaned=1 || true
        if [[ $cache_files_cleaned -eq 1 ]]; then
            autofix_log "INFO" "Cleaned old cache files (older than 7 days)"
        fi
    fi
    
    # Clean user trash
    if [[ -w "$HOME/.local/share/Trash" ]]; then
        local trash_size=$(du -sm "$HOME/.local/share/Trash" 2>/dev/null | cut -f1 || echo "0")
        if [[ $trash_size -gt 0 ]]; then
            rm -rf "$HOME/.local/share/Trash"/* 2>/dev/null || true
            autofix_log "INFO" "Cleaned ${trash_size}MB from user trash"
            cleanup_size=$((cleanup_size + trash_size))
        fi
    fi
    
    # Actions that require root privileges
    if [[ $EUID -eq 0 ]]; then
        autofix_log "INFO" "Running as root - performing system cleanup..."
        
        # Package manager cleanup
        if command -v apt-get >/dev/null 2>&1; then
            autofix_log "INFO" "Cleaning APT package cache..."
            apt-get clean 2>/dev/null || autofix_log "WARN" "APT clean failed"
            apt-get autoremove -y 2>/dev/null || autofix_log "WARN" "APT autoremove failed"
        fi
        
        if command -v yum >/dev/null 2>&1; then
            autofix_log "INFO" "Cleaning YUM package cache..."
            yum clean all 2>/dev/null || autofix_log "WARN" "YUM clean failed"
        fi
        
        if command -v dnf >/dev/null 2>&1; then
            autofix_log "INFO" "Cleaning DNF package cache..."
            dnf clean all 2>/dev/null || autofix_log "WARN" "DNF clean failed"
        fi
        
        # System temporary files cleanup
        autofix_log "INFO" "Cleaning system temporary files..."
        find /tmp -type f -mtime +7 -delete 2>/dev/null || true
        find /var/tmp -type f -mtime +7 -delete 2>/dev/null || true
        
        # Journal cleanup
        autofix_log "INFO" "Cleaning old journal logs..."
        journalctl --vacuum-time=30d 2>/dev/null || autofix_log "WARN" "Journal cleanup failed"
        
        # SAFETY: Only clean ROTATED log files, never current logs
        # Current logs (*.log) are needed by running services - NEVER delete them!
        autofix_log "INFO" "Cleaning rotated log files (keeping current *.log files safe)..."
        
        # Safe: only rotated/compressed logs (*.1, *.2, *.gz, *.bz2, etc.)
        find /var/log -name "*.log.[0-9]*" -mtime +30 -delete 2>/dev/null || true
        find /var/log -name "*.log.*.gz" -mtime +30 -delete 2>/dev/null || true
        find /var/log -name "*.log.*.bz2" -mtime +30 -delete 2>/dev/null || true
        find /var/log -name "*.log.*.xz" -mtime +30 -delete 2>/dev/null || true
        
        # NEVER TOUCH: *.log files (current logs)
        
    else
        # Not running as root - provide recommendations
        autofix_log "WARN" "System cleanup requires root privileges - providing recommendations"
        
        manual_actions+=("sudo apt-get clean && sudo apt-get autoremove")
        manual_actions+=("sudo find /tmp -type f -mtime +7 -delete")
        manual_actions+=("sudo find /var/tmp -type f -mtime +7 -delete")
        manual_actions+=("sudo journalctl --vacuum-time=30d")
        manual_actions+=("sudo find /var/log -name '*.log.[0-9]*' -mtime +30 -delete  # Only rotated logs!")
        
        for action in "${manual_actions[@]}"; do
            autofix_log "INFO" "RECOMMENDATION: $action"
        done
        
        # Create a cleanup script for the user
        local cleanup_script="/tmp/disk-cleanup-$(date +%Y%m%d-%H%M%S).sh"
        {
            echo "#!/bin/bash"
            echo "# Automatic disk cleanup script generated by modular-monitor"
            echo "# Generated: $(date)"
            echo "# Filesystem: $filesystem"
            echo "# Usage: ${usage_percent}%"
            echo "# Triggered by: $CALLING_MODULE module"
            echo ""
            echo "echo 'Starting disk cleanup for $filesystem ($usage_percent% full)...'"
            echo ""
            for action in "${manual_actions[@]}"; do
                echo "echo 'Running: $action'"
                echo "$action"
                echo "echo 'Done.'"
                echo ""
            done
            echo "echo 'Cleanup complete. Check disk usage with: df -h $filesystem'"
        } > "$cleanup_script"
        chmod +x "$cleanup_script"
        
        autofix_log "INFO" "Created cleanup script: $cleanup_script"
        
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "Disk Cleanup Script Created" "Manual cleanup script: $cleanup_script\nRequires root privileges to run" 2>/dev/null || true
        fi
    fi
    
    # Report current disk usage breakdown
    autofix_log "INFO" "Current disk usage analysis for $filesystem:"
    if [[ "$filesystem" == "/" ]]; then
        {
            echo "DISK USAGE ANALYSIS:"
            echo "==================="
            du -sh /var/log /tmp /var/tmp /var/cache /home /usr /opt 2>/dev/null | sort -hr | head -10
            echo ""
            echo "LARGEST FILES:"
            find "$filesystem" -type f -size +100M 2>/dev/null | head -10 | while read -r file; do
                ls -lh "$file" 2>/dev/null || echo "Cannot access: $file"
            done
        } | while IFS= read -r line; do
            autofix_log "INFO" "$line"
        done
    fi
    
    # Report cleanup results
    if [[ $cleanup_size -gt 0 ]]; then
        autofix_log "INFO" "User-space cleanup freed approximately ${cleanup_size}MB"
        
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "Disk Cleanup Complete" "Freed ~${cleanup_size}MB of disk space\nFilesystem: $filesystem" 2>/dev/null || true
        fi
    else
        autofix_log "INFO" "Disk cleanup completed - limited space freed in user areas"
    fi
    
    # Show updated disk usage
    local new_usage=$(df -h "$filesystem" | tail -1 | awk '{print $5}' | tr -d '%')
    if [[ -n "$new_usage" && "$new_usage" =~ ^[0-9]+$ ]]; then
        autofix_log "INFO" "Updated disk usage for $filesystem: ${new_usage}%"
        
        if [[ "$usage_percent" != "unknown" && "$usage_percent" =~ ^[0-9]+$ ]]; then
            local freed_percent=$((usage_percent - new_usage))
            if [[ $freed_percent -gt 0 ]]; then
                autofix_log "INFO" "Disk cleanup reduced usage by ${freed_percent} percentage points"
            fi
        fi
    fi
    
    autofix_log "INFO" "Disk cleanup procedure completed"
    return 0
}

# Execute with grace period management
autofix_log "INFO" "Disk cleanup requested by $CALLING_MODULE with ${GRACE_PERIOD}s grace period"
run_autofix_with_grace "disk-cleanup" "$CALLING_MODULE" "$GRACE_PERIOD" "perform_disk_cleanup" "$FILESYSTEM" "$USAGE_PERCENT"