#!/bin/bash
cat ~/.cursor/settings.json
./rebuild-extension.sh
./dev/gypsys-cli-tools/cursor/dev-install-extension.sh
~/bin/Cursor-1.0.0-x86_64.AppImage --no-sandbox

