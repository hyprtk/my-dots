# Hyprtk-On-Arch

Unified Hyprland & XFCE installer for 11 Arch-based distributions.

## Supported Distributions

- Arch Linux
- ArchBang
- ArchCraft
- ArchMan
- BSLx
- CachyOS
- EndeavourOS
- Garuda Linux
- Kiro
- Manjaro
- RebornOS

## Features

- **Auto-detection** of distribution and initramfs tool (dracut / mkinitcpio)
- **Interactive graphics driver selection**: Intel, AMD, Nvidia, or Virtualization
- **Professional ASCII headers** throughout
- **Install log** at `~/hyprtk-install-YYYYMMDD-HHMMSS.log` for debugging
- All package scripts inlined into a single `1-install.sh`

## Common Packages

- Terminal: alacritty / kitty / xfce4-terminal
- Editor: nvim / nano / micro
- Prompt: starship / ohmyposh
- Icons: Font Awesome / Papirus
- Menus: Rofi
- Colorscheme: pywal16 (dynamic)
- Browsers: chromium / brave
- Filemanager: Thunar
- Cursor: Bibata Modern Ice
- Virtual Machine: qemu/kvm, vmware workstation

## Getting Started

PLEASE BACKUP YOUR EXISTING ~/.config BEFORE STARTING.

```bash
git clone https://github.com/hyprtk/Hyprtk-On-Arch.git ~/hyprtk
cd ~/hyprtk
chmod +x 1-install.sh
./1-install.sh
```

## Installation Log

An install log is automatically created at `~/hyprtk-install-YYYYMMDD-HHMMSS.log`
to assist with debugging should any issues arise.

## Distro-Specific Files

Distribution-specific files (os-release, branding, splash, dracut/nvidia configs,
grub configs, scripts) are preserved in the `distro/` directory for reference
and installation use.
