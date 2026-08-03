#!/bin/bash
#   ██████   ██ ██         ██      ██           ██
#  ██░░░░██ ░██░░  ██████ ░██     ░░           ░██
# ██    ░░  ░██ ██░██░░░██░██      ██  ██████ ██████
#░██        ░██░██░██  ░██░██████ ░██ ██░░░░ ░░░██░
#░██        ░██░██░██████ ░██░░░██░██░░█████   ░██
#░░██    ██ ░██░██░██░░░  ░██  ░██░██ ░░░░░██  ░██
# ░░██████  ███░██░██     ░██  ░██░██ ██████   ░░██
#  ░░░░░░  ░░░ ░░ ░░      ░░   ░░ ░░ ░░░░░░     ░░
#
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

case $1 in
    d) cliphist list | rofi -dmenu -config ~/hyprtk/configs/rofi/config-cliphist.rasi | cliphist delete
       ;;

    w) if [ `echo -e "Clear\nCancel" | rofi -dmenu -config ~/hyprtk/configs/rofi/config-short.rasi` == "Clear" ] ; then
            cliphist wipe
       fi
       ;;

    *) cliphist list | rofi -dmenu -config ~/hyprtk/configs/rofi/config-cliphist.rasi | cliphist decode | wl-copy
       ;;
esac
