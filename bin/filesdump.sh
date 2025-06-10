#!/bin/bash

# Ensure two arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <source_folder> <destination_folder>"
    exit 1
fi

SOURCE="$1"
DESTINATION="$2"

# Check if source exists
if [ ! -d "$SOURCE" ]; then
    echo "Source folder does not exist: $SOURCE"
    exit 1
fi

# Create destination if it doesn't exist
mkdir -p "$DESTINATION"

# Function to copy and rename plain text files
copy_text_files() {
    local src="$1"
    local dest="$2"
    local prefix="$3"

    for item in "$src"/*; do
        if [ -d "$item" ]; then
            # If item is a directory, call the function recursively
            local dir_name=$(basename "$item")
            copy_text_files "$item" "$dest" "${prefix}${dir_name}_"
        elif [ -f "$item" ] && file "$item" | grep -qE 'text'; then
            # If item is a plain text file, copy it with the prefixed name
            local file_name=$(basename "$item")
            cp "$item" "$dest/${prefix}${file_name}"
        fi
    done
}

# Start copying text files
copy_text_files "$SOURCE" "$DESTINATION" ""

echo "All plain text files copied from $SOURCE to $DESTINATION."
