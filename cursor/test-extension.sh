#!/bin/bash

# Test script for cursor-git-extension

EXTENSION_DIR="$HOME/.cursor/extensions/cursor-git-extension-0.0.1"

echo "🔍 Testing Cursor Git Extension Installation"
echo "============================================="

# Check if extension directory exists
if [ ! -d "$EXTENSION_DIR" ]; then
    echo "❌ Extension directory not found: $EXTENSION_DIR"
    exit 1
fi

echo "✅ Extension directory exists: $EXTENSION_DIR"

# Check required files
if [ ! -f "$EXTENSION_DIR/package.json" ]; then
    echo "❌ package.json missing"
    exit 1
fi

if [ ! -f "$EXTENSION_DIR/out/extension.js" ]; then
    echo "❌ extension.js missing"
    exit 1
fi

echo "✅ Required files present"

# Check package.json content
echo ""
echo "📋 Extension Information:"
echo "------------------------"
grep -E '"name"|"version"|"displayName"' "$EXTENSION_DIR/package.json" | sed 's/^  //'

# Check if extension.js is valid JavaScript
if node -c "$EXTENSION_DIR/out/extension.js" 2>/dev/null; then
    echo "✅ extension.js is valid JavaScript"
else
    echo "❌ extension.js has syntax errors"
    exit 1
fi

# Test git repository detection
echo ""
echo "🔧 Testing Git Repository Detection:"
echo "------------------------------------"
cd "$(dirname "$0")"
if git rev-parse --git-dir >/dev/null 2>&1; then
    echo "✅ Git repository detected"
    echo "   Repository root: $(git rev-parse --show-toplevel)"
    echo "   Current branch: $(git branch --show-current)"
    echo "   Status: $(git status --porcelain | wc -l) uncommitted changes"
else
    echo "⚠️  Not in a git repository"
fi

echo ""
echo "🎯 Extension Installation Test Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Start Cursor IDE"
echo "2. Check the status bar for git information"
echo "3. Look for extension activation in Cursor's output panel"
echo "4. Check ~/dev/gypsys-cli-tools/cursor/activation-test.log for debug info"

echo ""
echo "Extension location: $EXTENSION_DIR" 