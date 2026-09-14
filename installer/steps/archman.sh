#!/bin/bash
# archman distro steps — os-release to /usr/lib/ (no splash/bootctl),
# backs up existing hypr config.

pre_hypr_symlink() {
    [ -e ~/.config/hypr ] && mv ~/.config/hypr ~/.config/hypr-old
    return 0
}
