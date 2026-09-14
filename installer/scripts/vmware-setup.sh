#!/bin/bash
# VMware Workstation + open-vm-tools setup. Distro-aware: open-vm-tools comes
# from each distro's repos; VMware Workstation itself (and its kernel modules)
# is installed only on Arch (AUR). Elsewhere the script installs the tools and
# points at the vendor bundle.
. "$(dirname "${BASH_SOURCE[0]}")/pkgmanager.sh"

echo ""
echo " Check If Virtualisation is enabled "
lscpu | grep Virtualization
sleep 2
echo ""
echo " Install kernel headers + open-vm-tools "
case "$HYPRTK_PM" in
    pacman) pkg_install linux-headers; pkg_install open-vm-tools ;;
    apt)    pkg_install "linux-headers-$(uname -r)" open-vm-tools open-vm-tools-desktop ;;
    dnf)    pkg_install kernel-devel open-vm-tools open-vm-tools-desktop ;;
    zypper) pkg_install kernel-default-devel open-vm-tools open-vm-tools-desktop ;;
    xbps)   pkg_install linux-headers open-vm-tools ;;
    apk)    pkg_install open-vm-tools open-vm-tools-plugins-all ;;
esac
sleep 2
echo ""
if [ "$HYPRTK_PM" = pacman ]; then
    echo " Install VMware Workstation (AUR) "
    aur_install vmware-keymaps
    aur_install vmware-workstation
else
    echo "  ! VMware Workstation is not packaged here — download the bundle from:" >&2
    echo "    https://www.vmware.com/products/workstation-pro.html" >&2
fi
sleep 2
echo ""
echo " Check Units Installed "
systemctl list-unit-files 2>/dev/null | grep vmware || true
sleep 2
echo ""
echo " Enable VMWare Services "
hyprtk_run_root systemctl enable --now vmware-networks.service 2>/dev/null || true
hyprtk_run_root systemctl enable --now vmware-usbarbitrator.service 2>/dev/null || true
sleep 2
echo ""
echo " Add VMWare modprobes "
hyprtk_run_root modprobe vmmon 2>/dev/null || true
hyprtk_run_root modprobe vmnet 2>/dev/null || true
hyprtk_run_root modprobe vmw_vmci 2>/dev/null || true
