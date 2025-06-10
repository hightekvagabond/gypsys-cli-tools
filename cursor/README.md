# Cursor IDE Git Integration Tools

This directory contains tools for managing Git repositories and AI best practices within Cursor IDE. The tools are designed to be automatically run when Cursor starts up, ensuring consistent repository management and best practices across all projects.

## Project Structure

```
~/dev/gypsys-cli-tools/
├── bin/
│   └── check-repos.sh      # Repository audit script
├── cursor/
│   ├── cursor-git-setup.sh # Git initialization and health check script
│   └── settings.json       # Cursor IDE settings
└── README.md
```

## Components

### cursor-git-setup.sh
This script is automatically run by Cursor IDE when:
- Opening a new window
- Opening a folder
- Opening a project

It performs the following functions:
1. Validates Git repository status
2. Initializes new repositories if needed
3. Checks repository health
4. Manages ai-best-practices submodule
5. Provides detailed logging and warnings

### settings.json
Cursor IDE configuration file that:
- Enables automatic script execution
- Configures when scripts should run
- Points to the correct script locations

### check-repos.sh
A comprehensive audit script that:
- Scans directories for Git repositories
- Validates repository health
- Manages submodules
- Provides detailed reporting

## Usage

The tools are designed to run automatically with Cursor IDE. No manual intervention is required unless:
1. A new repository needs to be initialized
2. Repository health issues are detected
3. Submodule updates require manual intervention

## Configuration

Key configuration variables in `cursor-git-setup.sh`:
- `SUBMODULE_REPO_URL`: URL for the ai-best-practices repository
- `SUBMODULE_NAME`: Name of the submodule directory
- `GIT_HOSTS_CONFIG`: Configuration for Git hosts and organizations

## Logging

The script supports multiple verbosity levels:
- 0: Quiet (errors only)
- 1: Warnings and errors (default)
- 2: Info, warnings, and errors
- 3: Debug, info, warnings, and errors

Set the `DEBUG_LEVEL` environment variable to control verbosity. 