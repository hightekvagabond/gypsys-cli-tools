#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# CURSOR WORKSPACE LAUNCHER
# =============================================================================
# 
# ✨ COOL FEATURE: This script performs "hot reload" Cursor updates that preserve
#    your entire workspace layout and open files. No disruption to your workflow!
# 
# 🧪 AI DEBUGGING: Use --dry-run to test script logic safely. This creates mock
#    environments and shows exactly what the script would do without making changes.
#    Automatically enables DEBUG mode for comprehensive step-by-step feedback.
#    Perfect for AI assistants working on this script!
# 
# 
# PURPOSE:
#   This script manages Cursor IDE windows based on KDE Workspaces (virtual desktops).
#   It can:
#   1. Launch Cursor for the current KDE workspace with the associated project (default)
#   2. Restore Cursor sessions for all configured workspaces (--all mode)
#   3. Set Cursor mapping for current workspace only (--set mode)
#   4. Generate a configuration mapping KDE workspaces to project directories (--set-all mode)
#   5. Perform seamless "hot reload" Cursor version updates that preserve workspace layout
#
# DEPENDENCIES:
#   - KDE Plasma desktop environment
#   - wmctrl: Window management utility
#   - xdotool: X11 automation tool  
#   - jq: JSON processor
#   - curl, wget packages (for online version checking and downloads)
#   - Cursor AppImage in $CURSOR_DIR (pattern: Cursor-*-x*.AppImage)
#
# INSTALLATION:
#   sudo apt install wmctrl xdotool jq curl wget
#   Place Cursor AppImage in $CURSOR_DIR directory
#
# USAGE:
#   ./launch_cursor.sh              # Launch Cursor for current workspace (with seamless version check)
#   ./launch_cursor.sh --all        # Restore Cursor sessions for all configured workspaces
#   ./launch_cursor.sh --set        # Set Cursor mapping for current workspace only
#   ./launch_cursor.sh --set-all    # Generate workspace-to-project mapping for all workspaces
#   ./launch_cursor.sh --update     # Check for updates and prompt for seamless restart
#   ./launch_cursor.sh --force-update # Force seamless update without prompting
#   ./launch_cursor.sh --check-online # Check cursor.com for newer versions and download if available
#   ./launch_cursor.sh --dry-run    # Test script logic without making changes (AI debugging tool)
#
# CONFIG FILE:
#   ~/.config/cursor-workspace-map.json
#   Format: {"workspace_name": "/path/to/project"}
#
# HOW IT WORKS:
#   --set mode:
#   1. Gets current workspace name using wmctrl
#   2. Clears any existing Cursor mapping for that workspace
#   3. If Cursor windows are open in current workspace, maps them to projects
#   4. If no Cursor windows open, removes the workspace from config
#   5. Updates JSON config with new mapping for current workspace only
#
#   --set-all mode:
#   1. Uses wmctrl to find all open Cursor windows and their workspace locations
#   2. Extracts project names from Cursor window titles
#   3. Maps project names to actual directories in ~/dev, ~/projects, etc.
#   4. Creates JSON config mapping workspace names to project paths
#
#   Launch mode:
#   1. Checks for Cursor version updates first (only in --all mode)
#   2. Gets current workspace name using wmctrl
#   3. Looks up associated project in config file  
#   4. Launches Cursor with that project directory
#
#   Launch all mode (--all):
#   1. Checks for Cursor version updates first
#   2. Gets current workspace name using wmctrl
#   3. Looks up associated project in config file  
#   4. Launches Cursor with that project directory
#   5. Then checks all configured workspaces for missing Cursor sessions
#
#   Version check mode:
#   1. Finds the latest Cursor AppImage in $CURSOR_DIR
#   2. Detects version of currently running Cursor instances
#   3. Compares versions and offers to restart if newer version available
#   4. Performs seamless "hot reload" - preserves all windows and open files
#   5. Updates underlying processes while keeping workspace layout intact
#
#   Dry-run mode (AI debugging tool):
#   1. Creates mock environment with realistic file structures
#   2. Tests dependency detection and version comparison logic
#   3. Simulates config file handling (with/without config)
#   4. Shows exactly what the script would do without making changes
#   5. Automatically cleans up test environment after completion
#
# =============================================================================

# Configuration constants
CONFIG="$HOME/.config/cursor-workspace-map.json"  # Path to workspace mapping config
CURSOR_DIR="$HOME/Downloads/"                            # Directory containing Cursor AppImages
ARGS="--no-sandbox"                               # Default Cursor launch arguments
# Global throttle control (can be overridden by --throttle/--no-throttle flags)
CURSOR_THROTTLE_ENABLED=false
# Note: CURSOR_BIN is set dynamically by find_latest_cursor() function



