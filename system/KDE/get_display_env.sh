#!/bin/bash
# dump-env.sh
# This script dumps environment details needed to diagnose multi-monitor and panel issues in KDE Plasma.

echo "========================================"
echo "System Info (uname -a):"
uname -a
echo "========================================"
echo

echo "========================================"
echo "KDE Plasma Version (plasmashell --version):"
plasmashell --version
echo "========================================"
echo

echo "========================================"
echo "xrandr --verbose Output:"
xrandr --verbose
echo "========================================"
echo

echo "========================================"
echo "Extracting EDID Data for each connected output:"
# Loop over each connected monitor and dump its EDID.
for output in $(xrandr | awk '/ connected/ {print $1}'); do
    echo "---- $output ----"
    # Dump EDID block (if any) for the output
    xrandr --verbose | awk '/^'"$output"' connected/,/^\S/' | sed -n '/EDID:/,/^[^[:space:]]/p'
    echo
done
echo "========================================"
echo

echo "========================================"
echo "Dumping _KDE_SCREEN_INDEX for each output (from xrandr info):"
xrandr --verbose | grep -E "^[[:space:]]*_KDE_SCREEN_INDEX"
echo "========================================"
echo

echo "========================================"
echo "Listing current Plasma panel configurations from the config file:"
if [ -f "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]; then
    grep -E '^\[Containments\]' "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
else
    echo "plasma-org.kde.plasma.desktop-appletsrc not found in ~/.config"
fi
echo "========================================"
echo

echo "========================================"
echo "KScreen configuration (if any):"
if [ -d "$HOME/.config/kscreen" ]; then
    ls -la "$HOME/.config/kscreen"
    for f in "$HOME"/.config/kscreen/*; do
        echo "---- $f ----"
        cat "$f"
        echo
    done
else
    echo "No kscreen directory found in ~/.config"
fi
echo "========================================"
echo

echo "========================================"
echo "qdbus Listing for org.kde.plasmashell (object /PlasmaShell):"
qdbus org.kde.plasmashell /PlasmaShell
echo "========================================"
echo

echo "========================================"
echo "Additional KDE related environment variables:"
env | grep -i kde
echo "========================================"
echo

echo "========================================"
echo "Dump complete. Please review the above output for details about your display, EDID, and panel configuration."

