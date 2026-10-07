#!/bin/bash
###############################################################################
# hyprtk Arch Linux ISO builder
#
# Builds a live Arch Linux ISO from the stock archiso `releng` profile with the
# hyprtk desktop already installed and preconfigured:
#
#   * every package in packages.hyprtk, verified against the sync databases
#   * the AUR extras in aur-packages.txt, built on the host (best-effort)
#   * matuwall, built from source on the host
#   * the hyprtk dotfiles vendored into /etc/skel (a trimmed ~/hyprtk repo plus
#     relative ~/.config symlinks) so every new user gets the desktop; the live
#     user `hyprtk` is created from that skel
#   * SDDM autologin straight into a pywal-themed Hyprland session
#
# Usage:  ./hyprtk-iso-builder.sh [options]
#         ./hyprtk-iso-builder.sh --profile-only     # assemble profile, don't build
#
# Run as your normal user; the script re-execs itself with sudo.
###############################################################################

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$SELF_DIR/airootfs"
PKGS_EXTRA="$SELF_DIR/packages.hyprtk"
AUR_LIST="$SELF_DIR/aur-packages.txt"
ORIG_ARGS=("$@")

# Official-repo build backends needed by the curated AUR list. makepkg runs
# with --nodeps (so it never touches the host), which means build backends have
# to be present already. Keep in sync with aur-packages.txt.
AUR_HOST_DEPS="python-poetry-core"

# ── Defaults ───────────────────────────────────────────────────────────────
ISO_NAME="${ISO_NAME:-hyprtk}"
ISO_VERSION="${ISO_VERSION:-$(date +%Y.%m.%d)}"
ISO_LABEL="${ISO_LABEL:-HYPRTK_$(date +%Y%m)}"
ISO_PUBLISHER="${ISO_PUBLISHER:-hyprtk}"
ISO_APPLICATION="${ISO_APPLICATION:-Hyprtk Live}"
LIVE_USER="hyprtk"

HYPRTK_DIR="${HYPRTK_DIR:-}"
ARCHISO_RELENG="${ARCHISO_RELENG:-/usr/share/archiso/configs/releng}"
BUILD_ROOT="${BUILD_ROOT:-/tmp/hyprtk-iso-build}"
OUT_DIR="${OUT_DIR:-}"
DO_AUR=1
DO_MATUWALL=1
PROFILE_ONLY=0
KEEP_WORK=0
ASSUME_YES=0

# ── Colors ─────────────────────────────────────────────────────────────────
MAGENTA='\033[35m'; CYAN='\033[0;36m'; WHITE='\033[0;37m'
RED='\033[1;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

_info() { printf "${CYAN}  → ${WHITE}%s${NC}\n" "$*"; }
_ok()   { printf "${CYAN}  ✓ ${WHITE}%s${NC}\n" "$*"; }
_warn() { printf "${YELLOW}  ! ${WHITE}%s${NC}\n" "$*"; }
_fail() { printf "${RED}  ✗ ${WHITE}%s${NC}\n" "$*" >&2; }
_die()  { _fail "$*"; exit 1; }

_box() {
    printf "${MAGENTA}+==========================================================+${NC}\n"
    printf "${MAGENTA}|${NC}  ${CYAN}%-56s${NC}${MAGENTA}|${NC}\n" "$1"
    printf "${MAGENTA}+==========================================================+${NC}\n"
}

_usage() {
    cat <<'EOF'
hyprtk Arch Linux ISO builder

Options:
  -y, --yes                Do not ask for confirmation.
  --hyprtk-dir DIR         hyprtk dotfiles source (default: $HYPRTK_DIR,
                           ~/hyprtk, else cloned from hyprtk/dotfiles).
  --iso-name NAME          ISO file name (default: hyprtk).
  --iso-label LABEL        ISO label, <=32 chars (default: HYPRTK_<YYYYMM>).
  --out-dir DIR            Where the ISO is written (default: your home).
  --build-root DIR         Scratch dir for profile/work (default: /tmp/hyprtk-iso-build).
  --no-aur                 Skip building the AUR extras.
  --no-matuwall            Skip building matuwall from source.
  --profile-only           Assemble the profile and stop (no ISO build).
  --keep-work              Keep the assembled profile after the build.
  -h, --help               This help.
EOF
}

