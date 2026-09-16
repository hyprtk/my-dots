#!/bin/bash
# ── Unified hyprtk installer (gum TUI) ────────────────────────────────────
# Merges the installers of all 11 supported distros (arch, archbang, archcraft,
# archman, bslx, cachy, endeavour, garuda, kiro, manjaro, reborn).
# Per-distro hooks live in installer/steps/<distro>.sh and are sourced here.
# Uses gum for TUI. Password entry remains functional via native sudo prompts.
# ──────────────────────────────────────────────────────────────────────────

# ── Color variables ────────────────────────────────────────────────────────
MAGENTA='\033[35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Script directory detection ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# _spin/_run run commands through a `bash -c` subshell; an install path with
# spaces or shell metacharacters would be re-parsed as code there. Refuse it
# up front rather than let it become injection.
case "$SCRIPT_DIR" in
    *[![:alnum:]_/.+-]*)
        echo -e "${RED}  ✗ ${WHITE}Install path contains spaces or special characters:${NC}" >&2
        echo -e "${RED}  ✗ ${WHITE}  $SCRIPT_DIR${NC}" >&2
        echo -e "${RED}  ✗ ${WHITE}Move the repo to a path like ~/hyprtk and re-run.${NC}" >&2
        exit 1
        ;;
esac

# ── Installation log ──────────────────────────────────────────────────────
LOG_FILE="$SCRIPT_DIR/install.log"
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Initialize log
: > "$LOG_FILE"
log "=== hyprtk installation started ==="
log "Script directory: $SCRIPT_DIR"

# ── Package-manager abstraction ────────────────────────────────────────────
# Detect the host package manager up front (pacman/apt/dnf/zypper/xbps/apk/…).
# The distro hooks run inside _spin subshells, so export SCRIPT_DIR (used to
# locate pkgmanager.sh) and the detected manager.
# shellcheck source=installer/scripts/pkgmanager.sh
. "$SCRIPT_DIR/installer/scripts/pkgmanager.sh"
export SCRIPT_DIR HYPRTK_PM

# ── Gum setup ──────────────────────────────────────────────────────────────
GUM="$SCRIPT_DIR/installer/standalone/gum"

check_gum() {
    if [ -x "$GUM" ]; then
        return
    fi
    if command -v gum &>/dev/null; then
        GUM="$(command -v gum)"
        return
    fi
    echo -e "${CYAN}gum not found. Installing...${NC}"
    pkg_install gum
    if command -v gum &>/dev/null; then
        GUM="$(command -v gum)"
    else
        echo -e "${YELLOW}  ! Could not install gum automatically.${NC}"
        echo -e "${WHITE}    Install it from your distro (or use the bundled copy) and re-run.${NC}"
        exit 1
    fi
}

# ── Helpers ────────────────────────────────────────────────────────────────
_box() {
    $GUM style \
        --border-foreground 5 \
        --border double \
        --align center \
        --padding "1 3" \
        --margin "1 0" \
        "$@"
}

_step() {
    clear
    _box "$(printf "${CYAN}%s${NC}" "$1")"
    echo ""
    log "STEP: $1"
}

_ok() {
    echo -e "${CYAN}  ✓ ${WHITE}$1${NC}"
    log "OK: $1"
}

_warn() {
    echo -e "${YELLOW}  ! ${WHITE}$1${NC}"
    log "WARN: $1"
}

_fail() {
    echo -e "${RED}  ✗ ${WHITE}$1${NC}"
    log "FAIL: $1"
}

die() {
    _fail "$1"
    log "FATAL: $1"
    exit 1
}

# Terminal width, used to keep the spinner's detail line from wrapping (a wrapped
# title breaks gum's cursor accounting, so the spinner redraws over itself).
_term_width() {
    local w
    w=$(tput cols 2>/dev/null)
    if [ -n "$w" ] && [ "$w" -gt 0 ] 2>/dev/null; then
        printf '%s' "$w"
    else
        printf '80'
    fi
}

# Trim a detail string so "  → <detail>" fits on one terminal line.
_fit_detail() {
    local detail="$1"
    local max=$(( $(_term_width) - 6 ))
    [ "$max" -lt 8 ] && max=8
    if [ "${#detail}" -gt "$max" ]; then
        printf '%s…' "${detail:0:$((max - 1))}"
    else
        printf '%s' "$detail"
    fi
}

