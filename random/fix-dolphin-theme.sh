#!/bin/bash
#
# Fix Dolphin Theme on GNOME/Unity
#
# This script configures Dolphin (Qt/KDE app) to use a consistent dark theme
# that matches your GNOME dark theme when running on Unity/GNOME Shell.
#

set -euo pipefail

echo "🎨 Fixing Dolphin Theme for GNOME/Unity"
echo ""

# Check if Dolphin is installed
if ! command -v dolphin &> /dev/null; then
    echo "❌ Dolphin is not installed!"
    exit 1
fi

# Install adwaita-qt for better GNOME integration (recommended)
# or qt5ct as fallback
if ! dpkg -l | grep -q "^ii.*adwaita-qt"; then
    echo "📦 Installing adwaita-qt for GNOME theme integration..."
    sudo apt-get install -y adwaita-qt
    echo "✅ adwaita-qt installed"
    echo ""
fi

# Also install qt5ct as a fallback/alternative
if ! command -v qt5ct &> /dev/null; then
    echo "📦 Installing qt5ct for additional Qt theme configuration..."
    sudo apt-get install -y qt5ct
    echo "✅ qt5ct installed"
    echo ""
fi

# Get current GTK theme
GTK_THEME=$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")
echo "Current GTK theme: $GTK_THEME"
echo ""

# Determine if we should use dark theme
USE_DARK=true
if [[ "$GTK_THEME" == *"dark"* ]] || [[ "$GTK_THEME" == *"Dark"* ]]; then
    USE_DARK=true
    echo "Detected dark GTK theme - configuring Dolphin for dark theme"
else
    USE_DARK=false
    echo "Detected light GTK theme - configuring Dolphin for light theme"
fi
echo ""

# Set Qt5 platform theme - prefer adwaita-qt for GNOME integration
QT_THEME_ENGINE="adwaita"
if dpkg -l | grep -q "^ii.*adwaita-qt"; then
    echo "✅ Using adwaita-qt for better GNOME theme integration"
else
    QT_THEME_ENGINE="qt5ct"
    echo "⚠️  Using qt5ct (adwaita-qt not available)"
fi

# Configure qt5ct (if using it as fallback)
if [[ "$QT_THEME_ENGINE" == "qt5ct" ]]; then
    QT5_CONFIG="$HOME/.config/qt5ct/qt5ct.conf"
    mkdir -p "$HOME/.config/qt5ct"

    if [[ "$USE_DARK" == "true" ]]; then
        cat > "$QT5_CONFIG" << EOF
[Appearance]
style=Breeze
color_scheme_path=/usr/share/qt5ct/colors/BreezeDark.conf
icon_theme=Yaru
EOF
        echo "✅ Configured qt5ct for dark theme (Breeze Dark)"
    else
        cat > "$QT5_CONFIG" << EOF
[Appearance]
style=Breeze
color_scheme_path=/usr/share/qt5ct/colors/Breeze.conf
icon_theme=Yaru
EOF
        echo "✅ Configured qt5ct for light theme (Breeze)"
    fi
else
    echo "ℹ️  Using adwaita-qt - it will automatically match your GNOME theme"
fi

if ! grep -q "QT_QPA_PLATFORMTHEME" "$HOME/.profile" 2>/dev/null; then
    echo "" >> "$HOME/.profile"
    echo "# Qt5 theme configuration for Dolphin" >> "$HOME/.profile"
    echo "export QT_QPA_PLATFORMTHEME=$QT_THEME_ENGINE" >> "$HOME/.profile"
    echo "✅ Added QT_QPA_PLATFORMTHEME=$QT_THEME_ENGINE to ~/.profile"
else
    # Update existing entry
    sed -i "s|export QT_QPA_PLATFORMTHEME=.*|export QT_QPA_PLATFORMTHEME=$QT_THEME_ENGINE|" "$HOME/.profile"
    echo "✅ Updated QT_QPA_PLATFORMTHEME to $QT_THEME_ENGINE in ~/.profile"
fi

# Also set it for current session
export QT_QPA_PLATFORMTHEME=$QT_THEME_ENGINE

# Configure KDE colors if kdeglobals exists, otherwise create it
KDE_GLOBALS="$HOME/.config/kdeglobals"
mkdir -p "$HOME/.config"

if [[ "$USE_DARK" == "true" ]]; then
    # Create/update kdeglobals with dark theme
    if ! grep -q "^\[Colors\]" "$KDE_GLOBALS" 2>/dev/null; then
        cat >> "$KDE_GLOBALS" << 'KDEEOF'

[Colors]
View\Background\Alternate=34,34,34
View\Background\Normal=34,34,34
Window\Background\Alternate=34,34,34
Window\Background\Normal=34,34,34
KDEEOF
        echo "✅ Created KDE color configuration"
    else
        echo "ℹ️  KDE colors already configured"
    fi
fi

echo ""
echo "🎯 Configuration complete!"
echo ""
echo "📝 Changes made:"
echo "   1. Installed/configured qt5ct for Qt5 theming"
echo "   2. Set QT_QPA_PLATFORMTHEME environment variable"
echo "   3. Configured KDE colors for dark theme"
echo ""
echo "🔄 To apply changes:"
echo "   1. Log out and log back in, OR"
echo "   2. Restart your session, OR"
echo "   3. Run: source ~/.profile && dolphin"
echo ""
echo "💡 Tip: You can also manually configure themes with: qt5ct"

