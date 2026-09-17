#!/bin/bash
# ── awww (wallpaper daemon) cross-distro installer ──────────────────────────
# awww is the wallpaper daemon the dotfiles drive (`awww img`); it is the
# renamed successor to swww. Upstream ships no distro packages for it, so the
# only places it exists are the Arch AUR — and now this script.
#
# Acquisition ladder:
#   1. already present               → nothing to do
#   2. native repo package           → Void/Alpine ship `swww`; awww/swww
#                                      symlinks are created in /usr/local/bin
#   3. source build via cargo        → Debian/Ubuntu, Fedora/RHEL, openSUSE (and
#                                      as a fallback anywhere): install the
#                                      per-family build deps, ensure a cargo that
#                                      meets upstream's MSRV (bootstrapping Rust
#                                      with rustup when the distro's rustc is
#                                      older), clone the pinned release and
#                                      `cargo build --release`, then install
#                                      awww + awww-daemon into /usr/local/bin
#   4. otherwise                     → warn + print the manual steps (non-fatal)
#
# Arch is deliberately skipped here: hypr/packages/hyprland.sh installs awww
# from the AUR. Every other family had no package at all — that was the gap.
# ─────────────────────────────────────────────────────────────────────────────
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=installer/scripts/pkgmanager.sh
. "$SELF_DIR/pkgmanager.sh"

# Pinned upstream release (workspace rust-version 1.89, Rust edition 2024).
AWWW_VERSION="v0.12.1"
AWWW_GIT="https://codeberg.org/LGFae/awww.git"
AWWW_MSRV="1.89.0"
BINDIR="/usr/local/bin"

say() { echo "awww: $*"; }

# ── Per-family data ────────────────────────────────────────────────────────
# Native packages that provide a compatible daemon. On Void/Alpine `swww` is
# the packaged name and provides `swww`/`swww-daemon`; we symlink awww names.
declare -A NATIVE_PKG
NATIVE_PKG[xbps]="swww"
NATIVE_PKG[apk]="swww"

# Build dependencies for the source build. awww's `common/build.rs` probes
# liblz4 (>= 1.8) through pkg-config and links it at runtime; the daemon build
# needs the wayland-client + wayland-protocols XML files (viewporter,
# fractional-scale-v1); rustup (and the build) need a C toolchain + curl.
declare -A BUILD_DEPS
BUILD_DEPS[apt]="build-essential pkg-config git curl ca-certificates libwayland-dev wayland-protocols liblz4-dev libxkbcommon-dev"
BUILD_DEPS[dnf]="gcc gcc-c++ make pkgconf-pkg-config git curl ca-certificates wayland-devel wayland-protocols-devel lz4-devel libxkbcommon-devel"
BUILD_DEPS[zypper]="gcc gcc-c++ make pkg-config git curl ca-certificates wayland-devel wayland-protocols-devel liblz4-devel libxkbcommon-devel"
BUILD_DEPS[xbps]="base-devel pkg-config git curl wayland-devel wayland-protocols liblz4-devel libxkbcommon-devel"
BUILD_DEPS[apk]="build-base pkgconf git curl wayland-dev wayland-protocols lz4-dev libxkbcommon-dev"

# Distro Rust toolchain, tried before the rustup bootstrap. Most current
# releases ship a cargo at or above AWWW_MSRV, so installing it from the distro
# is far cheaper than downloading a whole rustup toolchain; when the packaged
# compiler is too old, ensure_cargo falls back to rustup as before.
declare -A RUST_PKG
RUST_PKG[apt]="cargo rustc"
RUST_PKG[dnf]="cargo rust"
RUST_PKG[zypper]="cargo rust"
RUST_PKG[xbps]="cargo rust"
RUST_PKG[apk]="cargo rust"

