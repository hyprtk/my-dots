#!/bin/bash
# hyprtk-bar installer for Hyprtk
# Creates a venv, installs the app, and drops a launcher on PATH.
# Usage: ./install.sh             — install (system deps + venv)
#        ./install.sh --dry-run   — check requirements, install nothing
#        ./install.sh --no-deps   — install without touching system packages
#        ./install.sh --uninstall — remove everything
#        ./install.sh --help      — show this message

set -euo pipefail

APP_NAME="hyprtk-bar"
INSTALL_DIR="$HOME/.local/share/$APP_NAME"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/$APP_NAME"
CONFIG_FILE="$CONFIG_DIR/config.json"

usage() {
    echo "Usage: $0 [--dry-run|--no-deps|--no-extras|--wal-only|--uninstall|--help]"
    echo "  (no args)     Install the bar with system deps + feature dependencies."
    echo "  --dry-run     Check requirements and report what is missing; change nothing."
    echo "  --no-deps     Skip system package installation (assume typelibs present)."
    echo "  --no-extras   Skip the optional feature binaries (quick settings, monitor,"
    echo "                clipboard, theming, etc. — those features then degrade)."
    echo "  --wal-only    Provision only the bundled pywal16 (wal) and exit. Used by"
    echo "                the merged 1-install.sh before the bar itself is installed."
    echo "  --uninstall   Remove the bar, its launcher and desktop entry."
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "--uninstall" || "${1:-}" == "-u" ]]; then
    echo ":: Uninstalling $APP_NAME..."
    rm -rf "$INSTALL_DIR"
    rm -f "$BIN_DIR/$APP_NAME"
    rm -f "$BIN_DIR/wal"
    rm -f "$BIN_DIR/hyprtk-bar-menu-toggle.sh"
    rm -f "$BIN_DIR/hyprtk-bar-arc-toggle.sh"
    rm -f "$BIN_DIR/hyprtk-bar-clipboard-toggle.sh"
    rm -f "$APPS_DIR/$APP_NAME.desktop"
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
    rm -f "$HOME/.local/share/fonts/SymbolsNerdFont-Regular.ttf"
    command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
    # Remove the autostart block added to the Hyprland config.
    for f in "$HOME/.config/hypr/autostart.lua" "$HOME/.config/hypr/hyprland.lua"; do
        [ -f "$f" ] || continue
        if grep -q -- "-- >>> hyprtk-bar autostart" "$f" 2>/dev/null; then
            sed -i '/-- >>> hyprtk-bar autostart/,/-- <<< hyprtk-bar autostart <<</d' "$f"
            echo ":: Removed hyprtk-bar autostart from $f"
        fi
    done
    # Remove any /usr/local/bin symlinks created when ~/.local/bin was off PATH.
    if [ "$(id -u)" -eq 0 ]; then
        rm -f /usr/local/bin/$APP_NAME /usr/local/bin/wal /usr/local/bin/hyprtk-bar-*-toggle.sh 2>/dev/null || true
    elif command -v sudo >/dev/null 2>&1; then
        sudo rm -f /usr/local/bin/$APP_NAME /usr/local/bin/wal /usr/local/bin/hyprtk-bar-*-toggle.sh 2>/dev/null || true
    fi
    echo ":: Done. $APP_NAME has been uninstalled."
    exit 0
fi

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

SKIP_DEPS=0
if [[ "${1:-}" == "--no-deps" ]]; then
    SKIP_DEPS=1
fi

SKIP_EXTRAS=0
if [[ "${1:-}" == "--no-extras" ]]; then
    SKIP_EXTRAS=1
fi

WAL_ONLY=0
if [[ "${1:-}" == "--wal-only" ]]; then
    WAL_ONLY=1
    # Provisioning pywal needs no feature binaries; skip the extras pass.
    SKIP_EXTRAS=1
fi

