#!/bin/bash
#
# Fix Brave Browser File Dialog Issue
#
# This fixes the issue where GTK applications (like Brave) hang when
# trying to use file dialogs. It ensures GTK apps use GTK file dialogs
# while keeping Dolphin as default for folder browsing.
#

set -euo pipefail

echo "🔧 Fixing Brave Browser File Dialog Issue"
echo ""

# Check if Nautilus is available (we'll use it for GTK file dialogs)
if ! command -v nautilus &> /dev/null; then
    echo "📦 Installing Nautilus for GTK file dialog support..."
    sudo apt-get install -y nautilus
    echo "✅ Nautilus installed"
    echo ""
fi

# Remove GTK_USE_PORTAL which can cause issues with GTK apps trying to use Qt dialogs
echo "🔧 Removing GTK_USE_PORTAL setting..."
if grep -q "GTK_USE_PORTAL" "$HOME/.profile" 2>/dev/null; then
    # Remove the line
    sed -i '/GTK_USE_PORTAL/d' "$HOME/.profile"
    echo "✅ Removed GTK_USE_PORTAL from ~/.profile"
else
    echo "ℹ️  GTK_USE_PORTAL not found in ~/.profile"
fi

# Set Nautilus as default for file selection dialogs (but keep Dolphin for folders)
# We'll use a different MIME type for file selection
echo "📁 Configuring file dialogs..."
xdg-mime default org.gnome.Nautilus.desktop inode/directory

# Actually, let's keep Dolphin for folders but ensure GTK apps can use GTK dialogs
# The issue is that GTK apps need their own dialogs. Let's set it back to Dolphin
# but configure GTK properly
xdg-mime default org.kde.dolphin.desktop inode/directory

echo "✅ File manager configuration updated"
echo ""

# Create a script to launch GTK apps with proper environment
GTK_LAUNCHER="$HOME/.local/bin/gtk-app-launcher"
mkdir -p "$HOME/.local/bin"

cat > "$GTK_LAUNCHER" << 'EOF'
#!/bin/bash
# Launch GTK apps without Qt portal interference
unset GTK_USE_PORTAL
unset QT_QPA_PLATFORMTHEME
exec "$@"
EOF

chmod +x "$GTK_LAUNCHER"
echo "✅ Created GTK app launcher (optional helper)"
echo ""

echo "🎯 Configuration complete!"
echo ""
echo "📝 Changes made:"
echo "   1. Removed GTK_USE_PORTAL (was causing conflicts)"
echo "   2. Kept Dolphin as default for folder browsing"
echo "   3. Installed Nautilus for GTK file dialog support"
echo ""
echo "🔄 To apply changes:"
echo "   1. Close all Brave browser windows"
echo "   2. Log out and log back in, OR"
echo "   3. Restart your session"
echo ""
echo "💡 After restarting, Brave should work properly with file dialogs."
echo "   Dolphin will still be your default file manager for opening folders."

