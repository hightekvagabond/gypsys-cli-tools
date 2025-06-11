#!/bin/bash

# Debug output to verify script execution
echo "cursor-git-setup.sh started at $(date)" >> /tmp/cursor-git-setup.log
echo "Script path: $0" >> /tmp/cursor-git-setup.log
echo "Current directory: $PWD" >> /tmp/cursor-git-setup.log

# Function to send notification to Cursor
send_cursor_notification() {
    local title="$1"
    local message="$2"
    local type="${3:-info}"  # info, warning, error
    
    # Try to use zenity for system notifications if available
    if command -v zenity >/dev/null 2>&1; then
        zenity --notification --text="$title: $message" 2>/dev/null &
    fi
    
    # Also try notify-send
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message" 2>/dev/null &
    fi
    
    # Log for debugging
    echo "NOTIFICATION: $title - $message" >> /tmp/cursor-git-setup.log
}

# Configuration
SUBMODULE_REPO_URL="git@github.com:Imagination-Guild-LLC/ai-coder-best-practices.git"
SUBMODULE_NAME="ai-best-practices"
GIT_HOSTS_CONFIG="github.com:hightekvagabond,Imagination-Guild-LLC"

# Read submodules from extension configuration if available
if [[ -n "$CURSOR_EXT_SUBMODULES" ]]; then
    IFS=',' read -ra EXT_SUBMODULES <<< "$CURSOR_EXT_SUBMODULES"
    log_debug "Extension configured submodules: ${EXT_SUBMODULES[*]}"
else
    EXT_SUBMODULES=("$SUBMODULE_NAME")
fi

# Debug levels: 0=quiet, 1=errors/warnings only, 2=info, 3=verbose/debug
DEBUG_LEVEL=${DEBUG_LEVEL:-1}

# Function to display status message
show_status_message() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                 Cursor Git Setup Status                     ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║ Script started at: $(date)                                 ║"
    echo "║ Current directory: $PWD                                    ║"
    
    # Get git status
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local branch=$(git branch --show-current)
        local status=$(git status --porcelain)
        local unpushed=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
        
        echo "║ Git Status:                                              ║"
        echo "║   • Branch: $branch                                     ║"
        if [[ -n "$status" ]]; then
            echo "║   • Has uncommitted changes                            ║"
        fi
        if [[ "$unpushed" != "0" ]]; then
            echo "║   • Has $unpushed unpushed commit(s)                   ║"
        fi
    else
        echo "║ Not in a git repository                                ║"
    fi
    
    # Check submodule status
    if [[ -d "$SUBMODULE_NAME" ]]; then
        local submodule_status=$(git submodule status "$SUBMODULE_NAME" 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            echo "║ Submodule Status:                                      ║"
            echo "║   • $SUBMODULE_NAME is present                        ║"
            if [[ "$submodule_status" =~ ^\+ ]]; then
                echo "║   • Submodule has uncommitted changes                ║"
            fi
        fi
    fi
    
    echo "╚════════════════════════════════════════════════════════════╝"
}

# Send notification with git status
send_git_status_notification() {
    local git_info=""
    
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local branch=$(git branch --show-current)
        local status=$(git status --porcelain | wc -l)
        local unpushed=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
        
        git_info="Branch: $branch"
        if [[ "$status" != "0" ]]; then
            git_info="$git_info, $status changes"
        fi
        if [[ "$unpushed" != "0" ]]; then
            git_info="$git_info, $unpushed unpushed"
        fi
        
        send_cursor_notification "Git Status" "$git_info"
    else
        send_cursor_notification "Git Status" "Not in a git repository"
    fi
}

# Send initial status notification
send_git_status_notification

# Function to get the root of the git repository
get_git_root() {
    local current_dir="$PWD"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    return 1
}

# Logging functions
log_error() {
    [[ $DEBUG_LEVEL -ge 0 ]] && echo "[ERROR] $*" >&2
}

log_warn() {
    [[ $DEBUG_LEVEL -ge 1 ]] && echo "[WARN] $*"
}

log_info() {
    [[ $DEBUG_LEVEL -ge 2 ]] && echo "[INFO] $*"
}

log_ok() {
    [[ $DEBUG_LEVEL -ge 2 ]] && echo "[OK] $*"
}

log_debug() {
    [[ $DEBUG_LEVEL -ge 3 ]] && echo "[DEBUG] $*"
}

# Function to get GitHub username from git config
get_github_username() {
    git config --get user.name
}

