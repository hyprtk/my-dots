#!/bin/bash
# Update swaylock config from pywal-generated template
# Template: wal/templates/colors-swaylock.conf

SWAYLOCK_CACHE="$HOME/.cache/wal/colors-swaylock.conf"
SWAYLOCK_LIVE="$HOME/hyprtk/swaylock/config"
SWAYLOCK_PROJECT="$HOME/Projects/hyprtk/swaylock/config"

[ -f "$SWAYLOCK_CACHE" ] || exit 1

cp "$SWAYLOCK_CACHE" "$SWAYLOCK_LIVE"
cp "$SWAYLOCK_LIVE" "$SWAYLOCK_PROJECT"
