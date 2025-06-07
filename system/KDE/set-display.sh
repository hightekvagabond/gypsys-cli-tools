#!/bin/bash
# set-display.sh
# This script sets up the external monitor and then creates or repositions a bottom panel
# on the external monitor. It uses _KDE_SCREEN_INDEX from xrandr: your built‑in (eDP-1) is screen 1,
# and your external (HDMI-1-3) is screen 2.

# Global variables
MONITOR="HDMI-1-3"
PRIMARY="eDP-1"
# From your dump, external monitor _KDE_SCREEN_INDEX is 2.
EXTERNAL_SCREEN_INDEX=2
# Set a panel height (in pixels)
PANEL_HEIGHT=30

# (Optional) Known EDID signature for the external monitor (if needed)
KNOWN_EDID_SNIPPET="00ffffffffffff002e83"  # adjust if desired

# Function to extract EDID data (flattened) for a given monitor
get_monitor_edid() {
    xrandr --verbose | awk '/'"$MONITOR"'/,0' | sed -n '/EDID:/,/^[^[:space:]]/p' | \
      grep -v "EDID:" | tr -d ' \t\n'
}

# Retrieve EDID data for the monitor (for debugging, though your dump shows none for HDMI-1-3)
EDID_DATA=$(get_monitor_edid)
if [ -z "$EDID_DATA" ]; then
    echo "DEBUG: No EDID data found for $MONITOR (this is normal for some monitors)."
else
    echo "DEBUG: EDID data (first 100 chars): ${EDID_DATA:0:100}..."
fi

# Set up the external monitor using xrandr.
echo "DEBUG: Extending display: setting $MONITOR to the right of $PRIMARY."
xrandr --output "$MONITOR" --auto --right-of "$PRIMARY"
sleep 2  # allow time for the display configuration to update

# Parse external monitor geometry from xrandr output.
GEOMETRY_LINE=$(xrandr | grep "^$MONITOR")
echo "DEBUG: xrandr line for $MONITOR: $GEOMETRY_LINE"
if [[ $GEOMETRY_LINE =~ ([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+) ]]; then
    width=${BASH_REMATCH[1]}
    height=${BASH_REMATCH[2]}
    offsetX=${BASH_REMATCH[3]}
    offsetY=${BASH_REMATCH[4]}
    echo "DEBUG: Parsed geometry - width: $width, height: $height, offsetX: $offsetX, offsetY: $offsetY"
else
    echo "DEBUG: Failed to parse geometry for monitor $MONITOR."
fi

# Calculate the y coordinate for a bottom panel on the external monitor.
panel_y=$(( offsetY + height - PANEL_HEIGHT ))
echo "DEBUG: Calculated panel_y (for bottom panel): $panel_y"

# Build the Plasma script.
read -r -d '' plasmascript <<EOF
print("DEBUG: Starting Plasma script for external panel.");

// Dump list of existing panels and their properties.
var panelsList = panels();
for (var i = 0; i < panelsList.length; i++) {
    var p = panelsList[i];
    print("DEBUG: Panel id " + p.id + ", screen " + p.screen + ", location " + p.location +
          ", geometry " + JSON.stringify(p.geometry));
}

var extScreen = $EXTERNAL_SCREEN_INDEX;
var found = false;

// Look for any panel that already belongs to screen extScreen.
for (var i = 0; i < panelsList.length; i++) {
    if (panelsList[i].screen == extScreen) {
        print("DEBUG: Found panel id " + panelsList[i].id + " on external screen " + extScreen + ".");
        // If the panel is not at bottom, force its location.
        if (panelsList[i].location !== "bottom") {
            print("DEBUG: Panel id " + panelsList[i].id + " is not at bottom (" + panelsList[i].location + "). Changing location to bottom.");
            panelsList[i].location = "bottom";
        } else {
            print("DEBUG: Panel id " + panelsList[i].id + " is already at bottom.");
        }
        found = true;
        break;
    }
}

if (false){
#if (!found) {
    print("DEBUG: No panel found on external screen " + extScreen + ". Creating a new panel.");
    try {
        var newPanel = new Panel(extScreen);
        newPanel.location = "bottom";
        // Optionally, set geometry so that it aligns with the external monitor.
        newPanel.geometry = { x: $offsetX, y: $panel_y, width: $width, height: $PANEL_HEIGHT };
        newPanel.addWidget("org.kde.plasma.taskmanager");
        newPanel.addWidget("org.kde.plasma.systemtray");
        print("DEBUG: Created new panel with id " + newPanel.id + " on screen " + newPanel.screen + " at bottom.");
    } catch (e) {
        print("DEBUG: Error creating new panel on external screen: " + e);
    }
}

EOF

echo "DEBUG: Evaluating Plasma script:"
echo "$plasmascript"

# Evaluate the Plasma script via qdbus.
qdbus org.kde.plasmashell /PlasmaShell evaluateScript "$plasmascript"
echo "DEBUG: Plasma script evaluation complete."

