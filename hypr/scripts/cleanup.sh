#!/bin/bash
# ===================================================================
# Cleanup — Temporary file and cache cleaner
# ===================================================================

yay -Scc
su -c 'pacman -Qtdq | pacman -Rns -'
su -c 'pacman -Qqd | pacman -Rsu -'

