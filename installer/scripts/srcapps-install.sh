#!/bin/bash
# ── srcapps-install.sh — fallbacks for apps missing from distro archives ─────
# Complements hypr/packages/*.sh, which install the *native* packages where they
# exist. Where a distro has no archive package, this installs the app from source
# (or, for starship, its pinned upstream binary installer):
#
#   gtk4-layer-shell  wmww/gtk4-layer-shell (meson)   → matuwall LD_PRELOAD
#   swappy            jtheoof/swappy (meson)          → grim.sh screenshot editor
#   nwg-look          nwg-piotr/nwg-look (go)         → GTK settings tool
#   starship          starship.rs install.sh           → shell prompt
#   cliphist          sentriz/cliphist (go)            → clipboard history
#   eza               eza-community/eza (cargo)        → `ls` replacement (Debian 12)
#   ipp-usb           OpenPrinting/ipp-usb (go)        → driverless USB printing
#   hyprpicker        hyprwm/hyprpicker (cmake)        → colour picker (Alpine)
#   hyprsunset        hyprwm/hyprsunset (cmake)        → gamma/brightness (Void)
#   wob               francma/wob (meson)              → volume/brightness overlay (Void)
#
# hyprpicker/hyprsunset are NOT packaged on Alpine/Void, and neither are the
# Hyprland libraries they link (hyprutils, hyprlang, hyprwayland-scanner,
# hyprland-protocols), so those are built first (into /usr) and the app after.
#
# Each step is idempotent (skips when already present) and non-fatal: a failed
# build warns and the rest of the install continues, exactly like awww. Set
# HYPRTK_DRYRUN=1 to print the plan without building.
# ─────────────────────────────────────────────────────────────────────────────
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=installer/scripts/pkgmanager.sh
. "$SELF_DIR/pkgmanager.sh"

BINDIR=/usr/local/bin
G4_VER="v1.3.0"
SWAPPY_VER="v1.8.0"
NWG_VER="v1.1.1"
STARSHIP_VER="v1.26.0"
G4_GIT="https://github.com/wmww/gtk4-layer-shell.git"
SWAPPY_GIT="https://github.com/jtheoof/swappy.git"
NWG_GIT="https://github.com/nwg-piotr/nwg-look.git"
CLIPHIST_GIT="https://github.com/sentriz/cliphist.git"
IPPUSB_GIT="https://github.com/OpenPrinting/ipp-usb.git"
WOB_VER="0.15.1"
WOB_GIT="https://github.com/francma/wob.git"

say() { echo "srcapps: $*"; }

# ── Per-family build dependencies ───────────────────────────────────────────
declare -A G4_DEPS SWAPPY_DEPS NWG_DEPS
G4_DEPS[apt]="git build-essential meson ninja-build pkg-config libgtk-4-dev libwayland-dev wayland-protocols"
G4_DEPS[dnf]="git gcc gcc-c++ meson ninja-build pkgconf-pkg-config gtk4-devel wayland-devel wayland-protocols-devel"
G4_DEPS[zypper]="git gcc gcc-c++ meson ninja pkg-config gtk4-devel wayland-devel wayland-protocols-devel"
G4_DEPS[xbps]="git base-devel meson ninja pkg-config gtk4-devel wayland-devel wayland-protocols"
G4_DEPS[apk]="git build-base meson ninja pkgconf gtk4.0-dev wayland-dev wayland-protocols"

SWAPPY_DEPS[apt]="git build-essential meson ninja-build pkg-config libgtk-3-dev libwlroots-dev libwayland-dev wayland-protocols libpango1.0-dev libcairo2-dev libgdk-pixbuf-2.0-dev"
SWAPPY_DEPS[dnf]="git gcc gcc-c++ meson ninja-build pkgconf-pkg-config gtk3-devel wlroots-devel wayland-devel wayland-protocols-devel pango-devel cairo-devel gdk-pixbuf2-devel"
SWAPPY_DEPS[zypper]="git gcc gcc-c++ meson ninja pkg-config gtk3-devel wlroots-devel wayland-devel wayland-protocols-devel pango-devel cairo-devel gdk-pixbuf-devel"
SWAPPY_DEPS[xbps]="git base-devel meson ninja pkg-config gtk+3-devel wlroots-devel wayland-devel wayland-protocols pango-devel cairo-devel gdk-pixbuf-devel"
SWAPPY_DEPS[apk]="git build-base meson ninja pkgconf gtk+3.0-dev wlroots-dev wayland-dev wayland-protocols pango-dev cairo-dev gdk-pixbuf-dev"

