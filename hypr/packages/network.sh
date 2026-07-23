#!/bin/bash
source "$(dirname "$0")/../../scripts/library.sh"

figlet -f 3d "Network"
echo " Network Packages "
_install_pacman networkmanager network-manager-applet git freerdp curl gvfs gvfs-afc gvfs-dnssd gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-onedrive gvfs-smb gvfs-wsdd ntfs-3g samba
echo ""
