#!/bin/bash

echo "Testing Cursor Extension Status"
echo "==============================="

# Check extension directory
echo "Extension Directory:"
ls -la ~/.cursor/extensions/cursor-git-extension

# Check extension configuration
echo -e "\nExtension Configuration:"
cat ~/.cursor/extensions/cursor-git-extension/package.json

# Check extension logs
echo -e "\nRecent Extension Logs:"
tail -n 20 /tmp/cursor-extension-install.log 2>/dev/null || echo "No installation logs found"

# Check Cursor configuration
echo -e "\nCursor Configuration:"
ls -la ~/.cursor/

echo -e "\nTest Complete" 