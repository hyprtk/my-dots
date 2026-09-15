#!/bin/bash
#
#
#
# by hyprtk (Kori Tk) (2026)
# -----------------------------------------------------
# Install SDDM and disable any other display manager. Multi-distro: the SDDM
# package is installed through pkgmanager.sh; the systemctl disables are
# best-effort (units simply may not exist).
. "$(dirname "${BASH_SOURCE[0]}")/pkgmanager.sh"

# Install SDDM if not already installed
pkg_install sddm
echo ""
echo " Removing lightdm "
# Disable LightDM (and its Plymouth service if present)
hyprtk_run_root systemctl disable lightdm 2>/dev/null
hyprtk_run_root systemctl disable lightdm-plymouth 2>/dev/null
echo ""
echo " Removing gdm "
echo ""
hyprtk_run_root systemctl disable gdm 2>/dev/null
hyprtk_run_root systemctl disable gdm-plymouth 2>/dev/null
echo ""
echo " Removing lxdm "
echo ""
hyprtk_run_root systemctl disable lxdm 2>/dev/null
hyprtk_run_root systemctl disable lxdm-plymouth 2>/dev/null
echo ""
echo " Removing slim "
echo ""
hyprtk_run_root systemctl disable slim 2>/dev/null
hyprtk_run_root systemctl disable slim-plymouth 2>/dev/null
echo ""
echo " Removing kdm "
echo ""
hyprtk_run_root systemctl disable kdm 2>/dev/null
hyprtk_run_root systemctl disable kdm-plymouth 2>/dev/null
echo ""
echo " Removing ly "
echo ""
hyprtk_run_root systemctl disable ly 2>/dev/null
hyprtk_run_root systemctl disable ly-plymouth 2>/dev/null
echo ""
echo " Enabling sddm "
echo ""
hyprtk_run_root systemctl enable sddm 2>/dev/null

echo ""
# Optional: Force symlink replacement if needed (e.g., on EndeavourOS)
hyprtk_run_root systemctl enable sddm --force 2>/dev/null

# Debian/Ubuntu ship an sddm.service with an ExecStartPre that requires
# /etc/X11/default-display-manager to name sddm; a leftover lightdm entry (or a
# missing file) makes the unit fail on every start and no greeter appears. Arch
# has no such check, so this is a no-op there. See PORTABILITY.md.
if [ "$HYPRTK_PM" = apt ]; then
    hyprtk_run_root mkdir -p /etc/X11
    if command -v update-alternatives >/dev/null 2>&1 \
        && update-alternatives --query default-display-manager >/dev/null 2>&1; then
        hyprtk_run_root update-alternatives --set default-display-manager /usr/bin/sddm 2>/dev/null
    fi
    hyprtk_run_root sh -c 'printf "%s\n" /usr/bin/sddm > /etc/X11/default-display-manager'
fi

echo ""
echo "Switched to SDDM. Reboot to apply changes."
