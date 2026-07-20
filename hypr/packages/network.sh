#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "Network"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sudo pacman -S networkmanager network-manager-applet git freerdp curl gvfs gvfs-afc gvfs-dnssd gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-onedrive gvfs-smb gvfs-wsdd ntfs-3g samba --noconfirm
echo ""