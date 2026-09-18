#!/bin/bash
# ── hyprland-src-install.sh — build Hyprland >= 0.55 where the distro is older ─
# Hyprland 0.55 switched the config language to Lua: the dotfiles are entirely
# Lua-based (hypr/hyprland.lua + require(...)), so a Hyprland < 0.55 ignores them
# and generates a stock hyprland.conf — autostart, keybindings and window rules
# never apply. Alpine (3.24 and edge) ships 0.54.3 with no newer package, so
# this builds the pinned upstream release from source into /usr. Void ships no
# Hyprland at all — and none of its libraries — so for Void this also builds the
# hyprwm library chain (at Hyprland's pinned flake.lock revisions) first.
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

# ── Void: build the whole hyprwm library chain from source ──────────────────
# Void packages none of the Hyprland libraries, so they are built into /usr at
# the exact revisions Hyprland pins in its flake.lock — guaranteeing API/ABI
# compatibility with the pinned Hyprland tag. Each is skipped when its
# pkg-config module already resolves: srcapps-install.sh runs first and builds
# hyprutils/hyprlang/hyprland-protocols for hyprsunset, so those are usually
# already present. Build system (meson vs cmake) is detected per checkout.
VOID_HYPRWAYLAND_SCANNER_REV="b8632713a6beaf28b56f2a7b0ab2fb7088dbb404"

_has_cmake_config() {
    find /usr/lib/cmake /usr/lib64/cmake /usr/share/cmake \
        -maxdepth 1 -name "$1" 2>/dev/null | grep -q .
}

# Fetch one commit (shallow) and build it into /usr. $1 = repo, $2 = rev,
# $3 = optional patch function run on the checkout.
_build_hypr_rev() {
    local repo="$1" rev="$2" patchfn="${3:-}"
    local tmp
    tmp="$(mktemp -d)" || return 1
    say "  $repo: building (${rev:0:10})"
    if git init -q "$tmp/src" \
       && git -C "$tmp/src" remote add origin "https://github.com/hyprwm/$repo.git" \
       && git -C "$tmp/src" fetch -q --depth 1 origin "$rev" 2>/dev/null \
       && git -C "$tmp/src" checkout -q FETCH_HEAD 2>/dev/null; then
        [ -n "$patchfn" ] && "$patchfn" "$tmp/src"
        local ok=0
        if [ -f "$tmp/src/meson.build" ]; then
            ( cd "$tmp/src" \
              && meson setup build --prefix=/usr --buildtype=release >/dev/null 2>&1 \
              && ninja -C build >/dev/null 2>&1 \
              && hyprtk_run_root ninja -C build install >/dev/null 2>&1 ) && ok=1
        elif [ -f "$tmp/src/CMakeLists.txt" ]; then
            ( cd "$tmp/src" \
              && cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
                   -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF >/dev/null 2>&1 \
              && ninja -C build >/dev/null 2>&1 \
              && hyprtk_run_root ninja -C build install >/dev/null 2>&1 ) && ok=1
        fi
        if [ "$ok" = 1 ]; then
            hyprtk_run_root ldconfig >/dev/null 2>&1 || true
            rm -rf "$tmp"
            return 0
        fi
    fi
    rm -rf "$tmp"
    say "  $repo: build failed" >&2
    return 1
}

