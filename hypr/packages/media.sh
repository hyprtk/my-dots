#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "Media"

echo " Media Packages "

# Install or update pacman packages
_installOrUpdatePacman xclip
_installOrUpdatePacman pamixer
_installOrUpdatePacman wf-recorder
_installOrUpdatePacman pavucontrol
_installOrUpdatePacman tumbler
_installOrUpdatePacman vlc
_installOrUpdatePacman mpv
_installOrUpdatePacman ffmpeg

# Install or update yay packages
_installOrUpdateYay hyprquickframe-git
echo ""