# ── Argument parsing ───────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)        ASSUME_YES=1 ;;
        --hyprtk-dir)    HYPRTK_DIR="${2:?}"; shift ;;
        --iso-name)      ISO_NAME="${2:?}"; shift ;;
        --iso-label)     ISO_LABEL="${2:?}"; shift ;;
        --out-dir)       OUT_DIR="${2:?}"; shift ;;
        --build-root)    BUILD_ROOT="${2:?}"; shift ;;
        --no-aur)        DO_AUR=0 ;;
        --no-matuwall)   DO_MATUWALL=0 ;;
        --profile-only)  PROFILE_ONLY=1 ;;
        --keep-work)     KEEP_WORK=1 ;;
        -h|--help)       _usage; exit 0 ;;
        *) _die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

# ── Re-exec as root (mkarchiso + pacman need it) ───────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    _info "Root is required for mkarchiso - re-running with sudo..."
    _reexec=("${ORIG_ARGS[@]}")
    [ -n "$HYPRTK_DIR" ] && _reexec=(--hyprtk-dir "$HYPRTK_DIR" "${_reexec[@]}")
    exec sudo bash "$(readlink -f "$0")" ${_reexec[@]+"${_reexec[@]}"}
fi

REAL_USER="${SUDO_USER:-$(id -un)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
[ -n "$REAL_HOME" ] || REAL_HOME="/root"

BUILD_ROOT="${BUILD_ROOT%/}"
PROFILE="$BUILD_ROOT/profile"
WORK="$BUILD_ROOT/work"
AUR_STAGE="$PROFILE/airootfs/var/cache/hyprtk-aur"
MTW_STAGE="$PROFILE/airootfs/var/cache/hyprtk/matuwall-root"
SKEL_TAR="$PROFILE/airootfs/usr/share/hyprtk-iso/skel.tar"
HOST_CACHE="$REAL_HOME/.cache/hyprtk-iso"

if [ "$PROFILE_ONLY" -eq 1 ]; then KEEP_WORK=1; fi

cleanup() {
    if [ "$KEEP_WORK" -eq 0 ]; then
        rm -rf "$BUILD_ROOT"
    fi
}
trap cleanup EXIT

# Run a command as the invoking (non-root) user with a sane HOME.
_as_user() {
    runuser -u "$REAL_USER" -- \
        env HOME="$REAL_HOME" USER="$REAL_USER" LOGNAME="$REAL_USER" \
        XDG_CACHE_HOME="$REAL_HOME/.cache" "$@"
}

# ── Host dependency checks ─────────────────────────────────────────────────
_ensure_host_deps() {
    local -a need=()
    command -v mkarchiso >/dev/null 2>&1 || need+=(archiso)
    command -v rsync     >/dev/null 2>&1 || need+=(rsync)
    if [ "${#need[@]}" -gt 0 ]; then
        _info "Installing host build tools: ${need[*]}"
        pacman -S --noconfirm --needed "${need[@]}"
    fi
    [ -f "$ARCHISO_RELENG/packages.x86_64" ] \
        || _die "archiso releng profile not found under $ARCHISO_RELENG"
    command -v mkarchiso >/dev/null 2>&1 || _die "mkarchiso still not available"
}

# ── Locate the hyprtk dotfiles source ──────────────────────────────────────
_resolve_hyprtk() {
    local c
    for c in "$HYPRTK_DIR" "$REAL_HOME/hyprtk"; do
        if [ -n "$c" ] && [ -d "$c/hypr" ] && [ -d "$c/configs" ]; then
            printf '%s' "$c"; return
        fi
    done
    local dst="$HOST_CACHE/hyprtk-src"
    _info "No hyprtk source found locally - cloning hyprtk/dotfiles..." >&2
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    git clone --depth=1 https://github.com/hyprtk/dotfiles.git "$dst" >&2
    printf '%s' "$dst"
}

