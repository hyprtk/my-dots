#!/bin/bash

# Respect the initramfs tool chosen in the main installer if available,
# otherwise auto-detect
if [ -z "$INIT_TOOL" ]; then
    if command -v mkinitcpio &>/dev/null; then
        INIT_TOOL="mkinitcpio"
    elif command -v dracut &>/dev/null; then
        INIT_TOOL="dracut"
    else
        INIT_TOOL="mkinitcpio"
    fi
fi

_nvidia_initramfs_modules() {
    local modules="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
    if [ "$INIT_TOOL" = "dracut" ]; then
        echo "force_drivers+=\" $modules \"" | sudo tee /etc/dracut.conf.d/nvidia.conf >/dev/null
        sudo dracut --force --regenerate-all
    else
        sudo sed -i "s/^MODULES=()/MODULES=($modules)/" /etc/mkinitcpio.conf
        sudo mkinitcpio -P
    fi
}

_amd_initramfs_modules() {
    if [ "$INIT_TOOL" = "dracut" ]; then
        echo "force_drivers+=\" amdgpu \"" | sudo tee /etc/dracut.conf.d/amdgpu.conf >/dev/null
        sudo dracut --force --regenerate-all
    else
        sudo sed -i 's/^MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
        sudo mkinitcpio -P
    fi
}

_nvidia_grub_setup() {
    local grub_file="/etc/default/grub"
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file"; then
        local current
        current=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file" | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT=//' | tr -d '"')
        if ! echo "$current" | grep -q "nvidia_drm.modeset"; then
            sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau/' "$grub_file"
        fi
    else
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"' | sudo tee -a "$grub_file" >/dev/null
    fi
    if command -v grub-mkconfig &>/dev/null; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
}

echo "
╔══════════════════════════════════════════════════════╗
║           Which Graphics Card do you have?           ║
╚══════════════════════════════════════════════════════╝

  1) Intel
  2) AMD
  3) Nvidia
  4) Virtual Machine (QEMU/VMware)
  Defaults to AMD if you choose something else
"
echo ""
read GRAPHICSCARD
case $GRAPHICSCARD in
1)
  sudo pacman -S --noconfirm xf86-video-intel mesa vulkan-intel vulkan-intel;;
2)
  sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau vdpauinfo
  _amd_initramfs_modules;;
3)
  _nvidia_grub_setup
  _nvidia_initramfs_modules
  echo -e "options nvidia-drm modeset=1" | sudo tee /etc/modprobe.d/nvidia.conf >/dev/null
  sudo pacman -S --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva && yay --noconfirm -S libva-nvidia-driver-git;;
4)
  sudo pacman -S --noconfirm qemu-guest-agent spice-vdagent xf86-video-qxl mesa open-vm-tools
  yay --noconfirm -S xf86-video-vmware
  sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
  sudo systemctl enable --now spice-vdagentd 2>/dev/null || true
  sudo systemctl enable --now vmtoolsd 2>/dev/null || true;;
*)
  sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau vdpauinfo
  _amd_initramfs_modules;;
esac
echo ""
clear
echo "
╔══════════════════════════════════════════════════════╗
║     Your Graphics Card has been installed            ║
╚══════════════════════════════════════════════════════╝
"
