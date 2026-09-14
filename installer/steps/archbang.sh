#!/bin/bash
# archbang distro steps — removes swaylock, installs os-release to /etc/,
# no splash/bootctl step, backs up existing hypr config.

pre_install() {
    . "$SCRIPT_DIR/installer/scripts/pkgmanager.sh"
    pkg_remove plasma-meta kde-applications-meta plasma kde-applications swaylock
}

install_os_release() {
    sudo cp ~/hyprtk/installer/os-release/os-release-$DISTRO /etc/
}

pre_hypr_symlink() {
    [ -e ~/.config/hypr ] && mv ~/.config/hypr ~/.config/hypr-old
    return 0
}