# Function to get GitHub organizations
get_github_orgs() {
    gh org list --json name -q '.[].name' 2>/dev/null
}

# Function to check if a repo URL appears to be owned by user
is_user_repo() {
    local url="$1"
    
    # Parse different URL formats
    local host=""
    local owner=""
    
    if [[ "$url" =~ ^https://([^/]+)/([^/]+)/([^/]+)\.git$ ]]; then
        host="${BASH_REMATCH[1]}"
        owner="${BASH_REMATCH[2]}"
    elif [[ "$url" =~ ^git@([^:]+):([^/]+)/([^/]+)\.git$ ]]; then
        host="${BASH_REMATCH[1]}"
        owner="${BASH_REMATCH[2]}"
    else
        log_debug "Unknown URL format: $url"
        return 1
    fi
    
    # Check if this host/owner combination matches user's config
    IFS=';' read -ra HOST_CONFIGS <<< "$GIT_HOSTS_CONFIG"
    for host_config in "${HOST_CONFIGS[@]}"; do
        if [[ "$host_config" =~ ^([^:]+):(.+)$ ]]; then
            config_host="${BASH_REMATCH[1]}"
            config_owners="${BASH_REMATCH[2]}"
            
            if [[ "$host" == "$config_host" ]]; then
                # Check if owner matches any of the configured owners for this host
                IFS=',' read -ra OWNERS <<< "$config_owners"
                for config_owner in "${OWNERS[@]}"; do
                    if [[ "$owner" == "$config_owner" ]]; then
                        return 0
                    fi
                done
            fi
        fi
    done
    
    return 1
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Not in a git repository"
        return 1
    fi
    return 0
}

# Function to check repository health
check_repo_health() {
    local repo_path="$1"
    local has_issues=0

    # Check for uncommitted changes
    if ! git -C "$repo_path" diff-index --quiet HEAD -- 2>/dev/null; then
        log_warn "Repository has UNCOMMITTED CHANGES - CRITICAL DATA LOSS RISK!"
        has_issues=1
    elif ! git -C "$repo_path" diff-index --quiet --cached HEAD -- 2>/dev/null; then
        log_warn "Repository has staged but uncommitted changes - DATA LOSS RISK!"
        has_issues=1
    fi

    # Check for untracked files
    if [[ -n "$(git -C "$repo_path" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        log_warn "Repository has untracked files - potential DATA LOSS RISK!"
        has_issues=1
    fi

    # Check remote status
    if git -C "$repo_path" remote get-url origin >/dev/null 2>&1; then
        local origin_url=$(git -C "$repo_path" remote get-url origin 2>/dev/null)
        
        # Check if using HTTPS for what appears to be your own repo
        if [[ "$origin_url" =~ ^https:// ]] && is_user_repo "$origin_url"; then
            # Generate the SSH equivalent URL
            if [[ "$origin_url" =~ ^https://([^/]+)/([^/]+)/([^/]+)\.git$ ]]; then
                host="${BASH_REMATCH[1]}"
                owner="${BASH_REMATCH[2]}"
                repo="${BASH_REMATCH[3]}"
                ssh_url="git@${host}:${owner}/${repo}.git"
                log_warn "Repository uses HTTPS origin. To switch to SSH, run:"
                log_warn "  git remote set-url origin $ssh_url"
                has_issues=1
            fi
        fi

        # Check for unpushed commits
        if timeout 5 git -C "$repo_path" fetch --quiet 2>/dev/null; then
            local_main=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null)
            remote_main=$(git -C "$repo_path" rev-parse @{u} 2>/dev/null)
            
            if [[ -n "$local_main" && -n "$remote_main" && "$local_main" != "$remote_main" ]]; then
                ahead_count=$(git -C "$repo_path" rev-list --count @{u}..HEAD 2>/dev/null || echo "?")
                if [[ "$ahead_count" != "0" && "$ahead_count" != "?" ]]; then
                    log_warn "Repository has $ahead_count unpushed commit(s) - DATA LOSS RISK if computer fails!"
                    has_issues=1
                fi
            fi
        fi
    else
        log_warn "Repository has no remote origin configured"
        has_issues=1
    fi

    return $has_issues
}

# Function to initialize git repository
init_git_repo() {
    local folder_name=$(basename "$PWD")
    local username=$(get_github_username)
    
    echo "Initializing git repository for: $folder_name"
    git init
    
    # Get repository visibility
    read -p "Do you want this repository to be public? (y/n): " is_public
    local visibility="private"
    if [[ $is_public == "y" ]]; then
        visibility="public"
    fi
    
    # Get organization or personal account
    echo "Available organizations:"
    local orgs=($(get_github_orgs))
    echo "0) Personal account ($username)"
    for i in "${!orgs[@]}"; do
        echo "$((i+1))) ${orgs[$i]}"
    done
    
    read -p "Select organization number (0 for personal): " org_choice
    
    local repo_owner=$username
    if [[ $org_choice != "0" ]]; then
        repo_owner=${orgs[$((org_choice-1))]}
    fi
    
    # Create GitHub repository
    gh repo create "$folder_name" --$visibility --owner "$repo_owner" --source=. --remote=origin
    
    # Initial commit
    git add .
    git commit -m "Initial commit"
    git branch -M main
    git push -u origin main
}

# Function to check and update submodules
check_submodules() {
    local git_root=$(get_git_root)
    if [ -z "$git_root" ]; then
        log_error "Could not find git repository root"
        return 1
    fi

    local overall_success=0
    
    for submodule in "${EXT_SUBMODULES[@]}"; do
        log_info "Checking submodule: $submodule"
        
        if [ ! -d "$git_root/$submodule" ]; then
            # Determine the correct repo URL based on submodule name
            local repo_url="$SUBMODULE_REPO_URL"
            if [[ "$submodule" != "$SUBMODULE_NAME" ]]; then
                # For other submodules, try to construct URL from the pattern
                repo_url="git@github.com:Imagination-Guild-LLC/${submodule}.git"
                log_debug "Using constructed URL for $submodule: $repo_url"
            fi
            
            log_info "Adding $submodule submodule..."
            if (cd "$git_root" && git submodule add "$repo_url" "$submodule" 2>/dev/null); then
                (cd "$git_root" && git submodule update --init --recursive "$submodule")
                log_ok "Submodule $submodule added successfully"
            else
                log_warn "Failed to add submodule $submodule (may already exist or network issue)"
            fi
        else
            log_debug "Checking $submodule submodule status..."
            if check_single_submodule "$git_root/$submodule" "$submodule"; then
                log_ok "Submodule $submodule is healthy"
            else
                log_warn "Issues with submodule $submodule"
                overall_success=1
            fi
        fi
    done
    
    return $overall_success
}

# Function to check a single submodule
check_single_submodule() {
    local submodule_path="$1"
    local submodule_name="$2"
    
    (
        cd "$submodule_path" || exit 1
        
        # Try to fetch latest changes
        if ! git fetch --quiet 2>/dev/null; then
            log_warn "Submodule $submodule_name fetch failed (network/permission issue)"
            return 1
        fi
        
        # Check if we have a remote tracking branch
        if ! git rev-parse @{u} >/dev/null 2>&1; then
            log_warn "Submodule $submodule_name has no upstream branch configured"
            return 1
        fi
        
        local=$(git rev-parse @)
        remote=$(git rev-parse @{u})
        base=$(git merge-base @ @{u} 2>/dev/null)
        
        if [[ -z "$base" ]]; then
            log_warn "Cannot determine merge base for $submodule_name"
            return 1
        fi
        
        if [[ "$local" == "$remote" ]]; then
            log_debug "Submodule $submodule_name is up to date."
        elif [[ "$local" == "$base" ]]; then
            behind=$(git rev-list --count "$local..$remote" 2>/dev/null || echo "?")
            log_info "Submodule $submodule_name is behind by $behind commit(s), updating..."
            if git pull --quiet 2>/dev/null; then
                log_ok "Submodule $submodule_name updated successfully."
            else
                log_error "Submodule $submodule_name update failed - may need manual intervention."
                return 1
            fi
        elif [[ "$remote" == "$base" ]]; then
            ahead=$(git rev-list --count "$remote..$local" 2>/dev/null || echo "?")
            log_warn "Submodule $submodule_name is ahead by $ahead commit(s)."
        else
            log_warn "Submodule $submodule_name has diverged from origin - manual intervention required."
            return 1
        fi
    )
}

# Main execution
if ! check_git_repo; then
    echo "No git repository found. Would you like to initialize one? (y/n)"
    read -p "> " init_choice
    if [[ $init_choice == "y" ]]; then
        init_git_repo
    fi
else
    git_root=$(get_git_root)
    if [ -z "$git_root" ]; then
        log_error "Could not find git repository root"
        exit 1
    fi
    
    # Check repository health (warnings only, don't fail)
    check_repo_health "$git_root" || true
    
    # Check and update submodules
    check_submodules || log_warn "Failed to update one or more submodules"
fi 