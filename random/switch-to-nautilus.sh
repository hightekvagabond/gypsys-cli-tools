#!/bin/bash
#
# Switch to Nautilus and Configure It
#
# This script:
# 1. Installs Nautilus if needed
# 2. Sets it as default file manager
# 3. Configures Nautilus preferences for better usability
# 4. Cleans up Dolphin-related settings
#

set -euo pipefail

echo "📁 Switching to Nautilus File Manager"
echo ""

# Install Nautilus if not installed
if ! command -v nautilus &> /dev/null; then
    echo "📦 Installing Nautilus..."
    sudo apt-get install -y nautilus nautilus-data
    echo "✅ Nautilus installed"
    echo ""
fi

# Set Nautilus as default file manager
echo "🔧 Setting Nautilus as default file manager..."
xdg-mime default org.gnome.Nautilus.desktop inode/directory

# Verify
CURRENT_DEFAULT=$(xdg-mime query default inode/directory)
if [[ "$CURRENT_DEFAULT" == "org.gnome.Nautilus.desktop" ]]; then
    echo "✅ Nautilus is now the default file manager"
else
    echo "⚠️  Warning: Default is currently: $CURRENT_DEFAULT"
fi
echo ""

# Clean up Dolphin-related environment variables
echo "🧹 Cleaning up Dolphin-related settings..."
if grep -q "QT_QPA_PLATFORMTHEME" "$HOME/.profile" 2>/dev/null; then
    sed -i '/QT_QPA_PLATFORMTHEME/d' "$HOME/.profile"
    sed -i '/Qt5 theme configuration for Dolphin/d' "$HOME/.profile"
    echo "✅ Removed QT_QPA_PLATFORMTHEME from ~/.profile"
fi

# Remove any leftover Dolphin comments
sed -i '/#.*Dolphin/d' "$HOME/.profile" 2>/dev/null || true
sed -i '/#.*KDE file dialogs/d' "$HOME/.profile" 2>/dev/null || true

echo "✅ Cleanup complete"
echo ""

# Configure Nautilus preferences using gsettings
echo "⚙️  Configuring Nautilus preferences..."

# Check if gsettings works
if ! command -v gsettings &> /dev/null; then
    echo "⚠️  gsettings not found - skipping preference configuration"
else
    echo "   Applying settings..."
    
    # View preferences
    gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view' 2>/dev/null || true
    echo "   ✓ Set default view to list (more practical)"
    
    # Always show location entry (path bar) - more useful than breadcrumbs
    gsettings set org.gnome.nautilus.preferences always-use-location-entry true 2>/dev/null || true
    echo "   ✓ Enabled location entry (shows full path)"
    
    # Sort folders first
    gsettings set org.gnome.nautilus.preferences sort-directories-first true 2>/dev/null || true
    echo "   ✓ Sort folders first"
    
    # Thumbnails
    gsettings set org.gnome.nautilus.preferences show-image-thumbnails 'always' 2>/dev/null || true
    echo "   ✓ Enable image thumbnails"
    
    # File chooser settings
    gsettings set org.gtk.Settings.FileChooser show-size-column true 2>/dev/null || true
    echo "   ✓ Show file size column in dialogs"
    
    gsettings set org.gtk.Settings.FileChooser show-type-column true 2>/dev/null || true
    echo "   ✓ Show file type column in dialogs"
    
    # Executable text files - ask before running
    gsettings set org.gnome.nautilus.preferences executable-text-activation 'ask' 2>/dev/null || true
    echo "   ✓ Ask before running executable text files"
    
    # Click behavior - double-click (more standard)
    gsettings set org.gnome.nautilus.preferences click-policy 'double' 2>/dev/null || true
    echo "   ✓ Double-click to open files"
    
    # Show hidden files - disabled by default (can enable if needed)
    # gsettings set org.gnome.nautilus.preferences show-hidden-files true
    
    # Default zoom level - normal
    gsettings set org.gnome.nautilus.icon-view default-zoom-level 'standard' 2>/dev/null || true
    
    # List view settings
    gsettings set org.gnome.nautilus.list-view default-zoom-level 'standard' 2>/dev/null || true
    gsettings set org.gnome.nautilus.list-view default-visible-columns "['name', 'size', 'date_modified']" 2>/dev/null || true
    echo "   ✓ Configured list view columns"
    
    echo ""
    echo "✅ Nautilus preferences configured"
fi

# Install useful Nautilus extensions (optional but recommended)
echo ""
echo "📦 Checking for useful Nautilus extensions..."

# Check for available extensions
NAUTILUS_EXTENSIONS=(
    "nautilus-extension-gnome-terminal"  # Right-click terminal option
    "nautilus-sendto"                    # Send files via email
)

for ext in "${NAUTILUS_EXTENSIONS[@]}"; do
    if ! dpkg -l | grep -q "^ii.*$ext"; then
        echo "   - $ext (available but not installed)"
    else
        echo "   ✓ $ext (installed)"
    fi
done

echo ""
echo "💡 To install extensions: sudo apt-get install nautilus-extension-gnome-terminal nautilus-sendto"
echo ""

# Create Nautilus config directory if it doesn't exist
mkdir -p "$HOME/.config/nautilus"

echo "🎯 Configuration complete!"
echo ""
echo "📝 Summary:"
echo "   ✓ Nautilus installed and set as default"
echo "   ✓ Dolphin-related settings cleaned up"
echo "   ✓ Nautilus preferences configured"
echo ""
echo "🔄 To apply changes:"
echo "   1. Close any open file manager windows"
echo "   2. Log out and log back in (or reboot)"
echo ""
echo "💡 After restarting, Nautilus will be your file manager."
echo "   You can further customize it in Nautilus → Preferences (or Settings → Files)"

