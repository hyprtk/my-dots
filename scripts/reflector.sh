#!/bin/bash

# 1. Install reflector and rsync (required for some mirrors)
echo "Installing reflector..."
sudo pacman -Syu reflector rsync --noconfirm

# 2. Backup existing mirrorlist
echo "Backing up current mirrorlist..."
sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup

# 3. Find and save the fastest mirrors
# Options:
# --verbose: Show progress
# --latest 20: Consider only the 20 most recently synchronized mirrors
# --sort rate: Sort by download speed
# --protocol https: Use only HTTPS (secure)
# --save: Output to the pacman mirrorlist file
echo "Updating mirrorlist with fastest mirrors..."
sudo reflector --verbose --latest 20 --sort rate --protocol https --save /etc/pacman.d/mirrorlist

echo "Mirrorlist updated successfully."   

sudo systemctl enable --now reflector.timer   