# ── Package-manager detection ──────────────────────────────────────────────
# Returns the identifier of the system package manager, or "none".
detect_pkg_manager() {
    if command -v pacman >/dev/null 2>&1; then echo pacman; return; fi
    if command -v apt-get >/dev/null 2>&1; then echo apt; return; fi
    if command -v dnf >/dev/null 2>&1; then echo dnf; return; fi
    if command -v zypper >/dev/null 2>&1; then echo zypper; return; fi
    if command -v xbps-install >/dev/null 2>&1; then echo xbps; return; fi
    if command -v apk >/dev/null 2>&1; then echo apk; return; fi
    if command -v emerge >/dev/null 2>&1; then echo emerge; return; fi
    if command -v nix >/dev/null 2>&1; then echo nix; return; fi
    echo none
}

# System runtime deps per package manager (GI typelibs + Python GI bindings +
# venv tooling). PyGObject and pycairo are installed HERE — not pip-installed —
# because neither publishes binary wheels: a venv `pip install` would build them
# from source on every distro, needing a C compiler + GI/cairo headers. The bar
# therefore uses them through a `--system-site-packages` venv, and only the
# pure-Python `dbus-next` is pip-installed.
declare -A DEPS
DEPS[pacman]="gtk3 gtk-layer-shell gdk-pixbuf2 pango cairo gobject-introspection-runtime python python-gobject python-cairo python-pip"
DEPS[apt]="gir1.2-gtk-3.0 gir1.2-gtklayershell-0.1 gir1.2-gdkpixbuf-2.0 gir1.2-pango-1.0 gir1.2-cairo-1.0 gir1.2-xlib-2.0 python3-gi python3-gi-cairo python3-venv python3-pip"
DEPS[dnf]="gtk3 gtk-layer-shell gdk-pixbuf2 pango cairo gobject-introspection python3-gobject python3-cairo python3-pip"
DEPS[zypper]="typelib-1_0-Gtk-3_0 typelib-1_0-GtkLayerShell-0_1 typelib-1_0-GdkPixbuf-2_0 typelib-1_0-Pango-1_0 typelib-1_0-cairo-1_0 typelib-1_0-xlib-2_0 python3-gobject python3-gobject-Gdk python3-gobject-cairo python3-pip"
# Void/Alpine ship the GI typelibs in the -devel/-dev subpackages, not the base
# lib packages.
DEPS[xbps]="gtk+3-devel gtk-layer-shell-devel gdk-pixbuf-devel pango-devel cairo-devel gobject-introspection python3-gobject python3-cairo python3-pip"
DEPS[apk]="gtk+3.0-dev gtk-layer-shell-dev gdk-pixbuf-dev pango-dev cairo-dev gobject-introspection-dev py3-gobject3 py3-cairo py3-pip py3-virtualenv"
DEPS[emerge]="x11-libs/gtk+:3 gui-libs/gtk-layer-shell x11-libs/gdk-pixbuf x11-libs/pango x11-libs/cairo dev-libs/gobject-introspection dev-python/pygobject dev-python/pycairo"
DEPS[nix]="gtk3 gtk-layer-shell gdk-pixbuf pango cairo gobject-introspection python3"

# Optional feature dependencies — the external binaries the bar shells out to
# for quick settings, system monitor, clipboard, theming, etc. Installed by
# default (skip with --no-extras); each feature degrades gracefully when its
# tool is missing, so a partial install is still a working bar.
declare -A EXTRAS
EXTRAS[pacman]="networkmanager bluez bluez-utils pipewire pipewire-pulse wireplumber brightnessctl hyprsunset dmidecode pciutils cliphist wl-clipboard rofi libnotify wob papirus-icon-theme polkit awww matugen"
EXTRAS[apt]="network-manager bluez pipewire pipewire-pulse wireplumber brightnessctl dmidecode pciutils wl-clipboard rofi libnotify-bin papirus-icon-theme polkitd pkexec"
EXTRAS[dnf]="NetworkManager bluez pipewire pipewire-pulseaudio wireplumber brightnessctl dmidecode pciutils wl-clipboard rofi libnotify papirus-icon-theme polkit"
EXTRAS[zypper]="NetworkManager bluez pipewire pipewire-pulseaudio wireplumber brightnessctl dmidecode pciutils wl-clipboard rofi libnotify-tools papirus-icon-theme polkit"
EXTRAS[xbps]="NetworkManager bluez pipewire wireplumber brightnessctl dmidecode pciutils wl-clipboard rofi libnotify papirus-icon-theme polkit"
EXTRAS[apk]="networkmanager bluez pipewire wireplumber brightnessctl dmidecode pciutils wl-clipboard rofi libnotify papirus-icon-theme polkit"
EXTRAS[emerge]="net-misc/networkmanager net-wireless/bluez media-video/pipewire media-video/wireplumber x11-misc/rofi gui-apps/wl-clipboard x11-libs/libnotify"
EXTRAS[nix]="networkmanager bluez pipewire wireplumber rofi wl-clipboard libnotify"