NWG_DEPS[apt]="git golang-go libgtk-3-dev gcc"
NWG_DEPS[dnf]="git golang gtk3-devel gcc"
NWG_DEPS[zypper]="git go gtk3-devel gcc"
NWG_DEPS[xbps]="git go gtk+3-devel gcc"
NWG_DEPS[apk]="git go gtk+3.0-dev gcc"

# cliphist is a small Go program; wl-clipboard provides wl-paste at runtime.
declare -A CLIPHIST_DEPS
CLIPHIST_DEPS[apt]="git golang-go wl-clipboard"
CLIPHIST_DEPS[dnf]="git golang wl-clipboard"
CLIPHIST_DEPS[zypper]="git go wl-clipboard"
CLIPHIST_DEPS[xbps]="git go wl-clipboard"
CLIPHIST_DEPS[apk]="git go wl-clipboard"

# eza is Rust; only built where the archive lacks it (Debian 12), which is also
# where awww already bootstrapped a recent cargo via rustup.
declare -A EZA_DEPS
EZA_DEPS[apt]="cargo"

# ipp-usb is Go with cgo (libusb) + an avahi client; only built where unpackaged
# (Alpine). It also needs its udev rule installed to be triggered on device add.
declare -A IPPUSB_DEPS
IPPUSB_DEPS[apt]="git golang-go libusb-1.0-0-dev libavahi-client-dev"
IPPUSB_DEPS[dnf]="git golang libusb1-devel avahi-devel"
IPPUSB_DEPS[zypper]="git go libusb-1_0-devel avahi-devel"
IPPUSB_DEPS[xbps]="git go libusb-devel avahi-devel"
IPPUSB_DEPS[apk]="git go libusb-dev avahi-dev"

# wob is the volume/brightness overlay; only unpackaged on Void, so build from
# source there (meson, wayland + inih). Everywhere else the native package wins.
declare -A WOB_DEPS
WOB_DEPS[xbps]="git meson ninja wayland-devel wayland-protocols inih-devel libseccomp-devel scdoc"

# Hyprland library chain + apps (cmake). Built into /usr so pkg-config finds
# them. Only reached where hyprpicker/hyprsunset are unpackaged.
declare -A HYPRCHAIN_DEPS
HYPRCHAIN_DEPS[apt]="git cmake build-essential pkg-config libpixman-1-dev libpugixml-dev libwayland-dev wayland-protocols libxkbcommon-dev libcairo2-dev libpango1.0-dev libjpeg-dev"
HYPRCHAIN_DEPS[dnf]="git cmake gcc gcc-c++ pkgconf-pkg-config pixman-devel pugixml-devel wayland-devel wayland-protocols-devel libxkbcommon-devel cairo-devel pango-devel libjpeg-turbo-devel"
HYPRCHAIN_DEPS[zypper]="git cmake gcc gcc-c++ pkg-config libpixman-1-0-devel pugixml-devel wayland-devel wayland-protocols-devel libxkbcommon-devel cairo-devel pango-devel libjpeg8-devel"
HYPRCHAIN_DEPS[xbps]="git cmake base-devel pkg-config pixman-devel pugixml-devel wayland-devel wayland-protocols libxkbcommon-devel cairo-devel pango-devel libjpeg-turbo-devel"
HYPRCHAIN_DEPS[apk]="git cmake build-base pkgconf pixman-dev pugixml-dev wayland-dev wayland-protocols libxkbcommon-dev cairo-dev pango-dev libjpeg-turbo-dev"

