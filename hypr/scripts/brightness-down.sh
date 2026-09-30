#!/bin/bash
brightnessctl -e4 -n2 set 5%-
brightness=$(brightnessctl get)
max=$(brightnessctl max)
percent=$((brightness * 100 / max))
echo $percent > "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wobpipe"