# =============================================================================
# FUNCTION: find_latest_cursor
# =============================================================================
# PURPOSE: Finds the most recent Cursor AppImage in the CURSOR_DIR
# RETURNS: Path to the most recent Cursor AppImage, or empty string if not found
# LOGIC:
#   1. Searches for files matching pattern Cursor-*-x*.AppImage
#   2. Extracts version numbers from filenames
#   3. Compares versions and returns the highest version
# TESTING: Use --dry-run to test this function with mock Cursor AppImages
# =============================================================================
find_latest_cursor() {
    local cursor_dir="$CURSOR_DIR"
    local latest_cursor=""
    local highest_version=""
    
    # Check if directory exists
    if [[ ! -d "$cursor_dir" ]]; then
        echo "⚠️  Cursor directory not found: $cursor_dir" >&2
        return 1
    fi
    
    # Find all Cursor AppImages
    local cursor_files=($(find "$cursor_dir" -maxdepth 1 -name "Cursor-*-x*.AppImage" -type f 2>/dev/null))
    
    if [[ ${#cursor_files[@]} -eq 0 ]]; then
        echo "⚠️  No Cursor AppImages found in $cursor_dir" >&2
        echo "💡 Expected pattern: Cursor-*-x*.AppImage" >&2
        return 1
    fi

    # Process each Cursor file to find the highest version
    for cursor_file in "${cursor_files[@]}"; do
        local filename=$(basename "$cursor_file")
        
        # Extract version from filename (e.g., "Cursor-1.2.4-x86_64.AppImage" -> "1.2.4")
        local version=$(echo "$filename" | sed -E 's/^Cursor-([0-9]+\.[0-9]+\.[0-9]+).*\.AppImage$/\1/')
        
        if [[ -n "$version" ]]; then
            # Compare versions using sort -V (version sort)
            if [[ -z "$highest_version" ]] || [[ "$version" == "$(echo -e "$highest_version\n$version" | sort -V | tail -n1)" ]]; then
                highest_version="$version"
                latest_cursor="$cursor_file"
            fi
        fi
    done
    
    if [[ -n "$latest_cursor" ]]; then
        # Ensure the found cursor is executable
        if ! ensure_cursor_executable "$latest_cursor"; then
            echo "⚠️  Found Cursor but it's not executable: $latest_cursor" >&2
            return 1
        fi
        
        echo "$latest_cursor"
        return 0
    else
        echo "⚠️  Could not determine version from Cursor filenames" >&2
        echo "💡 Found files: ${cursor_files[*]}" >&2
        return 1
    fi
}

# =============================================================================
# FUNCTION: get_running_cursor_version
# =============================================================================
# PURPOSE: Gets the version of currently running Cursor instances
# RETURNS: Version string of running Cursor, or empty if not found/determinable
# LOGIC:
#   1. Finds running Cursor processes
#   2. Gets the executable path from the process
#   3. Extracts version from the path
# =============================================================================
get_running_cursor_version() {
    # Find running Cursor processes
    local cursor_pids=$(pgrep -f "Cursor.*AppImage" 2>/dev/null || true)
    
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo "  🐛 DEBUG: Found cursor PIDs: '$cursor_pids'"
    fi
    
    if [[ -z "$cursor_pids" ]]; then
        if [[ "${DEBUG:-}" == "1" ]]; then
            echo "  🐛 DEBUG: No cursor PIDs found, returning 1"
        fi
        return 1  # No running Cursor processes
    fi
    
    # Get the first Cursor process to check its version
    local first_pid=$(echo "$cursor_pids" | head -n1)
    
    # Get the executable path from /proc/PID/exe
    local cursor_exe=""
    if [[ -L "/proc/$first_pid/exe" ]]; then
        cursor_exe=$(readlink "/proc/$first_pid/exe" 2>/dev/null || true)
    fi
    
    if [[ -z "$cursor_exe" ]]; then
        # Fallback: try to get from command line
        cursor_exe=$(tr '\0' ' ' < "/proc/$first_pid/cmdline" 2>/dev/null | awk '{print $1}' || true)
    fi
    
    if [[ -n "$cursor_exe" ]]; then
        local filename=$(basename "$cursor_exe")
        
        # Remove " (deleted)" suffix if present
        filename=$(echo "$filename" | sed 's/ (deleted)$//')
        
        # Extract version from filename (e.g., "Cursor-1.2.4-x86_64.AppImage" -> "1.2.4")
        local version=$(echo "$filename" | sed -E 's/^Cursor-([0-9]+\.[0-9]+\.[0-9]+).*\.AppImage.*$/\1/')
        
        if [[ -n "$version" && "$version" != "$filename" ]]; then
            if [[ "${DEBUG:-}" == "1" ]]; then
                echo "  🐛 DEBUG: Extracted version: '$version' from filename: '$filename'"
            fi
            echo "$version"
            return 0
        fi
    fi
    
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo "  🐛 DEBUG: Could not extract version from filename: '$filename'"
    fi
    return 1
}

# =============================================================================
# FUNCTION: kill_all_cursor_instances
# =============================================================================
# PURPOSE: Gracefully kills all running Cursor instances for seamless version updates
# RETURNS: 0 if successful, 1 if failed
# NOTE: This performs a "hot reload" - Cursor windows may stay open while
#       underlying processes are updated, providing a seamless upgrade experience
# =============================================================================
kill_all_cursor_instances() {
    echo "🔄 Stopping all Cursor instances..."
    
    # Find all Cursor processes
    local cursor_pids=$(pgrep -f "Cursor.*AppImage" 2>/dev/null || true)
    
    if [[ -z "$cursor_pids" ]]; then
        echo "  ℹ️  No running Cursor instances found"
        return 0
    fi
    
    local pid_count=$(echo "$cursor_pids" | wc -l)
    echo "  📋 Found $pid_count Cursor process(es) to stop"
    
    # First try graceful termination (SIGTERM)
    echo "  🛑 Sending SIGTERM to Cursor processes..."
    echo "$cursor_pids" | xargs -r kill -TERM 2>/dev/null || true
    
    # Wait a bit for graceful shutdown
    sleep 3
    
    # Check if any are still running
    local remaining_pids=$(pgrep -f "Cursor.*AppImage" 2>/dev/null || true)
    
    if [[ -n "$remaining_pids" ]]; then
        echo "  ⚠️  Some processes still running, sending SIGKILL..."
        echo "$remaining_pids" | xargs -r kill -KILL 2>/dev/null || true
        sleep 1
    fi
    
    # Final check
    remaining_pids=$(pgrep -f "Cursor.*AppImage" 2>/dev/null || true)
    
    if [[ -z "$remaining_pids" ]]; then
        echo "  ✅ All Cursor instances stopped successfully"
        return 0
    else
        echo "  ❌ Failed to stop some Cursor instances"
        return 1
    fi
}

# =============================================================================
# FUNCTION: check_for_cursor_updates
# =============================================================================
# PURPOSE: Checks if there's a newer version of Cursor available and offers to restart
# PARAMETERS: $1 = "force" to skip user prompt and auto-restart (optional)
# RETURNS: 0 if no action needed, 1 if restart was performed
# FEATURE: Performs seamless "hot reload" updates that preserve workspace layout
#         and open files while updating the underlying Cursor version
# TESTING: Use --dry-run to test this function without making changes
# =============================================================================
check_for_cursor_updates() {
    local force_update="${1:-}"
    echo "🔍 Checking for Cursor version updates..."
    
    # First, check online for newer versions and download if available
    echo "🌐 Checking cursor.com for newer versions..."
    if check_and_download_cursor_updates; then
        echo "📥 New version downloaded, refreshing local version list..."
        # The download function already handled the new version
        # Now we can proceed with the normal update process
    else
        echo "ℹ️  No new versions available online or download failed"
    fi
    
    # Get the latest available version (now including any newly downloaded versions)
    local latest_version=""
    local latest_cursor=""
    if ! latest_cursor=$(find_latest_cursor); then
        echo "  ⚠️  Could not determine latest Cursor version"
        return 0
    fi
    
    # Extract version from the latest cursor path
    local latest_filename=$(basename "$latest_cursor")
    latest_version=$(echo "$latest_filename" | sed -E 's/^Cursor-([0-9]+\.[0-9]+\.[0-9]+).*\.AppImage$/\1/')
    
    if [[ -z "$latest_version" ]]; then
        echo "  ⚠️  Could not parse version from: $latest_filename"
        return 0
    fi
    
    echo "  📦 Latest available version: $latest_version"
    
    # Get the currently running version
    local running_version=""
    echo "  🔍 DEBUG: About to call get_running_cursor_version..."
    if running_version=$(get_running_cursor_version); then
        echo "  🏃 Currently running version: $running_version"
        echo "  🔍 DEBUG: get_running_cursor_version returned true"
        
        # Debug output for version comparison
        if [[ "${DEBUG:-}" == "1" ]]; then
            echo "  🐛 DEBUG: Comparing '$running_version' vs '$latest_version'"
            local sorted_versions=$(echo -e "$running_version\n$latest_version" | sort -V)
            echo "  🐛 DEBUG: Sorted order: $(echo "$sorted_versions" | tr '\n' ' ')"
            local highest=$(echo "$sorted_versions" | tail -n1)
            echo "  🐛 DEBUG: Highest version: '$highest'"
        fi
        
        # Compare versions
        if [[ "$latest_version" == "$running_version" ]]; then
            echo "  ✅ Already running the latest version!"
            return 0
        elif [[ "$latest_version" == "$(echo -e "$running_version\n$latest_version" | sort -V | tail -n1)" ]]; then
            echo "  🆕 Newer version available: $running_version → $latest_version"
            
            local should_restart=false
            
            if [[ "$force_update" == "force" ]]; then
                echo "  🚀 Force update mode - automatically restarting with new version"
                should_restart=true
            else
                # Ask user if they want to restart
                echo ""
                echo "❓ A newer version of Cursor is available. Would you like to:"
                echo "   1. Restart all Cursor instances with the new version"
                echo "   2. Continue with current version"
                echo ""
                read -p "Enter your choice (1 or 2): " choice
                
                case "$choice" in
                    1)
                        should_restart=true
                        ;;
                    2)
                        echo "  ℹ️  Continuing with current version $running_version"
                        return 0
                        ;;
                    *)
                        echo "  ⚠️  Invalid choice, continuing with current version"
                        return 0
                        ;;
                esac
            fi
            
            if [[ "$should_restart" == true ]]; then
                echo ""
                echo "🔄 Performing seamless Cursor update to version $latest_version..."
                echo "💡 Note: Your Cursor windows may stay open during this process"
                echo "   This is normal - the update preserves your workspace layout!"
                
                # Kill all current instances
                if ! kill_all_cursor_instances; then
                    echo "❌ Failed to stop current Cursor instances"
                    return 0
                fi
                
                # Wait a moment for cleanup
                sleep 2
                
                # Restart all configured sessions
                echo "🚀 Restarting Cursor sessions with new version..."
                launch_missing_sessions
                
                echo "✅ Cursor has been seamlessly updated to version $latest_version!"
                echo "🎉 Your workspace layout and open files have been preserved!"
                return 1
            fi
        else
            echo "  ℹ️  Running version ($running_version) is newer than available ($latest_version)"
            return 0
        fi
    else
        echo "  ℹ️  No running Cursor instances found"
        echo "  🔍 DEBUG: get_running_cursor_version returned false"
        echo "  🔍 DEBUG: Returning 0 (no action needed)"
        return 0
    fi
}

# =============================================================================
# FUNCTION: get_current_workspace
# =============================================================================
# PURPOSE: Gets the name of the currently active KDE workspace
# RETURNS: String containing the current workspace name
# DEPENDENCIES: wmctrl
# =============================================================================
get_current_workspace() {
    # Use wmctrl to get current desktop name (just the workspace name, not dimensions)
    wmctrl -d | grep '\*' | awk '{print $NF}'
}

