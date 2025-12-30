#!/bin/bash
# Fix APT repository issues blocking voice-commands installation

set -e

echo "Fixing APT repository issues..."
echo ""

# Fix Synaptics repository (accept changed origin)
echo "1. Accepting Synaptics repository changes..."
sudo apt-get update --allow-releaseinfo-change 2>/dev/null || true

# Disable problematic NVIDIA Workbench repo (expired key)
echo "2. Disabling NVIDIA Workbench repository (expired key)..."
if [ -f /etc/apt/sources.list.d/workbench.list ]; then
    sudo mv /etc/apt/sources.list.d/workbench.list /etc/apt/sources.list.d/workbench.list.disabled || true
fi

# Try update again
echo "3. Updating package lists..."
sudo apt-get update

echo ""
echo "✓ APT repositories fixed!"
echo ""
echo "Now run the voice commands installer:"
echo "  ./install.sh"



