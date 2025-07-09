#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# CURSOR WORKSPACE LAUNCHER
# =============================================================================
# 
# PURPOSE:
#   This script manages Cursor IDE windows based on KDE Workspaces (virtual desktops).
#   It can either:
#   1. Launch Cursor for the current KDE workspace with the associated project
#   2. Generate a configuration mapping KDE workspaces to project directories
#
# DEPENDENCIES:
#   - KDE Plasma desktop environment
#   - wmctrl: Window management utility
#   - xdotool: X11 automation tool  
#   - jq: JSON processor
#
# INSTALLATION:
#   sudo apt install wmctrl xdotool jq
#
# USAGE:
#   ./launch_cursor.sh        # Launch Cursor for current workspace
#   ./launch_cursor.sh --init # Generate workspace-to-project mapping
#
# CONFIG FILE:
#   ~/.config/cursor-workspace-map.json
#   Format: {"workspace_name": "/path/to/project"}
#
# HOW IT WORKS:
#   --init mode:
#   1. Uses wmctrl to find all open Cursor windows and their workspace locations
#   2. Extracts project names from Cursor window titles
#   3. Maps project names to actual directories in ~/dev, ~/projects, etc.
#   4. Creates JSON config mapping workspace names to project paths
#
#   Launch mode:
#   1. Gets current workspace name using wmctrl
#   2. Looks up associated project in config file  
#   3. Launches Cursor with that project directory
#
# =============================================================================

