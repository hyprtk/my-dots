#!/bin/bash
# hyprtk-bar-qt installer for Hyprtk
# Installs the Quickshell/QML shell + a Python venv (for the bundled pywal16),
# drops launcher/toggle helpers on PATH, and registers the Hyprland autostart.
# Usage: ./install.sh             — install (system deps + venv)
#        ./install.sh --dry-run   — check requirements, install nothing
#        ./install.sh --no-deps   — install without touching system packages
#        ./install.sh --no-extras — install without the optional feature binaries
#        ./install.sh --wal-only  — provision only the bundled pywal16 (wal)
#        ./install.sh --uninstall — remove everything
#        ./install.sh --help      — show this message

set -euo pipefail

APP_NAME="hyprtk-bar-qt"
INSTALL_DIR="$HOME/.local/share/$APP_NAME"
QS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/$APP_NAME"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
CONFIG_FILE="$CONFIG_DIR/config.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/$APP_NAME"

usage() {
    echo "Usage: $0 [--dry-run|--no-deps|--no-extras|--wal-only|--uninstall|--help]"
    echo "  (no args)     Install the bar with system deps + feature dependencies."
    echo "  --dry-run     Check requirements and report what is missing; change nothing."
    echo "  --no-deps     Skip system package installation (assume Quickshell/Qt present)."
    echo "  --no-extras   Skip the optional feature binaries (quick settings, monitor,"
    echo "                clipboard, theming, etc. — those features then degrade)."
    echo "  --wal-only    Provision only the bundled pywal16 (wal) and exit. Used by"
    echo "                the merged 1-install.sh before the bar itself is installed."
    echo "  --uninstall   Remove the bar, its launcher and desktop entry."
}

DRY_RUN=0
SKIP_DEPS=0
SKIP_EXTRAS=0
WAL_ONLY=0
DO_UNINSTALL=0

for _arg in "$@"; do
    case "$_arg" in
        -h|--help) usage; exit 0 ;;
        -u|--uninstall) DO_UNINSTALL=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --no-deps) SKIP_DEPS=1 ;;
        --no-extras) SKIP_EXTRAS=1 ;;
        --wal-only)
            # pywal16 is pure vendored Python: provisioning `wal` needs neither
            # Quickshell/Qt nor any optional feature binaries. Skipping both means
            # --wal-only never touches the package manager and never needs root.
            WAL_ONLY=1
            SKIP_DEPS=1
            SKIP_EXTRAS=1 ;;
        *) echo ":: WARN: unknown option '$_arg' (ignored)" >&2 ;;
    esac
done

