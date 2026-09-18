#!/bin/bash
# hyprtk-pkglist
# ── matuwall ─────────────────────────────────────────────────────────
# Matuwall (naurissteins/Matuwall) is a C11 + meson Wayland wallpaper picker.
# Upstream moved from a Python package to a native build, so the old
# `pip install .` no longer applies. There is no distro package for the C
# version — the AUR `matuwall` (0.1.x) is still the old Python/GTK4 app — so this
# always builds the upstream source with meson/ninja.
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

declare -A MATUWALL_DEPS
MATUWALL_DEPS[pacman]="base-devel meson ninja git scdoc"
MATUWALL_DEPS[apt]="build-essential meson ninja-build pkg-config git libwayland-dev wayland-protocols libxkbcommon-dev libpng-dev libjpeg-dev libwebp-dev scdoc"
MATUWALL_DEPS[dnf]="gcc meson ninja-build pkgconf-pkg-config git wayland-devel wayland-protocols-devel libxkbcommon-devel libpng-devel libjpeg-turbo-devel libwebp-devel scdoc"
MATUWALL_DEPS[zypper]="gcc meson ninja pkg-config git wayland-devel wayland-protocols-devel libxkbcommon-devel libpng16-devel libjpeg8-devel libwebp-devel scdoc"
MATUWALL_DEPS[xbps]="base-devel meson ninja pkg-config git wayland-devel wayland-protocols libxkbcommon-devel libpng-devel libjpeg-turbo-devel libwebp-devel scdoc"
MATUWALL_DEPS[apk]="build-base meson ninja pkgconf git wayland-dev wayland-protocols libxkbcommon-dev libpng-dev libjpeg-turbo-dev libwebp-dev scdoc"

if [ "${1:-}" = "--list" ]; then
    printf '%s' "${MATUWALL_DEPS[$HYPRTK_PM]:-}"
    echo
    exit 0
fi

if [ -n "${HYPRTK_DRYRUN:-}" ]; then
    echo "matuwall: would build from source (meson/ninja)"
    exit 0
fi

echo ""
echo " Matuwall Installer "
echo ""
echo "Installing Matuwall wallpaper picker..."
echo ""

SRC="$HOME/.local/share/Matuwall"

# The app was a Python venv app before the C11/meson rewrite; a system upgraded
# from the old installer keeps the orphaned venv (and its packaging metadata).
# Remove it on sight so upgrades leave no dead weight behind.
if [ -d "$SRC/.venv" ] || [ -d "$SRC/matuwall.egg-info" ]; then
    rm -rf -- "$SRC/.venv" "$SRC/matuwall.egg-info" 2>/dev/null || true
    echo " Removed the orphaned Python-era Matuwall venv. "
fi

if command -v matuwall >/dev/null 2>&1; then
    echo " Matuwall already installed! "
    sleep 2
    exit 0
fi

[ -n "${MATUWALL_DEPS[$HYPRTK_PM]:-}" ] && pkg_install ${MATUWALL_DEPS[$HYPRTK_PM]} || true

if ! command -v meson >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
    echo "  ! meson/ninja unavailable — cannot build matuwall" >&2
    exit 1
fi

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

if command -v matuwall >/dev/null 2>&1; then
    echo " Matuwall installed! "
else
    echo "  ! matuwall is not on PATH — the build failed (see above)" >&2
    exit 1
fi
sleep 2
