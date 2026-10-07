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

- Status Bar: hyprtk-bar
- Screenshots: grim & slurp
- Clipboard Manager: cliphist
- Logout: hyprlogout
- Screenlock: hyprlock (swaylock-effects fallback)
- Screen Capture: wf-recorder
- Settings: hyprmod

## Templating

Hyprland: Included is a pywal16 configuration that changes the color scheme based on a randomly selected wallpaper. 

	Keybinding SuperKey + Shift + w you can change the wallpaper.

	Keybinding SuperKey + Ctrl + w opens rofi with a list of installed wallpapers.

	Keybinding SuperKey + w opens matuwall to display all wallpapers on a film roll (Editable)

See also the .zshrc and the key bindings on Hyprland and XFCE for more alias definitions.

System theming (wallpaper, pywal, rofi, icons, lock screen, SDDM/GRUB) now lives in **hyprtk-bar**'s Theme Manager, opened from the wallpaper glyph in the bar. Bar themes ship with the bar; import or add your own from the Theme Manager's **Bar Themes** page.

## Getting started

To make it easy for you to get started with my garuda-dots, here's a list of recommended next steps.

PLEASE BACKUP YOUR EXISTING .config WITH YOUR DOTFILES BEFORE STARTING THE SCRIPTS.


# Make sure that you're in your home directory

	git clone https://github.com/hyprtk/dotfiles.git ~/hyprtk
	cd ~/hyprtk
	sh ./1-install.sh

#Please note that every Arch Linux system is different and I cannot guarantee that everything works fine on your system.

## Screenshots & Video

Manjaro Linux
![Model](https://raw.githubusercontent.com/hyprtk/dotfiles/main/assets/screenshots/manjaro1.png)
![Model](https://raw.githubusercontent.com/hyprtk/dotfiles/main/assets/screenshots/manjaro2.png)
![Model](https://raw.githubusercontent.com/hyprtk/dotfiles/main/assets/screenshots/manjaro3.png)
