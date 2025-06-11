#!/bin/bash

# Development Extension Installation Script
# Creates a symlink for easier development without requiring packaging each time

set -e

# Configuration
EXTENSION_NAME="cursor-git-extension"
EXTENSION_DIR="$(pwd)/cursor-git-extension"
CURSOR_EXTENSIONS_DIR="$HOME/.cursor/extensions"
EXTENSION_LINK="$CURSOR_EXTENSIONS_DIR/gypsy-dev.cursor-git-extension-0.0.7"

# Function to display status
show_status() {
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║            Development Extension Installation                  ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║ Extension: $EXTENSION_NAME"
    echo "║ Time: $(date)"
    echo "║ Source: $EXTENSION_DIR"
    echo "║ Target: $EXTENSION_LINK"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo
}

show_status

# Check if extension directory exists
if [ ! -d "$EXTENSION_DIR" ]; then
    echo "❌ Error: Extension directory '$EXTENSION_DIR' not found!"
    exit 1
fi

# Create extensions directory if it doesn't exist
mkdir -p "$CURSOR_EXTENSIONS_DIR"

# Remove existing link/directory if it exists
if [ -L "$EXTENSION_LINK" ] || [ -d "$EXTENSION_LINK" ]; then
    echo "🧹 Removing existing extension installation..."
    rm -rf "$EXTENSION_LINK"
fi

# Build the extension
echo "🔨 Building extension..."
cd "$EXTENSION_DIR"

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Compile TypeScript
echo "⚙️  Compiling TypeScript..."
npm run compile

# Create symlink
echo "🔗 Creating development symlink..."
ln -s "$EXTENSION_DIR" "$EXTENSION_LINK"

# Verify the installation
if [ -L "$EXTENSION_LINK" ] && [ -f "$EXTENSION_LINK/out/extension.js" ]; then
    echo "✅ Development extension installed successfully!"
    echo
    echo "📋 Development workflow:"
    echo "- Edit source files in: $EXTENSION_DIR"
    echo "- Run 'npm run compile' to rebuild"
    echo "- Reload Cursor window (Ctrl+R) to test changes"
    echo "- Extension is linked from: $EXTENSION_LINK"
    echo
    echo "🔧 Development commands:"
    echo "- Build: cd $EXTENSION_DIR && npm run compile"
    echo "- Watch: cd $EXTENSION_DIR && npm run watch"
    echo "- Package: cd $EXTENSION_DIR && npm run package"
    echo
    echo "🎯 Next steps:"
    echo "1. Restart Cursor IDE completely"
    echo "2. Open a git repository"
    echo "3. Check for 'Cursor Git Extension' in Extensions panel"
    echo "4. Look for git status in status bar"
else
    echo "❌ Error: Development extension installation failed!"
    exit 1
fi 