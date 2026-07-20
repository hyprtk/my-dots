#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "sddm check"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sh ~/hyprtk/scripts/rm-dm-managers.sh
echo ""
if [ ! -d /etc/sddm.conf.d/ ]; then
    sudo mkdir /etc/sddm.conf.d
    echo "Folder /etc/sddm.conf.d created."
fi
sudo cp ~/hyprtk/common/sddm/sddm.conf /etc/sddm.conf.d/
echo "File /etc/sddm.conf.d/sddm.conf updated."
echo ""