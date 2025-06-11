#!/bin/bash

# Cursor launcher script for git integration
# This ensures Cursor opens with the correct workspace folder

CURSOR_PATH="/home/gypsy/bin/Cursor-1.0.0-x86_64.AppImage"
WORKSPACE_PATH="/home/gypsy/dev/gypsys-cli-tools/cursor"

echo "🚀 Starting Cursor with workspace: $WORKSPACE_PATH"

# Check if Cursor executable exists
if [ ! -f "$CURSOR_PATH" ]; then
    echo "❌ Error: Cursor not found at $CURSOR_PATH"
    exit 1
fi

# Check if workspace exists
if [ ! -d "$WORKSPACE_PATH" ]; then
    echo "❌ Error: Workspace directory not found at $WORKSPACE_PATH"
    exit 1
fi

# Launch Cursor with the workspace
"$CURSOR_PATH" --no-sandbox "$WORKSPACE_PATH" 