#!/bin/bash
# installupdates.sh — apply system package updates from the bar's updates module.
#
# Distro-agnostic: detects the package manager and runs the matching full
# upgrade interactively in the terminal the bar opens it in (the bar's default
# is `alacritty -e <this script>`). Self-contained — no hyprtk dotfiles
# dependency (no library.sh, no yay/timeshift/btrfs assumptions).

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · updates
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

# The bar launches us detached (no tty). Re-launch ourselves inside the first
# terminal emulator we can find, so the interactive upgrade has a prompt and
# stays open for the trailing "Press Enter to close." read.
#
# The window is tagged app-id/class "hyprtk-updates" and title "Hyprtk Updates"
# so Hyprland (see the hyprtk dotfiles' hypr/windowrules.lua) floats it instead
# of tiling it full-screen.
if [ ! -t 0 ]; then
    upd_app="hyprtk-updates"
    upd_title="Hyprtk Updates"
    if command -v alacritty >/dev/null 2>&1; then
        exec alacritty --class "$upd_app" -T "$upd_title" -e "$0"
    elif command -v kitty >/dev/null 2>&1; then
        exec kitty --class="$upd_app" -T "$upd_title" "$0"
    elif command -v foot >/dev/null 2>&1; then
        exec foot --app-id="$upd_app" -T "$upd_title" "$0"
    elif command -v wezterm >/dev/null 2>&1; then
        exec wezterm start --class "$upd_app" -- "$0"
    elif command -v xfce4-terminal >/dev/null 2>&1; then
        exec xfce4-terminal --class="$upd_app" -T "$upd_title" --command "$0"
    elif command -v gnome-terminal >/dev/null 2>&1; then
        exec gnome-terminal --class="$upd_app" --title "$upd_title" -- "$0"
    elif command -v konsole >/dev/null 2>&1; then
        exec konsole -p tabtitle="$upd_title" -e "$0"
    elif command -v terminator >/dev/null 2>&1; then
        exec terminator -T "$upd_title" -e "$0"
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        exec x-terminal-emulator -T "$upd_title" -e "$0"
    elif command -v xterm >/dev/null 2>&1; then
        exec xterm -T "$upd_title" -e "$0"
    else
        echo "No terminal emulator found to run the update in." >&2
        echo "Install one (e.g. alacritty, kitty, foot) or run this manually:" >&2
        echo "  $0" >&2
        exit 1
    fi
fi

detect_pm() {
    command -v pacman       >/dev/null 2>&1 && { echo pacman; return; }
    command -v apt-get      >/dev/null 2>&1 && { echo apt;    return; }
    command -v dnf          >/dev/null 2>&1 && { echo dnf;    return; }
    command -v zypper       >/dev/null 2>&1 && { echo zypper; return; }
    command -v xbps-install >/dev/null 2>&1 && { echo xbps;   return; }
    command -v apk          >/dev/null 2>&1 && { echo apk;    return; }
    command -v emerge       >/dev/null 2>&1 && { echo emerge; return; }
    command -v nix          >/dev/null 2>&1 && { echo nix;    return; }
    echo none
}

PM="$(detect_pm)"
echo "Updating system packages ($PM) ..."
echo

case "$PM" in
    pacman)
        if command -v yay >/dev/null 2>&1; then
            yay
        elif command -v paru >/dev/null 2>&1; then
            paru
        else
            sudo pacman -Syu
        fi
        ;;
    apt)
        sudo apt-get update && sudo apt-get upgrade
        ;;
    dnf)
        sudo dnf upgrade --refresh
        ;;
    zypper)
        sudo zypper --non-interactive update
        ;;
    xbps)
        sudo xbps-install -Su
        ;;
    apk)
        sudo apk update && sudo apk upgrade
        ;;
    emerge)
        sudo emerge --update --deep --newuse @world
        ;;
    nix)
        echo "No package-manager update flow for Nix — update your flake/profile manually."
        ;;
    *)
        echo "No supported package manager found."
        ;;
esac

echo
echo "Update complete."
echo "Press Enter to close."
read -r _