# AUR-only extras (Arch) — installed via yay/paru when an AUR helper is present.
# NOTE: pywal16 is NOT here — it is vendored under vendor/pywal16 (see VENDOR.md).
EXTRAS_AUR="papirus-folders"

# True when the two typelibs the bar cannot run without are present.
typelib_present() {
    local name="$1" d
    for d in /usr/lib/girepository-1.0 /usr/lib64/girepository-1.0 \
             /usr/lib/x86_64-linux-gnu/girepository-1.0 \
             /usr/lib/aarch64-linux-gnu/girepository-1.0 \
             /usr/local/lib/girepository-1.0; do
        [ -f "$d/${name}.typelib" ] && return 0
    done
    return 1
}

deps_ok() {
    # `xlib-2.0` is required to import Gtk at all (PyGObject pulls GDK's
    # GdkX11 into the namespace). On Arch it ships in gobject-introspection-
    # runtime; checking it here stops the installer skipping that runtime when
    # Gtk/gtk-layer-shell typelibs alone happen to be present.
    typelib_present "Gtk-3.0" \
        && typelib_present "GtkLayerShell-0.1" \
        && typelib_present "xlib-2.0"
}

# gtk-layer-shell version as "major.minor.micro", or "" when not importable.
layer_shell_version() {
    python3 -c 'import gi; gi.require_version("GtkLayerShell", "0.1"); from gi.repository import GtkLayerShell as G; print("%d.%d.%d" % (G.get_major_version(), G.get_minor_version(), G.get_micro_version()))' 2>/dev/null || echo ""
}

# 0 when gtk-layer-shell is importable AND >= 0.9; 1 otherwise. Older releases
# lack the layer-shell API the bar anchors on (Debian <=12 0.8.0, Ubuntu <=24.04
# 0.8.2, Fedora <=40, Leap 15.x, Alpine <=3.20).
layer_shell_new_enough() {
    python3 -c 'import sys, gi; gi.require_version("GtkLayerShell", "0.1"); from gi.repository import GtkLayerShell as G; sys.exit(0 if (G.get_major_version(), G.get_minor_version(), G.get_micro_version()) >= (0, 9, 0) else 1)' 2>/dev/null
}

warn_layershell() {
    echo ":: WARN: gtk-layer-shell $(layer_shell_version) is below 0.9 — the bar" >&2
    echo "   may misbehave (missing layer-shell API). Upgrade the distro release," >&2
    echo "   or build a newer one from source:" >&2
    echo "     git clone https://github.com/wmww/gtk-layer-shell" >&2
    echo "     cd gtk-layer-shell && meson build && ninja -C build && sudo ninja -C build install" >&2
}

# Run a package-manager command with root (directly if already root, else sudo).
run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo ":: ERROR: need root to install system packages; no sudo found." >&2
        echo ":: Run as root:  $*" >&2
        return 1
    fi
}

install_pkgs() {
    local pm="$1"; shift
    case "$pm" in
        pacman) run_root pacman -S --noconfirm --needed "$@" ;;
        apt)    run_root apt-get install -y "$@" ;;
        dnf)    run_root dnf install -y "$@" ;;
        zypper) run_root zypper --non-interactive install "$@" ;;
        xbps)   run_root xbps-install -Sy "$@" ;;
        apk)    run_root apk add --no-cache "$@" ;;
        emerge)
            echo ":: Gentoo detected — install manually, then rerun with --no-deps:" >&2
            echo "     emerge -av $*" >&2
            return 1 ;;
        nix)
            echo ":: Nix detected — prefer a flake/derivation with these inputs:" >&2
            echo "     $*" >&2
            echo ":: Or install via nix-env, then rerun with --no-deps." >&2
            return 1 ;;
        *) return 1 ;;
    esac
}

