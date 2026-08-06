#!/bin/bash
wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
if wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED; then
    echo 0 > /tmp/wobpipe
else
    wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2*100)}' > /tmp/wobpipe
fi
