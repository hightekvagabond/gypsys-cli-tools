#!/usr/bin/env bash
# =============================================================================
# Repository Health Check Script
# =============================================================================
#
# PURPOSE:
# This script audits all subdirectories in a base directory (typically ~/dev) 
# to ensure they follow best practices for git repository management and 
# standardization. It performs three main functions:
#
# 1. REPOSITORY DETECTION: Identifies which directories are git repositories
#    and which are not, helping you clean up orphaned or forgotten projects.
#
# 2. REMOTE TRACKING: Ensures all git repositories have remote origins 
#    configured (GitHub, GitLab, CodeCommit, etc.) to prevent data loss and
#    enable collaboration/backup.
#
# 3. SUBMODULE STANDARDIZATION: Automatically manages a standardized submodule
#    across all repositories. This is useful for:
#    - Shared coding standards and linting rules
#    - Common development tools and scripts
#    - Documentation templates
#    - CI/CD pipeline configurations
#    - Any other files you want consistent across all projects
#
# SMART AUTO-UPDATING:
# - When submodules are behind: Automatically updates them in quiet mode
# - When submodules have diverged: Warns and requires manual intervention
# - Configurable verbosity levels for different use cases
#
# CONFIGURATION:
# Edit these variables to customize for your environment:
SUBMODULE_REPO_URL="git@github.com:Imagination-Guild-LLC/ai-coder-best-practices.git"
SUBMODULE_NAME="ai-best-practices"

# Git host configuration - define your usernames/organizations for different hosts
# Format: "host:username,host:username" or "host:username1,username2"
GIT_HOSTS_CONFIG="github.com:hightekvagabond,Imagination-Guild-LLC;gitlab.com:yourusername;codecommit.us-west-2.amazonaws.com:yourprofile"
#
# Examples:
# - Single user: "github.com:myusername"
# - Multiple users on same host: "github.com:personal,work-org"
# - Multiple hosts: "github.com:user1;gitlab.com:user2;bitbucket.org:user3"
# - AWS CodeCommit: "codecommit.us-west-2.amazonaws.com:profile-name"
#
# For your own use, change SUBMODULE_REPO_URL to point to your standardization
# repository and SUBMODULE_NAME to whatever you want the folder to be called.
#
# TYPICAL WORKFLOW:
# - Run daily with default settings: ./check-repos.sh
# - Only see problems, auto-fix what can be fixed safely
# - Review diverged submodules manually when warned
# - Clean up empty directories and add remotes to local-only repos as needed
#
# =============================================================================

set -uo pipefail

# Debug levels: 0=quiet, 1=errors/warnings only, 2=info, 3=verbose/debug
DEBUG_LEVEL=${DEBUG_LEVEL:-1}

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
  elif [[ "$url" =~ ^https://git-codecommit\.([^.]+)\.amazonaws\.com/v1/repos/([^/]+)$ ]]; then
    host="codecommit.${BASH_REMATCH[1]}.amazonaws.com"
    owner="aws-repo"  # CodeCommit doesn't have traditional owners
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
        # Special case for CodeCommit - if host matches, assume it's user's repo
        if [[ "$host" =~ codecommit.*amazonaws\.com ]]; then
          return 0
        fi
        
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
usage() {
  cat << EOF
Usage: $0 [OPTIONS]
Check git repositories and ai-best-practices submodules

Options:
  -q, --quiet     Quiet mode (DEBUG_LEVEL=0) - only critical errors
  -w, --warn      Warning mode (DEBUG_LEVEL=1) - errors and warnings [DEFAULT]
  -i, --info      Info mode (DEBUG_LEVEL=2) - includes success messages
  -v, --verbose   Verbose mode (DEBUG_LEVEL=3) - debug information
  -h, --help      Show this help

Examples:
  $0              # Default: show errors and warnings only
  $0 -q           # Quiet: only show critical errors
  $0 -i           # Show successes too
  $0 -v           # Show everything including debug info
  DEBUG_LEVEL=2 $0  # Set debug level via environment variable
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -q|--quiet)
      DEBUG_LEVEL=0
      shift
      ;;
    -w|--warn)
      DEBUG_LEVEL=1
      shift
      ;;
    -i|--info)
      DEBUG_LEVEL=2
      shift
      ;;
    -v|--verbose)
      DEBUG_LEVEL=3
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_debug "Scanning directories in: $BASE_DIR"

processed_count=0
repo_count=0
up_to_date_count=0
warning_count=0
error_count=0