# List the package names a hypr/packages/<name>.sh script installs, for the
# spinner's detail line. New-style scripts support `--list` (they source
# pkgmanager.sh and print their PKGS/AUR arrays); older scripts fall back to
# parsing `pacman -S` / `yay -S` lines. Dynamic arguments (command
# substitutions) and flags are skipped.
_script_packages() {
    local script="$1"
    [ -f "$script" ] || return 0
    if grep -q 'hyprtk-pkglist' "$script" 2>/dev/null; then
        bash "$script" --list 2>/dev/null
        return 0
    fi
    awk '
        { sub(/#.*/, ""); collecting = 0 }
        {
            n = split($0, f, /[[:space:]]+/)
            for (i = 1; i <= n; i++) {
                tok = f[i]
                if (collecting) {
                    if (tok ~ /^[&|;>]+/) { collecting = 0; continue }
                    gsub(/\\/, "", tok)
                    gsub(/^[&|;>]+/, "", tok)
                    if (tok == "" || tok ~ /^-/) continue
                    if (tok ~ /[()$]/) continue
                    if (!(tok in seen)) { seen[tok] = 1; out = out tok " " }
                    continue
                }
                if (tok == "-S" || tok == "--sync") collecting = 1
            }
        }
        END { sub(/ $/, "", out); printf "%s", out }
    ' "$script"
}

_spin() {
    local title="$1"
    local cmd="$2"
    local logfile="$3"
    local detail="${4:-}"
    local shown="$title"
    if [ -n "$detail" ]; then
        shown="$title"$'\n'"  → $detail"
    fi
    log "SPIN: $title${detail:+ | $detail}"
    $GUM spin --spinner dot --title "$shown" -- bash -c "$cmd >> '$logfile' 2>&1"
    local rc=$?
    if [ $rc -ne 0 ]; then
        log "SPIN FAILED (exit $rc): $title"
    else
        log "SPIN OK: $title"
    fi
    return $rc
}

_run() {
    local title="$1"
    local cmd="$2"
    local logfile="$3"
    log "RUN: $title"
    echo -e "${CYAN}  → ${WHITE}$title${NC}"
    bash -c "$cmd >> '$logfile' 2>&1"
    local rc=$?
    if [ $rc -ne 0 ]; then
        log "RUN FAILED (exit $rc): $title"
    else
        log "RUN OK: $title"
    fi
    return $rc
}

# ── Sudo credentials ───────────────────────────────────────────────────────
# Package steps run inside `gum spin`, which hides the terminal and would bury a
# native sudo password prompt (the install then looks like it hangs on yay).
# Ask for the password up front — visibly — then keep the cached credential
# alive in the background so a long build can't expire the timestamp mid-spin.
SUDO_KEEPALIVE_PID=""
_cleanup_keepalive() {
    if [ -n "$SUDO_KEEPALIVE_PID" ] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}
trap _cleanup_keepalive EXIT

_sudo_auth() {
    if sudo -n true 2>/dev/null; then
        log "SUDO: credentials already valid"
    else
        echo -e "${WHITE}  Enter your password to authorise the installation:${NC}"
        echo ""
        if ! sudo -v; then
            die "sudo authentication failed"
        fi
        log "SUDO: credentials cached"
    fi

    if [ -z "$SUDO_KEEPALIVE_PID" ] || ! kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        ( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
        SUDO_KEEPALIVE_PID=$!
    fi
}

# ── Preflight ──────────────────────────────────────────────────────────────
check_gum
clear

_box \
    "$(printf "${CYAN}HYPRTK DOTFILES${NC}")" \
    "$(printf "${CYAN}Hyprland Desktop Environment Installer${NC}")" \
    "" \
    "$(printf "${RED}DISCLAIMER${NC}")" \
    "$(printf "${WHITE}Installing these dotfiles may alter your system${NC}")" \
    "$(printf "${WHITE}configuration. A clean install is recommended for${NC}")" \
    "$(printf "${WHITE}best results.${NC}")"

echo ""
echo -e "${WHITE}  You will be asked for your Root password to proceed.${NC}"
echo ""

# ── Distro detection ──────────────────────────────────────────────────────
DISTRO=""
DISTRO_NAME=""
DISTRO_VERSION=""

_detect_distro() {
    local distro_id="" distro_name="" distro_version="" distro_pretty="" distro_like=""

    if [ -f /etc/os-release ]; then
        # os-release values may be double- OR single-quoted (Gentoo uses single
        # quotes: ID='gentoo'), so strip both.
        distro_id=$(grep -E '^ID=' /etc/os-release | head -1 | cut -d= -f2 | tr -d "\"'")
        distro_name=$(grep -E '^NAME=' /etc/os-release | head -1 | cut -d= -f2 | tr -d "\"'")
        distro_version=$(grep -E '^VERSION_ID=' /etc/os-release | head -1 | cut -d= -f2 | tr -d "\"'")
        distro_pretty=$(grep -E '^PRETTY_NAME=' /etc/os-release | head -1 | cut -d= -f2 | tr -d "\"'")
        distro_like=$(grep -E '^ID_LIKE=' /etc/os-release | head -1 | cut -d= -f2 | tr -d "\"'")
    fi

    # Handle "Hyprtk on (Arch Linux)" format — extract the distro name
    local clean_name="${distro_pretty:-$distro_name}"
    clean_name="${clean_name#Hyprtk on }"
    clean_name="${clean_name#Hyprtk on }"
    clean_name="${clean_name#(}"
    clean_name="${clean_name%)}"
    clean_name=$(echo "$clean_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # ── Arch-family (keeps the per-distro hooks in installer/steps/) ──────
    DISTRO=""
    case "$distro_id" in
        arch)                  DISTRO=arch ;;
        archbang)              DISTRO=archbang ;;
        archcraft)             DISTRO=archcraft ;;
        archman)               DISTRO=archman ;;
        bluestar|bslx)         DISTRO=bslx ;;
        cachyos|cachy)         DISTRO=cachy ;;
        endeavour|endeavouros) DISTRO=endeavour ;;
        garuda)                DISTRO=garuda ;;
        kiro)                  DISTRO=kiro ;;
        manjaro)               DISTRO=manjaro ;;
        reborn|rebornos)       DISTRO=reborn ;;
    esac

    # ── Other families (generic: no per-distro hooks) ────────────────────
    if [ -z "$DISTRO" ]; then
        case "$distro_id" in
            debian|ubuntu|linuxmint|pop|elementary|zorin|kali|raspbian|devuan|mx|neon|deepin|parrot|pureos) DISTRO=debian ;;
            fedora|rhel|centos|rocky|almalinux|ol|amzn|oracle) DISTRO=fedora ;;
            opensuse*|suse|sles|sled|tumbleweed) DISTRO=suse ;;
            void)    DISTRO=void ;;
            alpine)  DISTRO=alpine ;;
            gentoo|funtoo|calculate) DISTRO=gentoo ;;
            nixos)   DISTRO=nixos ;;
        esac
    fi

    # ID_LIKE fallback for derivatives not named above.
    if [ -z "$DISTRO" ] && [ -n "$distro_like" ]; then
        case "$distro_like" in
            *arch*)            DISTRO=arch ;;
            *debian*|*ubuntu*) DISTRO=debian ;;
            *fedora*|*rhel*)   DISTRO=fedora ;;
            *suse*)            DISTRO=suse ;;
            *void*)            DISTRO=void ;;
            *alpine*)          DISTRO=alpine ;;
            *gentoo*)          DISTRO=gentoo ;;
            *nix*)             DISTRO=nixos ;;
        esac
    fi

    DISTRO_NAME="${clean_name:-${distro_name:-Linux}}"
    DISTRO_VERSION="${distro_version:-N/A}"
}