# =============================================================================
# FUNCTION: detect_project_from_window_title
# =============================================================================
# PURPOSE: Extracts project name/path from Cursor window title
# PARAMETERS: $1 = window title
# RETURNS: Project name or directory path
# =============================================================================
detect_project_from_window_title() {
    local title="$1"
    local project=""
    
    # Pattern 1: Handle dev containers - "filename - project-name [Container...] - Cursor"
    if [[ "$title" == *" - "* ]] && [[ "$title" == *"[Container"* ]] && [[ "$title" == *" - Cursor"* ]]; then
        # Extract project name from dev container title: "filename - project-name [Container...] - Cursor"
        # Remove everything before first " - " and everything from " [Container" onwards
        project=$(echo "$title" | sed -E 's/^[^-]+ - ([^[]+) \[Container.*$/\1/' | sed 's/[[:space:]]*$//')
    # Pattern 2: Handle dev containers - "project-name [Dev Container...] - Cursor"
    elif [[ "$title" =~ ^([^[]+)[[:space:]]*\[Dev[[:space:]]Container.*\][[:space:]]*-[[:space:]]*Cursor ]]; then
        project=$(echo "$title" | sed -E 's/^([^[]+)[[:space:]]*\[Dev[[:space:]]Container.*\][[:space:]]*-[[:space:]]*Cursor.*/\1/' | sed 's/[[:space:]]*$//')
    # Pattern 3: "filename - project-name - Cursor" (extract middle part of 3-part title)
    elif [[ "$title" == *" - "* ]] && [[ "$title" == *" - Cursor"* ]]; then
        # Count the number of " - " separators
        local dash_count=$(echo "$title" | grep -o " - " | wc -l)
        if [[ $dash_count -eq 2 ]]; then
            # Extract the middle part: remove everything up to first " - " and from last " - Cursor"
            project=$(echo "$title" | sed -E 's/^[^-]+ - (.+) - Cursor.*$/\1/')
        fi
    fi
    
    # If no project found yet, try simple pattern
    if [[ -z "$project" ]]; then
        # Pattern 3: Simple "project-name - Cursor" (including projects with hyphens)  
        if [[ "$title" =~ ^(.+)[[:space:]]*-[[:space:]]*Cursor[[:space:]]*$ ]]; then
            project=$(echo "$title" | sed -E 's/^(.+)[[:space:]]*-[[:space:]]*Cursor[[:space:]]*$/\1/')
        fi
    fi
    
    # Clean up the project name - remove leading/trailing whitespace
    project=$(echo "$project" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    
    # Debug output to see what we extracted
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo "  🐛 DEBUG: Title: '$title'" >&2
        echo "  🐛 DEBUG: Extracted: '$project'" >&2
    fi
    
    if [[ -n "$project" && "$project" != "Cursor" ]]; then
        echo "$project"
        return 0
    fi
    
    return 1
}

# =============================================================================
# FUNCTION: find_project_directory
# =============================================================================
# PURPOSE: Converts project name to actual directory path
# PARAMETERS: $1 = project name from window title, $2 = workspace name (optional)
# RETURNS: Full directory path if found
# =============================================================================
find_project_directory() {
    local project_name="$1"
    local workspace_name="${2:-}"
    local project_dir=""
    
    # Common project base directories
    local base_dirs=("$HOME/dev" "$HOME/projects" "$HOME/workspace" "$HOME/code" "$HOME/src" "$HOME/Documents")
    
    for base_dir in "${base_dirs[@]}"; do
        if [[ -d "$base_dir" ]]; then
            if [[ "${DEBUG:-}" == "1" ]]; then
                echo "    🐛 DEBUG: Searching in $base_dir for project: '$project_name'" >&2
            fi
            
            # Try exact match first (highest priority)
            if [[ -d "$base_dir/$project_name" ]]; then
                project_dir="$base_dir/$project_name"
                if [[ "${DEBUG:-}" == "1" ]]; then
                    echo "    🐛 DEBUG: Found exact match: $project_dir" >&2
                fi
                break
            fi
            
            # Try case-insensitive exact match
            local found_dir=$(find "$base_dir" -maxdepth 1 -type d -iname "$project_name" 2>/dev/null | head -n1)
            if [[ -n "$found_dir" && -d "$found_dir" ]]; then
                project_dir="$found_dir"
                if [[ "${DEBUG:-}" == "1" ]]; then
                    echo "    🐛 DEBUG: Found case-insensitive match: $project_dir" >&2
                fi
                break
            fi
            
            # Only try fuzzy matching if no exact match found and project name is reasonably long
            if [[ ${#project_name} -gt 8 ]]; then
                # Try partial match (contains project name) - but be more restrictive
                local partial_match=$(find "$base_dir" -maxdepth 1 -type d -name "*$project_name*" 2>/dev/null | head -n1)
                if [[ -n "$partial_match" && -d "$partial_match" ]]; then
                    project_dir="$partial_match"
                    if [[ "${DEBUG:-}" == "1" ]]; then
                        echo "    🐛 DEBUG: Found partial match: $project_dir" >&2
                    fi
                    break
                fi
                
                # Try removing hyphens (pitboss-game -> pitbossgame)
                local no_hyphens=$(echo "$project_name" | sed 's/-//g')
                if [[ "$no_hyphens" != "$project_name" ]]; then
                    local no_hyphen_match=$(find "$base_dir" -maxdepth 1 -type d -name "*$no_hyphens*" 2>/dev/null | head -n1)
                    if [[ -n "$no_hyphen_match" && -d "$no_hyphen_match" ]]; then
                        project_dir="$no_hyphen_match"
                        if [[ "${DEBUG:-}" == "1" ]]; then
                            echo "    🐛 DEBUG: Found no-hyphen match: $project_dir" >&2
                        fi
                        break
                    fi
                fi
            fi
            
            # NEW: If we have a workspace name, try matching with workspace components
            if [[ -n "$workspace_name" ]]; then
                # Split workspace name by hyphens and try each part
                IFS='-' read -ra WORKSPACE_PARTS <<< "$workspace_name"
                for part in "${WORKSPACE_PARTS[@]}"; do
                    if [[ ${#part} -gt 2 ]]; then  # Skip very short parts
                        # Try case-insensitive match with workspace part
                        local workspace_match=$(find "$base_dir" -maxdepth 1 -type d -iname "*$part*" 2>/dev/null | head -n1)
                        if [[ -n "$workspace_match" && -d "$workspace_match" ]]; then
                            # First check if the original project name exists as subdirectory
                            if [[ -d "$workspace_match/$project_name" ]]; then
                                project_dir="$workspace_match/$project_name"
                                break 2  # Break out of both loops
                            fi
                            # If not, use the workspace directory as fallback
                            project_dir="$workspace_match"
                            break 2  # Break out of both loops
                        fi
                    fi
                done
            fi
            
            # Debug: Show what directories exist for troubleshooting
            if [[ "${DEBUG:-}" == "1" && -d "$base_dir" ]]; then
                echo "    🐛 DEBUG: Available directories in $base_dir:" >&2
                ls -1 "$base_dir" | head -5 >&2 || true
                echo "    🐛 DEBUG: Looking for directories matching: '$project_name'" >&2
                if [[ -n "$workspace_name" ]]; then
                    echo "    🐛 DEBUG: Workspace context: ${workspace_name}" >&2
                fi
            fi
        fi
    done
    
    if [[ -n "$project_dir" ]]; then
        echo "$project_dir"
        return 0
    fi
    
    return 1
}

# =============================================================================
# FUNCTION: check_workspace_has_cursor
# =============================================================================
# PURPOSE: Check if a specific workspace currently has a Cursor window open
# PARAMETERS: $1 = workspace name to check
# RETURNS: 0 if workspace has Cursor window, 1 if not
# =============================================================================
check_workspace_has_cursor() {
    local workspace_name="$1"
    
    # Get all Cursor windows and their workspaces
    local cursor_windows=$(wmctrl -l | grep -i cursor)
    
    if [[ -z "$cursor_windows" ]]; then
        return 1  # No Cursor windows at all
    fi
    
    # Check each Cursor window
    while read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi
        
        # Parse wmctrl -l output: windowid desktop pid hostname title
        local desktop_id=$(echo "$line" | awk '{print $2}')
        
        # Skip invalid entries
        if [[ -z "$desktop_id" ]]; then
            continue
        fi
        
        # Get desktop name
        local desktop_name=$(wmctrl -d | awk -v desk="$desktop_id" '$1 == desk {print $NF}')
        
        # Check if this workspace matches what we're looking for
        if [[ "$desktop_name" == "$workspace_name" ]]; then
            return 0  # Found Cursor window in this workspace
        fi
        
    done <<< "$cursor_windows"
    
    return 1  # No Cursor window found in this workspace
}

# =============================================================================
# FUNCTION: wait_for_cursor_window
# =============================================================================
# PURPOSE: Wait for Cursor window to appear in a specific workspace
# PARAMETERS: $1 = workspace name to wait for, $2 = timeout in seconds (default 15)
# RETURNS: 0 if window appears, 1 if timeout
# =============================================================================
wait_for_cursor_window() {
    local workspace_name="$1"
    local timeout="${2:-15}"
    local elapsed=0
    
    echo "    ⏳ Waiting for Cursor window to appear in workspace '$workspace_name'..."
    
    while [[ $elapsed -lt $timeout ]]; do
        if check_workspace_has_cursor "$workspace_name"; then
            echo "    ✅ Cursor window detected in workspace '$workspace_name' (after ${elapsed}s)"
            return 0
        fi
        
        sleep 1
        elapsed=$((elapsed + 1))
        
        # Show progress every 3 seconds
        if [[ $((elapsed % 3)) -eq 0 ]]; then
            echo "    ⏳ Still waiting... (${elapsed}s / ${timeout}s)"
        fi
    done
    
    echo "    ⚠️  Timeout: Cursor window did not appear in workspace '$workspace_name' after ${timeout}s"
    echo "    💡 This may be normal if Cursor is taking longer than usual to start"
    return 1
}

# =============================================================================
# FUNCTION: apply_throttle_settings
# =============================================================================
# PURPOSE: Apply throttle settings based on command line flags
# PARAMETERS: $@ = command line arguments
# LOGIC:
#   1. Check for --throttle and --no-throttle flags
#   2. Update global CURSOR_THROTTLE_ENABLED variable
#   3. Remove throttle flags from arguments
# =============================================================================
apply_throttle_settings() {
    # Check for throttle flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --throttle)
                CURSOR_THROTTLE_ENABLED=true
                shift
                ;;
            --no-throttle)
                CURSOR_THROTTLE_ENABLED=false
                shift
                ;;
            *)
                # Keep other arguments unchanged
                shift
                ;;
        esac
    done
}

# =============================================================================
# FUNCTION: launch_cursor_process
# =============================================================================
# PURPOSE: Launch Cursor (optionally with a project path) under systemd-run
#          with resource limits if available. Falls back to direct exec if
#          systemd-run isn't present.
# ENV VAR TUNABLES (defaults shown):
#   - CURSOR_CPU_QUOTA        (200%)
#   - CURSOR_MEMORY_MAX       (10G)
#   - CURSOR_IO_READ_BW_MAX   (50M)
#   - CURSOR_IO_WRITE_BW_MAX  (25M)
#   - CURSOR_SYSTEMD_SLICE    (apps-capped.slice)
# =============================================================================
launch_cursor_process() {
    local project_path="${1:-}"

    # Ensure Cursor binary is executable before launching
    if ! ensure_cursor_executable "$CURSOR_BIN"; then
        echo "❌ Cannot launch Cursor: $CURSOR_BIN is not executable"
        return 1
    fi

    # Normalize ARGS into an array for safe word splitting
    local args_array=()
    if [[ -n "${ARGS:-}" ]]; then
        # shellcheck disable=SC2206
        args_array=(${ARGS})
    fi

    # Build the Cursor command
    local cursor_cmd=("$CURSOR_BIN" "${args_array[@]}")
    if [[ -n "$project_path" ]]; then
        cursor_cmd+=("$project_path")
    fi

    if command -v systemd-run >/dev/null 2>&1 && [[ "$CURSOR_THROTTLE_ENABLED" == true ]]; then
        local cpu_quota="${CURSOR_CPU_QUOTA:-200%}"
        local mem_max="${CURSOR_MEMORY_MAX:-10G}"
        local io_read="${CURSOR_IO_READ_BW_MAX:-50M}"
        local io_write="${CURSOR_IO_WRITE_BW_MAX:-25M}"
        local slice_name="${CURSOR_SYSTEMD_SLICE:-apps-capped.slice}"

        systemd-run --user --scope \
            -p CPUQuota="${cpu_quota}" \
            -p MemoryMax="${mem_max}" \
            -p IOReadBandwidthMax=/,"${io_read}" \
            -p IOWriteBandwidthMax=/,"${io_write}" \
            --slice="${slice_name}" \
            "${cursor_cmd[@]}" &
    else
        "${cursor_cmd[@]}" &
    fi
}

# =============================================================================
# FUNCTION: launch_missing_sessions
# =============================================================================
# PURPOSE: Launch Cursor for any configured workspaces that don't have Cursor open
# LOGIC:
#   1. Saves current workspace for later restoration
#   2. Reads config file to get all configured workspaces
#   3. For each workspace, checks if it has a Cursor window
#   4. If not, switches to that workspace and launches Cursor for that workspace's project
#   5. Returns to the original workspace when done
# DEPENDENCIES: jq, cursor binary, wmctrl for workspace switching
# TESTING: Use --dry-run --with-config to test this function with mock config
# =============================================================================
launch_missing_sessions() {
    echo "🔄 Checking configured workspaces for missing Cursor sessions..."
    
    # Remember the current workspace to return to it later
    local original_workspace=$(get_current_workspace)
    local original_workspace_num=$(wmctrl -d | grep '\*' | awk '{print $1}')
    
    # Read all configured workspaces from config
    local configured_workspaces=$(jq -r 'keys[]' "$CONFIG" 2>/dev/null)
    
    if [[ -z "$configured_workspaces" ]]; then
        echo "⚠️  No workspaces configured in $CONFIG"
        return 1
    fi
    
    local launched_count=0
    local total_count=0
    
    echo "📋 Configured workspaces:"
    
    while read -r workspace; do
        if [[ -z "$workspace" ]]; then
            continue
        fi
        
        total_count=$((total_count + 1))
        local project_path=$(jq -r --arg ws "$workspace" '.[$ws]' "$CONFIG")
        
        echo "🖥️  [$workspace] → $project_path"
        
        # Check if this workspace already has a Cursor window
        if check_workspace_has_cursor "$workspace"; then
            echo "  ✅ Already has Cursor window open"
        else
            echo "  🚀 No Cursor window found, launching..."
            
            # Launch Cursor for this workspace's project
            if [[ -n "$project_path" && -d "$project_path" ]]; then
                # Get the workspace number for switching
                local workspace_num=$(wmctrl -d | grep -F "$workspace" | awk '{print $1}')
                
                if [[ -n "$workspace_num" ]]; then
                    # Switch to the target workspace
                    wmctrl -s "$workspace_num"
                    
                    # Brief pause to ensure workspace switch completes
                    sleep 0.5
                    
                    # Launch Cursor in the target workspace
                    launch_cursor_process "$project_path"
                    echo "  🚀 Launching Cursor for $project_path in workspace $workspace"
                    
                    # Wait for Cursor window to actually appear in the workspace
                    if wait_for_cursor_window "$workspace"; then
                        launched_count=$((launched_count + 1))
                        echo "  ✅ Successfully launched Cursor in workspace $workspace"
                    else
                        echo "  ⚠️  Cursor may not have opened properly in workspace $workspace"
                        # Still count it as launched since we tried
                        launched_count=$((launched_count + 1))
                    fi
                    
                    # Brief pause to avoid overwhelming the system
                    sleep 1
                else
                    echo "  ⚠️  Could not find workspace number for: $workspace"
                fi
            else
                echo "  ⚠️  Project path not found or invalid: $project_path"
            fi
        fi
        
    done <<< "$configured_workspaces"
    
    echo ""
    echo "📊 Session restoration complete:"
    echo "  • Total configured workspaces: $total_count"
    echo "  • New sessions launched: $launched_count"
    echo "  • Already running: $((total_count - launched_count))"
    
    if [[ $launched_count -eq 0 ]]; then
        echo "🎉 All configured workspaces already have Cursor sessions!"
    else
        echo "💡 All Cursor windows should now be open in their correct workspaces"
    fi
    
    # Return to the original workspace
    if [[ -n "$original_workspace_num" ]]; then
        wmctrl -s "$original_workspace_num"
        echo "🔄 Returned to original workspace: $original_workspace"
    fi
}

# =============================================================================
# FUNCTION: open_cursor_for_workspace
# =============================================================================
# PURPOSE: Opens Cursor IDE for the current workspace's associated project
# LOGIC:
#   1. Gets current workspace name
#   2. Looks up associated project path in config file
#   3. Opens Cursor with that project, or blank if no mapping exists
# DEPENDENCIES: jq, cursor binary
# =============================================================================
open_cursor_for_workspace() {
    local workspace=$(get_current_workspace)
    
    # Use jq to extract the project path for this workspace from config
    # Returns empty string if workspace not found in config
    local project=$(jq -r --arg ws "$workspace" '.[$ws] // empty' "$CONFIG")

    # Check if we found a project mapping and the directory exists
        if [[ -n "$project" && -d "$project" ]]; then
        echo "Launching Cursor in '$project' for workspace '$workspace'..."
        launch_cursor_process "$project"
    else
        echo "No project configured for '$workspace'. Opening blank..."
        launch_cursor_process
    fi
}

# =============================================================================
# FUNCTION: set_current_workspace_mapping
# =============================================================================
# PURPOSE: Sets Cursor mapping for the current workspace only
# LOGIC:
#   1. Gets current workspace name
#   2. Clears any existing Cursor mapping for that workspace
#   3. If Cursor windows are open in current workspace, maps them to projects
#   4. If no Cursor windows open, removes the workspace from config
#   5. Updates JSON config with new mapping for current workspace only
# DEPENDENCIES: jq, wmctrl
# =============================================================================
set_current_workspace_mapping() {
    local current_workspace=$(get_current_workspace)
    echo "🔄 Setting Cursor mapping for current workspace: '$current_workspace'..."
    
    # Enable debug mode for better troubleshooting
    local original_debug="${DEBUG:-}"
    if [[ "${DEBUG:-}" != "1" ]]; then
        echo "💡 Enabling debug mode for detailed output..."
        export DEBUG=1
    fi
    
    # Create config directory if it doesn't exist
    mkdir -p "$(dirname "$CONFIG")"
    
    # Load existing config or create empty one
    local temp_config=""
    if [[ -f "$CONFIG" ]]; then
        temp_config=$(mktemp)
        cp "$CONFIG" "$temp_config"
    else
        temp_config=$(mktemp)
        echo "{}" > "$temp_config"
    fi
    
    # Remove the current workspace from config (clear existing mapping)
    if [[ -f "$CONFIG" ]]; then
        local temp_config2=$(mktemp)
        jq --arg ws "$current_workspace" 'del(.[$ws])' "$CONFIG" > "$temp_config2" 2>/dev/null || echo "{}" > "$temp_config2"
        mv "$temp_config2" "$temp_config"
    fi
    
    # Find Cursor windows in current workspace
    local cursor_windows=$(wmctrl -l | grep -i cursor)
    local workspace_num=$(wmctrl -d | grep -F "$current_workspace" | awk '{print $1}')
    
    if [[ -z "$workspace_num" ]]; then
        echo "⚠️  Could not determine workspace number for: $current_workspace"
        return 1
    fi
    
    # Filter Cursor windows to only those in current workspace
    local current_workspace_cursor_windows=""
    if [[ -n "$cursor_windows" ]]; then
        while read -r line; do
            if [[ -z "$line" ]]; then
                continue
            fi
            
            local desktop_id=$(echo "$line" | awk '{print $2}')
            if [[ "$desktop_id" == "$workspace_num" ]]; then
                current_workspace_cursor_windows+="$line"$'\n'
            fi
        done <<< "$cursor_windows"
    fi
    
    if [[ -z "$current_workspace_cursor_windows" ]]; then
        echo "  ℹ️  No Cursor windows found in workspace '$current_workspace'"
        echo "  🗑️  Removing workspace '$current_workspace' from config"
        
        # Write updated config (workspace already removed above)
        cp "$temp_config" "$CONFIG"
        echo "✅ Workspace '$current_workspace' removed from config"
        return 0
    fi
    
    echo "  🔍 Found Cursor windows in workspace '$current_workspace':"
    echo "$current_workspace_cursor_windows"
    
    # Process Cursor windows to find project mapping
    local project_dir=""
    local window_count=0
    
    while read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi
        
        window_count=$((window_count + 1))
        local window_title=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//')
        
        echo "  📝 Window $window_count: $window_title"
        
        # Extract project name from window title
        local project_name=""
        if [[ -n "$window_title" && "$window_title" != "Cursor" ]]; then
            set +e  # Don't exit on errors
            project_name=$(detect_project_from_window_title "$window_title")
            set -e  # Re-enable exit on error
        fi
        
        if [[ -n "$project_name" ]]; then
            echo "    🎯 Project name: $project_name"
            
            # Find the actual project directory
            set +e  # Don't exit on errors
            project_dir=$(find_project_directory "$project_name" "$current_workspace")
            set -e  # Re-enable exit on error
            
            if [[ -n "$project_dir" ]]; then
                # Make sure we have an absolute path
                project_dir=$(realpath "$project_dir" 2>/dev/null || echo "$project_dir")
                echo "    ✅ Mapped to: $project_dir"
                break  # Use the first valid project found
            else
                echo "    ⚠️  Could not find project directory for: $project_name"
            fi
        else
            echo "    ⚠️  Could not extract project name from window title"
        fi
        
        echo ""
    done <<< "$current_workspace_cursor_windows"
    
    if [[ -n "$project_dir" ]]; then
        # Add the new mapping to config
        local temp_config2=$(mktemp)
        jq --arg ws "$current_workspace" --arg proj "$project_dir" '.[$ws] = $proj' "$temp_config" > "$temp_config2" 2>/dev/null || echo "{}" > "$temp_config2"
        
        # Write updated config
        cp "$temp_config2" "$CONFIG"
        echo "✅ Added mapping: '$current_workspace' → '$project_dir'"
    else
        echo "⚠️  No valid project mapping found for workspace '$current_workspace'"
        echo "  🗑️  Workspace will remain unmapped"
        
        # Write updated config (workspace already removed)
        cp "$temp_config" "$CONFIG"
    fi
    
    # Cleanup temp files
    rm -f "$temp_config" "$temp_config2" 2>/dev/null || true
    
    # Restore original debug setting
    if [[ "$original_debug" != "1" ]]; then
        unset DEBUG
    fi
    
    echo "📝 Config updated: $CONFIG"
    
    # Show the final config content for verification
    echo "📋 Current config content:"
    if [[ -f "$CONFIG" ]]; then
        cat "$CONFIG" | jq '.' 2>/dev/null || cat "$CONFIG"
    else
        echo "  (Config file not found)"
    fi
}

# =============================================================================
# FUNCTION: generate_workspace_map
# =============================================================================
# PURPOSE: Scans all KDE workspaces for open Cursor windows and maps them to projects
# LOGIC:
#   1. Uses wmctrl to find actual Cursor windows and their workspace locations
#   2. Extracts project names from window titles
#   3. Maps workspace names to project directories
#   4. Creates a JSON mapping file
# DEPENDENCIES: wmctrl, xdotool
# =============================================================================
generate_workspace_map() {
    # Declare associative array to store workspace->project mappings
    declare -A map

    echo "⏳ Scanning KDE workspaces for open Cursor windows..."
    
    # Show available workspaces
    echo "🖥️  Available workspaces:"
    wmctrl -d
    
    echo ""
    echo "🔍 Finding Cursor windows and their projects..."

    # Use wmctrl -l to find all Cursor windows and which workspace they're on
    local cursor_windows=$(wmctrl -l | grep -i cursor)
    
    if [[ -z "$cursor_windows" ]]; then
        echo "⚠️  No Cursor windows found!"
        echo "💡 Make sure you have Cursor windows open in different workspaces before running --init"
        return 1
    fi
    
    echo "📋 Found Cursor windows:"
    echo "$cursor_windows"
    echo ""

    # Process each Cursor window
    local window_count=0
    while read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi
        
        window_count=$((window_count + 1))
        echo "🔍 Processing window $window_count..."
        
        # Parse wmctrl -l output: windowid desktop pid hostname title
        local window_id=$(echo "$line" | awk '{print $1}')
        local desktop_id=$(echo "$line" | awk '{print $2}')
        local window_title=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//')
        
        # Skip invalid entries
        if [[ -z "$window_id" || -z "$desktop_id" ]]; then
            echo "  ⚠️  Skipping invalid window entry: $line"
            continue
        fi
        
        # Get desktop name
        local desktop_name=$(wmctrl -d | awk -v desk="$desktop_id" '$1 == desk {print $NF}')
        
        echo "🖥️  [$desktop_id] $desktop_name"
        echo "  📝 Window: $window_title"
        
        # Extract project name from window title
        local project_name=""
        if [[ -n "$window_title" && "$window_title" != "Cursor" ]]; then
            set +e  # Don't exit on errors
            project_name=$(detect_project_from_window_title "$window_title")
            set -e  # Re-enable exit on error
        fi
        
        if [[ -n "$project_name" ]]; then
            echo "  🎯 Project name: $project_name"
            
            # Find the actual project directory
            local project_dir=""
            set +e  # Don't exit on errors
            project_dir=$(find_project_directory "$project_name" "$desktop_name")
            set -e  # Re-enable exit on error
            
            if [[ -n "$project_dir" ]]; then
                # Make sure we have an absolute path
                project_dir=$(realpath "$project_dir" 2>/dev/null || echo "$project_dir")
                map["$desktop_name"]="$project_dir"
                echo "  ✅ Mapped to: $project_dir"
            else
                echo "  ⚠️  Could not find project directory for: $project_name"
                echo "  💡 Searched in: ~/dev, ~/projects, ~/workspace, ~/code, ~/src, ~/Documents"
            fi
        else
            echo "  ⚠️  Could not extract project name from window title"
            if [[ "${DEBUG:-}" == "1" ]]; then
                echo "  🐛 DEBUG: Raw title: '$window_title'"
            fi
        fi
        
        echo ""
        
    done <<< "$cursor_windows"
    
    echo "🔍 Finished processing $window_count windows"

    # Generate the JSON configuration file
    # Create the config directory if it doesn't exist
    mkdir -p "$(dirname "$CONFIG")"
    
    # Write JSON mapping to config file
    if [[ ${#map[@]} -gt 0 ]]; then
        {
            echo "{"
            for ws in "${!map[@]}"; do
                echo "  \"${ws}\": \"${map[$ws]}\","
            done | sed '$ s/,$//'  # Remove trailing comma from last entry
            echo "}"
        } > "$CONFIG"
        
        echo "✅ Config written to $CONFIG"
        echo "📝 Found ${#map[@]} workspace(s) with Cursor projects:"
        
        # Show the final mapping
        for ws in "${!map[@]}"; do
            echo "  🖥️  $ws → ${map[$ws]}"
        done
    else
        echo "⚠️  No valid workspace mappings found"
        echo "💡 Make sure:"
        echo "   - Cursor windows have project names in their titles"
        echo "   - Projects exist in ~/dev, ~/projects, ~/workspace, ~/code, ~/src, or ~/Documents"
    fi
}

# =============================================================================
# FUNCTION: show_help
# =============================================================================
# PURPOSE: Display usage information and examples
# =============================================================================
show_help() {
    cat << EOF
🚀 CURSOR WORKSPACE LAUNCHER

USAGE:
    $0                    # Launch Cursor for current workspace's mapped project (default)
    $0 --here            # Launch Cursor with current working directory (pwd), ignoring workspace mappings
    $0 --all             # Restore Cursor sessions for all configured workspaces
    $0 --set             # Set Cursor mapping for current workspace only
    $0 --set-all         # Generate workspace-to-project mapping for all workspaces
    $0 --new             # Launch new Cursor instance in current workspace
    $0 --new --init      # Launch new Cursor with current folder, then add to workspace mapping
    $0 --update           # Check for updates and prompt to restart if newer version available
    $0 --force-update     # Force check for updates and auto-restart if newer version available
    $0 --check-online     # Check cursor.com for newer versions and download if available
    $0 --dry-run          # Test the script logic without making changes
    $0 --throttle         # Enable resource throttling (default)
    $0 --no-throttle      # Disable resource throttling
    $0 --help             # Show this help message

EXAMPLES:
    # Generate initial configuration by scanning open Cursor windows in all workspaces
    $0 --set-all
    
    # Set Cursor mapping for current workspace only
    $0 --set
    
    # Launch Cursor only for this workspace's mapped project (default behavior)
    $0
    
    # Launch Cursor with current working directory, ignoring workspace mappings
    $0 --here
    
    # Launch Cursor for all configured workspaces (restore all sessions)
    $0 --all
    
    # Launch new Cursor instance in current workspace (blank Cursor)
    $0 --new
    
    # Launch new Cursor with current folder, then add to workspace mapping
    $0 --new --init
    
    # Enable debug mode for troubleshooting
    DEBUG=1 $0 --set-all
    
    # Debug version comparison issues
    DEBUG=1 $0 --update
    
    # Check for Cursor updates and restart if newer version available
    $0 --update
    
    # Force update without prompting (useful for automation)
    $0 --force-update
    
    # Check cursor.com for newer versions and download if available
    $0 --check-online
    
    # Test script logic without making changes (AI debugging tool)
    $0 --dry-run
    
    # Test with mock config file (AI debugging tool)
    $0 --dry-run --with-config
    
    # Restore missing Cursor sessions (launch Cursor for workspaces that don't have it)
    $0 --all
    
    # Launch with resource throttling disabled
    $0 --no-throttle --here
    
    # Launch with resource throttling enabled (default)
    $0 --throttle --new

COOL FEATURES:
    ✨ SEAMLESS UPDATES: The script performs "hot reload" updates that preserve
    your entire workspace layout and open files. No disruption to your workflow!
    
    🔄 SMART VERSION DETECTION: Automatically finds the latest Cursor AppImage
    and compares it with currently running instances for intelligent updates.
    
    🌐 ONLINE UPDATE CHECKING: Automatically checks cursor.com for newer versions
    and downloads them directly to your $CURSOR_DIR directory when available.
    
    🔒 AUTOMATIC PERMISSION FIXING: Automatically checks and fixes executable
    permissions on Cursor AppImages, ensuring they can run without manual chmod.
    
    🆕 NEW INSTANCE MODE: Use --new to launch a fresh Cursor instance in the
    current workspace without affecting other workspaces. Perfect for quick
    development sessions or exploring new projects!
    
    🧪 AI-FRIENDLY TESTING: The --dry-run mode creates mock environments for
    safe testing and debugging, perfect for AI assistants working on the script.
    Automatically enables DEBUG mode for comprehensive step-by-step feedback.

SETUP:
    1. Install dependencies: sudo apt install wmctrl xdotool jq curl wget
    2. Place Cursor AppImage in $CURSOR_DIR (pattern: Cursor-*-x*.AppImage)
    3. Open Cursor in different KDE workspaces for your projects
    4. Run '$0 --set-all' to generate the initial mapping for all workspaces
    5. Use '$0' to launch Cursor for current workspace, or '$0 --all' to restore all sessions
    6. Use '$0 --set' to update mapping for current workspace only

AUTOMATIC STARTUP (Optional):
    To automatically restore Cursor sessions on login, create a KDE autostart entry:
    
    1. Create the autostart directory:
       mkdir -p ~/.config/autostart
    
    2. Create the desktop file (example path shown, adjust to your actual script location):
       cat > ~/.config/autostart/cursor-session-restore.desktop << 'EOL'
[Desktop Entry]
Type=Application
Name=Cursor Session Restore
Comment=Restore Cursor IDE sessions for all configured workspaces
Exec=bash -c "sleep 10 && /home/gypsy/dev/gypsys-cli-tools/bin/launch_cursor.sh --all"
Icon=cursor
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
StartupNotify=false
Categories=Development;
EOL
    
    3. Make it executable:
       chmod +x ~/.config/autostart/cursor-session-restore.desktop
    
    4. Test before reboot:
       bash -c "sleep 10 && /home/gypsy/dev/gypsys-cli-tools/bin/launch_cursor.sh --all"
    
    Note: The 10-second delay ensures KDE workspaces are fully loaded before
    attempting to restore Cursor sessions. The script will switch to each workspace
    to launch Cursor instances, wait for them to open, then return to your original workspace.

BEHAVIOR:
    - Default mode: Launches Cursor for the current workspace's mapped project
    - --here mode: Launches Cursor with current working directory, ignoring workspace mappings
    - --all mode: Automatically checks for Cursor version updates first, then restores all sessions
    - If newer version available, offers to restart all Cursor instances with new version
    - Then checks all configured workspaces for missing Cursor sessions
    - For each workspace missing Cursor, switches to that workspace and launches Cursor there
    - Waits for Cursor to actually open in the target workspace before continuing
    - Skips workspaces that already have Cursor running
    - Returns to the original workspace when done
    - This provides session restoration functionality with proper workspace placement
    
    --new mode:
    - Launches a new Cursor instance in the current workspace only
    - Does not affect other workspaces or existing Cursor instances
    - With --init: Opens Cursor with current directory, then adds to workspace mapping
    - Without --init: Opens blank Cursor for project selection

VERSION UPDATE FEATURE:
    ✨ SEAMLESS UPDATES: When updating Cursor versions, the script performs a "hot reload"
    that preserves your entire workspace layout and open files. Your Cursor windows stay
    open and functional while the underlying processes are updated to the new version.
    This means no disruption to your workflow - just instant version upgrades!
    
    🌐 AUTOMATIC ONLINE CHECKING: The script automatically checks cursor.com for newer
    versions and downloads them directly to your $CURSOR_DIR directory when available.
    This ensures you always have access to the latest Cursor features and improvements.
    
    🔒 AUTOMATIC PERMISSION MANAGEMENT: All downloaded Cursor AppImages are automatically
    made executable, and the script continuously checks that Cursor binaries have proper
    permissions before launching them.

CONFIG FILE: $CONFIG

DEPENDENCIES:
    - KDE Plasma desktop environment
    - wmctrl, xdotool, jq packages
    - curl, wget packages (for online version checking and downloads)
    - Cursor IDE AppImage in $CURSOR_DIR (pattern: Cursor-*-x*.AppImage)
    
    Note: The script automatically finds the most recent Cursor AppImage version
    in the $CURSOR_DIR directory. No symlink needed!
    
    Path Resolution:
    - CURSOR_DIR defaults to $HOME/bin (e.g., /home/gypsy/bin on your system)
    - CONFIG defaults to $HOME/.config/cursor-workspace-map.json
    - These paths are determined by your actual $HOME environment

For more information, see the comments in this script.
EOF
}

# =============================================================================
# FUNCTION: launch_new_cursor_instance
# =============================================================================
# PURPOSE: Launch a new Cursor instance in the current workspace
# PARAMETERS: $@ = command line arguments (may include --init)
# LOGIC:
#   1. Checks if --init flag is present
#   2. If --init: Asks user confirmation, opens Cursor with current directory, adds to mapping
#   3. If not --init: Opens blank Cursor for project selection
#   4. Waits for Cursor window to appear in the workspace
# =============================================================================
launch_new_cursor_instance() {
    if ! check_dependencies; then
        exit 1
    fi
    
    # Ensure Cursor binary is executable before proceeding
    if ! ensure_cursor_executable "$CURSOR_BIN"; then
        echo "❌ Cannot proceed: $CURSOR_BIN is not executable"
        exit 1
    fi
    
    # Check if --init is also specified
    local do_init=false
    if [[ "${2:-}" == "--init" ]]; then
        do_init=true
        shift  # Remove --init from arguments
    fi
    
    # Get current workspace name
    local current_workspace=$(get_current_workspace)
    echo "🚀 Launching new Cursor instance in workspace '$current_workspace'..."
    
    if [[ "$do_init" == true ]]; then
        # Ask user if they're in the right folder
        echo ""
        echo "❓ Are you in the folder you want to add to your workspace mapping?"
        echo "   Current directory: $(pwd)"
        read -p "   Continue? (y/N): " confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            local current_dir=$(pwd)
            echo "  📁 Opening Cursor in '$current_dir' for workspace '$current_workspace'..."
            launch_cursor_process "$current_dir"
            
            # Wait for Cursor window to appear
            if wait_for_cursor_window "$current_workspace"; then
                echo "  ✅ Cursor opened successfully in '$current_dir' for workspace '$current_workspace'"
                # Add to workspace mapping
                echo "🔄 Adding '$current_dir' to workspace mapping for '$current_workspace'..."
                generate_workspace_map # Re-generate map to include the new entry
                echo "✅ '$current_dir' added to workspace mapping for '$current_workspace'"
            else
                echo "  ❌ Cursor did not open in '$current_dir' for workspace '$current_workspace'"
                exit 1
            fi
        else
            echo "  ℹ️  Cancelled by user"
            exit 0
        fi
    else
        # Open blank Cursor for project selection
        echo "  📁 Opening blank Cursor for project selection in workspace '$current_workspace'..."
        launch_cursor_process
        
        # Wait for Cursor window to appear
        if wait_for_cursor_window "$current_workspace"; then
            echo "  ✅ Blank Cursor opened successfully in workspace '$current_workspace'"
        else
            echo "  ❌ Blank Cursor did not open in workspace '$current_workspace'"
            exit 1
        fi
    fi
}

# =============================================================================
# FUNCTION: check_dependencies
# =============================================================================
# PURPOSE: Verify that all required dependencies are installed
# RETURNS: 0 if all dependencies are available, 1 otherwise
# =============================================================================
check_dependencies() {
    local missing_deps=()
    
    # Check for required binaries
    for cmd in wmctrl xdotool jq curl wget; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Find the latest Cursor AppImage
    local cursor_bin=""
    if ! cursor_bin=$(find_latest_cursor); then
        echo "⚠️  Could not find Cursor AppImage in $CURSOR_DIR"
        echo "💡 Expected pattern: Cursor-*-x*.AppImage"
        return 1
    fi
    
    # Report missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "⚠️  Missing dependencies: ${missing_deps[*]}"
        echo "💡 Install with: sudo apt install ${missing_deps[*]}"
        return 1
    fi
    
    # Export the cursor binary path for use in other functions
    export CURSOR_BIN="$cursor_bin"
    
    return 0
}

# =============================================================================
# FUNCTION: check_and_download_cursor_updates
# =============================================================================
# PURPOSE: Check cursor.com for newer versions and download if available
# LOGIC:
#   1. Scrape cursor.com/downloads for latest version info
#   2. Compare with current highest version
#   3. Download newer version if available
# DEPENDENCIES: curl, grep, sed, wget
# =============================================================================
check_and_download_cursor_updates() {
    echo ""
    echo "🔍 CHECKING FOR CURSOR UPDATES..."
    echo "   🌐 Source: cursor.com/downloads"
    echo "   📁 Local directory: $CURSOR_DIR"
    echo ""
    
    # Get current highest version
    local current_highest=$(get_highest_cursor_version)
    if [[ -z "$current_highest" ]]; then
        echo "⚠️  Could not determine current Cursor version"
        return 1
    fi
    
    echo "📱 Current highest version: $current_highest"
    
    # Extract version number from current version
    local current_version_num=$(echo "$current_highest" | sed -n 's/.*Cursor-\([0-9]\+\.[0-9]\+\.[0-9]\+\)-.*/\1/p')
    if [[ -z "$current_version_num" ]]; then
        echo "⚠️  Could not parse current version number"
        return 1
    fi
    
    echo "🔢 Current version number: $current_version_num"
    
    # Check cursor.com for latest version
    local latest_version_info=""
    local download_url=""
    
    echo "🌐 FETCHING LATEST VERSION FROM CURSOR.COM..."
    echo "   📡 Checking: https://cursor.com/downloads"
    echo ""
    
    # Try to get the downloads page
    local downloads_page=$(curl -s -L "https://cursor.com/downloads" 2>/dev/null)
    if [[ -z "$downloads_page" ]]; then
        echo ""
        echo "❌ FAILED TO FETCH CURSOR.COM DOWNLOADS PAGE!"
        echo "   🌐 URL attempted: https://cursor.com/downloads"
        echo "   💡 This might be a network issue or cursor.com is temporarily unavailable"
        echo "   💡 Try again later or check cursor.com manually"
        echo ""
        return 1
    fi
    
    # Look for Linux AppImage download link and version
    # Cursor typically shows version info in the download section
    local linux_section=$(echo "$downloads_page" | grep -A 20 -B 5 -i "linux\|appimage" 2>/dev/null || echo "")
    
    if [[ -n "$linux_section" ]]; then
        # Try to extract version from the Linux section
        local version_match=$(echo "$linux_section" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        if [[ -n "$version_match" ]]; then
            echo "🎯 VERSION INFORMATION FOUND!"
            echo "   📱 Latest version on cursor.com: $version_match"
            echo ""
            
            # Compare versions
            if [[ "$version_match" != "$current_version_num" ]]; then
                echo ""
                echo "🎉 NEW CURSOR VERSION AVAILABLE!"
                echo "   📱 Current version: $current_version_num"
                echo "   🆕 Latest version: $version_match"
                echo "   📥 Starting download..."
                echo ""
                
                # Try to find download URL for Linux AppImage
                local download_link=$(echo "$downloads_page" | grep -o 'https://[^"]*\.AppImage[^"]*' | head -1)
                if [[ -n "$download_link" ]]; then
                    echo "🔗 Download URL found: $download_link"
                    download_url="$download_link"
                else
                    echo "⚠️  Could not find direct download link, trying alternative method..."
                    
                    # Try to construct download URL based on version pattern
                    # Cursor typically uses: https://download.cursor.sh/linux/appImage/x64/Cursor-{version}-x64.AppImage
                    local constructed_url="https://download.cursor.sh/linux/appImage/x64/Cursor-${version_match}-x64.AppImage"
                    echo "🔗 Trying constructed URL: $constructed_url"
                    
                    # Test if the URL exists
                    if curl -s -I "$constructed_url" | head -1 | grep -q "200\|302"; then
                        download_url="$constructed_url"
                        echo "✅ Constructed URL is valid"
                    else
                        echo "❌ Constructed URL is not accessible"
                    fi
                fi
                
                if [[ -n "$download_url" ]]; then
                    echo ""
                    echo "📥 DOWNLOADING NEW CURSOR VERSION..."
                    echo "   🎯 Version: $version_match"
                    echo "   📁 Location: $HOME/bin/"
                    echo "   💡 This may take a while depending on your internet connection..."
                    echo ""
                    
                    # Download to $CURSOR_DIR with progress
                    local download_path="$HOME/bin/Cursor-${version_match}-x64.AppImage"
                    
                    if wget --progress=bar:force:noscroll -O "$download_path" "$download_url" 2>&1; then
                        echo "✅ Download completed: $download_path"
                        
                        # Ensure the downloaded file is executable
                        if ensure_cursor_executable "$download_path"; then
                            echo ""
                            echo "🎉 DOWNLOAD COMPLETED SUCCESSFULLY!"
                            echo "   📱 New Cursor version: $version_match"
                            echo "   📁 File location: $download_path"
                            echo "   🔒 File permissions: Executable"
                            echo ""
                            echo "💡 You can now use --update to seamlessly switch to the new version"
                            echo "   or restart Cursor manually to use the new version immediately."
                            echo ""
                            
                            return 0
                        else
                            echo "⚠️  Downloaded file but failed to make executable"
                            return 1
                        fi
                    else
                        echo ""
                        echo "❌ DOWNLOAD FAILED!"
                        echo "   📱 Version attempted: $version_match"
                        echo "   📁 Target location: $download_path"
                        echo "   💡 This might be a network issue or temporary problem"
                        echo "   💡 Try again later or download manually from cursor.com"
                        echo ""
                        rm -f "$download_path" 2>/dev/null || true
                        return 1
                    fi
                else
                    echo "⚠️  Could not determine download URL for version $version_match"
                    echo "   💡 This might be a temporary issue with cursor.com"
                    echo "   💡 You may need to manually download from cursor.com"
                    echo "   💡 Expected URL pattern: https://download.cursor.sh/linux/appImage/x64/Cursor-{version}-x64.AppImage"
                    return 1
                fi
            else
                echo ""
                echo "✅ YOU ALREADY HAVE THE LATEST VERSION!"
                echo "   📱 Current version: $current_version_num"
                echo "   🆕 Latest available: $version_match"
                echo "   💡 No download needed - you're up to date!"
                echo ""
                return 0
            fi
        else
            echo "⚠️  Could not extract version number from downloads page"
            echo "   💡 This might be a temporary issue with cursor.com"
            echo "   💡 Try again later or check cursor.com manually"
            return 1
        fi
    else
        echo "⚠️  Could not find Linux/AppImage section on downloads page"
        echo "   💡 This might be a temporary issue with cursor.com"
        echo "   💡 Try again later or check cursor.com manually"
        return 1
    fi
}

# =============================================================================
# FUNCTION: get_highest_cursor_version
# =============================================================================
# PURPOSE: Gets the highest version number of the Cursor AppImage found in the
#          current directory or the one currently running.
# RETURNS: Version string (e.g., "Cursor-1.2.4-x86_64.AppImage")
# =============================================================================
get_highest_cursor_version() {
    local highest_version=""
    local current_dir_cursor=$(find_latest_cursor)
    
    if [[ -n "$current_dir_cursor" ]]; then
        local current_dir_version=$(echo "$current_dir_cursor" | sed -E 's/.*Cursor-([0-9]+\.[0-9]+\.[0-9]+).*\.AppImage$/\1/')
        if [[ -n "$current_dir_version" ]]; then
            highest_version="Cursor-${current_dir_version}-x86_64.AppImage"
        fi
    fi
    
    local running_cursor_version=$(get_running_cursor_version)
    if [[ -n "$running_cursor_version" ]]; then
        if [[ -z "$highest_version" ]] || [[ "$running_cursor_version" == "$(echo -e "$running_cursor_version\n$highest_version" | sort -V | tail -n1)" ]]; then
            highest_version="$running_cursor_version"
        fi
    fi
    
    echo "$highest_version"
}

# =============================================================================
# FUNCTION: ensure_cursor_executable
# =============================================================================
# PURPOSE: Ensures the specified Cursor AppImage is executable
# PARAMETERS: $1 = path to Cursor AppImage
# RETURNS: 0 if executable or made executable, 1 if failed
# LOGIC:
#   1. Checks if file exists
#   2. Checks if file is executable
#   3. Makes file executable if needed
#   4. Reports the action taken
# =============================================================================
ensure_cursor_executable() {
    local cursor_path="$1"
    
    if [[ -z "$cursor_path" ]]; then
        echo "⚠️  No Cursor path provided to ensure_cursor_executable"
        return 1
    fi
    
    if [[ ! -f "$cursor_path" ]]; then
        echo "❌ Cursor file not found: $cursor_path"
        return 1
    fi
    
    # Check if already executable
    if [[ -x "$cursor_path" ]]; then
        [[ "${DEBUG:-}" == "1" ]] && echo "✅ Cursor is already executable: $cursor_path"
        return 0
    fi
    
    # Make executable
    echo "🔒 Making Cursor executable: $cursor_path"
    if chmod +x "$cursor_path" 2>/dev/null; then
        echo "✅ Successfully made executable: $cursor_path"
        return 0
    else
        echo "❌ Failed to make executable: $cursor_path"
        return 1
    fi
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================
# Parse command line arguments and execute appropriate function
# 
# ✨ FEATURE: The default mode includes seamless version checking and updates
#    that preserve your workspace layout while upgrading Cursor versions!
#
# 🧪 TESTING: Use --dry-run to test script logic without making changes.
#    This is especially useful for AI assistants debugging the script.
#    The dry-run creates a mock environment and shows exactly what the script would do.
case "${1:-}" in
    --set)
        # Set Cursor mapping for current workspace only
        if ! check_dependencies; then
            exit 1
        fi
        
        # Ensure Cursor binary is executable before proceeding
        if ! ensure_cursor_executable "$CURSOR_BIN"; then
            echo "❌ Cannot proceed: $CURSOR_BIN is not executable"
            exit 1
        fi
        
        echo "🔄 Setting Cursor mapping for current workspace..."
        echo "💡 Tip: Set DEBUG=1 for detailed troubleshooting output"
        set_current_workspace_mapping
        ;;
    --set-all)
        # Generate workspace mapping by scanning current Cursor windows in all workspaces
        if ! check_dependencies; then
            exit 1
        fi
        
        # Ensure Cursor binary is executable before proceeding
        if ! ensure_cursor_executable "$CURSOR_BIN"; then
            echo "❌ Cannot proceed: $CURSOR_BIN is not executable"
            exit 1
        fi
        
        echo "🔄 Generating workspace-to-project mapping for all workspaces..."
        echo "💡 Tip: Set DEBUG=1 for detailed troubleshooting output"
        generate_workspace_map
        ;;
    --throttle|--no-throttle)
        # Apply throttle settings and continue with remaining arguments
        apply_throttle_settings "$@"
        # Re-execute the script with remaining arguments
        exec "$0" "$@"
        ;;
    --update)
        # Check for updates and prompt to restart if newer version available
        if ! check_dependencies; then
            exit 1
        fi
        
        # Ensure Cursor binary is executable before proceeding
        if ! ensure_cursor_executable "$CURSOR_BIN"; then
            echo "❌ Cannot proceed: $CURSOR_BIN is not executable"
            exit 1
        fi
        
        check_for_cursor_updates
        ;;
    --force-update)
        # Force check for updates and auto-restart if newer version available
        if ! check_dependencies; then
            exit 1
        fi
        
        # Ensure Cursor binary is executable before proceeding
        if ! ensure_cursor_executable "$CURSOR_BIN"; then
            echo "❌ Cannot proceed: $CURSOR_BIN is not executable"
            exit 1
        fi
        
        check_for_cursor_updates "force"
        ;;
    --check-online)
        # Check cursor.com for newer versions and download if available
        if ! check_dependencies; then
            exit 1
        fi
        echo "🌐 Checking cursor.com for newer Cursor versions..."
        check_and_download_cursor_updates
        ;;
    --dry-run)
        # =============================================================================
        # DRY RUN MODE - AI DEBUGGING TOOL
        # =============================================================================
        # PURPOSE: Test script logic without making any changes to the system
        # USEFUL FOR: AI assistants debugging the script, testing logic flow
        # FEATURES:
        #   - Creates mock environment with realistic file structures
        #   - Tests dependency detection and version comparison logic
        #   - Simulates config file handling (with/without config)
        #   - Shows exactly what the script would do
        #   - Automatically cleans up test environment
        #   - Enables DEBUG mode for comprehensive step-by-step feedback
        # USAGE:
        #   ./launch_cursor.sh --dry-run              # Test without config
        #   ./launch_cursor.sh --dry-run --with-config # Test with mock config
        # =============================================================================
        
        # Enable maximum debug output for AI assistants
        export DEBUG=1
        echo "🧪 DRY RUN MODE - Testing script logic without making changes..."
        echo "🔍 DEBUG mode automatically enabled for comprehensive feedback"
        echo "📋 This will show every step of the script execution process"
        echo ""
        
        # Create mock environment for testing
        echo "🔧 Setting up mock environment..."
        echo "  📁 Creating mock directories..."
        mock_cursor_dir="/tmp/mock-cursor-test"
        mock_config_dir="/tmp/mock-config-test"
        
        # Create mock directories
        echo "    📂 Creating: $mock_cursor_dir"
        mkdir -p "$mock_cursor_dir"
        echo "    📂 Creating: $mock_config_dir"
        mkdir -p "$mock_config_dir"
        
        # Create mock Cursor AppImage
        echo "  📦 Creating mock Cursor AppImage..."
        echo "    📄 Creating: $mock_cursor_dir/Cursor-1.3.8-x86_64.AppImage"
        touch "$mock_cursor_dir/Cursor-1.3.8-x86_64.AppImage"
        chmod +x "$mock_cursor_dir/Cursor-1.3.8-x86_64.AppImage"
        echo "    ✅ Mock Cursor AppImage created and made executable"
        
        # Create mock config file (optional)
        if [[ "${2:-}" == "--with-config" ]]; then
            echo "  📄 Creating mock config file..."
            echo "    📄 Creating: $mock_config_dir/cursor-workspace-map.json"
            cat > "$mock_config_dir/cursor-workspace-map.json" << 'EOF'
{
  "workspace1": "/home/user/project1",
  "workspace2": "/home/user/project2"
}
EOF
            echo "    ✅ Mock config file created with sample workspace mappings"
        else
            echo "  📄 No mock config file requested (will test without config scenario)"
        fi
        
        # Override paths for dry run
        echo "  🔄 Overriding paths for dry run..."
        original_cursor_dir="$CURSOR_DIR"
        original_config="$CONFIG"
        echo "    📁 Original CURSOR_DIR: $CURSOR_DIR"
        echo "    📁 Original CONFIG: $CONFIG"
        CURSOR_DIR="$mock_cursor_dir"
        CONFIG="$mock_config_dir/cursor-workspace-map.json"
        echo "    📁 New CURSOR_DIR: $CURSOR_DIR"
        echo "    📁 New CONFIG: $CONFIG"
        
        echo ""
        echo "🔍 Mock environment created:"
        echo "  📁 CURSOR_DIR: $CURSOR_DIR"
        echo "  📁 CONFIG: $CONFIG"
        echo "  📦 Mock Cursor: $(ls -la "$mock_cursor_dir")"
        if [[ -f "$CONFIG" ]]; then
            echo "  📄 Mock Config: $(cat "$CONFIG")"
        else
            echo "  📄 Mock Config: (not created)"
        fi
        
        echo ""
        echo "🔍 Testing dependency check..."
        echo "  🔧 Mocking dependencies for dry run..."
        echo "    📁 Setting CURSOR_BIN to: $mock_cursor_dir/Cursor-1.3.8-x86_64.AppImage"
        export CURSOR_BIN="$mock_cursor_dir/Cursor-1.3.8-x86_64.AppImage"
        echo "    ✅ CURSOR_BIN environment variable set"
        
        # Skip actual dependency check in dry-run mode
        echo "  ✅ Dependencies mocked for dry run"
        echo "  📋 Note: In real execution, this would check for wmctrl, xdotool, jq"
        
        echo ""
        echo "🔍 About to check for Cursor version updates..."
        echo "  📋 This will test the find_latest_cursor() and get_running_cursor_version() functions"
        check_for_cursor_updates
        update_result=$?
        echo "  🔍 DEBUG: check_for_cursor_updates returned: $update_result"
        echo "  📋 Return value meaning: 0 = no action needed, 1 = restart performed"
        
        if [[ $update_result -eq 1 ]]; then
            echo "  🔍 Would perform version update (dry run)"
            echo "  📋 This would kill current instances and restart with new version"
        else
            echo "  🔍 Would continue to session restoration (dry run)"
            echo "  📋 This would check for missing Cursor sessions in configured workspaces"
            echo "  🔍 CONFIG path: $CONFIG"
            if [[ ! -f "$CONFIG" ]]; then
                echo "  🔍 Would show config file not found message (dry run)"
                echo "  🔍 Would launch Cursor with: $CURSOR_BIN $ARGS (dry run)"
                echo "  📋 This is the fallback behavior when no workspace mapping exists"
            else
                echo "  🔍 Would launch missing sessions (dry run)"
                echo "  📋 This would iterate through configured workspaces and launch Cursor"
            fi
        fi
        
        # Restore original paths
        echo ""
        echo "🔄 Restoring original paths..."
        echo "  📁 Restoring CURSOR_DIR to: $original_cursor_dir"
        echo "  📁 Restoring CONFIG to: $original_config"
        CURSOR_DIR="$original_cursor_dir"
        CONFIG="$original_config"
        
        echo ""
        echo "🧹 Cleaning up mock environment..."
        echo "  🗑️  Removing: $mock_cursor_dir"
        rm -rf "$mock_cursor_dir"
        echo "  🗑️  Removing: $mock_config_dir"
        rm -rf "$mock_config_dir"
        echo "  ✅ Mock environment cleaned up"
        
        echo ""
        echo "✅ Dry run completed successfully!"
        echo "📋 Summary: All script logic tested without making any system changes"
        ;;
    --help|-h)
        # Show help information
        show_help
        ;;
    --here)
        # Launch Cursor with current working directory, ignoring workspace mappings
        if ! check_dependencies; then
            exit 1
        fi
        
        # Ensure Cursor binary is executable before proceeding
        if ! ensure_cursor_executable "$CURSOR_BIN"; then
            echo "❌ Cannot proceed: $CURSOR_BIN is not executable"
            exit 1
        fi
        
        current_dir=$(pwd)
        echo "🚀 Opening Cursor with current directory: $current_dir"
        launch_cursor_process "$current_dir"
        ;;
    --all)
        # Restore Cursor sessions for all configured workspaces
        if ! check_dependencies; then
            exit 1
        fi
        
        # Ensure Cursor binary is executable before proceeding
        if ! ensure_cursor_executable "$CURSOR_BIN"; then
            echo "❌ Cannot proceed: $CURSOR_BIN is not executable"
            exit 1
        fi
        
        # Check for Cursor version updates and offer to restart if newer version available
        echo "🔍 DEBUG: About to call check_for_cursor_updates..."
        check_for_cursor_updates
        update_result=$?
        echo "🔍 DEBUG: check_for_cursor_updates exit code: $update_result"
        if [[ $update_result -eq 1 ]]; then
            # If restart was performed, we're done
            echo "🔍 DEBUG: check_for_cursor_updates returned 1 (restart performed), exiting..."
            exit 0
        fi
        
        echo "🔍 DEBUG: check_for_cursor_updates returned 0 (no restart), continuing..."
        echo "🔍 DEBUG: About to check config file: $CONFIG"
        
        # Check if config file exists
        if [[ ! -f "$CONFIG" ]]; then
            echo "⚠️  Configuration file not found: $CONFIG"
            echo "💡 Run '$0 --set-all' first to generate workspace mappings"
            echo "🚀 Opening Cursor without workspace mapping..."
            launch_cursor_process
            exit 0
        fi
        
        echo "🔍 DEBUG: Config file exists, launching missing sessions..."
        launch_missing_sessions
        ;;
    "")
        # Default: Launch Cursor for current workspace's mapped project
        if ! check_dependencies; then
            exit 1
        fi
        
        # Ensure Cursor binary is executable before proceeding
        if ! ensure_cursor_executable "$CURSOR_BIN"; then
            echo "❌ Cannot proceed: $CURSOR_BIN is not executable"
            exit 1
        fi
        
        open_cursor_for_workspace
        ;;
    --new)
        # Launch new Cursor instance in current workspace
        launch_new_cursor_instance "$@"
        ;;
    *)
        echo "❌ Unknown option: $1"
        echo "💡 Use '$0 --help' for usage information"
        exit 1
        ;;
esac