# ── Dry run ─────────────────────────────────────────────────────────────────
if [ -n "${HYPRTK_DRYRUN:-}" ]; then
    echo "srcapps: would install from source/upstream where missing:"
    echo "srcapps:   gtk4-layer-shell $G4_VER | swappy $SWAPPY_VER | nwg-look $NWG_VER | starship $STARSHIP_VER"
    echo "srcapps:   cliphist (go) | eza (cargo) | ipp-usb (go)"
    echo "srcapps:   hyprpicker (Alpine) / hyprsunset (Void) + Hyprland lib chain"
    echo "srcapps:   build deps (gtk4): ${G4_DEPS[$HYPRTK_PM]:-(none)}"
    echo "srcapps:   build deps (swappy): ${SWAPPY_DEPS[$HYPRTK_PM]:-(none)}"
    echo "srcapps:   build deps (nwg-look): ${NWG_DEPS[$HYPRTK_PM]:-(none)}"
    echo "srcapps:   build deps (cliphist): ${CLIPHIST_DEPS[$HYPRTK_PM]:-(none)}"
    echo "srcapps:   build deps (eza): ${EZA_DEPS[$HYPRTK_PM]:-(none)}"
    echo "srcapps:   build deps (ipp-usb): ${IPPUSB_DEPS[$HYPRTK_PM]:-(none)}"
    exit 0
fi

# ── Helpers ─────────────────────────────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }

have_gtk4_layer_shell() {
    pkg-config --exists gtk4-layer-shell-0 2>/dev/null && return 0
    ls /usr/lib/libgtk4-layer-shell.so* /usr/lib/*/libgtk4-layer-shell.so* \
       /usr/local/lib/libgtk4-layer-shell.so* /usr/local/lib/*/libgtk4-layer-shell.so* \
       >/dev/null 2>&1
}

# The dotfiles' matuwall launch uses LD_PRELOAD=/usr/lib/libgtk4-layer-shell.so
# (the Arch path). On multiarch distros the library lands in /usr/lib/<triplet>/
# instead, so make the Arch path resolve everywhere.
fix_ld_preload() {
    [ -e /usr/lib/libgtk4-layer-shell.so ] && return 0
    local lib=""
    lib="$(pkg-config --variable=libdir gtk4-layer-shell-0 2>/dev/null)/libgtk4-layer-shell.so"
    if [ ! -e "$lib" ]; then
        lib="$(ls -1 \
            /usr/local/lib64/libgtk4-layer-shell.so /usr/lib64/libgtk4-layer-shell.so \
            /usr/local/lib/*/libgtk4-layer-shell.so /usr/local/lib/libgtk4-layer-shell.so \
            /usr/lib/*/libgtk4-layer-shell.so.[0-9]* /usr/lib/libgtk4-layer-shell.so.[0-9]* \
            /usr/lib64/libgtk4-layer-shell.so.[0-9]* \
            2>/dev/null | head -1)"
    fi
    [ -n "$lib" ] && [ -e "$lib" ] && hyprtk_run_root ln -sf "$lib" /usr/lib/libgtk4-layer-shell.so
    return 0
}

# Clone + meson build + install. $1 url $2 tag $3.. extra meson setup args.
build_meson() {
    local url="$1" tag="$2"; shift 2
    local tmp
    tmp="$(mktemp -d)" || return 1
    if git clone --depth=1 --branch "$tag" "$url" "$tmp/src" >/dev/null 2>&1 \
       && ( cd "$tmp/src" && meson setup build "$@" >/dev/null 2>&1 \
            && ninja -C build >/dev/null 2>&1 \
            && hyprtk_run_root ninja -C build install >/dev/null 2>&1 ); then
        hyprtk_run_root ldconfig >/dev/null 2>&1 || true
        rm -rf "$tmp"
        return 0
    fi
    rm -rf "$tmp"
    return 1
}

