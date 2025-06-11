# Cursor IDE Git Integration Tools

This directory contains tools for managing Git repositories and AI best practices within Cursor IDE. The tools are designed to be automatically run when Cursor starts up, ensuring consistent repository management and best practices across all projects.

## Project Structure

```
~/dev/gypsys-cli-tools/
├── bin/
│   └── check-repos.sh      # Repository audit script
├── cursor/
│   ├── cursor-git-setup.sh # Git initialization and health check script
│   ├── settings.json       # Cursor IDE settings
│   └── cursor-git-extension/ # Custom VSCode/Cursor extension
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

### cursor-git-extension (Custom Extension)
A custom VSCode/Cursor extension that:
- Shows Git status and submodule health in a notification and status bar
- Can be installed manually using the VSIX file

## Usage

The tools are designed to run automatically with Cursor IDE. No manual intervention is required unless:
1. A new repository needs to be initialized
2. Repository health issues are detected
3. Submodule updates require manual intervention

## Installing the Custom Extension

1. **Build the VSIX (if not already built):**
   ```bash
   cd ~/dev/gypsys-cli-tools/cursor/cursor-git-extension
   npm install
   npm run compile
   npx vsce package
   ```
   This will create a file like `cursor-git-extension-0.0.1.vsix`.

2. **Install the extension using the CLI:**
   ```bash
   code --install-extension /home/gypsy/dev/gypsys-cli-tools/cursor/cursor-git-extension/cursor-git-extension-0.0.1.vsix
   ```
   Or, if using Cursor and it supports the CLI:
   ```bash
   cursor --install-extension /home/gypsy/dev/gypsys-cli-tools/cursor/cursor-git-extension/cursor-git-extension-0.0.1.vsix
   ```

3. **Alternatively, install using the GUI:**
   - Open Cursor/VSCode
   - Press `Ctrl+Shift+P` and select `Extensions: Install from VSIX...`
   - Select the `.vsix` file

4. **Restart Cursor/VSCode**
   - After installation, restart the IDE to activate the extension.

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