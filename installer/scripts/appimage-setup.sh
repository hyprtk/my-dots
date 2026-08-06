#!/bin/bash
# ── AppImage Launcher Setup ───────────────────────────
echo ""
sudo pacman -S fuse
sudo modprobe fuse
echo ""
sudo pacman -S git base-devel
git clone https://aur.archlinux.org/trizen.git ~/.cache/yay
cd trizen/
makepkg -sri
trizen -S appimagelauncher
