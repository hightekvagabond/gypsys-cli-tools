#!/bin/bash

# Debug output
echo "install-cursor-extension.sh started at $(date)" >> /tmp/cursor-extension-install.log
echo "Script path: $0" >> /tmp/cursor-extension-install.log
echo "Current directory: $PWD" >> /tmp/cursor-extension-install.log

# Configuration
EXTENSION_ID="cursor-git-extension"
CURSOR_EXTENSIONS_DIR="$HOME/.cursor/extensions"

# Function to display status message
show_status_message() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║             Cursor Extension Installation Status            ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║ Script started at: $(date)                                 ║"
    echo "║ Current directory: $PWD                                    ║"
    echo "║ Extension ID: $EXTENSION_ID                                ║"
    echo "║ Extensions Directory: $CURSOR_EXTENSIONS_DIR               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
}

# Show status message
show_status_message

# Create extensions directory if it doesn't exist
mkdir -p "$CURSOR_EXTENSIONS_DIR"

# Create the extension directory
EXTENSION_DIR="$CURSOR_EXTENSIONS_DIR/$EXTENSION_ID"
mkdir -p "$EXTENSION_DIR"

# Copy our extension files
echo "Installing extension..."
cp -r cursor-git-extension/* "$EXTENSION_DIR/"

# Install dependencies and build the extension
echo "Building extension..."
cd "$EXTENSION_DIR"
npm install
npm run compile

# Verify installation
if [ -d "$EXTENSION_DIR" ] && [ -f "$EXTENSION_DIR/out/extension.js" ]; then
    echo "Extension installed successfully!"
    echo "Please restart Cursor to activate the extension."
else
    echo "Error: Extension installation failed"
    exit 1
fi

echo "Installation complete!" 