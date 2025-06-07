#!/bin/bash

# Script to squash git history and prepare repository for public release

set -e  # Exit on any error

# Check if we're in a git repository root
if [ ! -d ".git" ]; then
    echo "Error: This script must be run from the root of a git repository."
    echo "Current directory: $(pwd)"
    echo "Please navigate to your git repository root and try again."
    exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo "⚠️  Warning: You have uncommitted changes!"
    echo "Please commit or stash your changes before running this script."
    exit 1
fi

# Check if remote origin exists
if ! git remote get-url origin &>/dev/null; then
    echo "Error: No remote 'origin' found. Please add a remote origin first."
    exit 1
fi

# Get current branch name (don't assume it's 'main')
CURRENT_BRANCH=$(git branch --show-current)

# Get the repository/directory name
REPO_NAME=$(basename "$(pwd)")
DATE=$(date +%F-%H%M%S)  # Include time to avoid conflicts
BACKUP_PATH="/tmp/repo-backup-${REPO_NAME}-${DATE}"

echo "Repository: ${REPO_NAME}"
echo "Current branch: ${CURRENT_BRANCH}"
echo "⚠️  WARNING: This will PERMANENTLY DELETE ALL GIT HISTORY!"
echo "📁 Backup will be created at: ${BACKUP_PATH}"
echo ""
read -p "Are you absolutely sure you want to continue? (type 'YES' to confirm): " confirmation

if [ "$confirmation" != "YES" ]; then
    echo "Operation cancelled."
    exit 0
fi

# Create complete backup including .git directory
echo "Creating complete backup..."
cp -a . "${BACKUP_PATH}"  # -a preserves all attributes and follows symlinks
echo "✅ Backup created successfully!"

# 1) create a brand‑new orphan branch with no parents
echo "Creating clean orphan branch..."
git checkout --orphan clean-main

# 2) stage everything exactly as it is now
echo "Staging all files..."
git add -A

# 3) one fresh commit
echo "Creating initial commit..."
git commit -m "Initial public release"

# 4) delete the old main (or master) branch label
echo "Removing old main branch..."
git branch -D main           # replace 'main' if your default is 'master'

# 5) rename the clean branch to main
echo "Renaming clean branch to main..."
git branch -m main

# 6) force‑push the new single‑commit history
echo "Force pushing new history..."
git push --force --set-upstream origin main

# 7) Convert repository from private to public (requires GitHub CLI)
echo ""
echo "Converting repository to public..."
if command -v gh &> /dev/null; then
    if gh repo edit --visibility public; then
        echo "✅ Repository converted to public successfully!"
    else
        echo "❌ Failed to convert repository to public. You may need to do this manually."
        echo "Manual URL: https://github.com/settings/repositories"
    fi
else
    echo "⚠️  GitHub CLI (gh) not found. Please install it or manually convert the repository to public."
    echo "You can install GitHub CLI from: https://cli.github.com/"
    echo "Manual conversion: Go to your repository settings on GitHub"
fi

echo ""
echo "🎉 Script completed! Your repository history has been squashed and pushed."
echo "📁 Backup available at: ${BACKUP_PATH}"
