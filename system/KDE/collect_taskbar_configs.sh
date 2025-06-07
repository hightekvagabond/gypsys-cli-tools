#!/bin/bash
# This script collects configuration files that are likely to affect your KDE taskbar.
# It processes known KDE config files (such as plasma-org.kde.plasma.desktop-appletsrc,
# plasmashellrc, and kwinrc) and searches within ~/.config and /etc for files that
# mention keywords like "taskbar", "panel", "plasmashell", or "kwin". It excludes paths
# that contain terms like "BraveSoftware" or "VirtualBox" to avoid unrelated data.
#
# Run this script with sudo if needed.

# Settings for per-file truncation.
MAX_SIZE=102400      # 100 KB per file threshold for truncation.
TRUNCATE_LINES=100   # Number of lines to show from start and end for large files.
# Maximum overall bundle file size (512 MB).
MAX_BUNDLE_SIZE=536870912

# Define inclusion and exclusion patterns.
INCLUDE_KEYWORDS="taskbar\|panel\|plasmashell\|kwin"
EXCLUDE_PATHS="BraveSoftware\|VirtualBox"

# Determine the real user's home directory if running under sudo.
if [ -n "$SUDO_USER" ]; then
  REAL_HOME=$(eval echo "~$SUDO_USER")
else
  REAL_HOME=$HOME
fi

# Define the output bundle file.
OUTPUT_FILE="/tmp/taskbar_troubleshoot_bundle_$(date +%s).txt"
touch "$OUTPUT_FILE"

echo "Collecting taskbar-related configuration files into: $OUTPUT_FILE"

# Check overall bundle file size.
check_bundle_size() {
    current_size=$(stat -c%s "$OUTPUT_FILE")
    if [ "$current_size" -ge "$MAX_BUNDLE_SIZE" ]; then
        echo "----- Bundle file reached maximum size of $MAX_BUNDLE_SIZE bytes. Further output truncated. -----" >> "$OUTPUT_FILE"
        echo "Max bundle size reached: $OUTPUT_FILE"
        exit 0
    fi
}

# Function to append a file's content with headers, truncating if too big.
append_file() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        echo "----- Begin file: $file_path -----" >> "$OUTPUT_FILE"
        file_size=$(stat -c%s "$file_path")
        if [ "$file_size" -gt "$MAX_SIZE" ]; then
            echo "NOTE: File is larger than ${MAX_SIZE} bytes. Output is truncated." >> "$OUTPUT_FILE"
            echo "----- First ${TRUNCATE_LINES} lines of $file_path -----" >> "$OUTPUT_FILE"
            head -n "$TRUNCATE_LINES" "$file_path" >> "$OUTPUT_FILE"
            echo "----- [TRUNCATED] -----" >> "$OUTPUT_FILE"
            echo "----- Last ${TRUNCATE_LINES} lines of $file_path -----" >> "$OUTPUT_FILE"
            tail -n "$TRUNCATE_LINES" "$file_path" >> "$OUTPUT_FILE"
        else
            cat "$file_path" >> "$OUTPUT_FILE"
        fi
        echo -e "\n----- End file: $file_path -----\n" >> "$OUTPUT_FILE"
        check_bundle_size
    fi
}

# 1. Collect known KDE config files.
KNOWN_FILES=(
  "$REAL_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  "$REAL_HOME/.config/plasmashellrc"
  "$REAL_HOME/.config/kwinrc"
)
for file in "${KNOWN_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "Collected known file: $file"
        append_file "$file"
    fi
done

# 2. Search ~/.config for files containing the include keywords,
#    but exclude files in directories that match the exclusion pattern.
echo "Searching $REAL_HOME/.config for taskbar-related files..."
mapfile -t config_files < <(grep -R -l -i "$INCLUDE_KEYWORDS" "$REAL_HOME/.config" 2>/dev/null | grep -Ev "$EXCLUDE_PATHS")
for file in "${config_files[@]}"; do
    if [ -f "$file" ]; then
        echo "Collected: $file"
        append_file "$file"
    fi
done

# 3. Search system-wide in /etc for taskbar-related files.
echo "Searching /etc for taskbar-related config files..."
mapfile -t etc_files < <(grep -R -l -i "$INCLUDE_KEYWORDS" /etc 2>/dev/null | grep -Ev "$EXCLUDE_PATHS")
for file in "${etc_files[@]}"; do
    if [ -f "$file" ]; then
        echo "Collected: $file"
        append_file "$file"
    fi
done

echo ""
echo "Collection complete."
echo "The bundled taskbar-related configuration file is located at: $OUTPUT_FILE"