# ── Package availability (packages and groups) ─────────────────────────────
_pkg_exists() {
    pacman -Si "$1" >/dev/null 2>&1 || pacman -Sg "$1" >/dev/null 2>&1
}

# ── Profile assembly ───────────────────────────────────────────────────────
_prepare_profile() {
    _info "Assembling archiso profile from releng: $PROFILE"
    rm -rf "$PROFILE" "$WORK"
    mkdir -p "$PROFILE"
    cp -aT "$ARCHISO_RELENG" "$PROFILE"

    # SDDM owns the display now - never leave releng's tty autologin in place.
    rm -f "$PROFILE/airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf"

    sed -i \
        -e "s|^iso_name=.*|iso_name=\"$ISO_NAME\"|" \
        -e "s|^iso_version=.*|iso_version=\"$ISO_VERSION\"|" \
        -e "s|^iso_label=.*|iso_label=\"$ISO_LABEL\"|" \
        -e "s|^iso_publisher=.*|iso_publisher=\"$ISO_PUBLISHER\"|" \
        -e "s|^iso_application=.*|iso_application=\"$ISO_APPLICATION\"|" \
        "$PROFILE/profiledef.sh"

    # Merge our airootfs overlay on top of releng's.
    cp -aT "$OVERLAY_DIR" "$PROFILE/airootfs"
    # The skel is packed into a tar by _build_skel (modes); drop the raw copy.
    rm -rf "$PROFILE/airootfs/usr/share/hyprtk-iso/skel"

    chmod +x "$PROFILE/airootfs/root/customize_airootfs.sh"
    chmod +x "$PROFILE/airootfs/usr/local/bin/hyprtk-first-run"
    chmod +x "$PROFILE/airootfs/usr/local/bin/hyprtk-deploy"
    chmod 0440 "$PROFILE/airootfs/etc/sudoers.d/10-hyprtk-live"
}

_merge_packages() {
    local pkgfile="$PROFILE/packages.x86_64"
    local -A seen=()
    local line p missing=() added=0

    while IFS= read -r line; do
        p="${line%%#*}"; p="${p//[[:space:]]/}"
        [ -n "$p" ] && seen["$p"]=1
    done < "$pkgfile"

    while IFS= read -r line; do
        p="${line%%#*}"; p="${p//[[:space:]]/}"
        [ -n "$p" ] || continue
        [ -n "${seen[$p]:-}" ] && continue
        if _pkg_exists "$p"; then
            printf '%s\n' "$p" >> "$pkgfile"
            seen["$p"]=1
            added=$((added + 1))
        else
            missing+=("$p")
        fi
    done < "$PKGS_EXTRA"

    _ok "Added $added hyprtk package(s) to releng's package list"
    if [ "${#missing[@]}" -gt 0 ]; then
        _warn "Dropped ${#missing[@]} package(s) not found in the repos:"
        printf "${YELLOW}      %s${NC}\n" "${missing[*]}"
    fi
}

# ── /etc/skel generation ───────────────────────────────────────────────────
# A relative symlink inside skel, e.g. ~/.config/hypr -> ../hyprtk/hypr.
# Targets trimmed out of the vendored copy are skipped, so an excluded asset
# (screenshots, papirus-icons, ...) never yields a dangling link.
SKEL=""
_skel_link() {
    local link_rel="$1" tgt_rel="$2"
    local link="$SKEL/$link_rel" tgt="$SKEL/hyprtk/$tgt_rel"
    [ -e "$tgt" ] || return 0
    mkdir -p "$(dirname "$link")"
    local rel
    rel="$(realpath -m --relative-to="$(dirname "$link")" "$tgt")"
    ln -sfn "$rel" "$link"
}

