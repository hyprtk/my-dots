#!/bin/bash
# reborn distro steps — os-release to /usr/lib/ (no splash/bootctl),
# multiline sudoers, backs up existing hypr config.

pre_hypr_symlink() {
    [ -e ~/.config/hypr ] && mv ~/.config/hypr ~/.config/hypr-old
    return 0
}

setup_sudoers() {
    # Validated drop-in; never append to /etc/sudoers (a partial write there
    # can lock sudo out entirely).
    printf 'Defaults env_reset,pwfeedback\n' | sudo tee /etc/sudoers.d/99-hyprtk-reborn >/dev/null
    sudo chmod 440 /etc/sudoers.d/99-hyprtk-reborn
    sudo visudo -c >/dev/null 2>&1 || {
        echo "error: sudoers validation failed; removing invalid drop-in" >&2
        sudo rm -f /etc/sudoers.d/99-hyprtk-reborn
        exit 1
    }
}