# Map the internal distro key to a package-manager family. The 11 Arch-based
# distros share the pacman family; the generic keys are already families.
_distro_family() {
    case "$1" in
        arch|archbang|archcraft|archman|bslx|cachy|endeavour|garuda|kiro|manjaro|reborn) echo arch ;;
        debian) echo debian ;;
        fedora) echo fedora ;;
        suse)   echo suse ;;
        void)   echo void ;;
        alpine) echo alpine ;;
        gentoo) echo gentoo ;;
        nixos)  echo nix ;;
        *)      echo unknown ;;
    esac
}

_detect_distro
DISTRO_FAMILY="$(_distro_family "$DISTRO")"

# Show detection result if found
if [ -n "$DISTRO" ]; then
    _box \
        "$(printf "${CYAN}DISTRO DETECTED${NC}")" \
        "" \
        "$(printf "${WHITE}Name:     ${CYAN}%s${NC}" "$DISTRO_NAME")" \
        "$(printf "${WHITE}ID:       ${CYAN}%s${NC}" "$DISTRO")" \
        "$(printf "${WHITE}Family:   ${CYAN}%s${NC}" "$DISTRO_FAMILY")" \
        "$(printf "${WHITE}Manager:  ${CYAN}%s${NC}" "$(hyprtk_pm_name)")" \
        "$(printf "${WHITE}Version:  ${CYAN}%s${NC}" "$DISTRO_VERSION")"
    echo ""
    log "Distro detected: $DISTRO_NAME ($DISTRO/$DISTRO_FAMILY) v$DISTRO_VERSION"
fi

# Manual selection if auto-detect failed
if [ -z "$DISTRO" ]; then
    _warn "Could not auto-detect distro from /etc/os-release"
    echo ""

    DISTROS=(
        "Arch Linux"
        "ArchBANG Linux"
        "Archcraft Linux"
        "Archman Linux"
        "BlueStar Linux"
        "CachyOS"
        "EndeavourOS"
        "Garuda Linux"
        "Kiro Linux"
        "Manjaro Linux"
        "RebornOS"
        "Debian / Ubuntu"
        "Fedora / RHEL"
        "openSUSE"
        "Void Linux"
        "Alpine Linux"
        "Gentoo"
        "NixOS"
        "Other / unknown"
    )

    $GUM style --foreground 5 --bold --padding "1 0" "Select your distribution:"

    SELECTED=$($GUM choose \
        --height=19 \
        --cursor.foreground=5 \
        --selected.foreground=0 \
        --selected.background=5 \
        --item.foreground=6 \
        "${DISTROS[@]}")

    if [[ -z "$SELECTED" ]]; then
        echo -e "${MAGENTA}  Installation cancelled.${NC}"
        log "Installation cancelled by user"
        exit 0
    fi

    case "$SELECTED" in
        "Arch Linux")       DISTRO=arch ;;
        "ArchBANG Linux")   DISTRO=archbang ;;
        "Archcraft Linux")  DISTRO=archcraft ;;
        "Archman Linux")    DISTRO=archman ;;
        "BlueStar Linux")   DISTRO=bslx ;;
        "CachyOS")          DISTRO=cachy ;;
        "EndeavourOS")      DISTRO=endeavour ;;
        "Garuda Linux")     DISTRO=garuda ;;
        "Kiro Linux")       DISTRO=kiro ;;
        "Manjaro Linux")    DISTRO=manjaro ;;
        "RebornOS")         DISTRO=reborn ;;
        "Debian / Ubuntu")  DISTRO=debian ;;
        "Fedora / RHEL")    DISTRO=fedora ;;
        "openSUSE")         DISTRO=suse ;;
        "Void Linux")       DISTRO=void ;;
        "Alpine Linux")     DISTRO=alpine ;;
        "Gentoo")           DISTRO=gentoo ;;
        "NixOS")            DISTRO=nixos ;;
        "Other / unknown")  DISTRO=unknown ;;
    esac
    DISTRO_NAME="$SELECTED"
