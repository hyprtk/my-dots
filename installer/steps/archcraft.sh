#!/bin/bash
# archcraft distro steps — os-release to /usr/lib/ (no splash/bootctl),
# wal re-init from the cached current wallpaper instead of default.png.

pre_hypr_symlink() {
    [ -e ~/.config/hypr ] && mv ~/.config/hypr ~/.config/hypr-old
    return 0
}

wal_init() {
    wal -i ~/.cache/current-wallpaper.png
}