install_yay() {
    # Build yay from the AUR when no helper is present (Arch only). makepkg
    # must run as a normal user, so refuse when running as root.
    if [ "$(id -u)" -eq 0 ]; then
        echo ":: NOTE: running as root — cannot build yay; install an AUR helper manually." >&2
        return 1
    fi
    echo ":: No AUR helper found — building yay from the AUR ..."
    install_pkgs pacman base-devel git || return 1
    local tmp
    tmp="$(mktemp -d)"
    if git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp/yay" \
        && ( cd "$tmp/yay" && makepkg -si --noconfirm ); then
        rm -rf "$tmp"
        return 0
    fi
    rm -rf "$tmp"
    echo ":: WARN: could not build yay — AUR extras will be skipped." >&2
    return 1
}

install_extras() {
    local pm="$1"
    if [ -n "${EXTRAS[$pm]:-}" ]; then
        echo ":: Installing optional feature dependencies via $pm ..."
        install_pkgs "$pm" ${EXTRAS[$pm]:-} || \
            echo ":: WARN: some optional packages failed to install — those features degrade gracefully."
    fi
    if [ "$pm" = "pacman" ] && [ -n "${EXTRAS_AUR:-}" ]; then
        local aur=""
        command -v yay >/dev/null 2>&1 && aur=yay
        [ -z "$aur" ] && command -v paru >/dev/null 2>&1 && aur=paru
        if [ -z "$aur" ] && [ "$SKIP_DEPS" -eq 0 ]; then
            install_yay && aur=yay
        fi
        if [ -n "$aur" ]; then
            echo ":: Installing AUR extras via $aur ..."
            "$aur" -S --noconfirm --needed ${EXTRAS_AUR} || \
                echo ":: WARN: some AUR packages failed to install."
        else
            echo ":: NOTE: no AUR helper (yay/paru) found — install manually: ${EXTRAS_AUR}"
        fi
    fi
}

# True when a directory is already on PATH.
on_path() {
    case ":$PATH:" in *":$1:"*) return 0 ;; *) return 1 ;; esac
}

# ── Bundled pywal16 ────────────────────────────────────────────────────────
# The `wal` CLI is vendored under vendor/pywal16 (see VENDOR.md), so neither
# the bar nor the merged 1-install.sh needs a separate AUR/PyPI pywal install.
# It runs from the bar's own venv via PYTHONPATH — no pip, no build, no network.
copy_vendor() {
    [ -d "$SCRIPT_DIR/vendor/pywal16/pywal" ] || return 1
    rm -rf "$INSTALL_DIR/vendor/pywal16"
    mkdir -p "$INSTALL_DIR/vendor"
    cp -r "$SCRIPT_DIR/vendor/pywal16" "$INSTALL_DIR/vendor/"
}

write_wal_launcher() {
    # The real launcher lives in the venv (so scripts can anchor on it via
    # ``$(dirname "$0")/../venv/bin/wal``); ~/.local/bin is a symlink for PATH.
    cat > "$INSTALL_DIR/venv/bin/wal" << WAL_LAUNCHER
#!/bin/bash
export PYTHONPATH="$INSTALL_DIR/vendor/pywal16\${PYTHONPATH:+:\$PYTHONPATH}"
exec "$INSTALL_DIR/venv/bin/python3" -m pywal "\$@"
WAL_LAUNCHER
    chmod +x "$INSTALL_DIR/venv/bin/wal"
    mkdir -p "$BIN_DIR"
    ln -sf "$INSTALL_DIR/venv/bin/wal" "$BIN_DIR/wal"
}

# Vendor tree + venv + launcher, then prove `wal` runs. Shared by whole-app
# installs and by `--wal-only`, which the merged 1-install.sh calls early so
# `wal` exists before its pywal init steps.
provision_wal() {
    if ! copy_vendor; then
        echo ":: WARN: vendored pywal16 missing ($SCRIPT_DIR/vendor/pywal16) — skipping wal." >&2
        return 1
    fi
    mkdir -p "$BIN_DIR"
    if [ ! -x "$INSTALL_DIR/venv/bin/python3" ]; then
        python3 -m venv --system-site-packages "$INSTALL_DIR/venv"
    fi
    write_wal_launcher
    "$BIN_DIR/wal" -v >/dev/null 2>&1
}

