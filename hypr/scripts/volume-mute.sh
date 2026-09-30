#!/bin/bash
wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
echo 0 > "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wobpipe"
