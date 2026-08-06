# Hyprland Dots

This is the configuration for Arch Linux, Arcolinux, Garuda, Manjaro based installations of Hyprland (Wayland) and/or XFCE (Xorg).

This will work on most flavours of Arch.


## Common Packages

- Terminal: alacritty
- Editor: nvim/ nano
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

- Status Bar: waybar
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

The templates are available in ~/hyprtk/configs/waybar/themes. You can add your own personal themes into this folder. The script will read in the folder structure.

## Getting started

To make it easy for you to get started with my dotfiles, here's a list of recommended next steps.

PLEASE BACKUP YOUR EXISTING .config WITH YOUR DOTFILES BEFORE STARTING THE SCRIPTS.


# Make sure that you're in your home directory

	git clone https://github.com/hyprtk/dotfiles.git ~/hyprtk
	cd ~/hyprtk
	sh ./1-install.sh

#Please note that every Arch Linux system is different and I cannot guarantee that everything works fine on your system.
## Screenshots & Video

Arch Linux
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/arch1.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/arch2.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/arch3.png)

ArchBANG Linux
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archbang1.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archbang2.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archbang3.png)

Archcraft Linux
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archcraft1.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archcraft2.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archcraft3.png)

Archman Linux
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archman1.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archman2.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archman3.png)

BlueStar Linux
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/bslx1.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/bslx2.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/bslx3.png)

CachyOS
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/cachy1.png)
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/cachy2.png)
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/cachy3.png)

EndeavourOS
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/endeavour1.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/endeavour2.png)
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/endeavour3.png)

Garuda
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/garuda1.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/garuda2.png)
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/garuda3.png)

Kiro Linux
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/kiro1.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/kiro2.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/kiro3.png)

Manjaro Linux
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/manjaro1.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/manjaro2.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/manjaro3.png)

RebornOS
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/reborn1.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/reborn2.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/reborn3.png)

## My Personal Dots - Dev Dots

Arch Linux
![MODEL](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/mydots1.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/mydots2.png)
![Model](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/mydots3.png)