# ── Apps ────────────────────────────────────────────────────────────────────
install_gtk4_layer_shell() {
    if have_gtk4_layer_shell; then say "gtk4-layer-shell: already present"; fix_ld_preload; return 0; fi
    [ -n "${G4_DEPS[$HYPRTK_PM]:-}" ] && pkg_install ${G4_DEPS[$HYPRTK_PM]} || true
    if ! have meson || ! have ninja || ! have git; then
        say "gtk4-layer-shell: meson/ninja/git unavailable — skipping" >&2
        return 1
    fi
    say "gtk4-layer-shell: building $G4_VER (matuwall needs this library)"
    if build_meson "$G4_GIT" "$G4_VER" \
            -Dvapi=false -Dintrospection=false -Dexamples=false -Ddocs=false; then
        fix_ld_preload
        say "gtk4-layer-shell: installed"
        return 0
    fi
    say "gtk4-layer-shell: build failed — matuwall runs without layer-shell" >&2
    return 1
}

install_swappy() {
    if have swappy; then say "swappy: already present"; return 0; fi
    [ -n "${SWAPPY_DEPS[$HYPRTK_PM]:-}" ] && pkg_install ${SWAPPY_DEPS[$HYPRTK_PM]} || true
    if ! have meson || ! have ninja || ! have git; then
        say "swappy: meson/ninja/git unavailable — skipping" >&2
        return 1
    fi
    say "swappy: building $SWAPPY_VER (screenshot editor)"
    if build_meson "$SWAPPY_GIT" "$SWAPPY_VER"; then
        say "swappy: installed"
        return 0
    fi
    say "swappy: build failed — screenshots open without the editor" >&2
    return 1
}

install_nwg_look() {
    if have nwg-look; then say "nwg-look: already present"; return 0; fi
    [ -n "${NWG_DEPS[$HYPRTK_PM]:-}" ] && pkg_install ${NWG_DEPS[$HYPRTK_PM]} || true
    if ! have go || ! have git; then
        say "nwg-look: go/git unavailable — skipping" >&2
        return 1
    fi
    say "nwg-look: building $NWG_VER"
    local tmp
    tmp="$(mktemp -d)" || return 1
    if git clone --depth=1 --branch "$NWG_VER" "$NWG_GIT" "$tmp/src" >/dev/null 2>&1 \
       && ( cd "$tmp/src" && go build -o "$tmp/nwg-look" . >/dev/null 2>&1 ) \
       && [ -x "$tmp/nwg-look" ]; then
        hyprtk_run_root install -Dm755 "$tmp/nwg-look" "$BINDIR/nwg-look"
        rm -rf "$tmp"
        say "nwg-look: installed"
        return 0
    fi
    rm -rf "$tmp"
    say "nwg-look: build failed" >&2
    return 1
}

install_cliphist() {
    if have cliphist; then say "cliphist: already present"; return 0; fi
    [ -n "${CLIPHIST_DEPS[$HYPRTK_PM]:-}" ] && pkg_install ${CLIPHIST_DEPS[$HYPRTK_PM]} || true
    if ! have go || ! have git; then
        say "cliphist: go/git unavailable — skipping" >&2
        return 1
    fi
    say "cliphist: building from source (clipboard history)"
    local tmp
    tmp="$(mktemp -d)" || return 1
    if git clone --depth=1 "$CLIPHIST_GIT" "$tmp/src" >/dev/null 2>&1 \
       && ( cd "$tmp/src" && go build -o "$tmp/cliphist" . >/dev/null 2>&1 ) \
       && [ -x "$tmp/cliphist" ]; then
        hyprtk_run_root install -Dm755 "$tmp/cliphist" "$BINDIR/cliphist"
        rm -rf "$tmp"
        say "cliphist: installed"
        return 0
    fi
    rm -rf "$tmp"
    say "cliphist: build failed" >&2
    return 1
}

