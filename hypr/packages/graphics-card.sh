#!/bin/bash

# Detect initramfs tool
if command -v dracut &>/dev/null; then
    INITRAMFS_TOOL="dracut"
elif command -v mkinitcpio &>/dev/null; then
    INITRAMFS_TOOL="mkinitcpio"
else
    INITRAMFS_TOOL="unknown"
fi

echo "
#########################################################
#                                                       #
#            Which Graphics Card do you have?           #
#                                                       #
#########################################################

1) Intel
2) AMD
3) Nvidia
4) Virtualization (QEMU/VMware)
Defaults to AMD if you choose
something else
"
echo ""
read GRAPHICSCARD
case $GRAPHICSCARD in
1)
  sudo pacman -S --noconfirm xf86-video-intel mesa vulkan-intel vulkan-intel;;
2)
  sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau vdpauinfo
  if [ "$INITRAMFS_TOOL" = "mkinitcpio" ]; then
    sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
    sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img
  elif [ "$INITRAMFS_TOOL" = "dracut" ]; then
    echo "Adding amdgpu to dracut modules..."
    echo 'force_drivers+=" amdgpu "' | sudo tee /etc/dracut.conf.d/amdgpu.conf
    sudo dracut --force --regenerate-all
  fi;;
3)
  sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprob.blacklist=nouveau"/' /etc/default/grub
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  if [ "$INITRAMFS_TOOL" = "mkinitcpio" ]; then
    sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf
    sudo pacman -S --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva && yay --noconfirm -S libva-nvidia-driver-git
    sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img
  elif [ "$INITRAMFS_TOOL" = "dracut" ]; then
    echo 'force_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "' | sudo tee /etc/dracut.conf.d/nvidia.conf
    echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf
    sudo pacman -S --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva && yay --noconfirm -S libva-nvidia-driver-git
    sudo dracut --force --regenerate-all
  fi;;
4)
  echo "Installing virtualization guest drivers (QEMU/virt & VMware)..."
  sudo pacman -S --noconfirm qemu-guest-agent spice-vdagent xf86-video-qxl mesa open-vm-tools
  yay --noconfirm -S xf86-video-vmware
  sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
  sudo systemctl enable --now spice-vdagentd 2>/dev/null || true
  sudo systemctl enable --now vmtoolsd 2>/dev/null || true
  echo "Virtualization drivers installed. For 3D acceleration, ensure VM supports virgl (QEMU) or 3D acceleration (VMware).";;
*)
  sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau vdpauinfo
  if [ "$INITRAMFS_TOOL" = "mkinitcpio" ]; then
    sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
    sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img
  elif [ "$INITRAMFS_TOOL" = "dracut" ]; then
    echo 'force_drivers+=" amdgpu "' | sudo tee /etc/dracut.conf.d/amdgpu.conf
    sudo dracut --force --regenerate-all
  fi;;
esac
echo ""
clear
echo "
#########################################################
#                                                       #
#         Your Graphics Card has been installed         #
#                                                       #
#########################################################
"
