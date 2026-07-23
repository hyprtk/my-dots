#!/bin/bash
source "$(dirname "$0")/../../scripts/library.sh"

figlet -f 3d "sddm check"
sh ~/hyprtk/scripts/rm-dm-managers.sh
echo ""
if [ ! -d /etc/sddm.conf.d/ ]; then
    sudo mkdir /etc/sddm.conf.d
    echo "Folder /etc/sddm.conf.d created."
fi
if [ -f ~/hyprtk/sddm/sddm.conf ]; then
    sudo cp ~/hyprtk/sddm/sddm.conf /etc/sddm.conf.d/
    echo "File /etc/sddm.conf.d/sddm.conf updated."
fi
echo ""
