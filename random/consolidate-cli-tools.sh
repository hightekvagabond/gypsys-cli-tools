#!/bin/bash

# CLI Repository Consolidation Tool
# 
# This script consolidates multiple individual CLI tool repositories into a single
# unified repository for better maintenance and organization. It:
#
# - Uses git subtree to merge repositories while preserving essential history
# - Adds deprecation notices to old repositories explaining the move
# - Archives old repositories (doesn't delete them) to be a good open source citizen
# - Creates a comprehensive README for the consolidated repository
# - Handles both 'main' and 'master' branch scenarios automatically
#
# Prerequisites:
# - Git (required)
# - GitHub CLI 'gh' (optional, for automatic repository archiving)
#
# Usage: ./consolidate-cli-tools.sh
# The script will prompt for your GitHub username and repository names interactively.

set -e  # Exit on any error

# Configuration
CONSOLIDATED_REPO="gypsys-cli-tools"  # Change this to your consolidated repo name
GITHUB_USERNAME="hightekvagabond"  # Will be prompted for

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command_exists git; then
        print_error "Git is not installed"
        exit 1
    fi
    
    if ! command_exists gh; then
        print_warning "GitHub CLI (gh) is not installed. You'll need to handle GitHub operations manually."
        USE_GH_CLI=false
    else
        USE_GH_CLI=true
    fi
}

