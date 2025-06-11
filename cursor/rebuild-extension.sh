#!/bin/bash

# Quick Extension Rebuild Script
# For development - just rebuilds the extension

set -e

EXTENSION_DIR="./cursor-git-extension"

echo "🔨 Rebuilding Cursor Git Extension..."
echo "Time: $(date)"
echo

# Navigate to extension directory
cd "$EXTENSION_DIR"

# Compile TypeScript
echo "⚙️  Compiling TypeScript..."
npm run compile

# Check if compilation was successful
if [ -f "out/extension.js" ]; then
    echo "✅ Extension rebuilt successfully!"
    echo
    echo "📋 Next steps:"
    echo "1. Reload Cursor window (Ctrl+R or Cmd+R)"
    echo "2. Test your changes"
    echo
    echo "🔍 For continuous development:"
    echo "npm run watch  # Watches for changes and rebuilds automatically"
else
    echo "❌ Error: Compilation failed!"
    exit 1
fi 