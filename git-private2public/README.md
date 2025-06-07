# Git Private to Public Repository Converter

This directory contains a script to convert a private repository to public by squashing all git history into a single commit and optionally changing repository visibility.

## Overview

The `git-private2public.sh` script performs the following operations:

1. **Safety Backup**: Creates a complete backup of your repository in `/tmp/`
2. **History Squashing**: Squashes all git commits into a single "Initial public release" commit
3. **Branch Cleanup**: Replaces the main branch with the clean history
4. **Force Push**: Updates the remote repository with the new clean history
5. **Visibility Change**: Optionally converts the repository from private to public using GitHub CLI

## Usage

```bash
# Navigate to your git repository root
cd /path/to/your/repository

# Run the script
/path/to/gypsys-cli-tools/git-private2public/git-private2public.sh
```

Or if you have the script in your PATH:

```bash
git-private2public.sh
```

## Requirements

- Must be run from the root of a git repository
- Git must be installed and configured
- Repository must have a remote origin configured
- For automatic visibility conversion: [GitHub CLI](https://cli.github.com/) must be installed and authenticated

## ⚠️ Important Warnings

**This script makes irreversible changes to your git history!**

- All commit history will be lost and replaced with a single commit
- The script creates a backup in `/tmp/repo-backup-<repo-name>-<date>`
- The force push will overwrite the remote repository history
- All contributors' commit history will be removed

## What the Script Does

1. **Validation**: Checks if you're in a git repository root
2. **Backup**: Creates a full backup at `/tmp/repo-backup-<repo-name>-<YYYY-MM-DD>`
3. **Clean Branch**: Creates an orphan branch with no parent commits
4. **Stage & Commit**: Stages all current files and creates a single commit
5. **Branch Swap**: Deletes old main branch and renames clean branch to main
6. **Push**: Force pushes the new history to origin
7. **Visibility**: Attempts to convert repository to public (if GitHub CLI available)

## GitHub CLI Setup

To enable automatic repository visibility conversion:

```bash
# Install GitHub CLI (Ubuntu/Debian)
sudo apt install gh

# Or using snap
sudo snap install gh

# Authenticate
gh auth login
```

## Example Output

```
Repository: my-awesome-project
Creating backup at: /tmp/repo-backup-my-awesome-project-2024-01-15
Backup created successfully!
Creating clean orphan branch...
Staging all files...
Creating initial commit...
Removing old main branch...
Renaming clean branch to main...
Force pushing new history...
Converting repository to public...
✅ Repository converted to public successfully!

🎉 Script completed! Your repository history has been squashed and pushed.
📁 Backup available at: /tmp/repo-backup-my-awesome-project-2024-01-15
```

## Troubleshooting

- **"Not in git repository"**: Navigate to your repository root directory
- **GitHub CLI errors**: Ensure you're authenticated with `gh auth login`
- **Push failures**: Check your git remote configuration and permissions
- **Backup failures**: Ensure you have write permissions to `/tmp/`

## Restoration

If you need to restore your original repository:

1. Navigate to your repository
2. Remove the current contents: `rm -rf .git * .*` (be careful!)
3. Copy back from backup: `cp -R /tmp/repo-backup-<repo-name>-<date>/* .`
4. Copy back git directory: `cp -R /tmp/repo-backup-<repo-name>-<date>/.git .`

## License

This script is part of the gypsys-cli-tools collection. 