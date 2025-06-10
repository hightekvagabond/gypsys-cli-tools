TODO: Auto-Move Windows to Secondary Screen on Monitor Connect (KDE)

Goal: When I connect a second monitor, move all windows that are assigned to a single virtual desktop (i.e., not "on all desktops") to the external screen automatically.

Steps:
1. Create script directory:
   ~/.local/share/kwin/scripts/move_to_secondary/

2. Create main script:
   ~/.local/share/kwin/scripts/move_to_secondary/contents/code/main.js
   - Listens for screen connection and moves non-"All Desktops" windows to screen 1.

3. Add metadata:
   ~/.local/share/kwin/scripts/move_to_secondary/metadata.desktop

4. Enable the script:
   Run these in terminal:
   qdbus org.kde.KWin /KWin org.kde.KWin.reloadConfig
   qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript move_to_secondary

5. (Optional) Use KDE System Settings → Window Management → KWin Scripts to verify it's enabled.

Notes:
- Script only acts at moment of screen change.
- Ignores windows set to “All Desktops”.
- Optional: package into installer script for reuse across systems.