PM="$(detect_pkg_manager)"

# ── Dry run: report requirements without changing anything ─────────────────
if [ "$DRY_RUN" -eq 1 ]; then
    echo ":: Dry run — nothing will be installed or modified."
    echo ":: Package manager: $PM"
    echo ":: Required typelibs:"
    for t in Gtk-3.0 GtkLayerShell-0.1 xlib-2.0; do
        if typelib_present "$t"; then
            printf '     OK       %s\n' "$t"
        else
            printf '     MISSING  %s\n' "$t"
        fi
    done
    v="$(layer_shell_version)"
    if [ -n "$v" ]; then
        echo ":: gtk-layer-shell version: $v (needs >= 0.9)"
        if ! layer_shell_new_enough; then
            echo "::   -> below 0.9; the bar may misbehave on this release."
        fi
    else
        echo ":: gtk-layer-shell version: not importable"
    fi
    printf ':: python3: %s\n' "$(command -v python3 || echo MISSING)"
    if python3 -c 'import venv' >/dev/null 2>&1; then
        echo ":: venv module: OK"
    else
        echo ":: venv module: MISSING (install your distro's python venv package)"
    fi
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) echo ":: ~/.local/bin on PATH: yes" ;;
        *) echo ":: ~/.local/bin on PATH: NO — install will link into /usr/local/bin" ;;
    esac
    echo ":: WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-<unset>}"
    echo ":: HYPRLAND_INSTANCE_SIGNATURE: ${HYPRLAND_INSTANCE_SIGNATURE:-<unset>}"
    if [ -f "$SCRIPT_DIR/assets/fonts/SymbolsNerdFont-Regular.ttf" ]; then
        echo ":: Bundled glyph font: assets/fonts/SymbolsNerdFont-Regular.ttf"
    fi
    if [ -d "$SCRIPT_DIR/themes" ]; then
        echo ":: Bundled bar themes: $(ls -d "$SCRIPT_DIR"/themes/*/ 2>/dev/null | wc -l)"
    fi
    if [ -d "$SCRIPT_DIR/Wallpapers" ]; then
        echo ":: Bundled wallpapers: $(ls "$SCRIPT_DIR"/Wallpapers/* 2>/dev/null | wc -l)"
    fi
    if [ -d "$SCRIPT_DIR/vendor/pywal16/pywal" ]; then
        echo ":: Bundled pywal16: vendor/pywal16 (provides wal; no AUR/PyPI needed)"
    else
        echo ":: Bundled pywal16: MISSING (vendor/pywal16)"
    fi
    if [ "$PM" = "pacman" ]; then
        if command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1; then
            echo ":: AUR helper: present"
        else
            echo ":: AUR helper: none — install will build yay (needs base-devel + git)"
        fi
    fi
    if [ "$PM" != "none" ]; then
        echo ":: System packages that would be installed: ${DEPS[$PM]:-}"
    fi
    if deps_ok; then
        echo ":: Result: core typelibs present."
    else
        echo ":: Result: core typelibs MISSING — the bar cannot start until installed."
    fi
    exit 0
fi

# ── System dependencies ─────────────────────────────────────────────────────
if [ "$SKIP_DEPS" -eq 0 ]; then
    if deps_ok; then
        echo ":: System dependencies present."
    elif [ "$PM" = "none" ]; then
        echo ":: WARN: no supported package manager detected." >&2
        echo ":: Install GTK3 + gtk-layer-shell typelibs manually, then rerun." >&2
    else
        echo ":: Installing system dependencies via $PM ..."
        install_pkgs "$PM" ${DEPS[$PM]:-}
    fi
    # After the deps step, gtk-layer-shell should be importable; warn (don't
    # fail) if it's present but below the 0.9 floor the bar expects.
    if [ "$SKIP_DEPS" -eq 0 ] && [ "$PM" != "none" ] && ! layer_shell_new_enough; then
        warn_layershell
    fi
