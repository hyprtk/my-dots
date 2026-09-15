#!/bin/bash
# ── sddmgrub ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

echo ""
echo " Configure sddm theme "
echo ""
if [ ! -d /etc/sddm.conf.d/ ]; then
    hyprtk_run_root mkdir -p /etc/sddm.conf.d
    echo "Folder /etc/sddm.conf.d created."
fi
echo ""
hyprtk_run_root cp "$_PKGDIR/../../configs/sddm/sddm.conf" /etc/sddm.conf.d/
echo "File /etc/sddm.conf.d/sddm.conf updated."
echo ""
cp "$_PKGDIR/../../default.png" ~/.cache/current-wallpaper.png
echo ""
# Sugar-Candy is AUR-only (sddm-theme-sugar-candy-git); non-Arch installs have
# no theme for sddm.conf's Current=Sugar-Candy. SDDM falls back to its embedded
# theme, so this is cosmetic — try upstream once, non-fatal.
SUGAR_THEME=/usr/share/sddm/themes/Sugar-Candy
if [ ! -d "$SUGAR_THEME" ] && command -v git >/dev/null 2>&1; then
    _tmp="$(mktemp -d)"
    if git clone --depth=1 https://framagit.org/MarianArlt/sddm-sugar-candy "$_tmp/Sugar-Candy" >/dev/null 2>&1; then
        hyprtk_run_root mkdir -p /usr/share/sddm/themes
        hyprtk_run_root cp -r "$_tmp/Sugar-Candy" "$SUGAR_THEME"
        echo "Installed the Sugar-Candy SDDM theme from upstream"
    fi
    rm -rf "$_tmp"
fi
if [ -d "$SUGAR_THEME" ]; then
    hyprtk_run_root cp ~/.cache/current-wallpaper.png "$SUGAR_THEME/Backgrounds/" 2>/dev/null || true
    hyprtk_run_root cp "$_PKGDIR/../../configs/sddm/theme.conf" "$SUGAR_THEME/" 2>/dev/null || true
    echo "Sugar-Candy theme assets updated."
else
    echo "Sugar-Candy theme not installed — SDDM will use its built-in theme."
fi
echo ""
hyprtk_run_root cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png 2>/dev/null || true
echo ""
echo " Configure grub theme "
echo ""
# Only touch GRUB when this machine actually boots GRUB; never wipe
# /usr/share/grub/themes (dropping GRUB_THEME makes GRUB_BACKGROUND apply).
if command -v grub-mkconfig >/dev/null 2>&1 && [ -f /boot/grub/grub.cfg ]; then
    echo " Enable OS-Prober "
    hyprtk_run_root sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    echo ""
    hyprtk_run_root sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
    hyprtk_run_root sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub
    hyprtk_run_root sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub
    hyprtk_run_root sed -i '/^GRUB_THEME=/d' /etc/default/grub
    echo ""
    echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"' | hyprtk_run_root tee -a /etc/default/grub >/dev/null
    echo -e 'GRUB_COLOR_NORMAL="white/black"' | hyprtk_run_root tee -a /etc/default/grub >/dev/null
    echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' | hyprtk_run_root tee -a /etc/default/grub >/dev/null
    echo ""
    hyprtk_run_root grub-mkconfig -o /boot/grub/grub.cfg
    echo ""
    echo " Disable OS-Prober "
    hyprtk_run_root sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    echo ""
    echo " GRUB & SDDM Updated with current wallpaper "
else
    echo " GRUB not detected (no grub-mkconfig / boot/grub/grub.cfg) - skipping GRUB steps "
fi