# ── Dry run ────────────────────────────────────────────────────────────────
if [ -n "${HYPRTK_DRYRUN:-}" ]; then
    echo "awww: would install the wallpaper daemon for $HYPRTK_PM"
    echo "awww: native package: ${NATIVE_PKG[$HYPRTK_PM]:-(none — source build)}"
    echo "awww: build deps: ${BUILD_DEPS[$HYPRTK_PM]:-(none)}"
    exit 0
fi

# ── Helpers ────────────────────────────────────────────────────────────────

# 0 when version $1 >= $2 (numeric dot-separated), 1 otherwise.
ver_ge() {
    local a="$1" b="$2" IFS=.
    # shellcheck disable=SC2206
    local av=($a) bv=($b) i
    for i in 0 1 2; do
        local x="${av[$i]:-0}" y="${bv[$i]:-0}"
        [ "$x" -gt "$y" ] 2>/dev/null && return 0
        [ "$x" -lt "$y" ] 2>/dev/null && return 1
    done
    return 0
}

cargo_new_enough() {
    command -v cargo >/dev/null 2>&1 || return 1
    local v
    v="$(cargo --version 2>/dev/null | awk '{print $2}')"
    [ -n "$v" ] && ver_ge "$v" "$AWWW_MSRV"
}

# awww's daemon implementation provides the wl_surface preferred_buffer_scale /
# preferred_buffer_transform handlers, which only exist once libwayland >= 1.22.
# Older bases (Debian 12 / bookworm ships 1.21) therefore cannot compile it —
# detect that up front rather than after a rustup download and a failed build.
wayland_new_enough() {
    command -v pkg-config >/dev/null 2>&1 || return 1
    local v
    v="$(pkg-config --modversion wayland-client 2>/dev/null)" || return 1
    [ -n "$v" ] && ver_ge "$v" "1.22"
}

# Ensure a cargo that satisfies upstream's MSRV, or return non-zero. The distro
# toolchain is used when it is new enough; otherwise Rust is bootstrapped with
# rustup (the MSRV moves ahead of every LTS release's packaged rustc).
ensure_cargo() {
    cargo_new_enough && return 0

    # Prefer the distro toolchain when one is packaged — it is a normal package
    # install instead of a ~200 MB rustup download. Only used if it satisfies
    # the MSRV; otherwise fall through to rustup.
    if [ -n "${RUST_PKG[$HYPRTK_PM]:-}" ]; then
        say "no cargo >= $AWWW_MSRV yet — trying the distro toolchain (${RUST_PKG[$HYPRTK_PM]})"
        pkg_install ${RUST_PKG[$HYPRTK_PM]} || true
        export PATH="$HOME/.cargo/bin:$PATH"
        cargo_new_enough && return 0
    fi

    say "no cargo >= $AWWW_MSRV on the system — installing Rust via rustup"
    local tmp
    tmp="$(mktemp)" || return 1
    if ! curl -fsSL --max-time 120 https://sh.rustup.rs -o "$tmp"; then
        rm -f "$tmp"
        say "could not download the rustup installer (network?)"
        return 1
    fi
    sh "$tmp" -y --profile minimal --default-toolchain stable
    rm -f "$tmp"
    export PATH="$HOME/.cargo/bin:$PATH"

    cargo_new_enough
}

# Point awww names at an already-installed swww (Void/Alpine package).
link_swww_to_awww() {
    local swww daemon
    swww="$(command -v swww 2>/dev/null)"
    daemon="$(command -v swww-daemon 2>/dev/null)"
    [ -n "$swww" ]   && hyprtk_run_root ln -sf "$swww"   "$BINDIR/awww"
    [ -n "$daemon" ] && hyprtk_run_root ln -sf "$daemon" "$BINDIR/awww-daemon"
    [ -n "$swww" ]
}

