#!/bin/bash
#
#
#
# by hyprtk (Kori Tk) (2026)
# -----------------------------------------------------
# Full system upgrade, with an optional Timeshift snapshot first. Distro-aware:
# the upgrade command is chosen from the detected package manager. Timeshift
# and the GRUB-refresh hook are skipped when their binaries are absent.
. "$(dirname "${BASH_SOURCE[0]}")/library.sh"
clear

# ── Confirm start ──────────────────────────────────────────────────────────
while true; do
    read -p "DO YOU WANT TO START THE UPDATE NOW? (Yy/Nn): " yn
    case $yn in
        [Yy]* ) echo ""; break ;;
        [Nn]* ) exit ;;
        * ) echo "Please answer yes or no." ;;
    esac
done

# ── Optional Timeshift snapshot ────────────────────────────────────────────
if command -v timeshift >/dev/null 2>&1; then
    while true; do
        read -p "DO YOU WANT TO CREATE A SNAPSHOT? (Yy/Nn): " yn
        case $yn in
            [Yy]* )
                echo ""
                read -p "Enter a comment for the snapshot: " c
                hyprtk_run_root timeshift --create --comments "$c"
                hyprtk_run_root timeshift --list
                [ -x "$HOME/hyprtk/configs/sddm/update-TS-run.sh" ] && \
                    hyprtk_run_root "$HOME/hyprtk/configs/sddm/update-TS-run.sh"
                echo "DONE. Snapshot $c created!"
                echo ""
                break ;;
            [Nn]* ) break ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
fi

echo "-----------------------------------------------------"
echo "Start update ($HYPRTK_PM)"
echo "-----------------------------------------------------"
echo ""

case "$HYPRTK_PM" in
    pacman)
        if command -v yay >/dev/null 2>&1; then
            yay
        elif command -v paru >/dev/null 2>&1; then
            paru
        else
            hyprtk_run_root pacman -Syu
        fi
        ;;
    apt)    hyprtk_run_root apt-get update && hyprtk_run_root apt-get upgrade ;;
    dnf)    hyprtk_run_root dnf upgrade --refresh ;;
    zypper) hyprtk_run_root zypper --non-interactive update ;;
    xbps)   hyprtk_run_root xbps-install -Su ;;
    apk)    hyprtk_run_root apk update && hyprtk_run_root apk upgrade ;;
    emerge) hyprtk_run_root emerge --update --deep --newuse @world ;;
    nix)    echo "No imperative update for Nix — update your flake/profile manually." ;;
    *)      echo "No supported package manager found." ;;
esac

command -v notify-send >/dev/null 2>&1 && notify-send "Update complete"
echo ""
echo "Update complete."
