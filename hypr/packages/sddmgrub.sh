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
hyprtk_run_root cp ~/.cache/current-wallpaper.png /usr/share/sddm/themes/Sugar-Candy/Backgrounds/ 2>/dev/null || true
echo "Current wallpaper copied into sddm theme folder"
echo ""
echo ""
hyprtk_run_root cp "$_PKGDIR/../../configs/sddm/theme.conf" /usr/share/sddm/themes/Sugar-Candy/ 2>/dev/null || true
echo "File theme.conf updated in /usr/share/sddm/themes/Sugar-Candy/"
echo ""
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
