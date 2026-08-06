#!/bin/bash

# Source library for package functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../installer/scripts/library.sh"

print_section_header "Graphics Card Detection"

echo -e "${COLOR_WHITE}Which Graphics Card do you have?${COLOR_RESET}"
echo ""
echo -e "${COLOR_CYAN}1) Intel${COLOR_RESET}"
echo -e "${COLOR_CYAN}2) AMD${COLOR_RESET}"
echo -e "${COLOR_CYAN}3) Nvidia${COLOR_RESET}"
echo -e "${COLOR_CYAN}4) Virtualization (QEMU/virt & VMware)${COLOR_RESET}"
echo -e "${COLOR_YELLOW}Defaults to AMD if you choose something else${COLOR_RESET}"
echo ""
read -p "Enter your choice (1-4): " GRAPHICSCARD

case $GRAPHICSCARD in
1)
  print_subsection_header "Installing Intel Graphics Drivers"
  _installOrUpdatePacman xf86-video-intel
  _installOrUpdatePacman mesa
  _installOrUpdatePacman vulkan-intel
  ;;
2)
  print_subsection_header "Installing AMD Graphics Drivers"
  _installOrUpdatePacman xf86-video-amdgpu
  _installOrUpdatePacman mesa
  _installOrUpdatePacman vulkan-radeon
  _installOrUpdatePacman vdpauinfo
  _installOrUpdatePacman corectrl
  _installOrUpdatePacman libvdpau
  sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
  update_initramfs_config "/etc/mkinitcpio.conf" "/boot/initramfs-custom.img"
  ;;
3)
  print_subsection_header "Installing Nvidia Graphics Drivers"
  sudo sed -i 's|^GRUB_CMDLINE_LINUX="\(.*\)"|GRUB_CMDLINE_LINUX="\1 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprob.blacklist=nouveau"|' /etc/default/grub
  sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/!b; /nvidia_drm.modeset/!s/"$/ nvidia_drm.modeset=1"/' /etc/default/grub || true
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
  echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf
  _installOrUpdatePacman nvidia-open-dkms
  _installOrUpdatePacman nvidia-utils
  _installOrUpdatePacman nvidia-settings
  _installOrUpdatePacman qt5-wayland
  _installOrUpdatePacman qt5ct
  _installOrUpdatePacman qt6-wayland
  _installOrUpdatePacman qt6ct
  _installOrUpdatePacman libva
  _installOrUpdateYay libva-nvidia-driver-git
  update_initramfs_config "/etc/mkinitcpio.conf" "/boot/initramfs-custom.img"
  ;;
4)
  print_subsection_header "Installing Virtualization Guest Drivers"
  echo -e "${COLOR_WHITE}Installing virtualization guest drivers (QEMU/virt & VMware)...${COLOR_RESET}"
  _installOrUpdatePacman qemu-guest-agent
  _installOrUpdatePacman spice-vdagent
  _installOrUpdatePacman xf86-video-qxl
  _installOrUpdatePacman mesa
  _installOrUpdateYay xf86-video-vmware
  _installOrUpdateYay open-vm-tools
  sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
  sudo systemctl enable --now spice-vdagentd 2>/dev/null || true
  sudo systemctl enable --now vmtoolsd 2>/dev/null || true
  ;;
*)
  print_subsection_header "Installing AMD Graphics Drivers (Default)"
  _installOrUpdatePacman xf86-video-amdgpu
  _installOrUpdatePacman mesa
  _installOrUpdatePacman vulkan-radeon
  _installOrUpdatePacman vdpauinfo
  _installOrUpdatePacman corectrl
  _installOrUpdatePacman libvdpau
  sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
  update_initramfs_config "/etc/mkinitcpio.conf" "/boot/initramfs-custom.img"
  ;;
esac

print_success_box "Graphics Card Drivers Installed"