fi

# Normalise: accept "*-dots" style input
DISTRO="${DISTRO%-dots}"
DISTRO_FAMILY="$(_distro_family "$DISTRO")"

# Validate
case "$DISTRO" in
    arch|archbang|archcraft|archman|bslx|cachy|endeavour|garuda|kiro|manjaro|reborn|debian|fedora|suse|void|alpine|gentoo|nixos|unknown) ;;
    *) die "unsupported distro '$DISTRO'" ;;
esac

_ok "Target distro: $DISTRO_NAME ($DISTRO/$DISTRO_FAMILY)"

# Confirm before proceeding
if ! $GUM confirm --prompt.foreground=5 "Proceed with $DISTRO installation?"; then
    echo -e "${MAGENTA}  Installation cancelled.${NC}"
    log "Installation cancelled by user"
    exit 0
fi

# Source distro-specific hooks
STEPS="$SCRIPT_DIR/installer/steps/$DISTRO.sh"
if [ -f "$STEPS" ]; then
    source "$STEPS"
    # Export hooks + DISTRO so they are visible to the bash -c subshells used
    # by _spin (several install_os_release hooks reference $DISTRO).
    export DISTRO
    export -f pre_install install_os_release install_boot pre_hypr_symlink wal_init grub_wallpaper grudupdater setup_sudoers 2>/dev/null
    log "Sourced distro hooks: $STEPS"
fi

# ── Pre-install (distro-specific cleanup) ─────────────────────────────────
# Authenticate once, visibly, before any spinner hides the terminal.
_sudo_auth
_step "Removing leftover Packages"
if type pre_install >/dev/null 2>&1; then
    pre_install
else
    pkg_remove plasma-meta kde-applications-meta plasma kde-applications
fi
_ok "Leftover packages removed"

# ── Load libraries ────────────────────────────────────────────────────────
_step "Loading Installation Libraries"
source "$SCRIPT_DIR/installer/scripts/library.sh"
# Export the library helpers AND the pkgmanager primitives they call, so the
# `bash -c` subshells used by _spin can resolve them (exported functions do not
# carry their own dependencies).
export -f _installSymLink _isInstalledPacman _isInstalledYay _installPackagesPacman _installPackagesYay 2>/dev/null
export -f hyprtk_detect_pm hyprtk_pm_name hyprtk_run_root pkg_is_installed pkg_install pkg_remove aur_helper aur_available aur_install 2>/dev/null
_ok "Library loaded"

# ── Timezone ──────────────────────────────────────────────────────────────
echo ""
bash "$SCRIPT_DIR/installer/scripts/set-timezone.sh" 2>/dev/null
_ok "Timezone configured"

# ── Install Yay (Arch only) ───────────────────────────────────────────────
# Only Arch-family systems need an AUR helper; every other family installs its
# feature packages straight from the distro repos.
if [ "$HYPRTK_PM" = pacman ]; then
    _step "Installing Yay"
    if pkg_is_installed yay; then
        _ok "yay already installed"
    else
        # makepkg -si (and base-devel) need sudo; make sure the cached credential
        # is fresh and prompt visibly rather than under the spinner.
        _sudo_auth
        _spin "Installing yay..." "_installPackagesPacman base-devel git && git clone https://aur.archlinux.org/yay-git.git ~/Downloads/yay-git && cd ~/Downloads/yay-git && makepkg -si --noconfirm" "$LOG_FILE" "base-devel + yay-git (AUR build)"
        _ok "yay installed"
    fi
else
    _ok "Non-Arch system ($HYPRTK_PM) — AUR helper not required"
fi

# ── Confirm start ─────────────────────────────────────────────────────────
if ! $GUM confirm --prompt.foreground=5 "Start the installation now?"; then
    echo -e "${MAGENTA}  Installation cancelled.${NC}"
    log "Installation cancelled by user"
    exit 0
fi

# ── Graphics card ─────────────────────────────────────────────────────────
_step "Graphics Card Setup"
bash "$SCRIPT_DIR/hypr/packages/graphics-card.sh"
_ok "Graphics card configured"

