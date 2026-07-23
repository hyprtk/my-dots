#!/bin/bash
source "$(dirname "$0")/../../scripts/library.sh"

GUM="${GUM:-$(command -v gum)}"
[ -x "$GUM" ] || GUM="$(dirname "$0")/../../standalone/gum"

GRAPHICSCARD=$(echo -e "Intel\nAMD\nNvidia" | "$GUM" choose --header.foreground=5 --cursor.foreground=5 --selected.foreground=0 --selected.background=5 --item.foreground=6 --height=4 --header="Which Graphics Card do you have?")

if [ -z "$GRAPHICSCARD" ]; then
    GRAPHICSCARD="AMD"
fi

case $GRAPHICSCARD in
Intel)
  _install_pacman xf86-video-intel mesa vulkan-intel;;
AMD)
  _install_pacman xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau vdpauinfo
  sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
  sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img;;
Nvidia)
  sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprob.blacklist=nouveau"/' /etc/default/grub
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
  echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf
  _install_pacman nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
  _install_aur libva-nvidia-driver-git
  sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img;;
esac
echo ""
clear