install_eza() {
    if have eza; then say "eza: already present"; return 0; fi
    # Prefer awww's rustup toolchain (recent); fall back to the distro cargo.
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
    if ! have cargo; then
        [ -n "${EZA_DEPS[$HYPRTK_PM]:-}" ] && pkg_install ${EZA_DEPS[$HYPRTK_PM]} || true
        [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
    fi
    if ! have cargo; then
        say "eza: cargo unavailable — skipping" >&2
        return 1
    fi
    say "eza: building from source (cargo)"
    local tmp
    tmp="$(mktemp -d)" || return 1
    if cargo install eza --locked --root "$tmp" >/dev/null 2>&1 && [ -x "$tmp/bin/eza" ]; then
        hyprtk_run_root install -Dm755 "$tmp/bin/eza" "$BINDIR/eza"
        rm -rf "$tmp"
        say "eza: installed"
        return 0
    fi
    rm -rf "$tmp"
    say "eza: build failed" >&2
    return 1
}

install_ippusb() {
    have ipp-usb || [ -x /usr/sbin/ipp-usb ] && { say "ipp-usb: already present"; return 0; }
    [ -n "${IPPUSB_DEPS[$HYPRTK_PM]:-}" ] && pkg_install ${IPPUSB_DEPS[$HYPRTK_PM]} || true
    if ! have go || ! have git; then
        say "ipp-usb: go/git unavailable — skipping" >&2
        return 1
    fi
    say "ipp-usb: building from source (driverless USB printing)"
    local tmp
    tmp="$(mktemp -d)" || return 1
    if git clone --depth=1 "$IPPUSB_GIT" "$tmp/src" >/dev/null 2>&1 \
       && ( cd "$tmp/src" && go build -ldflags "-s -w" -tags nethttpomithttp2 -mod=vendor -o "$tmp/ipp-usb" . >/dev/null 2>&1 ) \
       && [ -x "$tmp/ipp-usb" ]; then
        hyprtk_run_root mkdir -p /usr/sbin /etc/udev/rules.d /etc/ipp-usb /usr/share/ipp-usb/quirks
        hyprtk_run_root install -m755 "$tmp/ipp-usb" /usr/sbin/ipp-usb
        [ -f "$tmp/src/systemd-udev/71-ipp-usb.rules" ] \
            && hyprtk_run_root install -m644 "$tmp/src/systemd-udev/71-ipp-usb.rules" /etc/udev/rules.d/71-ipp-usb.rules
        [ -f "$tmp/src/ipp-usb.conf" ] \
            && hyprtk_run_root install -m644 "$tmp/src/ipp-usb.conf" /etc/ipp-usb/ipp-usb.conf
        [ -d "$tmp/src/ipp-usb-quirks" ] \
            && hyprtk_run_root cp -r "$tmp/src/ipp-usb-quirks/." /usr/share/ipp-usb/quirks/ 2>/dev/null || true
        rm -rf "$tmp"
        say "ipp-usb: installed (binary + udev rule)"
        return 0
    fi
    rm -rf "$tmp"
    say "ipp-usb: build failed" >&2
    return 1
}

install_wob() {
    have wob && { say "wob: already present"; return 0; }
    [ "$HYPRTK_PM" = xbps ] || return 0
    [ -n "${WOB_DEPS[$HYPRTK_PM]:-}" ] && pkg_install ${WOB_DEPS[$HYPRTK_PM]} || true
    if ! have meson || ! have ninja || ! have git; then
        say "wob: meson/ninja/git unavailable — skipping" >&2
        return 1
    fi
    say "wob: building $WOB_VER (volume/brightness overlay)"
    if build_meson "$WOB_GIT" "$WOB_VER" --prefix=/usr; then
        say "wob: installed"
        return 0
    fi
    say "wob: build failed" >&2
    return 1
}

# Clone + cmake build + install into /usr. $1 = repo name, $2 = pkg-config
# module to skip on (empty for the app itself).
build_hypr_cmake() {
    local repo="$1" mod="$2"
    if [ -n "$mod" ] && pkg-config --exists "$mod" 2>/dev/null; then
        say "  $repo: already present"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)" || return 1
    say "  $repo: building"
    if git clone --depth=1 "https://github.com/hyprwm/$repo" "$tmp/$repo" >/dev/null 2>&1 \
       && ( cd "$tmp/$repo" \
            && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF >/dev/null 2>&1 \
            && cmake --build build -j"$(nproc 2>/dev/null || echo 2)" >/dev/null 2>&1 \
            && hyprtk_run_root cmake --install build >/dev/null 2>&1 ); then
        hyprtk_run_root ldconfig >/dev/null 2>&1 || true
        rm -rf "$tmp"
        return 0
    fi
    rm -rf "$tmp"
    say "  $repo: build failed" >&2
    return 1
}