# ── Confirm core apps ────────────────────────────────────────────────────
if ! $GUM confirm --prompt.foreground=5 "Install core apps now?"; then
    echo -e "${MAGENTA}  Installation aborted.${NC}"
    log "Installation aborted by user"
    exit 0
fi

# ── Core packages ─────────────────────────────────────────────────────────
_step "Installing Core Packages"
# Mint/Ubuntu run background updaters that can hold the dpkg lock; announce a
# wait here (visible) instead of letting the first apt step look frozen.
hyprtk_apt_wait_lock
for pkg in hyprland xfce4 filetools webtools printers network media terminaltools systemtools system sddm-check sddmgrub matuwall manual_package_installs 3dprinting; do
    pkg_script="$SCRIPT_DIR/hypr/packages/$pkg.sh"
    pkg_detail="$(_fit_detail "$(_script_packages "$pkg_script")")"
    _spin "Installing $pkg..." "bash $pkg_script" "$LOG_FILE" "$pkg_detail"
    _ok "$pkg installed"
done

# hyprviz needs interactive sudo - run without spin
echo -e "${CYAN}  → ${WHITE}Installing hyprviz${NC}"
bash "$SCRIPT_DIR/hypr/packages/hyprviz.sh"
_ok "hyprviz installed"

# wallpapers needs y/n confirmation - run without spin
echo -e "${CYAN}  → ${WHITE}Installing wallpapers${NC}"
bash "$SCRIPT_DIR/hypr/packages/wallpapers.sh"
_ok "wallpapers installed"

# fonts needs y/n confirmation and sudo - run without spin
echo -e "${CYAN}  → ${WHITE}Installing fonts${NC}"
bash "$SCRIPT_DIR/hypr/packages/fonts.sh"
_ok "fonts installed"

# awww (wallpaper daemon). Arch installs it from the AUR in hyprland.sh; no
# other family packages it, so awww-install.sh builds it from source (or uses
# the native swww package on Void/Alpine), then the wrapper adds the pywal hook.
_spin "Installing awww wallpaper daemon..." "bash $SCRIPT_DIR/installer/scripts/awww-install.sh" "$LOG_FILE"
_spin "Installing awww wrapper..." "bash $SCRIPT_DIR/installer/scripts/awww-wrapper.sh" "$LOG_FILE"
_ok "awww wallpaper daemon installed"

# Apps some distros do not package (gtk4-layer-shell, swappy, nwg-look, starship)
# are built from source / installed from upstream when the native package is
# missing. Idempotent and non-fatal.
_spin "Installing apps that need source builds..." "bash $SCRIPT_DIR/installer/scripts/srcapps-install.sh" "$LOG_FILE"
_ok "Source-built apps processed"

if type grudupdater >/dev/null 2>&1; then
    _spin "Running grub updater..." "grudupdater" "$LOG_FILE"
fi

# ── Pywal16 (bundled in hyprtk-bar) ───────────────────────────────────────
# pywal16 is vendored inside hyprtk-bar (vendor/pywal16) and exposed as `wal`
# by the bar's installer — no separate AUR/PyPI download. It is provisioned
# here, early, because the pywal init steps below (and the dotfiles' wal
# templates) run before the full bar install near the end of this script.
_step "Installing Pywal16 (bundled)"
_spin "Provisioning bundled pywal16..." "bash $SCRIPT_DIR/installer/hyprtk-bar/install.sh --wal-only" "$LOG_FILE"
_ok "pywal16 ready (bundled wal)"

# ── Icons root ────────────────────────────────────────────────────────────
_step "Installing Icons (root)"
# Download to a temp file and run it locally instead of `wget -qO- ... | sh`:
# a pipe lets a partial/failed download execute as root with no artifact to
# inspect. Pin the URL to a specific commit/release when one is available.
_spin "Installing Papirus icons for root..." \
    "tmp=\$(mktemp) && wget -qO- --timeout=60 https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh > \"\$tmp\" && DESTDIR=/root/.local/share/icons sh \"\$tmp\"; rc=\$?; rm -f -- \"\$tmp\"; exit \$rc" \
    "$LOG_FILE"
_ok "Icons installed for root"

# ── Init pywal16 ─────────────────────────────────────────────────────────
_step "Initiating Pywal16"
_spin "Initializing pywal16..." "wal -i $SCRIPT_DIR/assets/Wallpapers/default.png" "$LOG_FILE"
_ok "pywal16 initiated"

_spin "Setting default wallpaper..." "cp $SCRIPT_DIR/assets/Wallpapers/default.png ~/.cache/current-wallpaper.png && sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png" "$LOG_FILE"
if type grub_wallpaper >/dev/null 2>&1; then
    _spin "Updating grub wallpaper..." "grub_wallpaper" "$LOG_FILE"
fi
_spin "Updating user directories..." "xdg-user-dirs-update --force && xdg-user-dirs-gtk-update --force" "$LOG_FILE"
_ok "Default wallpaper set"

