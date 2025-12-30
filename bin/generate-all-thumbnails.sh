#!/bin/bash
# Recursively generate thumbnails for all images

total_scanned=0
total_generated=0

echo "Generating thumbnails for ~/Pictures..."

find ~/ -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) 2>/dev/null | while read -r img; do
    ((total_scanned++))
    
    FILE_URI="file://$(readlink -f "$img")"
    HASH=$(echo -n "$FILE_URI" | md5sum | cut -d' ' -f1)
    
    # Check if thumbnail exists
    if [ ! -f ~/.cache/thumbnails/large/$HASH.png ]; then
        /usr/bin/gdk-pixbuf-thumbnailer -s 256 "$img" ~/.cache/thumbnails/large/$HASH.png 2>/dev/null
        if [ $? -eq 0 ]; then
            ((total_generated++))
            if [ $((total_generated % 10)) -eq 0 ]; then
                echo "Progress: generated $total_generated thumbnails..."
            fi
        fi
    fi
done

echo ""
echo "Done! Scanned $total_scanned images, generated $total_generated new thumbnails"
