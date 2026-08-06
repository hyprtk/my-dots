#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_subsection_header "Network"

echo " Network Packages "

# Install or update pacman packages
_installOrUpdatePacman networkmanager
_installOrUpdatePacman network-manager-applet
_installOrUpdatePacman git
_installOrUpdatePacman freerdp
_installOrUpdatePacman curl
_installOrUpdatePacman gvfs
_installOrUpdatePacman gvfs-afc
_installOrUpdatePacman gvfs-dnssd
_installOrUpdatePacman gvfs-goa
_installOrUpdatePacman gvfs-gphoto2
_installOrUpdatePacman gvfs-mtp
_installOrUpdatePacman gvfs-nfs
_installOrUpdatePacman gvfs-onedrive
_installOrUpdatePacman gvfs-smb
_installOrUpdatePacman gvfs-wsdd
_installOrUpdatePacman ntfs-3g
_installOrUpdatePacman samba
echo ""