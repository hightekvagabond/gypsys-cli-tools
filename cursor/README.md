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

## Node.js Environment Setup (Required)

This project follows **ai-best-practices for Node.js CLI development**, which requires proper Node.js version management using nvm (Node Version Manager):

### Quick Setup
```bash
# 1. Set up Node.js environment (installs nvm + Node 20.18.1)
npm run setup-node

# 2. Set up git integration
npm run setup

# 3. Build and install the extension
npm run rebuild-extension
```

### Manual Setup
```bash
# Install nvm (Node Version Manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc

# Use project's Node.js version from .nvmrc
nvm install 20.18.1
nvm use 20.18.1

# Install dependencies and rebuild extension
npm install
npm run rebuild-extension
```

### Node.js Virtual Environment Equivalent

This project uses **nvm** (Node Version Manager) as the equivalent to Python's virtual environments:

| Python Virtual Env | Node.js (nvm + npm) | Purpose |
|-------------------|---------------------|---------|
| `python -m venv venv` | `nvm install 20.18.1 && nvm use` | Environment isolation |
| `source venv/bin/activate` | `nvm use` | Activate environment |
| `requirements.txt` | `package.json` + `.nvmrc` | Dependency specification |
| `pip install -r requirements.txt` | `npm install` | Install dependencies |

## Usage

The tools are designed to run automatically with Cursor IDE. No manual intervention is required unless:
1. A new repository needs to be initialized
2. Repository health issues are detected
3. Submodule updates require manual intervention
4. Node.js environment needs to be set up (run `npm run setup-node` first)

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

# Cursor Git Extension & Setup Tools

A comprehensive git repository management extension for Cursor IDE with configurable notifications and automated submodule management.

## Features

### 🎯 Configurable Display Types
Choose exactly where different message types appear:
- **Status Bar**: Shows git status and quick info
- **Popup**: Modal dialogs for important messages
- **Notification**: Non-intrusive corner notifications
- **Output Channel**: Detailed logs in the output panel
- **None**: Silent (only logged for debugging)

### 🔧 User-Configurable Settings
- **Display Mappings**: Configure where INFO, WARN, ERROR, DEBUG, and OK messages are shown
- **Submodule Management**: Define which submodules to track and keep updated
- **Script Path**: Customize the path to your git setup script
- **Auto-run**: Control whether the script runs automatically on startup
- **Auto-refresh**: Set git status refresh intervals

### 📋 Available Commands
- `Cursor Git: Show Git Status` - Display detailed git status
- `Cursor Git: Run Git Setup Script` - Manually run the git setup automation
- `Cursor Git: Open Extension Settings` - Access configuration options
- `Cursor Git: Test Display Types` - Preview how different message types appear

## Configuration

### Extension Settings

Access via: `Cmd/Ctrl + ,` → Search for "Cursor Git Extension"

#### Display Mappings
```json
{
  "cursor-git-extension.displayMappings": {
    "INFO": "notification",
    "WARN": "popup", 
    "ERROR": "popup",
    "DEBUG": "output",
    "OK": "status"
  }
}
```

#### Submodule Management
```json
{
  "cursor-git-extension.submodules": [
    "ai-best-practices",
    "shared-utilities", 
    "common-configs"
  ]
}
```

#### Other Settings
```json
{
  "cursor-git-extension.scriptPath": "/path/to/your/cursor-git-setup.sh",
  "cursor-git-extension.showOnStartup": true,
  "cursor-git-extension.autoRefreshInterval": 30
}
```

## Display Type Options

| Type | Description | Best For |
|------|-------------|----------|
| `status` | Status bar indicator | Quick, persistent info |
| `popup` | Modal dialog | Critical messages requiring attention |
| `notification` | Corner notification | Non-disruptive info |
| `output` | Output channel log | Debugging and detailed logs |
| `none` | No display | Silent operation |

## Usage Examples

### Conservative Setup (Minimal Disruption)
```json
{
  "cursor-git-extension.displayMappings": {
    "INFO": "output",
    "WARN": "notification",
    "ERROR": "popup", 
    "DEBUG": "none",
    "OK": "status"
  }
}
```

### Developer Setup (Full Visibility)
```json
{
  "cursor-git-extension.displayMappings": {
    "INFO": "notification",
    "WARN": "popup",
    "ERROR": "popup",
    "DEBUG": "output", 
    "OK": "notification"
  }
}
```

### Status-Only Setup (Ultra Quiet)
```json
{
  "cursor-git-extension.displayMappings": {
    "INFO": "status",
    "WARN": "status",
    "ERROR": "status",
    "DEBUG": "none",
    "OK": "status"
  }
}
```

## Git Setup Script Features

The `cursor-git-setup.sh` script provides:

- **Repository Health Checks**: Detects uncommitted changes, untracked files, unpushed commits
- **Submodule Management**: Automatically adds and updates configured submodules
- **SSH Recommendations**: Suggests switching from HTTPS to SSH for your repositories
- **Configurable Logging**: Different verbosity levels (ERROR, WARN, INFO, DEBUG)
- **Extension Integration**: Reads submodule configuration from extension settings

### Environment Variables

The extension passes configuration to the script via:
- `CURSOR_EXT_SUBMODULES`: Comma-separated list of submodules to manage
- `DEBUG_LEVEL`: Logging verbosity (0=quiet, 1=errors/warnings, 2=info, 3=debug)

## Installation

### Extension Installation
```bash
# Install the packaged extension
code --install-extension cursor-git-extension-0.0.2.vsix
```

### Script Setup
1. Place `cursor-git-setup.sh` in your desired location
2. Update the extension settings with the correct path
3. Make the script executable: `chmod +x cursor-git-setup.sh`

## Troubleshooting

### Extension Not Running
- Check if Cursor recognizes the extension: `Developer: Reload Window`
- Verify script path in settings points to an executable file
- Check the Output Channel: "Cursor Git Setup" for detailed logs

### Script Errors
- Ensure git is installed and accessible
- Verify SSH keys are set up for private repositories
- Check network connectivity for submodule operations

### Submodule Issues
- Ensure submodule URLs are accessible
- Verify SSH keys have proper permissions
- Check that submodule names match repository names

## Contributing

This extension is part of the [gypsys-cli-tools](https://github.com/Imagination-Guild-LLC/gypsys-cli-tools) project.

### Development Setup
```bash
# Clone the repository
git clone https://github.com/Imagination-Guild-LLC/gypsys-cli-tools.git
cd gypsys-cli-tools/cursor

# Install dependencies
cd cursor-git-extension && npm install

# Compile and package
npm run compile
npm run package
```

## License

MIT License - See LICENSE file for details. 