#!/bin/bash

echo "╔════════════════════════════════════════════════════════════╗"
echo "║              Cursor Notification Settings Check            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

SETTINGS_FILE="$HOME/.cursor/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "⚠️  Cursor settings file not found at: $SETTINGS_FILE"
    echo "   This is normal if you haven't customized settings yet."
    echo ""
    echo "✅ DEFAULT BEHAVIOR: All notifications should be enabled by default"
    echo ""
else
    echo "📋 Current Cursor settings file: $SETTINGS_FILE"
    echo ""
    
    # Check notification-related settings
    echo "🔍 Checking notification settings..."
    
    if grep -q "showInformationMessages" "$SETTINGS_FILE"; then
        echo "   • Information Messages:"
        grep "showInformationMessages" "$SETTINGS_FILE" | sed 's/^/     /'
    else
        echo "   • Information Messages: ✅ Default (enabled)"
    fi
    
    if grep -q "showWarningMessages" "$SETTINGS_FILE"; then
        echo "   • Warning Messages:"
        grep "showWarningMessages" "$SETTINGS_FILE" | sed 's/^/     /'
    else
        echo "   • Warning Messages: ✅ Default (enabled)"
    fi
    
    if grep -q "showErrorMessages" "$SETTINGS_FILE"; then
        echo "   • Error Messages:"
        grep "showErrorMessages" "$SETTINGS_FILE" | sed 's/^/     /'
    else
        echo "   • Error Messages: ✅ Default (enabled)"
    fi
fi

echo ""
echo "🔧 TO ENABLE NOTIFICATIONS IN CURSOR:"
echo "   1. Open Cursor"
echo "   2. Press Ctrl+, (or Cmd+, on Mac)"
echo "   3. Search for 'notification'"
echo "   4. Ensure these are checked/enabled:"
echo "      □ Window: Show Information Messages"
echo "      □ Window: Show Warning Messages"
echo "      □ Window: Show Error Messages"
echo ""
echo "🎯 OR manually edit settings.json:"
echo "   Add these lines to $SETTINGS_FILE:"
echo '   {'
echo '     "window.showInformationMessages": true,'
echo '     "window.showWarningMessages": true,'
echo '     "window.showErrorMessages": true'
echo '   }'
echo ""
echo "🧪 TO TEST NOTIFICATIONS:"
echo "   1. Launch Cursor in this git repository"
echo "   2. Press Ctrl+Shift+P"
echo "   3. Type 'Cursor Git Extension'"
echo "   4. Run 'Show Notification Settings Help'"
echo "" 