# Cursor Git Extension Installation Guide

## The Problem You Were Having

Your extension wasn't installing into Cursor IDE properly because you were using the wrong installation method. Simply copying files to the extensions directory doesn't register the extension with Cursor's extension system.

## Correct Installation Methods

### Method 1: Development Installation (Recommended for Development)

Use the **development symlink approach** for active development:

```bash
./dev-install-extension.sh
```

This script:
- ✅ Creates a symlink in `~/.cursor/extensions/`
- ✅ Builds the extension properly
- ✅ Allows live development without reinstalling

**After running this script:**
1. Restart Cursor IDE completely
2. Open a git repository
3. Look for git status in the status bar
4. Check Extensions panel for "Cursor Git Extension"

### Method 2: VSIX Package Installation (Recommended for Distribution)

Use the **VSIX package approach** for proper installation:

```bash
./install-cursor-extension.sh
```

This script:
- ✅ Compiles TypeScript
- ✅ Creates a proper VSIX package
- ✅ Provides clear installation instructions

**Manual Installation Steps:**
1. Run the script to create the VSIX package
2. Open Cursor IDE
3. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
4. Type "Extensions: Install from VSIX"
5. Select the generated `.vsix` file
6. Restart Cursor

### Method 3: Command Line Installation

If Cursor's CLI works properly:

```bash
cursor --install-extension ./cursor-git-extension/cursor-git-extension-0.0.7.vsix
```

Or using VS Code CLI (which often works for Cursor):

```bash
code --install-extension ./cursor-git-extension/cursor-git-extension-0.0.7.vsix
```

## Development Workflow

For active development, use this workflow:

1. **Initial Setup:**
   ```bash
   ./dev-install-extension.sh
   ```

2. **Making Changes:**
   ```bash
   ./rebuild-extension.sh  # Quick rebuild
   # OR
   cd cursor-git-extension && npm run watch  # Continuous building
   ```

3. **Testing Changes:**
   - Press `Ctrl+R` (or `Cmd+R`) in Cursor to reload the window
   - Check status bar for git information
   - Test extension commands via `Ctrl+Shift+P`

## Verification Steps

### Check if Extension is Installed

1. **Via Extensions Panel:**
   - Open Extensions panel in Cursor
   - Search for "Cursor Git Extension"
   - Should show as installed

2. **Via Command Line:**
   ```bash
   code --list-extensions | grep cursor-git
   ```

3. **Via File System:**
   ```bash
   ls ~/.cursor/extensions/ | grep cursor-git
   ```

### Check if Extension is Active

1. **Status Bar:**
   - Should show git branch (🌿)
   - Should show modified files count (📝)
   - Should show commits ahead/behind (⬆️⬇️)

2. **Command Palette:**
   - Press `Ctrl+Shift+P`
   - Type "Cursor Git"
   - Should show extension commands

3. **Output Panel:**
   - Open Output panel
   - Select "Cursor Git Extension" from dropdown
   - Should show activation and status messages

## Troubleshooting

### Extension Not Showing Up

1. **Check Installation:**
   ```bash
   ls -la ~/.cursor/extensions/ | grep cursor-git
   ```

2. **Check Extension Registry:**
   ```bash
   grep -i "cursor-git" ~/.cursor/extensions/extensions.json
   ```

3. **Force Reinstall:**
   ```bash
   rm -rf ~/.cursor/extensions/*cursor-git*
   ./dev-install-extension.sh
   ```

### Extension Not Activating

1. **Check Activation Events:**
   - Extension activates on workspace ready
   - Make sure you have a folder/workspace open

2. **Check for Errors:**
   - Open Output panel
   - Look for "Cursor Git Extension" channel
   - Check for error messages

3. **Force Activation:**
   - Press `Ctrl+Shift+P`
   - Run "Cursor Git: Show Git Status"

### Git Script Not Running

1. **Check Script Path:**
   - Default: `/home/gypsy/dev/gypsys-cli-tools/cursor/cursor-git-setup.sh`
   - Verify file exists and is executable

2. **Check Script Permissions:**
   ```bash
   chmod +x /home/gypsy/dev/gypsys-cli-tools/cursor/cursor-git-setup.sh
   ```

3. **Test Script Manually:**
   ```bash
   /home/gypsy/dev/gypsys-cli-tools/cursor/cursor-git-setup.sh
   ```

## File Structure

After proper installation, you should have:

```
~/.cursor/extensions/
├── gypsy-dev.cursor-git-extension-0.0.7/  # Symlink to your dev directory
│   ├── package.json
│   ├── out/
│   │   └── extension.js
│   └── src/
│       └── extension.ts
```

## Why Your Previous Method Didn't Work

❌ **Wrong:** Copying files directly to extensions directory
- Cursor doesn't know about the extension
- Extension system doesn't register it
- No activation occurs

✅ **Right:** Using proper installation methods
- Extension is registered with Cursor
- Activation events work properly
- Commands and features are available

## Summary

Your extension is now properly installed using the development symlink method. The key was using the correct installation approach that registers the extension with Cursor's extension system, rather than just copying files to the extensions directory.

For future development:
1. Use `./rebuild-extension.sh` for quick rebuilds
2. Use `Ctrl+R` to reload Cursor window after changes
3. Check the Output panel for debugging information
4. Use `npm run watch` for continuous development 