#!/bin/bash

###############################################################################
# Docker Cleanup Script
# 
# Purpose: Clean up Docker artifacts to free up disk space
# Author: Gypsy
# 
# Features:
# - Dry-run mode to preview what will be cleaned
# - Removes stopped containers, dangling images, unused volumes, networks
# - Shows space savings statistics
# - Safe defaults with confirmation prompts
# - Aggressive mode for thorough cleanup
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
DRY_RUN=false
INTERACTIVE=true
AGGRESSIVE=false
VERBOSE=false

# Display help
show_help() {
    cat << EOF
Docker Cleanup Script - Free up disk space by removing Docker artifacts

Usage: $(basename "$0") [OPTIONS]

Options:
    -d, --dry-run       Show what would be removed without actually removing it
    -y, --yes          Skip confirmation prompts (non-interactive mode)
    -a, --aggressive   Remove all unused images (not just dangling ones)
    -v, --verbose      Show detailed output
    -h, --help         Show this help message

Cleanup Actions:
    1. Stopped containers
    2. Dangling images (untagged)
    3. Unused volumes (not attached to any container)
    4. Unused networks
    5. Build cache
    6. With --aggressive: ALL unused images (even tagged ones)

Examples:
    $(basename "$0") --dry-run              # Preview what would be cleaned
    $(basename "$0") --yes                  # Clean up without prompts
    $(basename "$0") --aggressive --yes     # Thorough cleanup without prompts
    $(basename "$0") --verbose              # Show detailed information

Safety Notes:
    - Named volumes are preserved unless unused
    - Running containers are never affected
    - Images in use by containers are preserved (unless --aggressive)
    - Dry-run mode is safe to use anytime

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                INTERACTIVE=false
                shift
                ;;
            -a|--aggressive)
                AGGRESSIVE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

# Print colored message
print_msg() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Check if Docker is installed and running
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_msg "$RED" "Error: Docker is not installed"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        print_msg "$RED" "Error: Docker daemon is not running or you don't have permission"
        print_msg "$YELLOW" "Try: sudo usermod -aG docker $USER"
        exit 1
    fi
}

# Get disk usage before cleanup
get_disk_usage() {
    docker system df
}

# Show what will be cleaned
show_cleanup_preview() {
    print_msg "$BLUE" "\n=== Cleanup Preview ==="
    
    # Stopped containers
    local stopped_containers=$(docker ps -aq -f status=exited 2>/dev/null | wc -l)
    print_msg "$YELLOW" "Stopped containers: $stopped_containers"
    
    # Dangling images
    local dangling_images=$(docker images -qf dangling=true 2>/dev/null | wc -l)
    print_msg "$YELLOW" "Dangling images: $dangling_images"
    
    if [ "$AGGRESSIVE" = true ]; then
        # All unused images
        local unused_images=$(docker images -q 2>/dev/null | wc -l)
        print_msg "$YELLOW" "Total images (will remove unused): $unused_images"
    fi
    
    # Unused volumes
    local unused_volumes=$(docker volume ls -qf dangling=true 2>/dev/null | wc -l)
    print_msg "$YELLOW" "Unused volumes: $unused_volumes"
    
    # Unused networks
    local networks=$(docker network ls --filter "type=custom" --format "{{.ID}}" 2>/dev/null | wc -l)
    print_msg "$YELLOW" "Custom networks: $networks"
    
    echo ""
}

# Clean stopped containers
clean_containers() {
    print_msg "$BLUE" "\n>>> Cleaning stopped containers..."
    
    if [ "$DRY_RUN" = true ]; then
        docker ps -a --filter "status=exited" --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}"
    else
        local removed=$(docker container prune -f 2>&1 | grep -oP 'Total reclaimed space: \K.*' || echo "0B")
        print_msg "$GREEN" "Removed stopped containers. Space reclaimed: $removed"
    fi
}

