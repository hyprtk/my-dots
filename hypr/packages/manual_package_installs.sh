#!/bin/bash
# hyprtk-pkglist
# ── manual_package_installs ─────────────────────────────────────────────────────────
# The full default application set (browser, editor, media, file tools, …).
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(pacman-contrib alacritty kitty rofi chromium starship ranger neovim mpv
          freerdp xfce4-power-manager thunar mousepad awesome-terminal-fonts
          ttf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd vlc exa
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
    PKGS=(alacritty kitty rofi chromium starship ranger neovim mpv freerdp2-x11
          xfce4-power-manager thunar mousepad fonts-font-awesome fonts-fira-code vlc
          eza python3-pip python3-psutil python3-rich python3-click
          xdg-desktop-portal-gtk pavucontrol tumbler blueman sddm papirus-icon-theme
          btop network-manager network-manager-gnome git nano xdg-user-dirs
          xdg-user-dirs-gtk os-prober policykit-1-gnome gnome-keyring gvfs
          gvfs-backends ntfs-3g samba xfce4-terminal wf-recorder file-roller micro
          xclip pamixer xautolock gnome-disk-utility)
    ;;
dnf)
    PKGS=(alacritty kitty rofi chromium starship ranger neovim mpv freerdp
          xfce4-power-manager thunar mousepad fontawesome-fonts fira-code-fonts vlc
          eza python3-pip python3-psutil python3-rich python3-click
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
          ntfs-3g samba xfce4-terminal wf-recorder file-roller micro xclip pamixer
          xautolock gnome-disk-utility)
    ;;
xbps)
    PKGS=(alacritty kitty rofi chromium starship ranger neovim mpv freerdp
          xfce4-power-manager thunar mousepad font-awesome fira-code vlc eza
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
          xfce4-power-manager thunar mousepad font-awesome fira-code vlc eza
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