fi

# ── Optional feature dependencies ─────────────────────────────────────────
if [ "$SKIP_EXTRAS" -eq 0 ] && [ "$SKIP_DEPS" -eq 0 ] && [ "$PM" != "none" ]; then
    install_extras "$PM"
elif [ "$SKIP_EXTRAS" -eq 0 ] && [ "$SKIP_DEPS" -eq 1 ]; then
    echo ":: NOTE: --no-deps implies --no-extras (system packages not managed here)."
fi

# ── --wal-only: provision the bundled `wal` and stop ──────────────────────
# The merged 1-install.sh runs its pywal init steps before the bar is installed,
# so it calls this early to get `wal` on PATH without a separate AUR install.
if [ "$WAL_ONLY" -eq 1 ]; then
    echo ":: Provisioning bundled pywal16 (wal) ..."
    if ! provision_wal; then
        echo ":: ERROR: could not provision the bundled wal." >&2
        exit 1
    fi
    echo ":: wal ready: $BIN_DIR/wal ($("$BIN_DIR/wal" -v 2>&1))"
    if ! on_path "$BIN_DIR"; then
        if [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
            run_root ln -sf "$BIN_DIR/wal" "/usr/local/bin/wal" 2>/dev/null || true
            echo ":: $BIN_DIR is not on PATH — linked wal into /usr/local/bin"
        else
            echo ":: NOTE: add $BIN_DIR to PATH so scripts can find wal." >&2
        fi
    fi
    exit 0
fi

echo ":: Installing $APP_NAME..."

mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APPS_DIR" "$CONFIG_DIR"

# ── Nerd Font for the glyph icons ──────────────────────────────────────────
# The bar draws its icons as Nerd Font glyphs (family "Symbols Nerd Font").
# Install the bundled font so they render even without a system font package.
if [ -f "$SCRIPT_DIR/assets/fonts/SymbolsNerdFont-Regular.ttf" ]; then
    mkdir -p "$HOME/.local/share/fonts"
    cp -f "$SCRIPT_DIR/assets/fonts/SymbolsNerdFont-Regular.ttf" "$HOME/.local/share/fonts/"
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
    fi
    echo ":: Installed Symbols Nerd Font (glyph icons)"
fi

# ── Bundled bar themes ─────────────────────────────────────────────────────
# Ship the hyprtk* bar themes so a fresh install already has them available in
# Theme Manager → Bar Themes (no manual importing). User-imported themes with
# other names are left untouched; the hyprtk* ones are refreshed.
if [ -d "$SCRIPT_DIR/themes" ]; then
    mkdir -p "$CONFIG_DIR/themes"
    cp -rf "$SCRIPT_DIR/themes/." "$CONFIG_DIR/themes/"
    echo ":: Installed bundled bar themes into $CONFIG_DIR/themes"
fi

# ── Bundled wallpapers ─────────────────────────────────────────────────────
# Ship a few default wallpapers into the user's Pictures folder. Existing files
# with the same name are left alone (no-clobber) so the user's own are safe.
if [ -d "$SCRIPT_DIR/Wallpapers" ]; then
    WALL_DIR="$HOME/Pictures/Wallpapers"
    mkdir -p "$WALL_DIR"
    cp -n "$SCRIPT_DIR"/Wallpapers/* "$WALL_DIR/" 2>/dev/null || true
    echo ":: Installed bundled wallpapers into $WALL_DIR"
fi

# ── Preserve the user's live config across install/update ────────────────
# An update must never reset the user's customisations. Back the live config
# up first; if it is ever missing afterwards (interrupted update, cleanup),
# restore the last-good backup so the bar comes back with the saved settings.
if [ -f "$CONFIG_FILE" ]; then
    cp -f "$CONFIG_FILE" "$CONFIG_DIR/config.json.bak" 2>/dev/null || true
    echo ":: Backed up existing config to $CONFIG_DIR/config.json.bak"
fi

cp -r "$SCRIPT_DIR/src" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/assets" "$INSTALL_DIR/" 2>/dev/null || true
cp -r "$SCRIPT_DIR/scripts" "$INSTALL_DIR/" 2>/dev/null || true
copy_vendor || echo ":: WARN: vendored pywal16 missing — pywal theming unavailable." >&2
cp "$SCRIPT_DIR/pyproject.toml" "$INSTALL_DIR/"

# venv with --system-site-packages: PyGObject and pycairo ship no binary
# wheels, so a plain venv pip-install would build them from source (needing a C
# compiler + GI/cairo headers) on every distro. Use the distro's own
# pygobject/pycairo (installed above via DEPS) and pip-install only the
# pure-Python dbus-next; the bar itself is editable-installed with --no-deps.
python3 -m venv --system-site-packages "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --quiet "dbus-next>=0.2.3,<0.3"
"$INSTALL_DIR/venv/bin/pip" install --quiet --no-deps -e "$INSTALL_DIR"

# Main launcher
cat > "$BIN_DIR/$APP_NAME" << LAUNCHER
#!/bin/bash
exec "$INSTALL_DIR/venv/bin/python3" -m hyprtk_bar "\$@"
LAUNCHER
chmod +x "$BIN_DIR/$APP_NAME"

# Bundled `wal` (vendored pywal16) — the bar and its scripts call it by name.
if [ -d "$INSTALL_DIR/vendor/pywal16/pywal" ]; then
    write_wal_launcher
fi

# ── Hyprland autostart ──────────────────────────────────────────────────────
# Register the bar with the user's Hyprland Lua config so it starts on login.
# Prefer a dedicated autostart.lua; some setups keep the autostart block inline
# in hyprland.lua instead. Idempotent, and removed again on --uninstall.
configure_autostart() {
    local dir="$HOME/.config/hypr" target=""
    if [ -f "$dir/autostart.lua" ]; then
        target="$dir/autostart.lua"
    elif [ -f "$dir/hyprland.lua" ]; then
        target="$dir/hyprland.lua"
    else
        echo ":: NOTE: no ~/.config/hypr/autostart.lua or hyprland.lua — add the"
        echo "   bar to autostart manually:"
        echo "     hl.on(\"hyprland.start\", function() hl.exec_cmd(\"~/.local/bin/$APP_NAME &\") end)"
        return 0
    fi
    # Drop any block we added previously so it can be upgraded in place.
    if grep -q -- "-- >>> hyprtk-bar autostart" "$target" 2>/dev/null; then
        sed -i '/-- >>> hyprtk-bar autostart/,/-- <<< hyprtk-bar autostart <<</d' "$target"
    fi
    # If the bar is autostarted elsewhere (e.g. the hyprtk dotfiles' own
    # autostart.lua), leave that alone.
    if grep -q "hyprtk-bar" "$target" 2>/dev/null; then
        echo ":: hyprtk-bar autostart already present in $target"
        return 0
    fi
    # The wallpaper daemon + watcher only make sense when a wallpaper backend is
    # actually installed (awww is Arch-only; swww is the portable fallback).
    # Skip them otherwise so a non-Arch install doesn't autostart a nonexistent
    # daemon on every login.
    local wall_daemon=""
    command -v awww >/dev/null 2>&1 && wall_daemon="awww-daemon"
    if [ -z "$wall_daemon" ] && command -v swww >/dev/null 2>&1; then
        wall_daemon="swww-daemon"
    fi
    {
        echo ""
        echo "-- >>> hyprtk-bar autostart (added by install.sh) >>>"
        echo 'hl.on("hyprland.start", function()'
        if [ -n "$wall_daemon" ]; then
            echo "    hl.exec_cmd(\"$wall_daemon &\")"
            echo '    hl.exec_cmd("~/.local/share/hyprtk-bar/scripts/wal-watcher.sh &")'
        fi
        echo '    hl.exec_cmd("~/.local/bin/hyprtk-bar &")'
        echo 'end)'
        echo '-- <<< hyprtk-bar autostart <<<'
    } >> "$target"
    echo ":: Added hyprtk-bar autostart to $target"
}

# Toggle scripts — Hyprland keybindings signal the bar through these
# (SIGUSR1 menu / SIGUSR2 arc menu / SIGHUP clipboard). Installed on PATH so
# a standalone install can bind them directly.
if [ -d "$SCRIPT_DIR/scripts" ]; then
    for script in "$SCRIPT_DIR"/scripts/hyprtk-bar-*-toggle.sh; do
        [ -f "$script" ] || continue
        cp "$script" "$BIN_DIR/"
        chmod +x "$BIN_DIR/$(basename "$script")"
    done
fi

cp "$SCRIPT_DIR/$APP_NAME.desktop" "$APPS_DIR/"
update-desktop-database "$APPS_DIR" 2>/dev/null || true

configure_autostart

# Restore the config if the live file is missing but a backup exists (the app
# itself also auto-restores on load; this is belt-and-braces for installs).
if [ ! -f "$CONFIG_FILE" ] && [ -f "$CONFIG_DIR/config.json.bak" ]; then
    cp -f "$CONFIG_DIR/config.json.bak" "$CONFIG_FILE" 2>/dev/null || true
    echo ":: Restored config from backup"
fi

# ── Self-test: verify the venv can import GTK + gtk-layer-shell ────────────
# The installer can succeed while the runtime is still unusable (e.g. GDK
# needs the xlib typelib, which Arch ships in gobject-introspection-runtime).
# Catch that here with a clear cause instead of a silent no-launch later.
if ! "$INSTALL_DIR/venv/bin/python3" -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk; gi.require_version("GtkLayerShell", "0.1"); from gi.repository import GtkLayerShell' 2>"$INSTALL_DIR/self-test.err"; then
    echo ":: ERROR: the bar cannot import GTK — the install is incomplete." >&2
    sed 's/^/   /' "$INSTALL_DIR/self-test.err" >&2 || true
    echo ":: On Arch this is usually fixed by:" >&2
    echo "     sudo pacman -S gobject-introspection-runtime" >&2
    echo "   (it provides the xlib/xfixes/xrandr typelibs GDK needs)." >&2
    rm -f "$INSTALL_DIR/self-test.err"
    exit 1
fi
rm -f "$INSTALL_DIR/self-test.err"
echo ":: Environment check passed."

# pywal is optional for the bar itself but drives all theming; warn (don't
# fail) if the bundled `wal` cannot run.
if [ -x "$BIN_DIR/wal" ]; then
    if "$BIN_DIR/wal" -v >/dev/null 2>&1; then
        echo ":: Bundled wal ready ($("$BIN_DIR/wal" -v 2>&1))."
    else
        echo ":: WARN: bundled wal self-test failed — pywal theming unavailable." >&2
    fi
else
    echo ":: WARN: no bundled wal launcher — pywal theming unavailable." >&2
fi

# ── Make the launcher reachable ────────────────────────────────────────────
# ~/.local/bin is not on PATH by default on a fresh Arch, and Hyprland's
# autostart does not source shell rc files either. When it is missing, link
# the launcher (and toggle scripts) into /usr/local/bin, which is always on
# PATH — so `hyprtk-bar` works immediately and in `exec-once` too.
if ! on_path "$BIN_DIR"; then
    linked=0
    if [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
        if run_root ln -sf "$BIN_DIR/$APP_NAME" "/usr/local/bin/$APP_NAME" 2>/dev/null; then
            linked=1
            for script in "$BIN_DIR"/hyprtk-bar-*-toggle.sh; do
                [ -f "$script" ] || continue
                run_root ln -sf "$script" "/usr/local/bin/$(basename "$script")" \
                    2>/dev/null || true
            done
            if [ -x "$BIN_DIR/wal" ]; then
                run_root ln -sf "$BIN_DIR/wal" "/usr/local/bin/wal" 2>/dev/null || true
            fi
            echo ":: $BIN_DIR is not on PATH — linked $APP_NAME into /usr/local/bin"
        fi
    fi
    if [ "$linked" -eq 0 ]; then
        echo ":: NOTE: add $BIN_DIR to PATH, or run $BIN_DIR/$APP_NAME"
    fi
fi

echo ":: Installed to $BIN_DIR/$APP_NAME"
echo ":: Config: ~/.config/hyprtk-bar/config.json"
echo ":: Run './install.sh --uninstall' to remove"