for proj in "$BASE_DIR"/*/; do
  [[ -d "$proj" ]] || continue
  proj="${proj%/}"
  name="$(basename "$proj")"
  
  log_debug "Processing: $name"
  ((processed_count++))
  
  # 1. Git repo?
  if ! git -C "$proj" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Check if directory is empty
    if [[ -z "$(ls -A "$proj" 2>/dev/null)" ]]; then
      log_warn "'$name' is not a Git repo yet (directory is empty - consider removing)."
    else
      log_warn "'$name' is not a Git repo yet."
    fi
    continue
  fi
  
  ((repo_count++))
  log_debug "'$name' is a valid git repository"
  
  # Check if git repo has a remote origin
  if ! git -C "$proj" remote get-url origin >/dev/null 2>&1; then
    log_warn "'$name' is a local-only git repo (no remote origin configured)."
    ((warning_count++))
  else
    origin_url=$(git -C "$proj" remote get-url origin 2>/dev/null)
    log_debug "'$name' has remote origin configured: $origin_url"
    
    # Check if using HTTPS for what appears to be your own repo
    if [[ "$origin_url" =~ ^https:// ]] && is_user_repo "$origin_url"; then
      # Generate the SSH equivalent URL
      ssh_url=""
      if [[ "$origin_url" =~ ^https://([^/]+)/([^/]+)/([^/]+)\.git$ ]]; then
        host="${BASH_REMATCH[1]}"
        owner="${BASH_REMATCH[2]}"
        repo="${BASH_REMATCH[3]}"
        ssh_url="git@${host}:${owner}/${repo}.git"
      elif [[ "$origin_url" =~ ^https://git-codecommit\.([^.]+)\.amazonaws\.com/v1/repos/([^/]+)$ ]]; then
        region="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        ssh_url="ssh://git-codecommit.${region}.amazonaws.com/v1/repos/${repo}"
      fi
      
      if [[ -n "$ssh_url" ]]; then
        log_warn "'$name' uses HTTPS origin. To switch to SSH, run:"
        log_warn "  cd $proj && git remote set-url origin $ssh_url"
      else
        log_warn "'$name' uses HTTPS origin (consider switching to SSH for easier authentication): $origin_url"
      fi
      ((warning_count++))
    fi
    
    # Check for uncommitted changes (highest data loss risk)
    if ! git -C "$proj" diff-index --quiet HEAD -- 2>/dev/null; then
      log_warn "'$name' has UNCOMMITTED CHANGES - CRITICAL DATA LOSS RISK!"
      ((warning_count++))
    elif ! git -C "$proj" diff-index --quiet --cached HEAD -- 2>/dev/null; then
      log_warn "'$name' has staged but uncommitted changes - DATA LOSS RISK!"
      ((warning_count++))
    fi
    
    # Check for untracked files
    if [[ -n "$(git -C "$proj" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
      log_warn "'$name' has untracked files - potential DATA LOSS RISK!"
      ((warning_count++))
    fi
    
    # Check if main repo has unpushed commits (data loss risk)
    # Only try to fetch if we can do it without authentication prompts
    if timeout 5 git -C "$proj" fetch --quiet 2>/dev/null; then
      local_main=$(git -C "$proj" rev-parse HEAD 2>/dev/null)
      remote_main=$(git -C "$proj" rev-parse @{u} 2>/dev/null)
      
      if [[ -n "$local_main" && -n "$remote_main" ]]; then
        if [[ "$local_main" != "$remote_main" ]]; then
          ahead_count=$(git -C "$proj" rev-list --count @{u}..HEAD 2>/dev/null || echo "?")
          if [[ "$ahead_count" != "0" && "$ahead_count" != "?" ]]; then
            log_warn "'$name' has $ahead_count unpushed commit(s) - DATA LOSS RISK if computer fails!"
            ((warning_count++))
          fi
        fi
      fi
    else
      log_debug "'$name' could not fetch from remote (network/auth/permission issue) - skipping unpushed commit check"
      
      # Still try to check against last known remote state without fetching
      local_main=$(git -C "$proj" rev-parse HEAD 2>/dev/null)
      remote_main=$(git -C "$proj" rev-parse @{u} 2>/dev/null)
      
      if [[ -n "$local_main" && -n "$remote_main" ]]; then
        if [[ "$local_main" != "$remote_main" ]]; then
          ahead_count=$(git -C "$proj" rev-list --count @{u}..HEAD 2>/dev/null || echo "?")
          if [[ "$ahead_count" != "0" && "$ahead_count" != "?" ]]; then
            log_warn "'$name' may have $ahead_count unpushed commit(s) - check manually (couldn't fetch latest remote state)."
            ((warning_count++))
          fi
        fi
      fi
    fi
  fi
  
  # 2. Submodule present?
  if [[ ! -d "$proj/$SUBMODULE_NAME" ]]; then
    log_info "'$name' missing submodule — adding it..."
    (
      cd "$proj" || { log_error "'$name' cannot access directory"; ((error_count++)); exit 1; }
      tmp_err=$(mktemp)
      
      git submodule add \
        "$SUBMODULE_REPO_URL" \
        "$SUBMODULE_NAME" 2>"$tmp_err"
      rc=$?
      
      if (( rc == 0 )); then
        log_info "'$name' submodule added successfully."
        ((submodule_added_count++))
      else
        log_error "'$name' submodule add failed (exit $rc):"
        [[ $DEBUG_LEVEL -ge 1 ]] && cat "$tmp_err" >&2
        ((error_count++))
      fi
      rm -f "$tmp_err"
    )
    continue
  fi
  
  log_debug "'$name' has $SUBMODULE_NAME submodule"
  
  # 3. Sync status
  (
    cd "$proj/$SUBMODULE_NAME" || { 
      log_error "'$name' cannot access $SUBMODULE_NAME directory"
      ((error_count++))
      exit 1
    }
    
    # Check if we can access the git repo
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      log_error "'$name' $SUBMODULE_NAME is not a valid git repository"
      ((error_count++))
      exit 1
    fi
    
    log_debug "'$name' fetching latest changes..."
    
    # Try to fetch, but don't fail if we can't
    if ! git fetch --quiet 2>/dev/null; then
      log_warn "'$name' submodule fetch failed (network/permission issue)"
      ((warning_count++))
      exit 0
    fi
    
    # Check if we have a remote tracking branch
    if ! git rev-parse @{u} >/dev/null 2>&1; then
      log_warn "'$name' submodule has no upstream branch configured"
      ((warning_count++))
      exit 0
    fi
    
    local=$(git rev-parse @)
    remote=$(git rev-parse @{u})
    base=$(git merge-base @ @{u} 2>/dev/null)
    
    if [[ -z "$base" ]]; then
      log_warn "'$name' submodule cannot determine merge base"
      ((warning_count++))
      exit 0
    fi
    
    if [[ "$local" == "$remote" ]]; then
      log_ok "'$name' submodule is up to date."
      ((up_to_date_count++))
    elif [[ "$local" == "$base" ]]; then
      behind=$(git rev-list --count "$local..$remote" 2>/dev/null || echo "?")
      
      # Auto-update if behind and we're at default debug level (1) or quiet (0)
      if [[ $DEBUG_LEVEL -le 1 ]]; then
        log_debug "'$name' submodule is behind by $behind commit(s), auto-updating..."
        if git pull --quiet 2>/dev/null; then
          log_info "'$name' submodule auto-updated (was $behind commit(s) behind)."
          ((submodule_updated_count++))
        else
          log_error "'$name' submodule auto-update failed - may need manual intervention."
          ((error_count++))
        fi
      else
        # In verbose modes, just warn without auto-updating
        log_warn "'$name' submodule is **behind** by $behind commit(s)."
        ((warning_count++))
      fi
    elif [[ "$remote" == "$base" ]]; then
      ahead=$(git rev-list --count "$remote..$local" 2>/dev/null || echo "?")
      log_warn "'$name' submodule is **ahead** by $ahead commit(s)."
      ((warning_count++))
    else
      log_warn "'$name' submodule has **diverged** from origin - manual intervention required."
      ((warning_count++))
    fi
  )
done

# Summary (only show if there's something to report or in info+ mode)
if [[ $DEBUG_LEVEL -ge 2 ]] || [[ $warning_count -gt 0 ]] || [[ $error_count -gt 0 ]] || [[ ${submodule_added_count:-0} -gt 0 ]] || [[ ${submodule_updated_count:-0} -gt 0 ]]; then
  echo
  echo "=== SUMMARY ==="
  log_info "Processed $processed_count directories, $repo_count git repositories"
  [[ ${submodule_added_count:-0} -gt 0 ]] && log_info "Added $submodule_added_count submodules"
  [[ ${submodule_updated_count:-0} -gt 0 ]] && log_info "Auto-updated $submodule_updated_count submodules"
  [[ ${up_to_date_count:-0} -gt 0 ]] && log_info "$up_to_date_count submodules up to date"
  [[ $warning_count -gt 0 ]] && log_warn "$warning_count warnings"
  [[ $error_count -gt 0 ]] && log_error "$error_count errors"
fi

# Exit with appropriate code
if [[ $error_count -gt 0 ]]; then
  exit 1
elif [[ $warning_count -gt 0 ]]; then
  exit 2
else
  exit 0
fi