# Get user input
get_user_input() {
    echo
    read -p "Enter your GitHub username: " GITHUB_USERNAME
    
    if [ -z "$GITHUB_USERNAME" ]; then
        print_error "GitHub username is required"
        exit 1
    fi
    
    echo
    echo "Enter the names of your CLI tool repositories (one per line, empty line to finish):"
    TOOL_REPOS=()
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            break
        fi
        TOOL_REPOS+=("$line")
    done
    
    if [ ${#TOOL_REPOS[@]} -eq 0 ]; then
        print_error "No repositories specified"
        exit 1
    fi
    
    echo
    print_status "Will consolidate these repositories:"
    for repo in "${TOOL_REPOS[@]}"; do
        echo "  - $repo"
    done
    
    echo
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Aborted by user"
        exit 0
    fi
}

# Clone or update the consolidated repository
setup_consolidated_repo() {
    print_status "Setting up consolidated repository..."
    
    if [ -d "$CONSOLIDATED_REPO" ]; then
        print_warning "Directory $CONSOLIDATED_REPO already exists"
        read -p "Remove and re-clone? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$CONSOLIDATED_REPO"
        else
            cd "$CONSOLIDATED_REPO"
            git pull origin main || git pull origin master
            return
        fi
    fi
    
    git clone "https://github.com/$GITHUB_USERNAME/$CONSOLIDATED_REPO.git"
    cd "$CONSOLIDATED_REPO"
}

# Add each tool as a subtree
consolidate_tools() {
    print_status "Consolidating CLI tools..."
    
    for repo in "${TOOL_REPOS[@]}"; do
        print_status "Adding $repo..."
        
        # Add as subtree with squashed history
        git subtree add --prefix="$repo" "https://github.com/$GITHUB_USERNAME/$repo.git" main --squash 2>/dev/null || \
        git subtree add --prefix="$repo" "https://github.com/$GITHUB_USERNAME/$repo.git" master --squash
        
        print_success "Added $repo to consolidated repository"
    done
    
    # Push changes
    print_status "Pushing consolidated repository..."
    git push origin main || git push origin master
    print_success "Consolidated repository updated"
}

# Create deprecation notice for old repositories
create_deprecation_notice() {
    local repo_name=$1
    cat > README.md << EOF
# ⚠️ REPOSITORY MOVED

This repository has been consolidated into [$CONSOLIDATED_REPO](https://github.com/$GITHUB_USERNAME/$CONSOLIDATED_REPO).

## New Location
- **New Repository**: https://github.com/$GITHUB_USERNAME/$CONSOLIDATED_REPO
- **Tool Location**: https://github.com/$GITHUB_USERNAME/$CONSOLIDATED_REPO/tree/main/$repo_name

## Why the move?
This tool has been moved to a consolidated repository to:
- Simplify maintenance
- Provide better organization
- Reduce repository sprawl

## What should you do?
1. Update any bookmarks or links to point to the new location
2. If you've cloned this repository, clone the new one instead
3. Update any scripts or documentation that reference this repository

## Installation
Please refer to the main repository for installation instructions:
https://github.com/$GITHUB_USERNAME/$CONSOLIDATED_REPO

---
*This repository will be archived to preserve any existing links, but all future development will happen in the consolidated repository.*
EOF
}

# Handle old repositories
handle_old_repositories() {
    print_status "Handling old repositories..."
    
    cd ..
    
    for repo in "${TOOL_REPOS[@]}"; do
        print_status "Processing old repository: $repo"
        
        # Clone the old repo if not already present
        if [ ! -d "$repo-old" ]; then
            git clone "https://github.com/$GITHUB_USERNAME/$repo.git" "$repo-old"
        fi
        
        cd "$repo-old"
        
        # Create deprecation notice
        create_deprecation_notice "$repo"
        
        # Commit the deprecation notice
        git add README.md
        git commit -m "Repository moved to $CONSOLIDATED_REPO

This repository has been consolidated into $CONSOLIDATED_REPO.
See the new location at: https://github.com/$GITHUB_USERNAME/$CONSOLIDATED_REPO/tree/main/$repo"
        
        # Push the changes
        git push origin main 2>/dev/null || git push origin master
        
        print_success "Added deprecation notice to $repo"
        
        # Archive the repository if GitHub CLI is available
        if [ "$USE_GH_CLI" = true ]; then
            print_status "Archiving repository $repo..."
            gh repo archive "$GITHUB_USERNAME/$repo" --yes
            print_success "Archived repository $repo"
        else
            print_warning "Please manually archive the repository $repo on GitHub:"
            print_warning "  1. Go to https://github.com/$GITHUB_USERNAME/$repo/settings"
            print_warning "  2. Scroll to 'Danger Zone'"
            print_warning "  3. Click 'Archive this repository'"
        fi
        
        cd ..
    done
}

# Create a summary README for the consolidated repo
create_consolidated_readme() {
    print_status "Creating consolidated README..."
    
    cd "$CONSOLIDATED_REPO"
    
    # Extract a nice title from the repo name (convert dashes to spaces, title case)
    REPO_TITLE=$(echo "$CONSOLIDATED_REPO" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')
    
    cat > README.md << EOF
# $REPO_TITLE

A collection of CLI tools consolidated into a single repository for easier maintenance.

## Tools Included

EOF
    
    for repo in "${TOOL_REPOS[@]}"; do
        if [ -f "$repo/README.md" ]; then
            # Extract the first line (title) from the tool's README
            TOOL_TITLE=$(head -n 1 "$repo/README.md" | sed 's/^# *//')
            echo "- **[$repo](./$repo/)** - $TOOL_TITLE" >> README.md
        else
            echo "- **[$repo](./$repo/)** - CLI tool" >> README.md
        fi
    done
    
    cat >> README.md << EOF

## Installation

Each tool can be used independently. Navigate to the specific tool directory for installation and usage instructions.

## Contributing

These are personal tools, but feel free to fork and adapt them for your own use.

## License

Each tool may have its own license. Check the individual tool directories for specific licensing information.
EOF
    
    git add README.md
    git commit -m "Add consolidated README"
    git push origin main || git push origin master
    
    print_success "Created consolidated README"
}

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary directories..."
    for repo in "${TOOL_REPOS[@]}"; do
        if [ -d "../$repo-old" ]; then
            rm -rf "../$repo-old"
        fi
    done
}

# Main execution
main() {
    echo "=== CLI Tools Consolidation Script ==="
    echo
    
    check_prerequisites
    get_user_input
    setup_consolidated_repo
    consolidate_tools
    create_consolidated_readme
    handle_old_repositories
    cleanup
    
    echo
    print_success "Consolidation complete!"
    echo
    print_status "Summary:"
    print_status "✅ Consolidated ${#TOOL_REPOS[@]} repositories into $CONSOLIDATED_REPO"
    print_status "✅ Added deprecation notices to old repositories"
    if [ "$USE_GH_CLI" = true ]; then
        print_status "✅ Archived old repositories"
    else
        print_warning "⚠️  Please manually archive the old repositories on GitHub"
    fi
    print_status "✅ Created consolidated README"
    echo
    print_status "New repository: https://github.com/$GITHUB_USERNAME/$CONSOLIDATED_REPO"
}

# Run main function
main "$@"