if [ "$DO_UNINSTALL" -eq 1 ]; then
    echo ":: Uninstalling $APP_NAME..."
    rm -rf "$INSTALL_DIR" "$QS_DIR" "$CACHE_DIR"
    rm -f "$BIN_DIR/wal"
    for h in "$SCRIPT_DIR"/bin/*; do
        [ -f "$h" ] || continue
        rm -f "$BIN_DIR/$(basename "$h")"
    done
    rm -f "$APPS_DIR/$APP_NAME.desktop"
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
    rm -f "$HOME/.local/share/fonts/SymbolsNerdFont-Regular.ttf"
    command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
    for f in "$HOME/.config/hypr/autostart.lua" "$HOME/.config/hypr/hyprland.lua"; do
        [ -f "$f" ] || continue
        if grep -q -- "-- >>> hyprtk-bar-qt autostart" "$f" 2>/dev/null \
            && grep -q -- "-- <<< hyprtk-bar-qt autostart <<<" "$f" 2>/dev/null; then
            sed -i '/-- >>> hyprtk-bar-qt autostart/,/-- <<< hyprtk-bar-qt autostart <<</d' "$f"
            echo ":: Removed hyprtk-bar-qt autostart from $f"
        fi
    done
    if [ "$(id -u)" -eq 0 ]; then
        rm -f /usr/local/bin/$APP_NAME /usr/local/bin/wal /usr/local/bin/$APP_NAME-* 2>/dev/null || true
    elif command -v sudo >/dev/null 2>&1; then
        sudo rm -f /usr/local/bin/$APP_NAME /usr/local/bin/wal /usr/local/bin/$APP_NAME-* 2>/dev/null || true
    fi
    echo ":: Done. $APP_NAME has been uninstalled."
    exit 0
fi

# ── Package-manager detection ──────────────────────────────────────────────
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

# ── System runtime deps ─────────────────────────────────────────────────────
# The bar is a Quickshell (Qt6) app: it needs the `qs` binary plus the Qt6 QML
# modules (QtQuick, Layouts, Controls) and SVG for icons. The Python backend is
# stdlib-only; the venv provisioned below exists only to run the bundled pywal16
# `wal` CLI. Package names are best-effort per family — on families that do not
# package Quickshell, build it from source (installer/scripts/srcapps-install.sh
# in the merged tree) and rerun with --no-deps.
declare -A DEPS
DEPS[pacman]="quickshell qt6-base qt6-declarative qt6-svg python python-pip"
DEPS[apt]="quickshell qt6-base-dev qt6-declarative-dev libqt6svg6-dev python3 python3-venv python3-pip"
DEPS[dnf]="quickshell qt6-qtbase qt6-qtdeclarative qt6-qtsvg python3 python3-pip"
DEPS[zypper]="quickshell libQt6Core6 libQt6Gui6 libQt6Qml6 libQt6Quick6 libQt6Svg6 python3 python3-pip"
DEPS[xbps]="quickshell qt6-base qt6-declarative qt6-svg python3 python3-pip python3-virtualenv"
DEPS[apk]="quickshell qt6-qtbase qt6-qtdeclarative qt6-qtsvg python3 py3-pip py3-virtualenv"
DEPS[emerge]="gui-apps/quickshell dev-qt/qtbase dev-qt/qtdeclarative dev-qt/qtsvg dev-lang/python"
DEPS[nix]="quickshell qt6.qtbase qt6.qtdeclarative qt6.qtsvg python3"

# Optional feature dependencies — external binaries the bar shells out to. Each
# feature degrades gracefully when its tool is missing (skip with --no-extras).
declare -A EXTRAS
EXTRAS[pacman]="networkmanager bluez bluez-utils pipewire pipewire-pulse wireplumber brightnessctl hyprsunset dmidecode pciutils cliphist wl-clipboard rofi libnotify wob papirus-icon-theme polkit awww matugen cava imagemagick python-pillow"
EXTRAS[apt]="network-manager bluez pipewire pipewire-pulse wireplumber brightnessctl dmidecode pciutils wl-clipboard rofi libnotify-bin papirus-icon-theme polkitd pkexec cava imagemagick python3-pil"
EXTRAS[dnf]="NetworkManager bluez pipewire pipewire-pulseaudio wireplumber brightnessctl dmidecode pciutils wl-clipboard rofi libnotify papirus-icon-theme polkit cava ImageMagick python3-pillow"
EXTRAS[zypper]="NetworkManager bluez pipewire pipewire-pulseaudio wireplumber brightnessctl dmidecode pciutils wl-clipboard rofi libnotify-tools papirus-icon-theme polkit cava ImageMagick python3-Pillow"
EXTRAS[xbps]="NetworkManager bluez pipewire wireplumber brightnessctl dmidecode pciutils wl-clipboard rofi libnotify papirus-icon-theme polkit cava ImageMagick python3-Pillow"
EXTRAS[apk]="networkmanager bluez pipewire wireplumber brightnessctl dmidecode pciutils wl-clipboard rofi libnotify papirus-icon-theme polkit cava imagemagick py3-pillow"
EXTRAS[emerge]="net-misc/networkmanager net-wireless/bluez media-video/pipewire media-video/wireplumber x11-misc/rofi gui-apps/wl-clipboard x11-libs/libnotify media-sound/cava media-gfx/imagemagick dev-python/pillow"
EXTRAS[nix]="networkmanager bluez pipewire wireplumber rofi wl-clipboard libnotify cava imagemagick python3Packages.pillow"

# AUR-only extras (Arch) — installed via yay/paru when an AUR helper is present.
EXTRAS_AUR="papirus-folders"

# True when the runtime the bar cannot run without is present.
deps_ok() {
    { command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1; } \
        && command -v python3 >/dev/null 2>&1 \
        && python3 -c 'import venv' >/dev/null 2>&1
}

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
            return 1 ;;
        *) return 1 ;;
    esac
}

# Pinned AUR commit for the yay bootstrap (makepkg runs whatever PKGBUILD it finds).
YAY_REF="cb43f84828ab4f9700f7c6f9c6d7a923d4cfaff0"

install_yay() {
    if [ "$(id -u)" -eq 0 ]; then
        echo ":: NOTE: running as root — cannot build yay; install an AUR helper manually." >&2
        return 1
    fi
    echo ":: No AUR helper found — building yay from the AUR (pinned ${YAY_REF:0:12}) ..."
    install_pkgs pacman base-devel git || return 1
    local tmp
    tmp="$(mktemp -d)"
    if git clone https://aur.archlinux.org/yay.git "$tmp/yay" \
        && git -C "$tmp/yay" checkout --quiet "$YAY_REF" \
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

on_path() {
    case ":$PATH:" in *":$1:"*) return 0 ;; *) return 1 ;; esac
}

# ── Bundled pywal16 ────────────────────────────────────────────────────────
# The `wal` CLI is vendored under vendor/pywal16 (see VENDOR.md), so neither the
# bar nor the merged 1-install.sh needs a separate AUR/PyPI pywal install. It
# runs from a venv via PYTHONPATH — no pip, no build, no network.
copy_vendor() {
    [ -d "$SCRIPT_DIR/vendor/pywal16/pywal" ] || return 1
    rm -rf "$INSTALL_DIR/vendor/pywal16"
    mkdir -p "$INSTALL_DIR/vendor"
    cp -r "$SCRIPT_DIR/vendor/pywal16" "$INSTALL_DIR/vendor/"
}

write_wal_launcher() {
    cat > "$INSTALL_DIR/venv/bin/wal" << WAL_LAUNCHER
#!/bin/bash
export PYTHONPATH="$INSTALL_DIR/vendor/pywal16\${PYTHONPATH:+:\$PYTHONPATH}"
exec "$INSTALL_DIR/venv/bin/python3" -m pywal "\$@"
WAL_LAUNCHER
    chmod +x "$INSTALL_DIR/venv/bin/wal"
    mkdir -p "$BIN_DIR"
    ln -sf "$INSTALL_DIR/venv/bin/wal" "$BIN_DIR/wal"
}

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

# ── Dry run ─────────────────────────────────────────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
    echo ":: Dry run — nothing will be installed or modified."
    echo ":: Package manager: $PM"
    printf ':: qs (Quickshell): %s\n' "$(command -v qs || command -v quickshell || echo MISSING)"
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
    if [ -d "$SCRIPT_DIR/vendor/pywal16/pywal" ]; then
        echo ":: Bundled pywal16: vendor/pywal16 (provides wal; no AUR/PyPI needed)"
    else
        echo ":: Bundled pywal16: MISSING (vendor/pywal16)"
    fi
    if [ "$PM" != "none" ]; then
        echo ":: System packages that would be installed: ${DEPS[$PM]:-}"
    fi
    if deps_ok; then
        echo ":: Result: Quickshell + python present."
    else
        echo ":: Result: Quickshell (qs) and/or python3 MISSING — the bar cannot start."
    fi
    exit 0
fi

# ── System dependencies ─────────────────────────────────────────────────────
if [ "$SKIP_DEPS" -eq 0 ]; then
    if deps_ok; then
        echo ":: System dependencies present."
    elif [ "$PM" = "none" ]; then
        echo ":: WARN: no supported package manager detected." >&2
        echo ":: Install Quickshell (qs) + Qt6 QML modules manually, then rerun with --no-deps." >&2
    else
        echo ":: Installing system dependencies via $PM ..."
        if ! install_pkgs "$PM" ${DEPS[$PM]:-}; then
            echo ":: WARN: could not install all system dependencies via $PM (see above)." >&2
            echo "::       The bar will not start until Quickshell (qs) is available." >&2
        fi
    fi
fi

# ── Optional feature dependencies ─────────────────────────────────────────
if [ "$SKIP_EXTRAS" -eq 0 ] && [ "$SKIP_DEPS" -eq 0 ] && [ "$PM" != "none" ]; then
    install_extras "$PM"
elif [ "$SKIP_EXTRAS" -eq 0 ] && [ "$SKIP_DEPS" -eq 1 ]; then
    echo ":: NOTE: --no-deps implies --no-extras (system packages not managed here)."
fi

# ── --wal-only ──────────────────────────────────────────────────────────────
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

mkdir -p "$INSTALL_DIR" "$QS_DIR" "$BIN_DIR" "$APPS_DIR" "$CONFIG_DIR" "$CACHE_DIR"

# ── Nerd Font for the glyph icons ──────────────────────────────────────────
if [ -f "$SCRIPT_DIR/assets/fonts/SymbolsNerdFont-Regular.ttf" ]; then
    mkdir -p "$HOME/.local/share/fonts"
    cp -n "$SCRIPT_DIR/assets/fonts/SymbolsNerdFont-Regular.ttf" "$HOME/.local/share/fonts/"
    command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
    echo ":: Installed Symbols Nerd Font (glyph icons)"
fi

# ── Bundled bar themes ─────────────────────────────────────────────────────
if [ -d "$SCRIPT_DIR/themes" ]; then
    mkdir -p "$CONFIG_DIR/themes"
    cp -rf "$SCRIPT_DIR/themes/." "$CONFIG_DIR/themes/"
    echo ":: Installed bundled bar themes into $CONFIG_DIR/themes"
fi

# ── Bundled desktop-widget themes ──────────────────────────────────────────
if [ -d "$SCRIPT_DIR/assets/widgets" ]; then
    mkdir -p "$CONFIG_DIR/widget-themes"
    cp -rf "$SCRIPT_DIR/assets/widgets/." "$CONFIG_DIR/widget-themes/"
    echo ":: Installed bundled widget themes into $CONFIG_DIR/widget-themes"
fi

# ── Bundled wallpapers ─────────────────────────────────────────────────────
if [ -d "$SCRIPT_DIR/Wallpapers" ]; then
    WALL_DIR="$HOME/Pictures/Wallpapers"
    mkdir -p "$WALL_DIR"
    cp -n "$SCRIPT_DIR"/Wallpapers/* "$WALL_DIR/" 2>/dev/null || true
    echo ":: Installed bundled wallpapers into $WALL_DIR"
fi

# ── Preserve the user's live config across install/update ─────────────────
if [ -f "$CONFIG_FILE" ]; then
    cp -f "$CONFIG_FILE" "$CONFIG_DIR/config.json.bak" 2>/dev/null || true
    echo ":: Backed up existing config to $CONFIG_DIR/config.json.bak"
fi

# ── Install the QML shell tree (Quickshell reads it from the config dir) ────
# Replace the runtime subtrees so modules removed upstream do not linger.
dirs=(bar surface components config data state theme backend bin)
mkdir -p "$QS_DIR"
cp "$SCRIPT_DIR/shell.qml" "$QS_DIR/"
for d in "${dirs[@]}"; do
    rm -rf "$QS_DIR/$d"
    cp -a "$SCRIPT_DIR/$d" "$QS_DIR/$d"
done
find "$QS_DIR" -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true

# ── Bundled scripts (installed tree the QML + launcher call) ────────────────
if [ -d "$SCRIPT_DIR/scripts" ]; then
    rm -rf "$INSTALL_DIR/scripts"
    cp -a "$SCRIPT_DIR/scripts" "$INSTALL_DIR/scripts"
    chmod +x "$INSTALL_DIR/scripts"/*.sh 2>/dev/null || true
fi

# ── Seed the default config on a fresh install ─────────────────────────────
# bar-qt has its own config; on a machine that also has the GTK bar the backend
# migrates from it once. Ship a default so a standalone install works too.
if [ ! -f "$CONFIG_FILE" ] && [ -f "$SCRIPT_DIR/config.json" ]; then
    cp -f "$SCRIPT_DIR/config.json" "$CONFIG_FILE"
fi
# Seed from the GTK config when present (the backend's own migrator).
python3 "$INSTALL_DIR/backend/hyprtk_bar_qt/paths.py" >/dev/null 2>&1 || true
python3 "$QS_DIR/backend/hyprtk_bar_qt/paths.py" >/dev/null 2>&1 || true

# ── Bundled `wal` (vendored pywal16) + venv ────────────────────────────────
if [ -d "$SCRIPT_DIR/vendor/pywal16/pywal" ]; then
    copy_vendor || echo ":: WARN: could not copy vendor/pywal16." >&2
    if [ ! -x "$INSTALL_DIR/venv/bin/python3" ]; then
        python3 -m venv --system-site-packages "$INSTALL_DIR/venv" \
            || echo ":: WARN: could not create the venv — is python3 (with venv) installed?" >&2
    fi
    write_wal_launcher
else
    echo ":: WARN: vendored pywal16 missing — pywal theming unavailable." >&2
fi

# ── Launcher + toggle helpers on PATH ──────────────────────────────────────
for s in "$SCRIPT_DIR"/bin/*; do
    [ -f "$s" ] || continue
    chmod +x "$s"
    ln -sf "$QS_DIR/bin/$(basename "$s")" "$BIN_DIR/$(basename "$s")"
done

# Rewrite Exec to this user's actual launcher path.
_exec_path="$(printf '%s' "$BIN_DIR/$APP_NAME" | sed -e 's/[\\&|]/\\&/g')"
if [ -f "$SCRIPT_DIR/$APP_NAME.desktop" ]; then
    sed "s|^Exec=.*|Exec=$_exec_path|" "$SCRIPT_DIR/$APP_NAME.desktop" > "$APPS_DIR/$APP_NAME.desktop"
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
fi

# ── Hyprland autostart ──────────────────────────────────────────────────────
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
    if grep -q -- "-- >>> hyprtk-bar-qt autostart" "$target" 2>/dev/null \
        && grep -q -- "-- <<< hyprtk-bar-qt autostart <<<" "$target" 2>/dev/null; then
        sed -i '/-- >>> hyprtk-bar-qt autostart/,/-- <<< hyprtk-bar-qt autostart <<</d' "$target"
    fi
    if grep -q "hyprtk-bar-qt" "$target" 2>/dev/null; then
        echo ":: hyprtk-bar-qt autostart already present in $target"
        return 0
    fi
    local wall_daemon=""
    command -v awww >/dev/null 2>&1 && wall_daemon="awww-daemon"
    if [ -z "$wall_daemon" ] && command -v swww >/dev/null 2>&1; then
        wall_daemon="swww-daemon"
    fi
    {
        echo ""
        echo "-- >>> hyprtk-bar-qt autostart (added by install.sh) >>>"
        echo 'hl.on("hyprland.start", function()'
        if [ -n "$wall_daemon" ]; then
            echo "    hl.exec_cmd(\"$wall_daemon &\")"
        fi
        echo '    hl.exec_cmd("~/.local/bin/hyprtk-bar-qt &")'
        echo 'end)'
        echo '-- <<< hyprtk-bar-qt autostart <<<'
    } >> "$target"
    echo ":: Added hyprtk-bar-qt autostart to $target"
}

configure_autostart

# Restore the config if the live file is missing but a backup exists.
if [ ! -f "$CONFIG_FILE" ] && [ -f "$CONFIG_DIR/config.json.bak" ]; then
    cp -f "$CONFIG_DIR/config.json.bak" "$CONFIG_FILE" 2>/dev/null || true
    echo ":: Restored config from backup"
fi

# ── Self-test ───────────────────────────────────────────────────────────────
if deps_ok; then
    echo ":: Environment check passed ($( { command -v qs || command -v quickshell; } 2>/dev/null ))."
else
    echo ":: WARN: Quickshell (qs) not found — the bar cannot start until it is installed." >&2
fi
if [ -x "$BIN_DIR/wal" ]; then
    if "$BIN_DIR/wal" -v >/dev/null 2>&1; then
        echo ":: Bundled wal ready ($("$BIN_DIR/wal" -v 2>&1))."
    else
        echo ":: WARN: bundled wal self-test failed — pywal theming unavailable." >&2
    fi
fi

# ── Make the launcher reachable ────────────────────────────────────────────
if ! on_path "$BIN_DIR"; then
    linked=0
    if [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
        if run_root ln -sf "$BIN_DIR/$APP_NAME" "/usr/local/bin/$APP_NAME" 2>/dev/null; then
            linked=1
            for script in "$BIN_DIR"/$APP_NAME-*; do
                [ -e "$script" ] || continue
                run_root ln -sf "$script" "/usr/local/bin/$(basename "$script")" 2>/dev/null || true
            done
            [ -x "$BIN_DIR/wal" ] && run_root ln -sf "$BIN_DIR/wal" "/usr/local/bin/wal" 2>/dev/null || true
            echo ":: $BIN_DIR is not on PATH — linked $APP_NAME into /usr/local/bin"
        fi
    fi
    [ "$linked" -eq 0 ] && echo ":: NOTE: add $BIN_DIR to PATH, or run $BIN_DIR/$APP_NAME"
fi

echo ":: Installed to $BIN_DIR/$APP_NAME"
echo ":: Shell:   $QS_DIR"
echo ":: Scripts: $INSTALL_DIR/scripts"
echo ":: Config:  ~/.config/hyprtk-bar-qt/config.json"
echo ":: Run './install.sh --uninstall' to remove"
