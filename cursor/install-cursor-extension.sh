#!/bin/bash

# Cursor Extension Installation Script
# This script properly installs the extension using VSIX packaging

set -e

# Configuration
EXTENSION_NAME="cursor-git-extension"
EXTENSION_DIR="./cursor-git-extension"
VSIX_FILE="cursor-git-extension-0.0.7.vsix"

# Function to display status
show_status() {
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║               Cursor Extension Installation                    ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║ Extension: $EXTENSION_NAME"
    echo "║ Time: $(date)"
    echo "║ Directory: $PWD"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo
}

show_status

# Check if extension directory exists
if [ ! -d "$EXTENSION_DIR" ]; then
    echo "❌ Error: Extension directory '$EXTENSION_DIR' not found!"
    exit 1
fi

# Navigate to extension directory
cd "$EXTENSION_DIR"

echo "🔨 Building extension..."

# Install dependencies
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Compile TypeScript
echo "⚙️  Compiling TypeScript..."
npm run compile

# Package the extension
echo "📦 Packaging extension..."
npx vsce package --out "$VSIX_FILE"

# Check if VSIX was created
if [ ! -f "$VSIX_FILE" ]; then
    echo "❌ Error: Failed to create VSIX package!"
    exit 1
fi

echo "✅ Extension packaged successfully: $VSIX_FILE"
echo
echo "🎯 Installation Methods:"
echo "----------------------------------------"
echo "METHOD 1: Manual Installation (Recommended)"
echo "1. Open Cursor IDE"
echo "2. Press Ctrl+Shift+P (or Cmd+Shift+P on Mac)"
echo "3. Type 'Extensions: Install from VSIX'"
echo "4. Select this file: $(pwd)/$VSIX_FILE"
echo
echo "METHOD 2: Command Line (if cursor CLI works)"
echo "cursor --install-extension $(pwd)/$VSIX_FILE"
echo
echo "METHOD 3: VS Code CLI (alternative)"
echo "code --install-extension $(pwd)/$VSIX_FILE"
echo
echo "📋 After installation:"
echo "- Restart Cursor IDE"
echo "- Open a git repository"
echo "- Check the status bar for git status"
echo "- Use Ctrl+Shift+P -> 'Cursor Git' commands"
echo
echo "🔍 Troubleshooting:"
echo "- Check Cursor's extension panel for the extension"
echo "- Look for 'Cursor Git Extension' in installed extensions"
echo "- Check the Output panel for any error messages"
echo
echo "Extension ready for installation!" 