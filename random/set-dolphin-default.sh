#!/bin/bash
#
# Set Dolphin as Default File Manager on GNOME
#
# This script configures Dolphin (KDE file manager) as the default
# file manager for GNOME/Unity desktop environment.
#

set -euo pipefail

echo "🐬 Setting Dolphin as Default File Manager"
echo ""

# Check if Dolphin is installed
if ! command -v dolphin &> /dev/null; then
    echo "❌ Dolphin is not installed!"
    echo "   Install it with: sudo apt-get install dolphin"
    exit 1
fi

echo "✅ Dolphin is installed: $(which dolphin)"
echo ""

# Set Dolphin as default for directories
echo "📁 Setting Dolphin as default file manager..."
xdg-mime default org.kde.dolphin.desktop inode/directory

# Verify the change
CURRENT_DEFAULT=$(xdg-mime query default inode/directory)
if [[ "$CURRENT_DEFAULT" == "org.kde.dolphin.desktop" ]]; then
    echo "✅ Successfully set Dolphin as default file manager"
else
    echo "⚠️  Warning: Default is currently: $CURRENT_DEFAULT"
    echo "   Expected: org.kde.dolphin.desktop"
fi

echo ""
echo "🎯 Configuration complete!"
echo ""
echo "Dolphin is now your default file manager."
echo "Opening folders will now use Dolphin instead of Nautilus/Nemo."
echo ""
echo "💡 Tip: You can also set Dolphin as 'Files' in your applications menu"
echo "   by creating a custom desktop entry if you prefer that name."