# Clean dangling images
clean_dangling_images() {
    print_msg "$BLUE" "\n>>> Cleaning dangling images..."
    
    if [ "$DRY_RUN" = true ]; then
        docker images --filter "dangling=true" --format "table {{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}"
    else
        local removed=$(docker image prune -f 2>&1 | grep -oP 'Total reclaimed space: \K.*' || echo "0B")
        print_msg "$GREEN" "Removed dangling images. Space reclaimed: $removed"
    fi
}

# Clean all unused images (aggressive)
clean_all_images() {
    print_msg "$BLUE" "\n>>> Cleaning ALL unused images (aggressive mode)..."
    
    if [ "$DRY_RUN" = true ]; then
        docker images --format "table {{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}"
    else
        local removed=$(docker image prune -a -f 2>&1 | grep -oP 'Total reclaimed space: \K.*' || echo "0B")
        print_msg "$GREEN" "Removed unused images. Space reclaimed: $removed"
    fi
}

# Clean unused volumes
clean_volumes() {
    print_msg "$BLUE" "\n>>> Cleaning unused volumes..."
    
    if [ "$DRY_RUN" = true ]; then
        docker volume ls --filter "dangling=true" --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}"
    else
        local removed=$(docker volume prune -f 2>&1 | grep -oP 'Total reclaimed space: \K.*' || echo "0B")
        print_msg "$GREEN" "Removed unused volumes. Space reclaimed: $removed"
    fi
}

# Clean unused networks
clean_networks() {
    print_msg "$BLUE" "\n>>> Cleaning unused networks..."
    
    if [ "$DRY_RUN" = true ]; then
        docker network ls --filter "type=custom" --format "table {{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}"
    else
        docker network prune -f &> /dev/null || true
        print_msg "$GREEN" "Removed unused networks"
    fi
}

# Clean build cache
clean_build_cache() {
    print_msg "$BLUE" "\n>>> Cleaning build cache..."
    
    if [ "$DRY_RUN" = true ]; then
        docker buildx du 2>/dev/null || docker system df | grep "Build Cache"
    else
        local removed=$(docker builder prune -f 2>&1 | grep -oP 'Total reclaimed space: \K.*' || echo "0B")
        print_msg "$GREEN" "Removed build cache. Space reclaimed: $removed"
    fi
}

# Confirm action
confirm_action() {
    if [ "$INTERACTIVE" = false ]; then
        return 0
    fi
    
    local message="$1"
    print_msg "$YELLOW" "\n$message"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_msg "$RED" "Cleanup cancelled by user"
        exit 0
    fi
}

# Main cleanup function
main() {
    parse_args "$@"
    
    print_msg "$BLUE" "=== Docker Cleanup Script ==="
    
    # Check prerequisites
    check_docker
    
    # Show current disk usage
    if [ "$VERBOSE" = true ]; then
        print_msg "$BLUE" "\n=== Current Docker Disk Usage ==="
        get_disk_usage
    fi
    
    # Show preview
    show_cleanup_preview
    
    # Confirm if not in non-interactive mode
    if [ "$DRY_RUN" = false ]; then
        local mode_text="standard"
        [ "$AGGRESSIVE" = true ] && mode_text="AGGRESSIVE"
        confirm_action "Ready to perform $mode_text cleanup."
    else
        print_msg "$YELLOW" "\n=== DRY RUN MODE - No changes will be made ===\n"
    fi
    
    # Perform cleanup
    clean_containers
    clean_dangling_images
    
    if [ "$AGGRESSIVE" = true ]; then
        clean_all_images
    fi
    
    clean_volumes
    clean_networks
    clean_build_cache
    
    # Show final disk usage
    if [ "$DRY_RUN" = false ]; then
        print_msg "$BLUE" "\n=== Docker Disk Usage After Cleanup ==="
        get_disk_usage
        print_msg "$GREEN" "\n✓ Cleanup complete!"
    else
        print_msg "$YELLOW" "\n=== Dry run complete - no changes made ==="
        print_msg "$YELLOW" "Run without --dry-run to perform actual cleanup"
    fi
}

# Run main function
main "$@"

