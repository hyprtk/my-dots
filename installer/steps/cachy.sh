#!/bin/bash
# cachy distro steps — os-release to /usr/lib/ plus systemd propagate paths,
# cachyos-branding hook, backs up existing hypr config.

install_os_release() {
    sudo cp ~/hyprtk/installer/os-release/os-release-$DISTRO /usr/lib/
    sudo cp ~/hyprtk/installer/os-release/os-release-$DISTRO /run/systemd/propagate/.os-release-stage/
    sudo cp ~/hyprtk/installer/os-release/os-release-$DISTRO /run/user/$UID/systemd/propagate/.os-release-stage/
    sudo cp ~/hyprtk/installer/os-release/cachyos-branding /usr/share/libalpm/scripts/
    sudo bash /usr/share/libalpm/scripts/cachyos-branding
}

pre_hypr_symlink() {
    [ -e ~/.config/hypr ] && mv ~/.config/hypr ~/.config/hypr-old
    return 0
}
