#/bin/bash

# Get the currently running kernel version
KERNEL_VERSION=$(uname -r)

echo "
#########################################################
#                                                       #
#            Which Graphics Card do you have?           #
#                                                       #
#########################################################

1) Intel
2) AMD
3) Nvidia
Defaults to AMD if you choose
something else
"
echo ""
read GRAPHICSCARD

case $GRAPHICSCARD in
1)
  echo "Installing Intel Drivers..."
  sudo pacman -S --noconfirm xf86-video-intel mesa vulkan-intel
  ;;
2|*)
  echo "Installing AMD Drivers..."
  sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
  sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
  sudo mkinitcpio -k "$KERNEL_VERSION" -g /boot/initramfs-linux.img
  ;;
3)
  echo "Installing Nvidia Drivers..."
  # Update GRUB for Kernel Mode Setting (KMS)
  sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"/' /etc/default/grub
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  
  # Add modules to mkinitcpio
  sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
  echo "options nvidia-drm modeset=1" | sudo tee /etc/modprobe.d/nvidia.conf
  
  # Install packages
  sudo pacman -S --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
  
  # Generate initramfs for the specific detected kernel
  sudo mkinitcpio -p "$KERNEL_VERSION" -g /boot/initramfs-linux.img
  ;;
esac

echo ""
#clear
echo "
#########################################################
#                                                       #
#    Graphics for Kernel $KERNEL_VERSION installed      #
#                                                       #
#########################################################
"