#!/bin/bash
# ── graphics-card ─────────────────────────────────────────────────────────
# Installs the GPU driver stack per family. The initramfs / GRUB tweaks below
# are guarded: they only run where the tooling actually exists.
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

# Enumerate every package this script can install (the union of the Intel, AMD
# and Nvidia branches) for the container-matrix / package-name audit. No
# `hyprtk-pkglist` marker: 1-install.sh runs this script interactively, so its
# spinner must not claim a GPU-specific list.
if [ "${1:-}" = "--list" ]; then
    case "$HYPRTK_PM" in
    pacman)
        printf '%s ' xf86-video-intel mesa vulkan-intel \
            xf86-video-amdgpu vulkan-radeon vdpauinfo corectrl libvdpau \
            nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct \
            qt6-wayland qt6ct libva libva-nvidia-driver-git
        ;;
    apt)
        printf '%s ' mesa-vulkan-drivers intel-media-va-driver-non-free \
            i965-va-driver mesa-va-drivers libvdpau-va-gl1 \
            nvidia-driver nvidia-settings libva2 libva-drm2
        ;;
    dnf)
        printf '%s ' mesa-dri-drivers mesa-vulkan-drivers libva-intel-media-driver \
            mesa-va-drivers-freeworld akmod-nvidia xorg-x11-drv-nvidia-cuda nvidia-settings
        ;;
    zypper)
        printf '%s ' Mesa Mesa-libva intel-media-driver \
            nvidia-open-driver-G06-signed-kmp-default nvidia-settings
        ;;
    xbps)
        printf '%s ' mesa-dri mesa-vulkan-intel intel-video-accel \
            mesa-vulkan-radeon mesa-vaapi nvidia nvidia-settings
        ;;
    apk)
        printf '%s ' mesa-vulkan-intel mesa-dri-gallium intel-media-driver \
            mesa-vulkan-ati mesa-va-gallium nvidia nvidia-settings
        ;;
    esac
    echo
    exit 0
fi

# Regenerate the boot image with whichever initramfs tool this distro ships.
regen_initramfs() {
    if command -v mkinitcpio >/dev/null 2>&1 && [ -f /etc/mkinitcpio.conf ]; then
        hyprtk_run_root mkinitcpio -P >/dev/null 2>&1 || true
    elif command -v update-initramfs >/dev/null 2>&1; then
        hyprtk_run_root update-initramfs -u >/dev/null 2>&1 || true
    elif command -v dracut >/dev/null 2>&1; then
        hyprtk_run_root dracut --force >/dev/null 2>&1 || true
    fi
}

# Add a module to /etc/mkinitcpio.conf MODULES line when it is still empty.
add_mkinitcpio_module() {
    [ -f /etc/mkinitcpio.conf ] || return 0
    hyprtk_run_root sed -i "s/MODULES=()/MODULES=($1)/" /etc/mkinitcpio.conf 2>/dev/null || true
}

echo "
#########################################################
#                                                       #
#            Which Graphics Card do you have?           #
#                                                       #
#########################################################

1) Intel
2) AMD
3) Nvidia
Defaults to AMD if you choose
something else
"
echo ""
read -r GRAPHICSCARD

case "$GRAPHICSCARD" in
1)
    case "$HYPRTK_PM" in
        pacman) PKGS=(xf86-video-intel mesa vulkan-intel) ;;
        apt)    PKGS=(mesa-vulkan-drivers intel-media-va-driver-non-free i965-va-driver) ;;
        dnf)    PKGS=(mesa-dri-drivers mesa-vulkan-drivers libva-intel-media-driver) ;;
        zypper) PKGS=(Mesa Mesa-libva intel-media-driver) ;;
        xbps)   PKGS=(mesa-dri mesa-vulkan-intel intel-video-accel) ;;
        apk)    PKGS=(mesa-vulkan-intel mesa-dri-gallium intel-media-driver) ;;
    esac
    pkg_install "${PKGS[@]}"
    ;;
3)
    case "$HYPRTK_PM" in
        pacman)
            PKGS=(nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct
                  qt6-wayland qt6ct libva)
            AUR=(libva-nvidia-driver-git)
            ;;
        apt)
            PKGS=(nvidia-driver nvidia-settings libva2 libva-drm2)
            # Ubuntu/Mint ship no generic `nvidia-driver` meta — only versioned
            # ones (nvidia-driver-5xx). When the meta is missing, pick the newest
            # available versioned driver so the GPU stack still installs.
            if ! apt-get install -s -y nvidia-driver >/dev/null 2>&1; then
                _nv="$(apt-cache search --names-only '^nvidia-driver-[0-9][0-9][0-9]$' 2>/dev/null \
                       | awk '{print $1}' | sed 's/^nvidia-driver-//' | sort -n | tail -1)"
                if [ -n "$_nv" ]; then
                    PKGS=(nvidia-driver-"$_nv" nvidia-settings libva2 libva-drm2)
                    echo "  → nvidia-driver absent; using nvidia-driver-$_nv"
                fi
            fi
            ;;
        dnf)    PKGS=(akmod-nvidia xorg-x11-drv-nvidia-cuda nvidia-settings) ;;
        zypper) PKGS=(nvidia-open-driver-G06-signed-kmp-default nvidia-settings) ;;
        xbps)   PKGS=(nvidia nvidia-settings) ;;
        apk)    PKGS=(nvidia nvidia-settings) ;;
    esac
    # Kernel command line: only when this machine boots GRUB.
    if [ -f /etc/default/grub ] && command -v grub-mkconfig >/dev/null 2>&1; then
        hyprtk_run_root sed -i \
            's/GRUB_CMDLINE_LINUX="[^"]*"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"/' \
            /etc/default/grub 2>/dev/null || true
        hyprtk_run_root grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
    fi
    add_mkinitcpio_module 'nvidia nvidia_modeset nvidia_uvm nvidia_drm'
    echo "options nvidia-drm modeset=1" | hyprtk_run_root tee /etc/modprobe.d/nvidia.conf >/dev/null 2>&1 || true
    pkg_install "${PKGS[@]}"
    aur_install "${AUR[@]}"
    regen_initramfs
    ;;
# The AMD arm keeps the catch-all ("defaults to AMD"), so it must come *after*
# the explicit 3) arm — otherwise `*` also matches "3" and Nvidia is unreachable.
2|*)
    case "$HYPRTK_PM" in
        pacman) PKGS=(xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau) ;;
        apt)    PKGS=(mesa-vulkan-drivers mesa-va-drivers libvdpau-va-gl1) ;;
        dnf)    PKGS=(mesa-dri-drivers mesa-vulkan-drivers mesa-va-drivers-freeworld) ;;
        zypper) PKGS=(Mesa Mesa-libva) ;;
        xbps)   PKGS=(mesa-dri mesa-vulkan-radeon mesa-vaapi) ;;
        apk)    PKGS=(mesa-vulkan-ati mesa-va-gallium mesa-dri-gallium) ;;
    esac
    pkg_install "${PKGS[@]}"
    add_mkinitcpio_module amdgpu
    regen_initramfs
    ;;
esac

echo ""
clear
echo "
#########################################################
#                                                       #
#         Your Graphics Card has been installed         #
#                                                       #
#########################################################
"