# ── Confirm Hyprland config ──────────────────────────────────────────────
if ! $GUM confirm --prompt.foreground=5 "Configure Hyprland now?"; then
    echo -e "${MAGENTA}  Hyprland configuration skipped.${NC}"
    log "Hyprland configuration skipped by user"
else
    # ── Thunar xfconf ────────────────────────────────────────────────────
    _step "Launching Thunar to generate xfconf"
    _spin "Generating xfconf..." "thunar & sleep 3 && killall thunar" "$LOG_FILE"
    _ok "Thunar xfconf generated"

    # ── Bluetooth ────────────────────────────────────────────────────────
    _step "Enabling Bluetooth"
    _spin "Enabling bluetooth..." "sudo systemctl start bluetooth && sudo systemctl enable bluetooth" "$LOG_FILE"
    _ok "Bluetooth enabled"

    # ── Cockpit / os-release ─────────────────────────────────────────────
    _step "Enabling Cockpit"
    if type install_os_release >/dev/null 2>&1; then
        _spin "Installing os-release..." "install_os_release" "$LOG_FILE"
    elif [ -f "$SCRIPT_DIR/installer/os-release/os-release-$DISTRO" ]; then
        _spin "Copying os-release..." "sudo cp $SCRIPT_DIR/installer/os-release/os-release-$DISTRO /usr/lib/" "$LOG_FILE"
    else
        _warn "No os-release branding for $DISTRO — keeping the system's own"
    fi
    if type install_boot >/dev/null 2>&1; then
        _spin "Installing boot splash..." "install_boot" "$LOG_FILE"
    fi
    _spin "Enabling cockpit..." "sudo cp $SCRIPT_DIR/configs/User-Management/manage-users.desktop /usr/share/applications/ && sudo systemctl enable --now cockpit.socket && sudo systemctl start cockpit.socket" "$LOG_FILE"
    _ok "Cockpit enabled"

    # ── Samba ────────────────────────────────────────────────────────────
    _step "Enabling Samba"
    # Service names differ: Arch uses smb/nmb, most others smbd/nmbd.
    _spin "Enabling samba..." "sudo mkdir -p /etc/samba && sudo cp $SCRIPT_DIR/configs/smb/smb.conf /etc/samba/ && (sudo systemctl enable --now smb nmb 2>/dev/null || sudo systemctl enable --now smbd nmbd 2>/dev/null); true" "$LOG_FILE"
    _warn "Update interfaces in /etc/samba/smb.conf with your IP address"
    _ok "Samba enabled"

    # ── NVIDIA info ──────────────────────────────────────────────────────
    _step "NVIDIA Information"
    echo -e "${WHITE}  If you installed an NVIDIA card, follow the instructions in:${NC}"
    echo -e "${CYAN}  ~/hyprtk/hypr/nvidia.lua${NC}"
    $GUM input --placeholder "Press Enter to continue..."

    # ── Confirm dotfiles ────────────────────────────────────────────────
    if ! $GUM confirm --prompt.foreground=5 "Install dotfiles now?"; then
        echo -e "${MAGENTA}  Dotfile installation skipped.${NC}"
        log "Dotfile installation skipped by user"
    else
        # ── .config directory ───────────────────────────────────────────
        _step "Checking .config Directory"
        if [ -d ~/.config ]; then
            _ok ".config folder exists"
        else
            mkdir ~/.config
            _ok ".config folder created"
        fi

        # ── General symlinks ───────────────────────────────────────────
        _step "Installing General Configs"
        _spin "Installing alacritty..." "_installSymLink alacritty ~/.config/alacritty $SCRIPT_DIR/configs/alacritty/ ~/.config" "$LOG_FILE"
        _spin "Installing ranger..." "_installSymLink ranger ~/.config/ranger $SCRIPT_DIR/configs/ranger/ ~/.config" "$LOG_FILE"
        _spin "Installing vim..." "_installSymLink vim ~/.config/vim $SCRIPT_DIR/configs/vim/ ~/.config" "$LOG_FILE"
        _spin "Installing nvim..." "_installSymLink nvim ~/.config/nvim $SCRIPT_DIR/configs/nvim/ ~/.config" "$LOG_FILE"
        _spin "Installing starship..." "_installSymLink starship ~/.config/starship.toml $SCRIPT_DIR/configs/starship/starship.toml ~/.config/starship.toml" "$LOG_FILE"
        _spin "Installing rofi..." "_installSymLink rofi ~/.config/rofi $SCRIPT_DIR/configs/rofi/ ~/.config" "$LOG_FILE"
        _spin "Installing wal..." "_installSymLink wal ~/.config/wal $SCRIPT_DIR/configs/wal/ ~/.config" "$LOG_FILE"
        _spin "Installing btop..." "_installSymLink btop ~/.config/btop $SCRIPT_DIR/configs/btop/ ~/.config" "$LOG_FILE"
        _ok "General configs installed"

        # ── Re-init pywal16 ───────────────────────────────────────────
        _step "Re-Initiating Pywal16"
        if type wal_init >/dev/null 2>&1; then
            _spin "Running wal_init..." "wal_init" "$LOG_FILE"
        else
            _spin "Initializing pywal16..." "wal -i $SCRIPT_DIR/assets/Wallpapers/default.png" "$LOG_FILE"
        fi
        _ok "Pywal16 templates initiated"

        # ── GTK ───────────────────────────────────────────────────────
        _step "Installing GTK Configs"
        _spin "Installing GTK 3.0..." "_installSymLink gtk-3.0 ~/.config/gtk-3.0 $SCRIPT_DIR/configs/gtk/gtk-3.0/ ~/.config/" "$LOG_FILE"
        _spin "Installing GTK 4.0..." "_installSymLink gtk-4.0 ~/.config/gtk-4.0 $SCRIPT_DIR/configs/gtk/gtk-4.0/ ~/.config/" "$LOG_FILE"
        _spin "Installing themes..." "_installSymLink themes ~/.local/share/themes $SCRIPT_DIR/assets/themes ~/.local/share/" "$LOG_FILE"
        _spin "Installing icons..." "_installSymLink icons ~/.local/share/icons $SCRIPT_DIR/assets/papirus-icons/icons ~/.local/share/" "$LOG_FILE"
        _ok "GTK configs installed"

        # ── Xfce ──────────────────────────────────────────────────────
        _step "Installing Xfce Configs"
        _spin "Installing xfce4..." "_installSymLink xfce4 ~/.config/xfce4 $SCRIPT_DIR/configs/xfce4 ~/.config/" "$LOG_FILE"
        _spin "Installing Thunar..." "_installSymLink Thunar ~/.config/Thunar $SCRIPT_DIR/configs/Thunar ~/.config/" "$LOG_FILE"
        _spin "Installing Mousepad..." "_installSymLink Mousepad ~/.config/Mousepad $SCRIPT_DIR/configs/Mousepad ~/.config/" "$LOG_FILE"
        _ok "Xfce configs installed"

        # ── Hyprland ──────────────────────────────────────────────────
        _step "Installing Hyprland Configs"
        if type pre_hypr_symlink >/dev/null 2>&1; then
            _spin "Running pre_hypr_symlink..." "pre_hypr_symlink" "$LOG_FILE"
        fi
        _spin "Installing hypr..." "_installSymLink hypr ~/.config/hypr $SCRIPT_DIR/hypr/ ~/.config" "$LOG_FILE"
        _spin "Installing fastfetch..." "_installSymLink fastfetch ~/.config/fastfetch $SCRIPT_DIR/configs/fastfetch/ ~/.config" "$LOG_FILE"
        _spin "Installing swaylock..." "_installSymLink swaylock ~/.config/swaylock $SCRIPT_DIR/configs/swaylock/ ~/.config" "$LOG_FILE"
        _spin "Installing swappy..." "_installSymLink swappy ~/.config/swappy $SCRIPT_DIR/configs/swappy/ ~/.config" "$LOG_FILE"
        _spin "Installing hyprlogout..." "_installSymLink hyprlogout ~/.config/hyprlogout $SCRIPT_DIR/configs/hyprlogout/ ~/.config" "$LOG_FILE"
        _spin "Installing waypaper..." "_installSymLink waypaper ~/.config/waypaper $SCRIPT_DIR/configs/waypaper/ ~/.config" "$LOG_FILE"
        _spin "Installing zshrc..." "_installSymLink zshrc ~/.config/zshrc $SCRIPT_DIR/configs/zshrc/ ~/.config" "$LOG_FILE"
        _spin "Installing ohmyposh..." "_installSymLink ohmyposh ~/.config/ohmyposh $SCRIPT_DIR/configs/ohmyposh/ ~/.config" "$LOG_FILE"
        _spin "Installing matuwall..." "_installSymLink matuwall ~/.config/matuwall $SCRIPT_DIR/configs/matuwall/ ~/.config" "$LOG_FILE"
        _spin "Installing wob..." "_installSymLink wob ~/.config/wob $SCRIPT_DIR/configs/wob/ ~/.config" "$LOG_FILE"
        _spin "Creating ~/.local/bin..." "mkdir -p ~/.local/bin" "$LOG_FILE"
        _ok "Hyprland configs installed"

        # ── ZSH ──────────────────────────────────────────────────────
        _step "Installing ZSH"
        _spin "Installing zsh..." "_installPackagesPacman zsh" "$LOG_FILE"
        # oh-my-zsh install needs interactive input - run without spin.
        # Fetch to a temp file and run it (avoids `sh -c "$(curl ...)"`, which
        # hides the fetched code and runs a partial download if the fetch fails).
        echo -e "${CYAN}  → ${WHITE}Installing oh-my-zsh${NC}"
        tmp="$(mktemp)" && curl -fsSL --max-time 90 \
            https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
            -o "$tmp" && bash "$tmp" --unattended
        rc=$?
        rm -f -- "$tmp"
        if [ "$rc" -ne 0 ]; then
            _fail "oh-my-zsh install exited $rc (network?)"
        fi
        _ok "ZSH installed"

        _step "Installing ZSH Plugins"
        _spin "Installing zsh-autosuggestions..." "[ -d \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions ] || git clone https://github.com/zsh-users/zsh-autosuggestions \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions 2>/dev/null" "$LOG_FILE"
        _spin "Installing zsh-syntax-highlighting..." "[ -d \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting ] || git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting 2>/dev/null" "$LOG_FILE"
        _spin "Installing fast-syntax-highlighting..." "[ -d \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting ] || git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting 2>/dev/null" "$LOG_FILE"
        _ok "ZSH plugins installed"

        # ── .zshrc ────────────────────────────────────────────────────
        _step "Updating .zshrc"
        _spin "Installing .zshrc..." "_installSymLink .zshrc ~/.zshrc $SCRIPT_DIR/.zshrc ~/.zshrc" "$LOG_FILE"
        # chsh needs password - run without spin
        echo -e "${CYAN}  → ${WHITE}Setting default shell to zsh${NC}"
        ZSH_BIN="$(command -v zsh || echo /bin/zsh)"
        sudo chsh -s "$ZSH_BIN"
        chsh -s "$ZSH_BIN" 2>/dev/null || true
        _ok ".zshrc updated"

        # ── Standalone apps ──────────────────────────────────────────
        _step "Installing Standalone Apps"
        _spin "Installing standalone binaries..." "_installSymLink standalone ~/.local/bin $SCRIPT_DIR/installer/standalone/ ~/.local/bin" "$LOG_FILE"
        _spin "Installing oh-my-zsh..." "_installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh $SCRIPT_DIR/configs/oh-my-zsh/oh-my-zsh.sh ~/.oh-my-zsh" "$LOG_FILE"
        _ok "Standalone apps installed"

        # ── hyprtk-bar ──────────────────────────────────────────────
        _step "Installing hyprtk-bar"
        _spin "Installing hyprtk-bar..." "bash $SCRIPT_DIR/installer/hyprtk-bar/install.sh" "$LOG_FILE"
        _ok "hyprtk-bar installed (autostarted by autostart.lua; owns the notification daemon; hosts the arc menu overlay)"

        # ── Root user config ─────────────────────────────────────────
        _step "Setting Up Root User Config"
        echo -e "${CYAN}  → ${WHITE}Copying root config${NC}"
        sudo find /root/.config -type l -delete 2>/dev/null
        # configs/root/ holds hidden root-home files (.bashrc, .config, ...).
        # Copy its contents into /root/ — never glob `configs/root/*` onto `/`.
        sudo cp -rf "$SCRIPT_DIR"/configs/root/. /root/ 2>/dev/null || true
        log "Root config copied"
        _ok "Root user config copied"

        # ── Sudoers ──────────────────────────────────────────────────
        if type setup_sudoers >/dev/null 2>&1; then
            _spin "Configuring sudoers..." "setup_sudoers" "$LOG_FILE"
        else
            # Defaults appended via a validated drop-in, never `tee -a /etc/sudoers`.
            _spin "Configuring sudoers..." \
                "printf 'Defaults env_reset,pwfeedback\n' | sudo tee /etc/sudoers.d/99-hyprtk-defaults >/dev/null && sudo chmod 440 /etc/sudoers.d/99-hyprtk-defaults && sudo visudo -c >/dev/null 2>&1" \
                "$LOG_FILE"
        fi
        _ok "Sudoers configured"

        # ── Bar sudo access (passwordless) ──────────────────────────
        _step "Configuring Bar Sudo Access"
        echo -e "${CYAN}  → ${WHITE}Installing hyprtk-bar sudoers (passwordless sudo)${NC}"
        sudo bash "$SCRIPT_DIR/installer/scripts/setup-sudoers.sh"
        _ok "Bar passwordless sudo configured"
    fi
fi

# ── Cleanup ────────────────────────────────────────────────────────────────
if [ -n "${HOME:-}" ]; then
    rm -rf -- "$HOME/dotfiles" 2>/dev/null || true
fi

# ── Completion ─────────────────────────────────────────────────────────────
log "=== hyprtk installation completed ==="
clear
_box \
    "$(printf "${CYAN}INSTALLATION COMPLETE${NC}")" \
    "" \
    "$(printf "${WHITE}Done!${NC}")" \
    "" \
    "$(printf "${WHITE}Installation log:${NC}")" \
    "$(printf "${CYAN}%s${NC}" "$LOG_FILE")" \
    "" \
    "$(printf "${WHITE}Next steps:${NC}")" \
    "$(printf "${CYAN}1. Update keyboard layout${NC}")" \
    "$(printf "${CYAN}   in ~/hyprtk/hypr/input.lua${NC}")" \
    "$(printf "${CYAN}2. Update screen resolution${NC}")" \
    "$(printf "${CYAN}   in ~/hyprtk/hypr/monitors.lua${NC}")" \
    "$(printf "${WHITE}3. Reboot your system${NC}")" \
    "" \
    "$(printf "${CYAN}github.com/hyprtk/dotfiles${NC}")"

echo ""
