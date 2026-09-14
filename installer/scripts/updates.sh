#!/bin/sh
#
#
# by hyprtk (Kori Tk) (2026)
# -----------------------------------------------------
# Pending-update count, distro-agnostic. Detects the package manager and emits
# the waybar-style JSON the hyprtk-bar updates module reads. Every query is
# read-only (no sudo, no index/cache writes), so it is safe on a timer.
#
# Output contract: {"text": "<n>", "alt": "<n>", "tooltip": "<n> Updates", "class": "green|yellow|red"}
# -----------------------------------------------------

thresh_yellow=25
thresh_red=100

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

pending_count() {
    case "$1" in
        pacman)
            arch=0; aur=0
            command -v checkupdates >/dev/null 2>&1 && \
                arch=$(checkupdates 2>/dev/null | wc -l)
            if command -v yay >/dev/null 2>&1; then
                aur=$(yay -Qua 2>/dev/null | wc -l)
            elif command -v paru >/dev/null 2>&1; then
                aur=$(paru -Qua 2>/dev/null | wc -l)
            fi
            echo $((arch + aur))
            ;;
        apt)    apt-get -s upgrade 2>/dev/null | grep -c '^Inst ' ;;
        dnf)    dnf -q check-update 2>/dev/null | grep -Ec '\.[a-zA-Z0-9_]+$' ;;
        zypper) zypper -n list-updates 2>/dev/null | grep -Ec '^\s*[vp]\s+\|' ;;
        xbps)   xbps-install -Sun 2>/dev/null | grep -c ' update ' ;;
        apk)    apk list --upgradeable 2>/dev/null | wc -l ;;
        emerge) emerge --pretend --update --deep --newuse @world 2>/dev/null | grep -c 'ebuild' ;;
        nix)    echo 0 ;;
        *)      echo 0 ;;
    esac
}

PM="$(detect_pm)"
updates="$(pending_count "$PM" | tr -dc '0-9')"
[ -n "$updates" ] || updates=0

css_class="green"
[ "$updates" -gt "$thresh_yellow" ] && css_class="yellow"
[ "$updates" -gt "$thresh_red" ] && css_class="red"

if [ "$updates" -gt 0 ]; then
    printf '{"text": "%s", "alt": "%s", "tooltip": "%s Updates", "class": "%s"}\n' \
        "$updates" "$updates" "$updates" "$css_class"
else
    printf '{"text": "0", "alt": "0", "tooltip": "0 Updates", "class": "green"}\n'
fi
