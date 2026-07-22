#!/bin/bash

# Convert all JPG and JPEG files to PNG
for img in *.jpg *.jpeg *.JPG *.JPEG; do
    # Skip if the file does not exist (handles empty glob case)
    [ -e "$img" ] || continue
    
    # Remove the old extension and add .png
    base="${img%.*}"
    magick "$img" "${base}.png"
    
    # Delete the original file
    rm -v "$img"
done

echo "Conversion and deletion complete."   