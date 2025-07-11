#!/bin/bash

# Configuration
SUBMODULE_REPO_URL="git@github.com:Imagination-Guild-LLC/ai-coder-best-practices.git"
SUBMODULE_NAME="ai-best-practices"
GIT_HOSTS_CONFIG="github.com:hightekvagabond,Imagination-Guild-LLC"

# Debug levels: 0=quiet, 1=errors/warnings only, 2=info, 3=verbose/debug
DEBUG_LEVEL=${DEBUG_LEVEL:-1}

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

# Function to check and update ai-best-practices submodule
check_ai_best_practices() {
    local git_root=$(get_git_root)
    if [ -z "$git_root" ]; then
        log_error "Could not find git repository root"
        return 1
    fi

    if [ ! -d "$git_root/$SUBMODULE_NAME" ]; then
        log_info "Adding $SUBMODULE_NAME submodule..."
        (cd "$git_root" && git submodule add "$SUBMODULE_REPO_URL" "$SUBMODULE_NAME")
        (cd "$git_root" && git submodule update --init --recursive)
    else
        log_debug "Checking $SUBMODULE_NAME submodule status..."
        (
            cd "$git_root/$SUBMODULE_NAME" || exit 1
            
            # Try to fetch latest changes
            if ! git fetch --quiet 2>/dev/null; then
                log_warn "Submodule fetch failed (network/permission issue)"
                return 1
            fi
            
            # Check if we have a remote tracking branch
            if ! git rev-parse @{u} >/dev/null 2>&1; then
                log_warn "Submodule has no upstream branch configured"
                return 1
            fi
            
            local=$(git rev-parse @)
            remote=$(git rev-parse @{u})
            base=$(git merge-base @ @{u} 2>/dev/null)
            
            if [[ -z "$base" ]]; then
                log_warn "Cannot determine merge base"
                return 1
            fi
            
            if [[ "$local" == "$remote" ]]; then
                log_ok "Submodule is up to date."
            elif [[ "$local" == "$base" ]]; then
                behind=$(git rev-list --count "$local..$remote" 2>/dev/null || echo "?")
                log_info "Submodule is behind by $behind commit(s), updating..."
                if git pull --quiet 2>/dev/null; then
                    log_ok "Submodule updated successfully."
                else
                    log_error "Submodule update failed - may need manual intervention."
                    return 1
                fi
            elif [[ "$remote" == "$base" ]]; then
                ahead=$(git rev-list --count "$remote..$local" 2>/dev/null || echo "?")
                log_warn "Submodule is ahead by $ahead commit(s)."
            else
                log_warn "Submodule has diverged from origin - manual intervention required."
                return 1
            fi
        )
    fi
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
    
    # Check repository health
    check_repo_health "$git_root"
    
    # Check and update ai-best-practices submodule
    check_ai_best_practices
fi 