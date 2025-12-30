#!/bin/bash

###############################################################################
# Find Space Wasters - Disk Space Analysis Tool
# 
# Purpose: Find large files and directories consuming disk space
# Author: Gypsy
# 
# Features:
# - Multiple analysis modes (largest files, directories, old files)
# - Uses best available tools (ncdu, du, find)
# - Excludes common irrelevant paths
# - Human-readable output
# - Can install ncdu if not present
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default options
TARGET_DIR="/"
TOP_N=20
MIN_SIZE="100M"
ANALYSIS_MODE="summary"
EXCLUDE_PATHS=(
    "/proc"
    "/sys"
    "/dev"
    "/run"
    "/tmp"
    "/var/lib/docker/overlay2"
)

# Display help
show_help() {
    cat << EOF
Find Space Wasters - Disk Space Analysis Tool

Usage: $(basename "$0") [OPTIONS] [DIRECTORY]

Options:
    -m, --mode MODE        Analysis mode (summary, files, dirs, old, all)
    -n, --top N           Show top N results (default: 20)
    -s, --size SIZE       Minimum file size (default: 100M)
                          Examples: 100M, 1G, 500K
    -i, --interactive     Launch ncdu (interactive tool) if available
    -g, --gui             Launch baobab (GUI tool) if available
    --install-ncdu        Install ncdu (best interactive terminal tool)
    -h, --help            Show this help message

Analysis Modes:
    summary              Quick overview of disk usage (default)
    files                Find largest files
    dirs                 Find largest directories
    old                  Find large old files (>1 year, >100M)
    all                  Run all analyses

Directory:
    Path to analyze (default: /)

Examples:
    $(basename "$0")                              # Quick summary of entire system
    $(basename "$0") -m files /home              # Find largest files in /home
    $(basename "$0") -m dirs -n 10 .             # Top 10 largest dirs in current path
    $(basename "$0") -m old /var                 # Find large old files in /var
    $(basename "$0") -i /home                    # Interactive analysis with ncdu
    $(basename "$0") --install-ncdu              # Install ncdu tool

Recommended Tools:
    - ncdu:    Best interactive terminal tool (apt install ncdu)
    - baobab:  Great GUI tool (apt install baobab) ✓ Installed
    - duf:     Modern disk usage overview (apt install duf)
    - dust:    Modern du alternative (cargo install du-dust)

EOF
}

# Print colored message
print_msg() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Print section header
print_header() {
    echo ""
    print_msg "$BLUE" "═══════════════════════════════════════════════════════════"
    print_msg "$CYAN" "$1"
    print_msg "$BLUE" "═══════════════════════════════════════════════════════════"
}

# Parse size to bytes for comparison
parse_size() {
    local size=$1
    echo "$size" | numfmt --from=iec 2>/dev/null || echo "$size"
}

# Build exclude arguments for find/du
build_excludes() {
    local excludes=""
    for path in "${EXCLUDE_PATHS[@]}"; do
        excludes="$excludes -path $path -prune -o"
    done
    echo "$excludes"
}

# Check if running as root (needed for full system scan)
check_permissions() {
    if [ "$TARGET_DIR" = "/" ] && [ "$EUID" -ne 0 ]; then
        print_msg "$YELLOW" "⚠️  Not running as root - some directories may be inaccessible"
        print_msg "$YELLOW" "   Run with sudo for complete system analysis"
        echo ""
    fi
}

# Install ncdu
install_ncdu() {
    print_msg "$CYAN" "Installing ncdu (NCurses Disk Usage)..."
    print_msg "$YELLOW" "This will install a package on your system."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo apt update && sudo apt install -y ncdu
        print_msg "$GREEN" "✓ ncdu installed successfully!"
        print_msg "$CYAN" "Try running: $(basename "$0") -i $TARGET_DIR"
    else
        print_msg "$RED" "Installation cancelled"
    fi
    exit 0
}

# Show disk usage summary
show_summary() {
    print_header "Disk Usage Summary"
    
    print_msg "$CYAN" "Filesystem Overview:"
    df -h --exclude-type=tmpfs --exclude-type=devtmpfs | grep -v "loop" || df -h
    
    print_header "Largest Mount Points"
    df -h --exclude-type=tmpfs --exclude-type=devtmpfs | tail -n +2 | sort -k5 -rh | head -10
    
    if [ -d "/var" ]; then
        print_header "Common Space Consumers"
        echo "Analyzing common directories... (this may take a moment)"
        
        check_dir() {
            local dir=$1
            if [ -d "$dir" ]; then
                local size=$(sudo du -sh "$dir" 2>/dev/null | cut -f1)
                printf "  %-30s %s\n" "$dir" "$size"
            fi
        }
        
        check_dir "/var/log"
        check_dir "/var/lib/docker"
        check_dir "/var/cache"
        check_dir "/var/tmp"
        check_dir "/home"
        check_dir "/usr"
        check_dir "/opt"
        check_dir "/tmp"
    fi
}