_build_skel() {
    local src="$1"
    # Stage into a scratch dir, then tar it: mkarchiso copies the profile's
    # airootfs with --no-preserve=mode, which strips the exec bits off every
    # script and binary in the skel tree (oh-my-posh, gum, all the ~/hyprtk
    # scripts). A tar archive preserves them; customize extracts it.
    SKEL="$BUILD_ROOT/skel"
    rm -rf "$SKEL"
    mkdir -p "$SKEL/hyprtk"

    _info "Vendoring trimmed hyprtk tree"
    # installer/standalone is the target of ~/.local/bin, so running the bar or
    # hyprtk-usb installers on the build host writes their launchers straight
    # into the source tree (see .gitignore). Those launchers are generated and
    # carry absolute /home/<builder> paths, so never vendor them: the target
    # user's hyprtk-first-run (re)creates them for its own HOME. Shipping the
    # stale ones made first-run skip the bar install (the launcher existed and
    # was executable) and left a dangling ~/.local/bin/hyprtk-bar.
    rsync -a --delete \
        --exclude='.git/' \
        --exclude='.scratch/' \
        --exclude='install.log' \
        --exclude='assets/screenshots/' \
        --exclude='distro/' \
        --exclude='configs/root/.cache/' \
        --exclude='configs/root/.local/' \
        --exclude='installer/standalone/hyprtk-bar' \
        --exclude='installer/standalone/hyprtk-bar-*-toggle.sh' \
        --exclude='installer/standalone/wal' \
        --exclude='installer/standalone/hyprtk-usb-gui' \
        --exclude='installer/standalone/hyprtk-usb-helper' \
        "$src"/ "$SKEL/hyprtk"/

    # Committed skel extras (the hyprtk-first-run systemd unit, etc.).
    cp -aT "$OVERLAY_DIR/usr/share/hyprtk-iso/skel" "$SKEL"

    _info "Creating ~/.config symlinks in /etc/skel"
    _skel_link ".config/alacritty"        "configs/alacritty"
    _skel_link ".config/ranger"           "configs/ranger"
    _skel_link ".config/vim"              "configs/vim"
    _skel_link ".config/nvim"             "configs/nvim"
    _skel_link ".config/starship.toml"    "configs/starship/starship.toml"
    _skel_link ".config/rofi"             "configs/rofi"
    _skel_link ".config/wal"              "configs/wal"
    _skel_link ".config/btop"             "configs/btop"
    _skel_link ".config/gtk-3.0"          "configs/gtk/gtk-3.0"
    _skel_link ".config/gtk-4.0"          "configs/gtk/gtk-4.0"
    _skel_link ".local/share/themes"      "assets/themes"
    _skel_link ".local/share/icons"       "assets/papirus-icons/icons"
    _skel_link ".config/xfce4"            "configs/xfce4"
    _skel_link ".config/Thunar"           "configs/Thunar"
    _skel_link ".config/Mousepad"         "configs/Mousepad"
    _skel_link ".config/hypr"             "hypr"
    _skel_link ".config/fastfetch"        "configs/fastfetch"
    _skel_link ".config/swaylock/config"  "configs/swaylock/config"
    _skel_link ".config/swappy"           "configs/swappy"
    _skel_link ".config/hyprlogout"       "configs/hyprlogout"
    _skel_link ".config/waypaper"         "configs/waypaper"
    _skel_link ".config/zshrc"            "configs/zshrc"
    _skel_link ".config/ohmyposh"         "configs/ohmyposh"
    _skel_link ".config/matuwall/config.toml" "configs/matuwall/config.toml"
    _skel_link ".config/wob"              "configs/wob"
    _skel_link ".local/bin"               "installer/standalone"
    _skel_link ".zshrc"                   ".zshrc"

    _bake_oh_my_zsh "$SKEL"

    _info "Packing /etc/skel (tar preserves the exec bits mkarchiso strips)"
    mkdir -p "$(dirname "$SKEL_TAR")"
    tar -cpf "$SKEL_TAR" -C "$SKEL" .
    rm -rf "$SKEL"
    _ok "Skel archive: $(du -h "$SKEL_TAR" | cut -f1)"
}

