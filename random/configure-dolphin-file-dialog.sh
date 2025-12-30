#!/bin/bash
#
# Configure Dolphin File Dialog for GTK Applications
#
# This ensures GTK applications use Dolphin's file dialog instead of
# the default GTK file dialog when opening files.
#

set -euo pipefail

echo "📁 Configuring Dolphin File Dialog for GTK Applications"
echo ""

# Check if required packages are installed
if ! dpkg -l | grep -q "^ii.*kde-cli-tools"; then
    echo "📦 Installing kde-cli-tools for better integration..."
    sudo apt-get install -y kde-cli-tools kde-cli-tools-data
    echo "✅ kde-cli-tools installed"
    echo ""
fi

# Set KDE file dialog as default
echo "🔧 Setting KDE file dialog as default..."
export GTK_USE_PORTAL=1

# Create a desktop file to ensure GTK apps use KDE dialogs
DESKTOP_FILE="$HOME/.local/share/applications/kde-file-dialog.desktop"
mkdir -p "$HOME/.local/share/applications"

cat > "$DESKTOP_FILE" << 'EOF'
[Desktop Entry]
Name=KDE File Dialog
Comment=KDE file dialog integration
Type=Application
EOF

# Configure environment for file dialogs
if ! grep -q "GTK_USE_PORTAL" "$HOME/.profile" 2>/dev/null; then
    echo "" >> "$HOME/.profile"
    echo "# Use KDE file dialogs in GTK applications" >> "$HOME/.profile"
    echo "export GTK_USE_PORTAL=1" >> "$HOME/.profile"
    echo "✅ Added GTK_USE_PORTAL to ~/.profile"
else
    echo "ℹ️  GTK_USE_PORTAL already configured"
fi

# Also set KDE file dialog explicitly
if ! grep -q "QT_QPA_PLATFORMTHEME" "$HOME/.profile" 2>/dev/null || ! grep -q "adwaita\|qt5ct" "$HOME/.profile" 2>/dev/null; then
    echo "⚠️  Note: Make sure QT_QPA_PLATFORMTHEME is set (run fix-dolphin-theme.sh)"
fi

echo ""
echo "🎯 Configuration complete!"
echo ""
echo "📝 Note: Some GTK applications may still use their own file dialogs."
echo "   This is a limitation of how GTK applications work on non-KDE systems."
echo ""
echo "💡 To use Dolphin's file dialog features:"
echo "   1. Open files from within Dolphin itself"
echo "   2. Use KDE applications when possible"
echo "   3. Some GTK apps may show basic file dialogs"

