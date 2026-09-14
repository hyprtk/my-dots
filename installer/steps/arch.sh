#!/bin/bash
# arch distro steps — base behavior with the full boot pipeline:
# splash to bootctl + mkinitcpio (os-release to /usr/lib/ is the default fallback).

install_boot() {
    sudo cp ~/hyprtk/assets/splash/splash-arch.bmp /usr/share/systemd/bootctl/
    sudo mkinitcpio -P
}
