#/bin/bash
figlet -f 3d "sddm check"
sh ~/my-dots/scripts/rm-dm-managers.sh
echo ""
if [ ! -d /etc/sddm.conf.d/ ]; then
    sudo mkdir /etc/sddm.conf.d
    echo "Folder /etc/sddm.conf.d created."
fi
sudo cp ~/my-dots/sddm/sddm.conf /etc/sddm.conf.d/
echo "File /etc/sddm.conf.d/sddm.conf updated."
echo ""