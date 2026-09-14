#!/bin/bash
# updates.sh — pending-package-update count for the hyprtk-bar updates module.
#
# Distro-agnostic: detects the package manager and counts pending updates,
# emitting the waybar-style JSON the module reads. Safe to run on a timer —
# every check is a read-only query (no sudo, no index/cache writes).
#
# Output contract (read by src/hyprtk_bar/updates.py):
#   {"text": "<count>", "alt": "<count>", "tooltip": "<count> Updates", "class": "green|yellow|red"}

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · updates
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

thresh_yellow=25
thresh_red=100

# Detect the package manager (mirrors install.sh's detection order).
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

# Count pending updates per package manager (read-only, no sudo).
pending_count() {
    case "$1" in
        pacman)
            local arch=0 aur=0
            command -v checkupdates >/dev/null 2>&1 && \
                arch=$(checkupdates 2>/dev/null | wc -l)
            if command -v yay >/dev/null 2>&1; then
                aur=$(yay -Qua 2>/dev/null | wc -l)
            elif command -v paru >/dev/null 2>&1; then
                aur=$(paru -Qua 2>/dev/null | wc -l)
            fi
            echo $((arch + aur))
            ;;
        apt)
            # Dry-run upgrade (no root): each candidate is an "Inst <pkg> ..." line.
            apt-get -s upgrade 2>/dev/null | grep -c '^Inst '
            ;;
        dnf)
            # check-update lists one NEVRA per line below the header block;
            # count lines ending in a package arch (name-…-release.arch).
            dnf -q check-update 2>/dev/null | grep -Ec '\.[a-zA-Z0-9_]+$'
            ;;
        zypper)
            # list-updates rows start with a status letter (v|p) then '|'.
            zypper -n list-updates 2>/dev/null | grep -Ec '^\s*[vp]\s+\|'
            ;;
        xbps)
            # -S refreshes the index, -u lists, -n dry-runs (no root needed).
            xbps-install -Sun 2>/dev/null | grep -c ' update '
            ;;
        apk)
            apk list --upgradeable 2>/dev/null | wc -l
            ;;
        emerge)
            emerge --pretend --update --deep --newuse @world 2>/dev/null | grep -c 'ebuild'
            ;;
        nix)
            # No conventional "pending updates" count for Nix.
            echo 0
            ;;
        *)
            echo 0
            ;;
    esac
}

PM="$(detect_pm)"
updates="$(pending_count "$PM" | tr -dc '0-9')"
[ -n "$updates" ] || updates=0

css_class="green"
[ "$updates" -gt "$thresh_yellow" ] && css_class="yellow"
[ "$updates" -gt "$thresh_red" ] && css_class="red"

printf '{"text": "%s", "alt": "%s", "tooltip": "%s Updates", "class": "%s"}\n' \
    "$updates" "$updates" "$updates" "$css_class"
