#!/bin/bash
#
#
#
# by hyprtk (Kori Tk) (2026)
# -----------------------------------------------------
# QEMU/KVM + libvirt + virt-manager. Distro-aware package lists; the service /
# group / network steps are best-effort and portable.
. "$(dirname "${BASH_SOURCE[0]}")/pkgmanager.sh"

echo ""
echo "-------------------------------------"
echo "-> Check for Virtualisation intel/amd"
echo "-------------------------------------"
echo ""
lscpu | grep Virtualization
echo ""
sleep 3
echo "-------------------------------------"
echo "-> Install Qemu/Virt Manager "
echo "-------------------------------------"
echo ""
case "$HYPRTK_PM" in
    pacman)
        pkg_install qemu-full dnsmasq vde2 openbsd-netcat libguestfs swtpm
        aur_install bridge-utils virt-manager virt-viewer
        ;;
    apt)
        pkg_install qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients \
                    virt-manager virt-viewer dnsmasq bridge-utils swtpm libguestfs-tools
        ;;
    dnf)
        pkg_install qemu-kvm qemu-img libvirt virt-manager virt-install dnsmasq \
                    bridge-utils swtpm libguestfs-tools
        ;;
    zypper)
        pkg_install qemu-kvm libvirt-daemon virt-manager dnsmasq bridge-utils swtpm libguestfs
        ;;
    xbps)
        pkg_install qemu libvirt virt-manager dnsmasq bridge-utils swtpm libguestfs
        ;;
    apk)
        pkg_install qemu-system-x86_64 qemu-img libvirt virt-manager dnsmasq bridge-utils swtpm
        ;;
esac
echo ""
sleep 3
echo "-------------------------------------"
echo "-> Enable Services "
echo "-------------------------------------"
echo ""
hyprtk_run_root systemctl enable --now libvirtd.service 2>/dev/null || true
systemctl status libvirtd.service --no-pager 2>/dev/null | head -5 || true
echo ""
sleep 3
echo "-------------------------------------"
echo "-> Add User to Virt Group "
echo "-------------------------------------"
echo ""
hyprtk_run_root usermod -aG libvirt,kvm "$(whoami)" 2>/dev/null || \
    hyprtk_run_root usermod -aG libvirt "$(whoami)" 2>/dev/null || true
echo ""
sleep 3
echo "-------------------------------------"
echo "-> Load KVM modules "
echo "-------------------------------------"
echo ""
if grep -qm1 '^vmx' /proc/cpuinfo 2>/dev/null; then
    printf 'kvm\nkvm_intel\n' | hyprtk_run_root tee /etc/modules-load.d/kvm.conf >/dev/null
elif grep -qm1 '^svm' /proc/cpuinfo 2>/dev/null; then
    printf 'kvm\nkvm_amd\n' | hyprtk_run_root tee /etc/modules-load.d/kvm.conf >/dev/null
fi
echo ""
sleep 3
echo "-------------------------------------"
echo "-> Start default libvirt network "
echo "-------------------------------------"
echo ""
hyprtk_run_root virsh net-autostart default 2>/dev/null || true
hyprtk_run_root virsh net-start default 2>/dev/null || true
echo ""
sleep 3
