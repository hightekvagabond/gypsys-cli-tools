#!/bin/bash
# Cleanup script for failed installation attempts

echo "Cleaning up partial installation..."

# Clean up /tmp
echo "Removing temporary files..."
rm -f /tmp/talon-linux.tar.xz
rm -rf /tmp/talon

echo "✓ Cleanup complete"
echo ""
echo "You can now run ./install.sh again"

