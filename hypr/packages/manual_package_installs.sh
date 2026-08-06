#!/bin/bash
# Manual Package Installation Reference
# Complete list of all packages from hyprtk installer
# Use this file if you need to manually install packages

# ============================================================================
# PACMAN PACKAGES (Official Repository)
# ============================================================================

# Hyprland Core
sudo pacman -S --noconfirm \
    hyprland \
    xdg-desktop-portal-wlr \
    swayidle \
    swappy \
    cliphist \
    xorg-xhost \
    nwg-look \
    mission-center \
    curl \
    imagemagick \
    jq \
    bc \
    brightnessctl \
    playerctl \
    libadwaita \
    gtk-layer-shell \
    python \
    python-pip \
    python-virtualenv \
    python-gobject \
    gtk4 \
    wob

# XFCE4
sudo pacman -S --noconfirm \
    xfce4 \
    xfce4-goodies \
    parole

# File Tools
sudo pacman -S --noconfirm \
    thunar \
    mousepad

# Web Tools
sudo pacman -S --noconfirm \
    chromium

# Network
sudo pacman -S --noconfirm \
    networkmanager \
    network-manager-applet \
    git \
    freerdp \
    curl \
    gvfs \
    gvfs-afc \
    gvfs-dnssd \
    gvfs-goa \
    gvfs-gphoto2 \
    gvfs-mtp \
    gvfs-nfs \
    gvfs-onedrive \
    gvfs-smb \
    gvfs-wsdd \
    ntfs-3g \
    samba

# Media
sudo pacman -S --noconfirm \
    xclip \
    pamixer \
    wf-recorder \
    pavucontrol \
    tumbler \
    vlc \
    mpv \
    ffmpeg

# Terminal Tools
sudo pacman -S --noconfirm \
    eza \
    micro \
    xfce4-terminal \
    btop \
    alacritty \
    kitty \
    starship \
    ranger \
    nano \
    figlet \
    neovim

# System Tools
sudo pacman -S --noconfirm \
    timeshift \
    file-roller \
    gparted \
    xfce4-power-manager \
    rofi \
    dunst \
    cockpit

# System
sudo pacman -S --noconfirm \
    sddm \
    blueman \
    pacman-contrib \
    fzf \
    font-manager \
    awesome-terminal-fonts \
    ttf-font-awesome \
    ttf-fira-sans \
    ttf-fira-code \
    ttf-firacode-nerd \
    exa \
    python-pip \
    python-psutil \
    python-rich \
    python-click \
    xdg-desktop-portal-gtk \
    xdg-user-dirs \
    xdg-user-dirs-gtk \
    os-prober \
    polkit-gnome \
    gnome-keyring \
    pcp \
    pcp-gui \
    gtk4-layer-shell \
    hyprpicker

# Graphics (Intel)
sudo pacman -S --noconfirm \
    xf86-video-intel \
    mesa \
    vulkan-intel

# Graphics (AMD)
sudo pacman -S --noconfirm \
    xf86-video-amdgpu \
    mesa \
    vulkan-radeon \
    vdpauinfo \
    corectrl \
    libvdpau

# Graphics (Nvidia)
sudo pacman -S --noconfirm \
    nvidia-open-dkms \
    nvidia-utils \
    nvidia-settings \
    qt5-wayland \
    qt5ct \
    qt6-wayland \
    qt6ct \
    libva

# Graphics (Virtualization)
sudo pacman -S --noconfirm \
    qemu-guest-agent \
    spice-vdagent \
    xf86-video-qxl \
    mesa

# PCP PMDA packages
sudo pacman -S --noconfirm $(pacman -Ssq 'pcp-pmda-*')

# ============================================================================
# YAY PACKAGES (AUR)
# ============================================================================

# Hyprland
yay -S --noconfirm \
    awww \
    swaylock-effects \
    gvfs-afc \
    gvfs-goa \
    gvfs-gphoto2 \
    gvfs-mtp \
    gvfs-nfs \
    gvfs-smb \
    7zip \
    unzip \
    unrar \
    waybar-git

# XFCE4
yay -S --noconfirm \
    tumbler-extra-thumbnailers

# File Tools
yay -S --noconfirm \
    thunar-shares-plugin

# Web Tools
yay -S --noconfirm \
    brave-bin \
    github-desktop-bin

# Printers
yay -S --noconfirm \
    cups \
    cups-pdf \
    cups-filters \
    nss-mdns \
    system-config-printer \
    cups-browsed \
    libusb \
    ipp-usb \
    xdg-utils \
    colord \
    logrotate

# Media
yay -S --noconfirm \
    hyprquickframe-git

# Terminal Tools
yay -S --noconfirm \
    fastfetch

# System Tools
yay -S --noconfirm \
    gnome-disk-utility

# System
yay -S --noconfirm \
    bibata-cursor-theme \
    trizen \
    sublime-text-4 \
    sddm-theme-sugar-candy-git \
    pacseek

# 3D Printing
yay -S --noconfirm \
    orca-slicer-bin \
    bambustudio-bin

# Graphics (Nvidia)
yay -S --noconfirm \
    libva-nvidia-driver-git

# Graphics (Virtualization)
yay -S --noconfirm \
    xf86-video-vmware \
    open-vm-tools

# ============================================================================
# SPECIAL PACKAGES (Manual Install Required)
# ============================================================================

# HyprViz (AUR - manual git clone)
# cd ~/Downloads/yay-git/src/
# git clone https://aur.archlinux.org/hyprviz-bin.git
# cd hyprviz-bin
# makepkg -si

# ============================================================================
# PACKAGE COUNT SUMMARY
# ============================================================================
# Total Pacman Packages: ~95
# Total Yay Packages: ~35
# Total Packages: ~130