manual_steps() {
    local why="$1"
    echo "awww: $why" >&2
    echo "awww: awww has no package on this distro — install it manually:" >&2
    if [ -n "${BUILD_DEPS[$HYPRTK_PM]:-}" ]; then
        echo "  1. packages: ${BUILD_DEPS[$HYPRTK_PM]}" >&2
    fi
    echo "  2. rustup toolchain:  https://rustup.rs  (cargo >= $AWWW_MSRV)" >&2
    echo "  3. git clone --depth=1 --branch $AWWW_VERSION $AWWW_GIT" >&2
    echo "  4. cd awww && cargo build --release --locked" >&2
    echo "  5. sudo install -Dm755 target/release/awww{,-daemon} -t $BINDIR" >&2
}

# ── Source build ───────────────────────────────────────────────────────────
build_from_source() {
    if [ -n "${BUILD_DEPS[$HYPRTK_PM]:-}" ]; then
        say "installing build dependencies: ${BUILD_DEPS[$HYPRTK_PM]}"
        pkg_install ${BUILD_DEPS[$HYPRTK_PM]} || true
    else
        say "no build-dependency list for $HYPRTK_PM — assuming a toolchain is present"
    fi

    if ! wayland_new_enough; then
        manual_steps "libwayland < 1.22 (Debian 12 ships 1.21) — awww needs the wl_surface preferred_buffer_scale events; use a newer base or backports"
        return 1
    fi

    if ! ensure_cargo; then
        manual_steps "cargo >= $AWWW_MSRV is unavailable"
        return 1
    fi

    local tmp
    tmp="$(mktemp -d)" || return 1
    say "cloning awww $AWWW_VERSION"
    if ! git clone --depth=1 --branch "$AWWW_VERSION" "$AWWW_GIT" "$tmp/awww"; then
        rm -rf "$tmp"
        manual_steps "git clone failed"
        return 1
    fi

    say "building awww — this compiles from source and can take a few minutes"
    if ! ( cd "$tmp/awww" && cargo build --release --locked ); then
        rm -rf "$tmp"
        manual_steps "cargo build failed"
        return 1
    fi

    hyprtk_run_root install -Dm755 "$tmp/awww/target/release/awww"        "$BINDIR/awww"
    hyprtk_run_root install -Dm755 "$tmp/awww/target/release/awww-daemon" "$BINDIR/awww-daemon"
    # swww compatibility names, so scripts written for either name work.
    hyprtk_run_root ln -sf awww        "$BINDIR/swww"
    hyprtk_run_root ln -sf awww-daemon "$BINDIR/swww-daemon"
    rm -rf "$tmp"
    say "installed awww + awww-daemon to $BINDIR"
}

# ── Main ───────────────────────────────────────────────────────────────────
if command -v awww >/dev/null 2>&1 && command -v awww-daemon >/dev/null 2>&1; then
    say "already installed: $(command -v awww)"
    exit 0
fi

case "$HYPRTK_PM" in
    pacman)
        # hypr/packages/hyprland.sh installs awww from the AUR; nothing to do.
        say "Arch: awww is provided by the AUR via the hyprland package step"
        exit 0
        ;;
    emerge)
        manual_steps "Gentoo packages are never installed automatically"
        exit 0
        ;;
    nix)
        say "NixOS: add awww to your configuration, e.g.:"
        say "  inputs.awww.url = \"git+$AWWW_GIT\";"
        say "  environment.systemPackages = [ inputs.awww.packages.\${pkgs.stdenv.hostPlatform.system}.awww ];"
        exit 0
        ;;
esac

native="${NATIVE_PKG[$HYPRTK_PM]:-}"
if [ -n "$native" ]; then
    say "installing native package: $native"
    pkg_install "$native" || true
    if command -v swww >/dev/null 2>&1 || command -v awww >/dev/null 2>&1; then
        link_swww_to_awww || true
        say "wallpaper daemon ready via $native"
        exit 0
    fi
    say "native package did not provide a daemon — falling back to a source build"
fi

if build_from_source; then
    exit 0
fi

manual_steps "automatic installation was not possible"
exit 0
