#!/bin/bash
counter=151  # Set your starting number here (e.g., 1, 5, 10)
for file in *.png; do
    if [ -f "$file" ]; then
        newname=$(printf "%d.png" "$counter")
        mv "$file" "$newname"
        ((counter++))
    fi
done   