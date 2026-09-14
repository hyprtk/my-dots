#!/bin/bash
# kiro distro steps — removes xfce4 + sddm-git + fastfetch-git,
# os-release to /usr/lib/ (no splash/bootctl), backs up existing hypr config.
# grudupdater.sh is NOT shipped in any source tree — omitted (guarded no-op).

pre_install() {
    . "$SCRIPT_DIR/installer/scripts/pkgmanager.sh"
    pkg_remove plasma-meta kde-applications-meta plasma kde-applications \
               xfce4 xfce4-goodies thunar catfish thunar-shares-plugin \
               sddm-git fastfetch-git
    sleep 5
}

pre_hypr_symlink() {
    [ -e ~/.config/hypr ] && mv ~/.config/hypr ~/.config/hypr-old
    return 0
}

grudupdater() {
    # Kiro's original installer ran a grub updater here, but that script has no
    # source in any of the 11 distro trees. Skipped by design.
    :
}
