#!/bin/bash

GUM="${GUM:-$(command -v gum)}"
[ -x "$GUM" ] || GUM="$(dirname "$0")/../../standalone/gum"

GRAPHICSCARD=$(echo -e "Intel\nAMD\nNvidia" | "$GUM" choose --header.foreground=5 --cursor.foreground=5 --selected.foreground=0 --selected.background=5 --item.foreground=6 --height=4 --header="Which Graphics Card do you have?") || true

if [ -z "$GRAPHICSCARD" ]; then
    GRAPHICSCARD="AMD"
fi

case $GRAPHICSCARD in
Intel)
  _install_pacman xf86-video-intel mesa vulkan-intel;;
AMD)
  _install_pacman xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau vdpauinfo
  sudo sed -i 's/^MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf 2>/dev/null || true
  _rebuild_initramfs;;
Nvidia)
  sudo sed -i 's/^GRUB_CMDLINE_LINUX="[^"]*"/GRUB_CMDLINE_LINUX="nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"/' /etc/default/grub 2>/dev/null || true
  if command -v grub-mkconfig &>/dev/null; then
    sudo grub-mkconfig -o /boot/grub/grub.cfg
  fi
  sudo sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf 2>/dev/null || true
  echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf >/dev/null
  _install_pacman nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
  _install_aur libva-nvidia-driver-git
  _rebuild_initramfs;;
esac
echo ""
clear
