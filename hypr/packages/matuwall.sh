#!/bin/bash
# hyprtk-pkglist
# ── matuwall ─────────────────────────────────────────────────────────
# Matuwall (naurissteins/Matuwall) is a C11 + meson Wayland wallpaper picker.
# Upstream moved from a Python package to a native build, so the old
# `pip install .` no longer applies; this builds it from source with meson/ninja
# (there is no distro package). On Arch the AUR package `matuwall` is used when
# an AUR helper is present.
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

declare -A MATUWALL_DEPS
MATUWALL_DEPS[pacman]="base-devel meson ninja git scdoc"
MATUWALL_DEPS[apt]="build-essential meson ninja-build pkg-config git libwayland-dev wayland-protocols libxkbcommon-dev libpng-dev libjpeg-turbo8-dev libwebp-dev scdoc"
MATUWALL_DEPS[dnf]="gcc meson ninja-build pkgconf-pkg-config git wayland-devel wayland-protocols-devel libxkbcommon-devel libpng-devel libjpeg-turbo-devel libwebp-devel scdoc"
MATUWALL_DEPS[zypper]="gcc meson ninja pkg-config git wayland-devel wayland-protocols-devel libxkbcommon-devel libpng16-devel libjpeg-turbo-devel libwebp-devel scdoc"
MATUWALL_DEPS[xbps]="base-devel meson ninja pkg-config git wayland-devel wayland-protocols libxkbcommon-devel libpng-devel libjpeg-turbo-devel libwebp-devel scdoc"
MATUWALL_DEPS[apk]="build-base meson ninja pkgconf git wayland-dev wayland-protocols libxkbcommon-dev libpng-dev libjpeg-turbo-dev libwebp-dev scdoc"

if [ "${1:-}" = "--list" ]; then
    printf '%s' "${MATUWALL_DEPS[$HYPRTK_PM]:-}"
    [ "$HYPRTK_PM" = pacman ] && printf ' matuwall'
    echo
    exit 0
fi

if [ -n "${HYPRTK_DRYRUN:-}" ]; then
    echo "matuwall: would install the AUR package (Arch) or build from source (meson) elsewhere"
    exit 0
fi

echo ""
echo " Matuwall Installer "
echo ""
echo "Installing Matuwall wallpaper picker..."
echo ""

SRC="$HOME/.local/share/Matuwall"

# Arch: the AUR has it; use it when a helper is available.
if [ "$HYPRTK_PM" = pacman ] && aur_available; then
    aur_install matuwall || true
fi

# Build from source when there is no usable package (or the AUR install failed).
if ! command -v matuwall >/dev/null 2>&1; then
    [ -n "${MATUWALL_DEPS[$HYPRTK_PM]:-}" ] && pkg_install ${MATUWALL_DEPS[$HYPRTK_PM]} || true
    if ! command -v meson >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
        echo "  ! meson/ninja unavailable — cannot build matuwall" >&2
    else
        if [ -d "$SRC/.git" ]; then
            git -C "$SRC" pull --ff-only >/dev/null 2>&1 || true
        else
            rm -rf "$SRC"
            git clone https://github.com/naurissteins/Matuwall.git "$SRC" || true
        fi
        if [ -d "$SRC" ] && ( cd "$SRC" \
             && { [ -d build ] || meson setup build --buildtype=release; } >/dev/null 2>&1 \
             && ninja -C build >/dev/null 2>&1 \
             && hyprtk_run_root ninja -C build install >/dev/null 2>&1 ); then
            hyprtk_run_root ldconfig >/dev/null 2>&1 || true
        fi
    fi
fi

if command -v matuwall >/dev/null 2>&1; then
    echo " Matuwall installed! "
else
    echo "  ! matuwall is not on PATH — the build failed (see above)" >&2
    exit 1
fi
sleep 2