# Find largest files
find_largest_files() {
    print_header "Top $TOP_N Largest Files (≥$MIN_SIZE)"
    
    print_msg "$YELLOW" "Scanning $TARGET_DIR for large files..."
    echo ""
    
    # Build find command with excludes
    local find_cmd="find '$TARGET_DIR' -type f -size +$MIN_SIZE"
    for path in "${EXCLUDE_PATHS[@]}"; do
        find_cmd="$find_cmd -not -path '$path/*'"
    done
    find_cmd="$find_cmd -exec ls -lh {} \; 2>/dev/null | awk '{print \$5, \$9}' | sort -rh | head -$TOP_N"
    
    eval "$find_cmd" | nl -w2 -s'. ' | while IFS= read -r line; do
        echo "$line"
    done
    
    if [ $? -ne 0 ]; then
        print_msg "$RED" "Error scanning files. Try with sudo for full access."
    fi
}

# Find largest directories
find_largest_dirs() {
    print_header "Top $TOP_N Largest Directories in $TARGET_DIR"
    
    print_msg "$YELLOW" "Calculating directory sizes... (this may take a while)"
    echo ""
    
    # Use du with depth limit for better performance
    sudo du -h "$TARGET_DIR" --max-depth=3 2>/dev/null \
        | grep -v -E "(^/proc|^/sys|^/dev|^/run)" \
        | sort -rh \
        | head -$TOP_N \
        | nl -w2 -s'. '
}

# Find large old files
find_old_files() {
    print_header "Large Old Files (>1 year, ≥$MIN_SIZE)"
    
    print_msg "$YELLOW" "Scanning for old large files in $TARGET_DIR..."
    echo ""
    
    sudo find "$TARGET_DIR" -type f -size +$MIN_SIZE -mtime +365 \
        -not -path "*/proc/*" \
        -not -path "*/sys/*" \
        -not -path "*/dev/*" \
        -not -path "*/docker/overlay2/*" \
        -printf "%s %p\n" 2>/dev/null \
        | sort -rn \
        | head -$TOP_N \
        | while read size path; do
            human_size=$(numfmt --to=iec-i --suffix=B $size)
            printf "%3s. %-10s %s\n" "$(( ++count ))" "$human_size" "$path"
        done
}

# Launch interactive ncdu
launch_ncdu() {
    if command -v ncdu &> /dev/null; then
        print_msg "$GREEN" "Launching ncdu (interactive disk usage analyzer)..."
        print_msg "$CYAN" "Navigation: ↑↓ to move, → to enter, ← to go back, d to delete, q to quit"
        echo ""
        sleep 2
        sudo ncdu "$TARGET_DIR" --exclude /proc --exclude /sys --exclude /dev
    else
        print_msg "$RED" "ncdu is not installed."
        print_msg "$YELLOW" "Install it with: $(basename "$0") --install-ncdu"
        print_msg "$YELLOW" "Or manually: sudo apt install ncdu"
        exit 1
    fi
}

# Launch GUI tool
launch_gui() {
    if command -v baobab &> /dev/null; then
        print_msg "$GREEN" "Launching baobab (Disk Usage Analyzer)..."
        baobab "$TARGET_DIR" &
        print_msg "$GREEN" "✓ baobab launched in background"
    else
        print_msg "$RED" "baobab is not installed."
        print_msg "$YELLOW" "Install it with: sudo apt install baobab"
        exit 1
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--mode)
                ANALYSIS_MODE="$2"
                shift 2
                ;;
            -n|--top)
                TOP_N="$2"
                shift 2
                ;;
            -s|--size)
                MIN_SIZE="$2"
                shift 2
                ;;
            -i|--interactive)
                launch_ncdu
                exit 0
                ;;
            -g|--gui)
                launch_gui
                exit 0
                ;;
            --install-ncdu)
                install_ncdu
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                print_msg "$RED" "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                TARGET_DIR="$1"
                shift
                ;;
        esac
    done
}

# Main function
main() {
    parse_args "$@"
    
    print_msg "$BLUE" "╔═══════════════════════════════════════════════════════════╗"
    print_msg "$BLUE" "║         Find Space Wasters - Disk Analysis Tool          ║"
    print_msg "$BLUE" "╚═══════════════════════════════════════════════════════════╝"
    
    # Check if target directory exists
    if [ ! -d "$TARGET_DIR" ]; then
        print_msg "$RED" "Error: Directory does not exist: $TARGET_DIR"
        exit 1
    fi
    
    check_permissions
    
    # Run requested analysis
    case "$ANALYSIS_MODE" in
        summary)
            show_summary
            ;;
        files)
            find_largest_files
            ;;
        dirs)
            find_largest_dirs
            ;;
        old)
            find_old_files
            ;;
        all)
            show_summary
            find_largest_files
            find_largest_dirs
            find_old_files
            ;;
        *)
            print_msg "$RED" "Unknown analysis mode: $ANALYSIS_MODE"
            show_help
            exit 1
            ;;
    esac
    
    print_header "Recommendations"
    echo "  • Use -i flag for interactive analysis: $(basename "$0") -i $TARGET_DIR"
    echo "  • Use -g flag for GUI analysis: $(basename "$0") -g $TARGET_DIR"
    echo "  • Run with sudo for complete system access"
    echo "  • Check Docker: /var/lib/docker can consume lots of space"
    echo "  • Clean apt cache: sudo apt clean"
    echo "  • Clean old logs: sudo journalctl --vacuum-time=30d"
    echo "  • Clean old snaps: snap list --all | awk '/disabled/{print \$1, \$3}'"
    echo ""
}

# Run main function
main "$@"


