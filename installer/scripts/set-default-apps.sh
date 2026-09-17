#!/bin/bash
# ── Register the suite's preferred apps with XDG ─────────────────────────────
# The dotfiles install alacritty, thunar and brave, but a fresh distro still
# points XDG at its own defaults (seen on Fedora: kitty as the inode/directory
# handler, firefox as the browser). hyprtk-bar's quick links resolve the
# "System default" apps from exactly those settings, so without this they show
# the distro's apps instead of the suite's. User-level; best-effort.
#
# The session terminal is $TERMINAL, set in hypr/environment.lua.
set -u

if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default thunar.desktop inode/directory 2>/dev/null || true
fi

if command -v xdg-settings >/dev/null 2>&1; then
    for d in brave-browser.desktop brave.desktop; do
        if [ -f "/usr/share/applications/$d" ]; then
            xdg-settings set default-web-browser "$d" 2>/dev/null || true
            break
        fi
    done
fi

echo "preferred apps registered (file manager: thunar; browser: brave if present)"
