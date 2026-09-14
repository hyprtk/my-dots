#!/bin/bash
# bslx distro steps — plasma removal with -Rcs, grub wallpaper copy,
# os-release to /usr/lib/ (no splash/bootctl), backs up existing hypr config.

pre_install() {
    . "$SCRIPT_DIR/installer/scripts/pkgmanager.sh"
    pkg_remove plasma-meta kde-applications-meta plasma kde-applications
}

grub_wallpaper() {
    sudo cp ~/.cache/current-wallpaper.png /boot/grub/current-wallpaper.png
}

pre_hypr_symlink() {
    [ -e ~/.config/hypr ] && mv ~/.config/hypr ~/.config/hypr-old
    return 0
}
