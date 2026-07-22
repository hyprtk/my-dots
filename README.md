# Hyprtk-On-Arch

Unified Hyprland + XFCE dotfiles for 11 Arch-based distributions:

Arch Linux · ArchBang · ArchCraft · Archman · BSLX · CachyOS · EndeavourOS · Garuda · Kiro · Manjaro · RebornOS

This will work on most flavours of Arch.

## Common Packages

- Terminal: alacritty
- Editor: nvim / nano
- Prompt: starship
- Icons: Font Awesome
- Menus: Rofi
- Colorscheme: pywal16 (dynamic)
- Browsers: chromium (brave optional)
- Filemanager: Thunar
- Cursor: Bibata Modern Ice
- Icons: Papirus-Icon-Theme
- Virtual Machine: qemu/kvm, vmware workstation, winboat

## Hyprland

- Status Bar: waybar (multiple themes)
- Screenshots: grim & slurp
- Clipboard Manager: cliphist
- Logout: hyprlogout
- Screenlock: swaylock-effects
- Screen Capture: wf-recorder

## Templating

Hyprland: Included is a pywal16 configuration that changes the color scheme based on a randomly selected wallpaper.

	Keybinding SuperKey + Shift + w you can change the wallpaper.
	Keybinding SuperKey + Ctrl + w opens rofi with a list of installed wallpapers.
	Keybinding SuperKey + w opens matuwall to display all wallpapers on a film roll (Editable)

See also the .zshrc and the key bindings on Hyprland and XFCE for more alias definitions.

Hyprland: In addition, you can switch the Waybar Template

	Keybinding SUPER + CTRL + T or by pressing the _ icon under the picture icon in waybar.

The templates are available in common/waybar/themes. You can add your own personal themes into this folder. The script will read in the folder structure.

## Getting started

PLEASE BACKUP YOUR EXISTING .config WITH YOUR DOTFILES BEFORE STARTING THE SCRIPTS.

	git clone https://github.com/hyprtk/Hyprtk-On-Arch.git ~/hyprtk
	cd ~/hyprtk
	sh ./1-install.sh

Please note that every Arch Linux system is different and I cannot guarantee that everything works fine on your system.

## Project Structure

```
Hyprtk-On-Arch/
├── 1-install.sh           # Unified installer
├── common/                # Shared configs (all apps)
├── distro/                # Per-distribution files
│   ├── os-release/        # OS release files for all 11 distros
│   ├── dracut/            # Dracut configs
│   ├── nvidia/            # Nvidia configs
│   ├── grub/              # GRUB configs
│   ├── splash/            # Splash screen
│   └── root/              # Root user config overrides
├── hypr/                  # Hyprland configs
├── scripts/               # Installer & utility scripts
├── common/Wallpapers/
└── common/screenshots/
```
