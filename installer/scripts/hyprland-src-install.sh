#!/bin/bash
# ── hyprland-src-install.sh — build Hyprland >= 0.55 where the distro is older ─
# Hyprland 0.55 switched the config language to Lua: the dotfiles are entirely
# Lua-based (hypr/hyprland.lua + require(...)), so a Hyprland < 0.55 ignores them
# and generates a stock hyprland.conf — autostart, keybindings and window rules
# never apply. Alpine (3.24 and edge) ships 0.54.3 with no newer package, so
# this builds the pinned upstream release from source into /usr.
#
# What it does (idempotent, non-fatal):
#   1. if the installed Hyprland is already >= 0.55, do nothing;
#   2. install the build deps;
#   3. ensure wayland-protocols >= 1.49 (build the XML-only release if the
#      distro ships an older one — 3.24 has 1.48);
#   4. ensure hyprutils >= 0.14.0 (0.56.x needs it; Alpine has 0.13.1);
#   5. clone the pinned Hyprland tag, apply the one source fix it needs on
#      musl/Alpine libstdc++ (std::ranges::starts_with is not implemented),
#      then cmake + ninja + install into /usr.
#
# Set HYPRTK_DRYRUN=1 to print the plan without building.
# ─────────────────────────────────────────────────────────────────────────────
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=installer/scripts/pkgmanager.sh
. "$SELF_DIR/pkgmanager.sh"

HYPRLAND_MIN="0.55"
HYPRLAND_TAG="v0.56.2"
HYPRUTILS_MIN="0.14.0"
HYPRUTILS_TAG="v0.14.2"
WP_MIN="1.49"
WP_TAG="1.49"

say() { echo "hyprland: $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# _ver_ge ACTUAL MIN — true when ACTUAL (dotted) >= MIN.
_ver_ge() {
    awk -v a="$1" -v b="$2" 'BEGIN{
        if (a == "") exit 1
        n = split(a, A, "."); m = split(b, B, ".")
        for (i = 1; i <= 3; i++) {
            ai = (i <= n ? A[i] + 0 : 0); bi = (i <= m ? B[i] + 0 : 0)
            if (ai > bi) exit 0
            if (ai < bi) exit 1
        }
        exit 0
    }'
}

# Installed Hyprland version (empty when absent). XDG_RUNTIME_DIR must be set
# or `Hyprland --version` aborts before printing.
_hypr_ver() {
    [ -x /usr/bin/Hyprland ] || return 0
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}" /usr/bin/Hyprland --version 2>/dev/null \
        | awk '/^Hyprland / { print $2; exit }'
}

_pc_ver() { pkg-config --modversion "$1" 2>/dev/null; }

# Clone + cmake build + install into /usr (as the invoking user, install as
# root). $1 = git URL, $2 = tag, $3 = label, extra args after are cmake flags.
_build_cmake() {
    local url="$1" tag="$2" label="$3"; shift 3
    local tmp
    tmp="$(mktemp -d)" || return 1
    say "  $label: building ($tag)"
    if git clone --depth 1 --branch "$tag" "$url" "$tmp/src" >/dev/null 2>&1 \
       && ( cd "$tmp/src" \
            && cmake -S . -B build -G Ninja \
                 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
                 -DBUILD_TESTING=OFF "$@" >/dev/null 2>&1 \
            && ninja -C build >/dev/null 2>&1 \
            && hyprtk_run_root ninja -C build install >/dev/null 2>&1 ); then
        hyprtk_run_root ldconfig >/dev/null 2>&1 || true
        rm -rf "$tmp"
        return 0
    fi
    rm -rf "$tmp"
    say "  $label: build failed" >&2
    return 1
}

# wayland-protocols is XML-only; built with meson.
_build_wayland_protocols() {
    local tmp
    tmp="$(mktemp -d)" || return 1
    say "  wayland-protocols: building ($WP_TAG)"
    if git clone --depth 1 --branch "$WP_TAG" \
           https://gitlab.freedesktop.org/wayland/wayland-protocols "$tmp/wp" >/dev/null 2>&1 \
       && ( cd "$tmp/wp" \
            && meson setup build --prefix=/usr >/dev/null 2>&1 \
            && ninja -C build >/dev/null 2>&1 \
            && hyprtk_run_root ninja -C build install >/dev/null 2>&1 ); then
        rm -rf "$tmp"
        return 0
    fi
    rm -rf "$tmp"
    say "  wayland-protocols: build failed" >&2
    return 1
}