# Build the Hyprland libraries the app links. $1 = app id ("picker"|"sunset").
ensure_hypr_libs() {
    build_hypr_cmake hyprland-protocols hyprland-protocols || return 1
    build_hypr_cmake hyprutils        hyprutils           || return 1
    build_hypr_cmake hyprwayland-scanner hyprwayland-scanner || return 1
    [ "$1" = sunset ] && { build_hypr_cmake hyprlang hyprlang || return 1; }
    return 0
}

_build_hypr_app() {  # $1 repo/app $2 libs-app-id
    local app="$1" id="$2"
    if have "$app"; then say "$app: already present"; return 0; fi
    [ -n "${HYPRCHAIN_DEPS[$HYPRTK_PM]:-}" ] && pkg_install ${HYPRCHAIN_DEPS[$HYPRTK_PM]} || true
    if ! have cmake || ! have git || ! have pkg-config; then
        say "$app: cmake/git/pkg-config unavailable — skipping" >&2
        return 1
    fi
    say "$app: building the Hyprland library chain + app"
    ensure_hypr_libs "$id" || { say "$app: library chain failed" >&2; return 1; }
    build_hypr_cmake "$app" "" || { say "$app: build failed" >&2; return 1; }
    say "$app: installed"
    return 0
}

# hyprpicker is packaged on every family except Alpine (archive / cppiber PPA /
# COPR elsewhere), so only build the chain there. hyprsunset likewise only goes
# missing on Void. Both are no-ops (success) on the other families.
install_hyprpicker() {
    [ "$HYPRTK_PM" = apk ] || return 0
    _build_hypr_app hyprpicker picker
}

install_hyprsunset() {
    [ "$HYPRTK_PM" = xbps ] || return 0
    _build_hypr_app hyprsunset sunset
}

install_starship() {
    if have starship; then say "starship: already present"; return 0; fi
    pkg_install curl ca-certificates
    if ! have curl; then say "starship: curl unavailable — skipping" >&2; return 1; fi
    say "starship: installing $STARSHIP_VER (upstream installer)"
    local tmp
    tmp="$(mktemp)" || return 1
    if curl -fsSL --max-time 120 https://starship.rs/install.sh -o "$tmp" \
       && hyprtk_run_root sh "$tmp" -y -b "$BINDIR" >/dev/null 2>&1; then
        rm -f "$tmp"
        say "starship: installed"
        return 0
    fi
    rm -f "$tmp"
    say "starship: install failed — the prompt falls back gracefully" >&2
    return 1
}

# ── Main ────────────────────────────────────────────────────────────────────
FAILED=0
install_gtk4_layer_shell || FAILED=$((FAILED + 1))
install_swappy            || FAILED=$((FAILED + 1))
install_nwg_look          || FAILED=$((FAILED + 1))
install_starship          || FAILED=$((FAILED + 1))
install_cliphist          || FAILED=$((FAILED + 1))
install_eza               || FAILED=$((FAILED + 1))
install_ippusb            || FAILED=$((FAILED + 1))
install_hyprpicker        || FAILED=$((FAILED + 1))
install_hyprsunset        || FAILED=$((FAILED + 1))
install_wob               || FAILED=$((FAILED + 1))

if [ "$FAILED" -ne 0 ]; then
    say "$FAILED app(s) could not be built — the rest of the install continues"
fi
exit 0
