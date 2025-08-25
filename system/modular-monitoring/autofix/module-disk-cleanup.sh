#!/bin/bash
# Disk Cleanup Autofix
# Attempts to clean up disk space when usage is high

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Source module config
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
    source "$SCRIPT_DIR/config.conf"
fi

attempt_disk_cleanup() {
    local filesystem="$1"
    local usage="$2"
    
    log "AUTOFIX: Attempting disk cleanup for $filesystem (${usage}% full)..."
    
    # Common cleanup actions that are safe
    local cleanup_actions=()
    
    # 1. Clean package cache (requires root)
    if command -v apt-get >/dev/null 2>&1; then
        cleanup_actions+=("apt-get clean")
    fi
    
    if command -v yum >/dev/null 2>&1; then
        cleanup_actions+=("yum clean all")
    fi
    
    if command -v dnf >/dev/null 2>&1; then
        cleanup_actions+=("dnf clean all")
    fi
    
    # 2. Clean temporary files (requires root for system temps)
    cleanup_actions+=("find /tmp -type f -mtime +7 -delete")
    cleanup_actions+=("find /var/tmp -type f -mtime +7 -delete")
    
    # 3. Clean log files (requires root)
    cleanup_actions+=("journalctl --vacuum-time=30d")
    cleanup_actions+=("find /var/log -name '*.log' -mtime +30 -delete")
    
    if [[ ${#cleanup_actions[@]} -gt 0 ]]; then
        log "AUTOFIX: Disk cleanup recommended - requires root privileges"
        send_alert "warning" "💾 Disk cleanup: Automated cleanup needed for $filesystem (${usage}% full)"
        
        for action in "${cleanup_actions[@]}"; do
            log "AUTOFIX: Recommended action: $action"
        done
        
        # Show current disk usage breakdown
        log "AUTOFIX: Current disk usage for $filesystem:"
        if [[ "$filesystem" == "/" ]]; then
            du -sh /var/log /tmp /var/tmp /var/cache 2>/dev/null | while read -r size dir; do
                log "AUTOFIX:   $size $dir"
            done
        fi
    else
        log "AUTOFIX: No safe automatic cleanup actions available"
    fi
    
    return 0
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    filesystem="${1:-/}"
    usage="${2:-unknown}"
    attempt_disk_cleanup "$filesystem" "$usage"
fi