# ── Per-family build dependencies (apk = Alpine) ────────────────────────────
declare -A HYPR_SRC_DEPS
HYPR_SRC_DEPS[apk]="cmake ninja samurai build-base pkgconf git jq lua5.5-dev
    aquamarine-dev cairo-dev elogind-dev glaze hyprcursor-dev hyprgraphics-dev
    hyprland-protocols hyprlang-dev hyprutils-dev hyprwayland-scanner hyprwire-dev
    libdrm-dev libei-dev libinput-dev libliftoff-dev libxcb-dev libxcursor-dev
    libxkbcommon-dev mesa-dev muparser-dev pango-dev pixman-dev re2-dev
    readline-dev spirv-tools-dev tomlplusplus-dev udis86-git-dev
    vulkan-loader-dev wayland-dev wayland-protocols xcb-util-errors-dev
    xcb-util-image-dev xcb-util-renderutil-dev xcb-util-wm-dev
    xkeyboard-config-dev xwayland-dev glslang-dev meson"

# ── Main ────────────────────────────────────────────────────────────────────
_cur="$(_hypr_ver)"
if _ver_ge "$_cur" "$HYPRLAND_MIN"; then
    say "Hyprland ${_cur:-?} already >= $HYPRLAND_MIN — nothing to build"
    exit 0
fi
say "installed Hyprland ${_cur:-none} < $HYPRLAND_MIN — need the Lua-config release"

case "$HYPRTK_PM" in
    apk) ;;
    *)
        say "no Hyprland source path for '$HYPRTK_PM' — leaving the distro package" >&2
        exit 0
        ;;
esac

if [ "${HYPRTK_DRYRUN:-0}" = "1" ]; then
    say "plan: install deps; build wayland-protocols $WP_TAG; hyprutils $HYPRUTILS_TAG; Hyprland $HYPRLAND_TAG"
    exit 0
fi

say "installing build dependencies"
# shellcheck disable=SC2086
pkg_install ${HYPR_SRC_DEPS[$HYPRTK_PM]} || true

if ! have cmake || ! have ninja || ! have git || ! have pkg-config || ! have meson; then
    say "cmake/ninja/git/pkg-config/meson unavailable — skipping" >&2
    exit 1
fi

_wp="$(_pc_ver wayland-protocols)"
if ! _ver_ge "$_wp" "$WP_MIN"; then
    say "wayland-protocols ${_wp:-none} < $WP_MIN"
    _build_wayland_protocols || true
fi

_hu="$(_pc_ver hyprutils)"
if ! _ver_ge "$_hu" "$HYPRUTILS_MIN"; then
    say "hyprutils ${_hu:-none} < $HYPRUTILS_MIN"
    _build_cmake https://github.com/hyprwm/hyprutils.git "$HYPRUTILS_TAG" hyprutils || true
fi

say "building Hyprland $HYPRLAND_TAG (this takes a while)"
_tmp="$(mktemp -d)" || exit 1
if git clone --depth 1 --branch "$HYPRLAND_TAG" \
       https://github.com/hyprwm/Hyprland "$_tmp/Hyprland" >/dev/null 2>&1; then
    # Alpine's libstdc++ (GCC 15.2, 3.24 and edge) has no std::ranges::starts_with
    # (C++23); replace it with a portable equivalence before configuring.
    _misc="$_tmp/Hyprland/src/helpers/MiscFunctions.cpp"
    if [ -f "$_misc" ] && grep -q 'std::ranges::starts_with(str_view, prefixes)' "$_misc"; then
        say "  patching std::ranges::starts_with for Alpine libstdc++"
        sed -i 's/std::ranges::starts_with(str_view, prefixes)/(str_view.size() >= prefixes.size() \&\& std::equal(prefixes.begin(), prefixes.end(), str_view.begin()))/' "$_misc"
    fi
    if ( cd "$_tmp/Hyprland" \
         && cmake --no-warn-unused-cli -DNO_HYPRPM=true -DCMAKE_BUILD_TYPE=Release \
              -DCMAKE_INSTALL_PREFIX=/usr -S . -B build -G Ninja >/dev/null 2>&1 \
         && ninja -C build >/dev/null 2>&1 \
         && hyprtk_run_root ninja -C build install >/dev/null 2>&1 ); then
        hyprtk_run_root ldconfig >/dev/null 2>&1 || true
        _new="$(_hypr_ver)"
        say "Hyprland ${_new:-?} installed to /usr/bin"
        [ -n "$_new" ] && _ver_ge "$_new" "$HYPRLAND_MIN" \
            && say "  ! reboot to start the Lua-config Hyprland session"
        rm -rf "$_tmp"
        exit 0
    fi
fi
rm -rf "$_tmp"
say "Hyprland build failed — keeping the distro package" >&2
exit 1