# GCC 14's libstdc++ has no std::vector::append_range / insert_range (C++23 —
# libstdc++ added them in GCC 15). Replace every X.append_range(R) /
# X.insert_range(P, R) with small helpers that splice the range once (single
# evaluation, so temporaries are safe).
_patch_gcc14_range_members() {
    local dir="$1" f
    local helper='#include <vector>
#include <iterator>
namespace hyprtk { template <class C, class R> void append_range(C& c, R&& r) { c.insert(c.end(), std::begin(r), std::end(r)); } template <class C, class P, class R> void insert_range(C& c, P p, R&& r) { c.insert(p, std::begin(r), std::end(r)); } }'
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        case "$f" in */build/*) continue ;; esac
        grep -q 'hyprtk::append_range\|hyprtk::insert_range' "$f" && continue
        printf '%s\n' "$helper" | cat - "$f" > "$f.hyprtk" && mv "$f.hyprtk" "$f"
        sed -i -E 's/([A-Za-z0-9_.>-]+)\.append_range\(/hyprtk::append_range(\1, /g' "$f"
        sed -i -E 's/([A-Za-z0-9_.>-]+)\.insert_range\(/hyprtk::insert_range(\1, /g' "$f"
    done < <(grep -rlE '\.(append_range|insert_range)\(' "$dir")
}

# GCC 14 rejects `cond ? classWithPtrConversion : nullptr` (C++26 lets the
# common type resolve); make the pointer conversion explicit.
_patch_gcc14_xwm() {
    local f="$1/src/xwayland/XWM.hpp"
    [ -f "$f" ] || return 0
    local old='return m_connection ? *m_connection : nullptr;'
    local new='return m_connection ? static_cast<xcb_connection_t*>(*m_connection) : nullptr;'
    grep -qF "$old" "$f" || return 0
    python3 - "$f" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
open(p, 'w').write(s.replace(old, new))
PY
}

# GCC 14 has no C++26 #embed (GCC 15+). Replace the embedded example config with
# an equivalent raw string literal built from the same file.
_expand_gcc14_embed() {
    local hdr="$1/src/config/lua/DefaultConfig.hpp"
    local lua="$1/example/hyprland.lua"
    [ -f "$hdr" ] && grep -q '#embed' "$hdr" || return 0
    [ -f "$lua" ] || return 0
    say "  expanding #embed for GCC 14 toolchain"
    local d="HYPRTKEMBED"
    while grep -q ")$d\"" "$lua"; do d="${d}X"; done
    {
        sed -n '1,/EXAMPLE_CONFIG_BYTES_LUA/p' "$hdr" | sed '$d'
        printf 'inline constexpr std::string_view EXAMPLE_CONFIG_LUA = R"%s(' "$d"
        cat "$lua"
        printf ')%s";\n' "$d"
    } > "$hdr.hyprtk" && mv "$hdr.hyprtk" "$hdr"
}

# Revisions from Hyprland v0.56.2's flake.lock (kept in sync with HYPRLAND_TAG).
_ensure_void_hypr_libs() {
    say "building the Hyprland library chain (Void)"
    _has_cmake_config hyprwayland-scanner \
        || _build_hypr_rev hyprwayland-scanner "$VOID_HYPRWAYLAND_SCANNER_REV" || true
    pkg-config --exists hyprland-protocols \
        || _build_hypr_rev hyprland-protocols 1cb6db5fd6bb8aee419f4457402fa18293ace917 || true
    # hyprutils/hyprlang may exist as Void packages but be older than Hyprland
    # 0.56 needs — rebuild the pinned revision in that case, and do it *before*
    # the consumers so the whole chain links one libhyprutils.
    _ver_ge "$(_pc_ver hyprutils)" "$HYPRUTILS_MIN" \
        || _build_hypr_rev hyprutils 5a7b8cf221914ce4714407950e4ffbdddcd8b66f || true
    _ver_ge "$(_pc_ver hyprlang)" 0.6.7 \
        || _build_hypr_rev hyprlang 090117506ddc3d7f26e650ff344d378c2ec329cc || true
    pkg-config --exists hyprcursor \
        || _build_hypr_rev hyprcursor 39435900785d0c560c6ae8777d29f28617d031ef || true
    pkg-config --exists hyprgraphics \
        || _build_hypr_rev hyprgraphics 8699c38f0e4a1ca3bfc84f84ba020509ced1f133 || true
    pkg-config --exists hyprwire \
        || _build_hypr_rev hyprwire 7d935bb54674aa0fbd327d2a6888bd0630079ed0 _patch_gcc14_range_members || true
    pkg-config --exists aquamarine \
        || _build_hypr_rev aquamarine 1a10fe26a9f7d989c359e6a9ea61aa2e44d06c36 || true
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

# Void names (xbps). Everything here resolves in the Void repositories; the
# hyprwm libraries themselves are built by _ensure_void_hypr_libs above.
HYPR_SRC_DEPS[xbps]="git cmake ninja samurai meson base-devel pkgconf jq python3
    lua55 lua55-devel wayland-devel wayland-protocols
    MesaLib-devel glslang glslang-devel SPIRV-Tools-devel vulkan-loader-devel
    cairo-devel pango-devel pixman-devel libXcursor-devel libjpeg-turbo-devel
    lcms2-devel libzip-devel pugixml-devel glib-devel libuuid-devel
    librsvg-devel file-devel libwebp-devel libpng-devel tomlplusplus-devel
    re2-devel muparser-devel readline-devel
    libdrm-devel libinput-devel libei-devel libliftoff-devel libseat-devel
    elogind-devel libdisplay-info-devel udis86-devel libxkbcommon-devel
    xorg-server-xwayland
    libxcb-devel xcb-util-wm-devel xcb-util-cursor-devel xcb-util-errors-devel
    xcb-util-image-devel xcb-util-renderutil-devel xkeyboard-config
    hyprwayland-scanner"

# ── Main ────────────────────────────────────────────────────────────────────
_cur="$(_hypr_ver)"
if _ver_ge "$_cur" "$HYPRLAND_MIN"; then
    say "Hyprland ${_cur:-?} already >= $HYPRLAND_MIN — nothing to build"
    exit 0
fi
say "installed Hyprland ${_cur:-none} < $HYPRLAND_MIN — need the Lua-config release"

case "$HYPRTK_PM" in
    apk|xbps) ;;
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

# Void packages none of the Hyprland libraries — build the pinned chain first.
[ "$HYPRTK_PM" = xbps ] && _ensure_void_hypr_libs

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
    # The toolchain libstdc++ has no std::ranges::starts_with (C++23) — true for
    # Alpine's GCC 15.2 and Void's GCC 14.2 alike; replace it with a portable
    # equivalence (functionally identical where the symbol does exist).
    _misc="$_tmp/Hyprland/src/helpers/MiscFunctions.cpp"
    if [ -f "$_misc" ] && grep -q 'std::ranges::starts_with(str_view, prefixes)' "$_misc"; then
        say "  patching std::ranges::starts_with for the toolchain libstdc++"
        sed -i 's/std::ranges::starts_with(str_view, prefixes)/(str_view.size() >= prefixes.size() \&\& std::equal(prefixes.begin(), prefixes.end(), str_view.begin()))/' "$_misc"
    fi
    # Void/GCC 14: additional C++23/26 constructs the toolchain lacks.
    if [ "$HYPRTK_PM" = xbps ]; then
        _patch_gcc14_xwm "$_tmp/Hyprland"
        _patch_gcc14_range_members "$_tmp/Hyprland"
        _expand_gcc14_embed "$_tmp/Hyprland"
    fi
    # Void's GCC 14.2 libstdc++ predates C++26's string + string_view operator;
    # supply it from a compatibility header (guarded, so it is inert on newer
    # toolchains). Its paired C++23/26 gaps are patched inline above / in
    # hyprwire (_patch_gcc14_append_range).
    _cxxflags=()
    if [ "$HYPRTK_PM" = xbps ] && [ -f "$SELF_DIR/hyprtk-gcc14-compat.hpp" ]; then
        say "  adding the GCC 14 libstdc++ compatibility header"
        _cxxflags+=("-DCMAKE_CXX_FLAGS=-include $SELF_DIR/hyprtk-gcc14-compat.hpp")
    fi
    if ( cd "$_tmp/Hyprland" \
         && cmake --no-warn-unused-cli -DNO_HYPRPM=true -DCMAKE_BUILD_TYPE=Release \
              -DCMAKE_INSTALL_PREFIX=/usr "${_cxxflags[@]}" -S . -B build -G Ninja >/dev/null 2>&1 \
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
if [ "$HYPRTK_PM" = xbps ]; then
    say "Hyprland build failed — see PORTABILITY.md" >&2
    say "  fallback: add the community binary repository, then re-run:" >&2
    say "    echo 'repository=https://github.com/void-land/hyprland-void-packages/releases/latest/download/' | sudo tee /etc/xbps.d/hyprland-packages.conf" >&2
    say "    sudo xbps-install -S && sudo xbps-install -Sy hyprland xdg-desktop-portal-hyprland" >&2
else
    say "Hyprland build failed — keeping the distro package" >&2
fi
exit 1