# Bake oh-my-zsh + the plugins the shipped zshrc expects, so a new user's shell
# works offline (1-install.sh clones these at install time).
_bake_oh_my_zsh() {
    local tmp="$1"
    local omz="$tmp/.oh-my-zsh"
    if ! command -v git >/dev/null 2>&1; then
        _warn "git missing - oh-my-zsh not baked"
        return 0
    fi
    _info "Baking oh-my-zsh + plugins"
    rm -rf "$omz"
    if ! git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$omz" >/dev/null 2>&1; then
        _warn "oh-my-zsh clone failed - the shell will lack it"
        return 0
    fi
    rm -rf "$omz/.git"
    mkdir -p "$omz/custom/plugins"
    local repo name
    for repo in "zsh-users/zsh-autosuggestions" \
                "zsh-users/zsh-syntax-highlighting" \
                "zdharma-continuum/fast-syntax-highlighting"; do
        name="${repo##*/}"
        if git clone --depth=1 "https://github.com/$repo" "$omz/custom/plugins/$name" >/dev/null 2>&1; then
            rm -rf "$omz/custom/plugins/$name/.git"
        else
            _warn "plugin clone failed: $name"
        fi
    done
    # hyprtk overrides oh-my-zsh.sh with its own copy (as 1-install.sh does).
    ln -sfn ../hyprtk/configs/oh-my-zsh/oh-my-zsh.sh "$omz/oh-my-zsh.sh"
    _ok "oh-my-zsh baked ($(du -sh "$omz" | cut -f1))"
}

