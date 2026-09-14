#!/bin/bash
# hyprtk-pkglist
# ── sddm-check ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

if [ "${1:-}" = "--list" ]; then printf 'sddm\n'; exit 0; fi

bash "$_PKGDIR/../../installer/scripts/rm-dm-managers.sh"
echo ""
if [ ! -d /etc/sddm.conf.d/ ]; then
    hyprtk_run_root mkdir -p /etc/sddm.conf.d
    echo "Folder /etc/sddm.conf.d created."
fi
hyprtk_run_root cp "$_PKGDIR/../../configs/sddm/sddm.conf" /etc/sddm.conf.d/
echo "File /etc/sddm.conf.d/sddm.conf updated."
echo ""
