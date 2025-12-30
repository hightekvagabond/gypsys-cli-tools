#!/bin/bash
#
# Create a "Files" alias for Dolphin
#
# This creates a custom desktop entry that shows Dolphin as "Files"
# in your applications menu, so you can have a familiar name.
#

set -euo pipefail

DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/org.kde.dolphin-files.desktop"

echo "📝 Creating 'Files' alias for Dolphin"
echo ""

# Create directory if it doesn't exist
mkdir -p "$DESKTOP_DIR"

# Create the desktop entry
cat > "$DESKTOP_FILE" << 'EOF'
[Desktop Entry]
Name=Files
Comment=Access and organize files with Dolphin
Exec=dolphin %U
Icon=system-file-manager
Terminal=false
Type=Application
Categories=GNOME;GTK;Utility;Core;FileManager;
MimeType=inode/directory;
Keywords=folder;manager;explore;disk;filesystem;
EOF

echo "✅ Created desktop entry: $DESKTOP_FILE"
echo ""
echo "🔄 Updating desktop database..."
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true

echo ""
echo "✅ Done! You should now see 'Files' in your applications menu."
echo "   (This launches Dolphin)"
echo ""
echo "💡 To remove this alias, delete: $DESKTOP_FILE"

