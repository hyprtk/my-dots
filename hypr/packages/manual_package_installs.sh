#!/bin/bash
# ── manual_package_installs ─────────────────────────────────────────────────
# MANUAL-ONLY helper. This file is intentionally NOT part of 1-install.sh and
# must never be run by it on any distribution — it exists so a user can install
# extra/optional applications on top of the base install by running it by hand.
#
# Because of that it is also excluded from the package audit/matrix tooling
# (installer/scripts/verify/package-audit.sh, container-matrix.sh) and carries
# no `hyprtk-pkglist` marker, so it never contributes to the installer surface.
# The full default application set (browser, editor, media, file tools, …).
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(pacman-contrib alacritty kitty rofi chromium starship ranger neovim mpv
          freerdp xfce4-power-manager thunar mousepad awesome-terminal-fonts
          otf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd vlc eza
          python-pip python-psutil python-rich python-click xdg-desktop-portal-gtk
          pavucontrol tumbler blueman sddm papirus-icon-theme btop networkmanager
          network-manager-applet git nano xdg-user-dirs xdg-user-dirs-gtk os-prober
          polkit-gnome gnome-keyring gvfs ntfs-3g samba xfce4-terminal wf-recorder
          file-roller micro xclip pamixer xautolock)
    AUR=(brave-bin pfetch bibata-cursor-theme trizen sddm-theme-sugar-candy-git
         sddm-sugar-candy-git gnome-disk-utility thunar-shares-plugin sublime-text-4
         pacseek github-desktop-bin waypaper nitrogen)
    ;;
apt)
    PKGS=(alacritty kitty rofi chromium starship ranger neovim mpv freerdp3-x11
          xfce4-power-manager thunar mousepad fonts-font-awesome fonts-firacode vlc
          eza python3-pip python3-psutil python3-rich python3-click
          xdg-desktop-portal-gtk pavucontrol tumbler blueman sddm papirus-icon-theme
          btop network-manager network-manager-gnome git nano xdg-user-dirs
          xdg-user-dirs-gtk os-prober policykit-1-gnome gnome-keyring gvfs
          gvfs-backends ntfs-3g samba xfce4-terminal wf-recorder file-roller micro
          xclip pamixer xautolock gnome-disk-utility)
    ;;
dnf)
    PKGS=(alacritty kitty rofi chromium starship ranger neovim mpv freerdp
          xfce4-power-manager Thunar mousepad fontawesome-fonts-all fira-code-fonts
          vlc eza python3-pip python3-psutil python3-rich python3-click
          xdg-desktop-portal-gtk pavucontrol tumbler blueman sddm papirus-icon-theme
          btop NetworkManager network-manager-applet git nano xdg-user-dirs
          xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring gvfs gvfs-afc
          gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb ntfs-3g samba
          xfce4-terminal wf-recorder file-roller micro xclip pamixer xautolock
          gnome-disk-utility)
    ;;
zypper)
    PKGS=(alacritty kitty rofi chromium starship ranger neovim mpv freerdp
          xfce4-power-manager thunar mousepad fontawesome-fonts fira-code-fonts vlc
          eza python3-pip python3-psutil python3-rich python3-click
          xdg-desktop-portal-gtk pavucontrol tumbler blueman sddm papirus-icon-theme
          btop NetworkManager NetworkManager-applet git nano xdg-user-dirs
          xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring gvfs gvfs-backends
          ntfs-3g samba xfce4-terminal wf-recorder file-roller micro-editor xclip
          pamixer xautolock gnome-disk-utility)
    ;;
xbps)
    PKGS=(alacritty kitty rofi chromium starship ranger neovim mpv freerdp
          xfce4-power-manager Thunar mousepad font-awesome font-firacode vlc eza
          python3-pip python3-psutil python3-rich python3-click
          xdg-desktop-portal-gtk pavucontrol tumbler blueman sddm papirus-icon-theme
          btop NetworkManager network-manager-applet git nano xdg-user-dirs
          xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring gvfs gvfs-afc
          gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb ntfs-3g samba
          xfce4-terminal wf-recorder file-roller micro xclip pamixer xautolock
          gnome-disk-utility)
    ;;
apk)
    PKGS=(alacritty kitty rofi chromium starship ranger neovim mpv freerdp
          xfce4-power-manager thunar mousepad font-awesome font-fira-code-nerd vlc eza
          py3-pip py3-psutil py3-rich py3-click xdg-desktop-portal-gtk pavucontrol
          tumbler blueman sddm papirus-icon-theme btop networkmanager
          network-manager-applet git nano xdg-user-dirs xdg-user-dirs-gtk os-prober
          polkit-gnome gnome-keyring gvfs ntfs-3g samba xfce4-terminal wf-recorder
          file-roller micro xclip pamixer xautolock gnome-disk-utility)
    ;;
esac

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