# ── AUR extras (built on the host as the real user) ────────────────────────
_build_aur() {
    if [ "$DO_AUR" -ne 1 ]; then _info "Skipping AUR extras (--no-aur)"; return 0; fi
    [ -f "$AUR_LIST" ] || return 0

    local -a pkgs=()
    local line p
    while IFS= read -r line; do
        p="${line%%#*}"; p="${p//[[:space:]]/}"
        [ -n "$p" ] && pkgs+=("$p")
    done < "$AUR_LIST"
    [ "${#pkgs[@]}" -gt 0 ] || return 0

    if ! command -v makepkg >/dev/null 2>&1; then
        _warn "makepkg not found - skipping AUR extras (install base-devel)"
        return 0
    fi
    pacman -Qi base-devel >/dev/null 2>&1 \
        || _warn "base-devel not installed - some AUR builds will fail"
    # shellcheck disable=SC2086
    pacman -S --needed --noconfirm $AUR_HOST_DEPS >/dev/null 2>&1 \
        || _warn "could not install AUR host build deps: $AUR_HOST_DEPS"

    _info "Building ${#pkgs[@]} AUR package(s) as $REAL_USER (best-effort)"
    local srcdir="$HOST_CACHE/aur"
    rm -rf "$srcdir"; mkdir -p "$srcdir" "$AUR_STAGE"
    chown -R "$REAL_USER" "$srcdir" 2>/dev/null || true

    local -a ok=() bad=()
    for p in "${pkgs[@]}"; do
        local d="$srcdir/$p"
        if ! _as_user git clone --depth=1 "https://aur.archlinux.org/$p.git" "$d" >/dev/null 2>&1; then
            _warn "could not fetch $p"; bad+=("$p"); continue
        fi
        if _as_user bash -c "cd '$d' && makepkg -f --nocheck --nodeps --skippgpcheck --noconfirm" >"$srcdir/$p.log" 2>&1; then
            cp -f "$d"/*.pkg.tar.* "$AUR_STAGE"/ 2>/dev/null || true
            ok+=("$p")
        else
            _warn "build failed: $p (log: $srcdir/$p.log)"
            bad+=("$p")
        fi
    done

    if [ "${#ok[@]}" -gt 0 ]; then _ok "AUR built: ${ok[*]}"; fi
    if [ "${#bad[@]}" -gt 0 ]; then _warn "AUR skipped: ${bad[*]}"; fi
    return 0
}

# ── matuwall (C/meson, built from source on the host) ──────────────────────
_build_matuwall() {
    if [ "$DO_MATUWALL" -ne 1 ]; then _info "Skipping matuwall (--no-matuwall)"; return 0; fi
    if ! command -v meson >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
        _warn "meson/ninja missing - skipping matuwall (SUPER+W picker will be absent)"
        return 0
    fi

    _info "Building matuwall from source"
    local d="$HOST_CACHE/matuwall"
    rm -rf "$d"; mkdir -p "$(dirname "$d")"
    if ! _as_user git clone --depth=1 https://github.com/naurissteins/Matuwall.git "$d" >/dev/null 2>&1; then
        _warn "could not clone Matuwall - skipping"; return 0
    fi
    chown -R "$REAL_USER" "$d" 2>/dev/null || true
    if _as_user bash -c \
            "cd '$d' && meson setup build --prefix=/usr --buildtype=release && ninja -C build" \
            >"$d/build.log" 2>&1; then
        rm -rf "$MTW_STAGE"; mkdir -p "$MTW_STAGE"
        if DESTDIR="$MTW_STAGE" ninja -C "$d/build" install >>"$d/build.log" 2>&1; then
            _ok "matuwall staged"
        else
            _warn "matuwall install step failed (log: $d/build.log)"
        fi
    else
        _warn "matuwall build failed (log: $d/build.log)"
    fi
    return 0
}

# ── Build ──────────────────────────────────────────────────────────────────
_run_mkarchiso() {
    [ -n "$OUT_DIR" ] || OUT_DIR="$REAL_HOME"
    mkdir -p "$OUT_DIR"
    _info "Running mkarchiso (this takes a while)..."
    mkarchiso -v -w "$WORK" -o "$OUT_DIR" "$PROFILE"

    local iso
    iso="$(find "$OUT_DIR" -maxdepth 1 -name "$ISO_NAME-*.iso" -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | head -1 | cut -d' ' -f2-)"
    [ -n "$iso" ] || iso="$(find "$OUT_DIR" -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | head -1 | cut -d' ' -f2-)"
    [ -n "$iso" ] && [ -f "$iso" ] || _die "no ISO produced in $OUT_DIR"

    _box "ISO BUILD COMPLETE"
    _ok "ISO:  $iso"
    _ok "Size: $(du -h "$iso" | cut -f1)"
    printf "${WHITE}  Live user 'hyprtk' (password 'hyprtk', passwordless sudo) autologins to Hyprland.${NC}\n"
    printf "${WHITE}  Users created later inherit the desktop from /etc/skel.${NC}\n"
}

# ── Main ───────────────────────────────────────────────────────────────────
_box "HYPRTK ARCH LINUX ISO BUILDER"
echo
_ensure_host_deps

HYPRTK_SRC="$(_resolve_hyprtk)"
_ok "hyprtk source: $HYPRTK_SRC"

mkdir -p "$HOST_CACHE"
chown "$REAL_USER" "$HOST_CACHE" 2>/dev/null || true

if [ "$ASSUME_YES" -ne 1 ] && [ "$PROFILE_ONLY" -ne 1 ]; then
    printf "${WHITE}Build a live ISO from this source? [y/N] ${NC}"
    read -r reply
    if [[ ! "$reply" =~ ^[Yy] ]]; then echo "Aborted."; exit 0; fi
fi

_prepare_profile
_merge_packages
_build_skel "$HYPRTK_SRC"
_build_matuwall
_build_aur

if [ "$PROFILE_ONLY" -eq 1 ]; then
    _box "PROFILE READY (no build)"
    _ok "Profile: $PROFILE"
    _ok "Kept at $BUILD_ROOT (--keep-work)"
    exit 0
fi

_run_mkarchiso