# Configuration constants
CONFIG="$HOME/.config/cursor-workspace-map.json"  # Path to workspace mapping config
CURSOR_BIN="$HOME/bin/cursor"                     # Path to Cursor executable
ARGS="--no-sandbox"                               # Default Cursor launch arguments

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
    
    # Pattern 1: Handle dev containers first - "project-name [Dev Container...] - Cursor"
    if [[ "$title" =~ ^([^[]+)[[:space:]]*\[Dev[[:space:]]Container.*\][[:space:]]*-[[:space:]]*Cursor ]]; then
        project=$(echo "$title" | sed -E 's/^([^[]+)[[:space:]]*\[Dev[[:space:]]Container.*\][[:space:]]*-[[:space:]]*Cursor.*/\1/' | sed 's/[[:space:]]*$//')
    # Pattern 2: "filename - project-name - Cursor" (extract middle part of 3-part title)
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
            # Try exact match first
            if [[ -d "$base_dir/$project_name" ]]; then
                project_dir="$base_dir/$project_name"
                break
            fi
            
            # Try case-insensitive match
            local found_dir=$(find "$base_dir" -maxdepth 1 -type d -iname "$project_name" 2>/dev/null | head -n1)
            if [[ -n "$found_dir" && -d "$found_dir" ]]; then
                project_dir="$found_dir"
                break
            fi
            
            # Try partial match (contains project name)
            local partial_match=$(find "$base_dir" -maxdepth 1 -type d -name "*$project_name*" 2>/dev/null | head -n1)
            if [[ -n "$partial_match" && -d "$partial_match" ]]; then
                project_dir="$partial_match"
                break
            fi
            
            # Try removing hyphens (pitboss-game -> pitbossgame)
            local no_hyphens=$(echo "$project_name" | sed 's/-//g')
            if [[ "$no_hyphens" != "$project_name" ]]; then
                local no_hyphen_match=$(find "$base_dir" -maxdepth 1 -type d -name "*$no_hyphens*" 2>/dev/null | head -n1)
                if [[ -n "$no_hyphen_match" && -d "$no_hyphen_match" ]]; then
                    project_dir="$no_hyphen_match"
                    break
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
                echo "    🐛 DEBUG: Directories in $base_dir:" >&2
                ls -1 "$base_dir" | grep -i "$(echo "$project_name" | cut -d'-' -f1)" | head -3 >&2 || true
                if [[ -n "$workspace_name" ]]; then
                    echo "    🐛 DEBUG: Also checking workspace parts: ${workspace_name}" >&2
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
# FUNCTION: launch_missing_sessions
# =============================================================================
# PURPOSE: Launch Cursor for any configured workspaces that don't have Cursor open
# LOGIC:
#   1. Reads config file to get all configured workspaces
#   2. For each workspace, checks if it has a Cursor window
#   3. If not, launches Cursor for that workspace's project
# DEPENDENCIES: jq, cursor binary
# =============================================================================
launch_missing_sessions() {
    echo "🔄 Checking configured workspaces for missing Cursor sessions..."
    
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
                "$CURSOR_BIN" $ARGS "$project_path" &
                launched_count=$((launched_count + 1))
                echo "  ✅ Launched Cursor for $project_path"
                
                # Brief pause to avoid overwhelming the system
                sleep 1
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
        echo "💡 Tip: Wait a moment for all Cursor windows to fully load"
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
        "$CURSOR_BIN" $ARGS "$project" &
    else
        echo "No project configured for '$workspace'. Opening blank..."
        "$CURSOR_BIN" $ARGS &
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
    $0                    # Restore Cursor sessions for all configured workspaces
    $0 --init             # Generate workspace-to-project mapping
    $0 --help             # Show this help message

EXAMPLES:
    # Generate initial configuration by scanning open Cursor windows
    $0 --init
    
    # Enable debug mode for troubleshooting
    DEBUG=1 $0 --init
    
    # Restore missing Cursor sessions (launch Cursor for workspaces that don't have it)
    $0

SETUP:
    1. Install dependencies: sudo apt install wmctrl xdotool jq
    2. Open Cursor in different KDE workspaces for your projects
    3. Run '$0 --init' to generate the mapping
    4. Use '$0' to restore missing Cursor sessions across all workspaces

BEHAVIOR:
    - Default mode checks all configured workspaces
    - Launches Cursor for any workspace that doesn't currently have it open
    - Skips workspaces that already have Cursor running
    - This provides session restoration functionality

CONFIG FILE: $CONFIG

DEPENDENCIES:
    - KDE Plasma desktop environment
    - wmctrl, xdotool, jq packages
    - Cursor IDE installed at: $CURSOR_BIN

For more information, see the comments in this script.
EOF
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
    for cmd in wmctrl xdotool jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for Cursor binary
    if [[ ! -f "$CURSOR_BIN" ]]; then
        echo "⚠️  Cursor binary not found at: $CURSOR_BIN"
        echo "💡 Please install Cursor or update CURSOR_BIN variable in script"
        return 1
    fi
    
    # Report missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "⚠️  Missing dependencies: ${missing_deps[*]}"
        echo "💡 Install with: sudo apt install ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================
# Parse command line arguments and execute appropriate function
case "${1:-}" in
    --init)
        # Generate workspace mapping by scanning current Cursor windows
        if ! check_dependencies; then
            exit 1
        fi
        echo "🔄 Generating workspace-to-project mapping..."
        echo "💡 Tip: Set DEBUG=1 for detailed troubleshooting output"
        generate_workspace_map
        ;;
    --help|-h)
        # Show help information
        show_help
        ;;
    "")
        # Default: Launch missing Cursor sessions for all configured workspaces
        if ! check_dependencies; then
            exit 1
        fi
        
        # Check if config file exists
        if [[ ! -f "$CONFIG" ]]; then
            echo "⚠️  Configuration file not found: $CONFIG"
            echo "💡 Run '$0 --init' first to generate workspace mappings"
            echo "🚀 Opening Cursor without workspace mapping..."
            "$CURSOR_BIN" $ARGS &
            exit 0
        fi
        
        launch_missing_sessions
        ;;
    *)
        echo "❌ Unknown option: $1"
        echo "💡 Use '$0 --help' for usage information"
        exit 1
        ;;
esac

