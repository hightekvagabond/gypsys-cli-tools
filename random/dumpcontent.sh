#!/bin/bash

# Check if directory is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/directory"
    exit 1
fi

# Set the target directory from the command-line argument
TARGET_DIR="$1"

# Check if the directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Directory does not exist. Exiting."
    exit 1
fi

# Generate the output file name based on the directory name
DIR_NAME=$(basename "$TARGET_DIR")
OUTPUT_FILE="dump_${DIR_NAME}.txt"

# Initialize the output file
> "$OUTPUT_FILE"

# Function to spider the directory and capture file paths and content
spider_directory() {
    local dir="$1"

    # Loop through all files in the directory and subdirectories
    find "$dir" -type f | while IFS= read -r file
    do
        # Get the relative path of the file
        rel_path=$(realpath --relative-to="$dir" "$file")

        # Write separators and file name to output file
        echo "==========================================" >> "$OUTPUT_FILE"
        echo "File: $rel_path" >> "$OUTPUT_FILE"
        echo "==========================================" >> "$OUTPUT_FILE"

        # Write the content of the file to the output file
        cat "$file" >> "$OUTPUT_FILE"

        # Add a newline after each file's content for separation
        echo "" >> "$OUTPUT_FILE"
    done
}

# Start spidering from the target directory
spider_directory "$TARGET_DIR"

echo "Finished. Output saved to $OUTPUT_FILE"

