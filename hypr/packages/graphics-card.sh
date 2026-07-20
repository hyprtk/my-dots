#!/bin/bash

GRAPHICSCARD="${1:-2}"

case $GRAPHICSCARD in
  1|intel)
    sudo pacman -S --noconfirm xf86-video-intel mesa vulkan-intel
    ;;
  2|amd)
    sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
    sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf 2>/dev/null || true
    sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img 2>/dev/null || true
    ;;
  3|nvidia)
    sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"/' /etc/default/grub 2>/dev/null || true
    sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
    sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf 2>/dev/null || true
    echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf 2>/dev/null || true
    sudo pacman -S --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
    yay --noconfirm -S libva-nvidia-driver-git 2>/dev/null || true
    sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img 2>/dev/null || true
    ;;
  4|virt)
    echo "Installing virtualization guest drivers (QEMU/virt & VMware)..."
    sudo pacman -S --noconfirm qemu-guest-agent spice-vdagent xf86-video-qxl mesa open-vm-tools
    yay --noconfirm -S xf86-video-vmware 2>/dev/null || true
    sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
    sudo systemctl enable --now spice-vdagentd 2>/dev/null || true
    sudo systemctl enable --now vmtoolsd 2>/dev/null || true
    echo "Virtualization drivers installed. For 3D acceleration, ensure VM supports virgl (QEMU) or 3D acceleration (VMware)."
    ;;
  *)
    sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
    sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf 2>/dev/null || true
    sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img 2>/dev/null || true
    ;;
esac
