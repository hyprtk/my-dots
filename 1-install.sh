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

# User-local bin dirs. openSUSE (and some minimal installs) do not put
# ~/.local/bin on PATH for non-login shells, so bare `wal`/`hyprtk-bar`/
# standalone tools would be "command not found". Prepend both, idempotently.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
case ":$PATH:" in
    *":/usr/local/bin:"*) ;;
    *) PATH="$PATH:/usr/local/bin" ;;
esac
export PATH

# ── Installation log ──────────────────────────────────────────────────────
LOG_FILE="$SCRIPT_DIR/install.log"
# Steps that failed (non-zero exit) during the run. Collected so the installer
# can report the truth at the end instead of printing OK for a failed step.
HYPRTK_FAILED=()
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
    # The bundled gum is a glibc ELF binary. On a musl system (Alpine) the file
    # exists and is executable but cannot actually run, so "exists"/"is on PATH"
    # is not enough — prove each candidate runs before trusting it. This matters
    # because the dotfiles symlink the bundled copy into ~/.local/bin (on PATH),
    # so `command -v gum` can resolve to the broken copy too.
    local cand
    for cand in "$GUM" "$(command -v gum 2>/dev/null)" /usr/bin/gum /usr/local/bin/gum; do
        [ -n "$cand" ] && [ -x "$cand" ] || continue
        if "$cand" --version >/dev/null 2>&1; then
            GUM="$cand"
            return
        fi
    done
    echo -e "${CYAN}gum not found. Installing...${NC}"
    pkg_install gum
    for cand in /usr/bin/gum /usr/local/bin/gum "$(command -v gum 2>/dev/null)"; do
        [ -n "$cand" ] && [ -x "$cand" ] || continue
        if "$cand" --version >/dev/null 2>&1; then
            GUM="$cand"
            return
        fi
    done
    echo -e "${YELLOW}  ! Could not install gum automatically.${NC}"
    echo -e "${WHITE}    Install it from your distro (or use the bundled copy) and re-run.${NC}"
    exit 1
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
    if [ "${HYPRTK_PTY_WRAP:-0}" = "1" ] && command -v script >/dev/null 2>&1; then
        # run0 (openSUSE's sudo) fails with "Failed to set unit properties" when
        # its stdio is redirected. Give the step a real PTY via `script`, then
        # redirect script's output to the log. `script -c` runs the command with
        # `sh`, which would drop the exported bash functions the step may use
        # (_installSymLink, ...), so stage it in a temp file and run it with bash.
        local __wrap
        __wrap="$(mktemp)"
        printf '%s\n' "$cmd" > "$__wrap"
        $GUM spin --spinner dot --title "$shown" -- \
            bash -c 'script -qec "bash $1" /dev/null >> "$2" 2>&1' _ "$__wrap" "$logfile"
        local rc=$?
        rm -f "$__wrap"
    else
        $GUM spin --spinner dot --title "$shown" -- bash -c "$cmd >> '$logfile' 2>&1"
        local rc=$?
    fi
    if [ $rc -ne 0 ]; then
        log "SPIN FAILED (exit $rc): $title"
        HYPRTK_FAILED+=("$title")
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
    if [ "${HYPRTK_PTY_WRAP:-0}" = "1" ] && command -v script >/dev/null 2>&1; then
        local __wrap
        __wrap="$(mktemp)"
        printf '%s\n' "$cmd" > "$__wrap"
        bash -c 'script -qec "bash $1" /dev/null >> "$2" 2>&1' _ "$__wrap" "$logfile"
        local rc=$?
        rm -f "$__wrap"
    else
        bash -c "$cmd >> '$logfile' 2>&1"
        local rc=$?
    fi
    if [ $rc -ne 0 ]; then
        log "RUN FAILED (exit $rc): $title"
        HYPRTK_FAILED+=("$title")
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
# openSUSE Tumbleweed's `sudo` is a shim to run0 (systemd), which authenticates
# through polkit. Unlike classic sudo it keeps no reusable timestamp, and any
# non-interactive caller (everything under `gum spin`) is refused with
# "interactive authentication has not been enabled by the calling program".
# Installing a temporary polkit rule that lists this user makes run0 passwordless
# for the rest of the install; it is removed on exit. Other distros keep the
# classic `sudo -v` + keepalive path.
HYPRTK_TMP_POLKIT="/etc/polkit-1/rules.d/51-hyprtk-install.rules"
# doas-only systems (Alpine): doas has no timestamped credential cache like
# sudo, so a temporary nopass drop-in authorises this user for the install; it
# is removed on exit (same pattern as the run0 polkit rule below).
HYPRTK_TMP_DOAS=""
_cleanup_keepalive() {
    if [ -n "$SUDO_KEEPALIVE_PID" ] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    if [ -e "$HYPRTK_TMP_POLKIT" ]; then
        sudo -n rm -f "$HYPRTK_TMP_POLKIT" 2>/dev/null || true
    fi
    if [ -n "${HYPRTK_TMP_DOAS:-}" ] && [ -e "$HYPRTK_TMP_DOAS" ]; then
        doas -n rm -f "$HYPRTK_TMP_DOAS" 2>/dev/null || true
    fi
}
trap _cleanup_keepalive EXIT

# True when `sudo` is systemd's run0 wrapper rather than classic sudo.
_sudo_is_run0() {
    local resolved
    resolved="$(readlink -f "$(command -v sudo 2>/dev/null)" 2>/dev/null)"
    case "$resolved" in *run0*) return 0 ;; esac
    [ -x /usr/bin/run0 ] && sudo --version 2>/dev/null | grep -qi run0
}

# Make elevation non-interactive for the duration of the install.
_sudo_bootstrap() {
    # Detect run0 FIRST: its stdio must be a PTY, so _spin/_run need the
    # `script` wrapper whenever run0 is the elevator — even if a polkit rule is
    # already in place (in which case `sudo -n` succeeds but plain `sudo` with a
    # redirected stdio still fails with "Failed to set unit properties").
    if _sudo_is_run0; then
        HYPRTK_PTY_WRAP=1
        export HYPRTK_PTY_WRAP

        # Already passwordless (rule left over from a previous run)? Done.
        sudo -n true 2>/dev/null && return 0

        echo -e "${WHITE}  openSUSE run0/polkit detected — authorising this user once.${NC}"
        echo ""
        if ! sudo -v; then
            return 1
        fi
        local tmp
        tmp="$(mktemp)"
        # Documented run0 mechanism: add the user to the passwordless list.
        cat > "$tmp" <<POLKIT
// Temporary: written by the hyprtk installer, removed when it exits.
polkit._run0_nopasswd = polkit._run0_nopasswd || [];
polkit._run0_nopasswd.push("$(id -un)");
POLKIT
        if ! sudo install -m 0644 -o root -g root "$tmp" "$HYPRTK_TMP_POLKIT"; then
            rm -f "$tmp"
            return 1
        fi
        rm -f "$tmp"
        # polkit watches rules.d; give it a moment, then confirm.
        local i
        for i in 1 2 3 4 5; do
            sudo -n true 2>/dev/null && return 0
            sleep 1
        done
        return 1
    fi

    # doas-only systems (Alpine): the `sudo` compatibility shim in
    # pkgmanager.sh routes every sudo call to doas. doas keeps no credential
    # cache, so authenticate once, then install a temporary nopass drop-in
    # (doas.d is merged, like polkit's rules.d) for the rest of the install.
    if ! type -P sudo >/dev/null 2>&1 && command -v doas >/dev/null 2>&1; then
        doas -n true 2>/dev/null && return 0

        echo -e "${WHITE}  Alpine doas detected — authorising this user once.${NC}"
        echo ""
        echo -e "${WHITE}  Enter your password to authorise the installation:${NC}"
        if ! doas true; then
            return 1
        fi
        local tmp drop
        tmp="$(mktemp)"
        printf 'permit nopass %s\n' "$(id -un)" > "$tmp"
        # A lexically-last drop-in: doas evaluates /etc/doas.d/*.conf in order
        # with later files winning, so a high number overrides the distro's own
        # rules (e.g. 20-wheel.conf's `permit persist :wheel`).
        drop="/etc/doas.d/99-hyprtk-install.conf"
        doas mkdir -p /etc/doas.d
        if ! doas cp "$tmp" "$drop"; then
            rm -f "$tmp"
            return 1
        fi
        doas chown root:root "$drop"
        doas chmod 0644 "$drop"
        rm -f "$tmp"
        HYPRTK_TMP_DOAS="$drop"
        doas -n true 2>/dev/null
        return $?
    fi

    echo -e "${WHITE}  Enter your password to authorise the installation:${NC}"
    echo ""
    sudo -v || return 1
    return 0
}

_sudo_auth() {
    if ! _sudo_bootstrap; then
        die "sudo authentication failed"
    fi
    log "SUDO: elevation ready"

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

# ── Extra repositories ────────────────────────────────────────────────────
# Some packages live outside the base repos: RPMFusion on Fedora (NVIDIA,
# mesa-*-freeworld), Debian contrib/non-free, Void nonfree. Enable them first
# so every later package step can resolve its names.
_step "Enabling Extra Repositories"
_spin "Enabling extra repositories..." "bash $SCRIPT_DIR/installer/scripts/enable-extra-repos.sh" "$LOG_FILE"
_ok "Extra repositories enabled"

# ── Core packages ─────────────────────────────────────────────────────────
_step "Installing Core Packages"
# Mint/Ubuntu run background updaters that can hold the dpkg lock; announce a
# wait here (visible) instead of letting the first apt step look frozen.
hyprtk_apt_wait_lock
for pkg in hyprland xfce4 filetools webtools printers network media terminaltools systemtools system sddm-check sddmgrub matuwall 3dprinting; do
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

# ── Hyprland >= 0.55 (Lua config) ─────────────────────────────────────────
# The dotfiles are Lua-based (hypr/hyprland.lua); Hyprland < 0.55 ignores them
# and writes a stock hyprland.conf. Where the distro is older (Alpine ships
# 0.54.3, even on edge) the pinned upstream release is built from source. On
# Void this also builds the hyprwm library chain — and it runs *before*
# srcapps-install.sh so hyprsunset/hyprpicker link the same chain. Idempotent
# (skips when already >= 0.55) and non-fatal.
_spin "Ensuring Hyprland >= 0.55 (Lua config)..." "bash $SCRIPT_DIR/installer/scripts/hyprland-src-install.sh" "$LOG_FILE"
_ok "Hyprland Lua-config release ensured"

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
# Download to a temp file and run it locally instead of `curl ... | sh`: a pipe
# lets a partial/failed download execute as root with no artifact to inspect.
# curl is a core-package dependency; fall back to wget only for minimal systems
# that have neither in base (Void ships neither). Pin the URL to a specific
# commit/release when one is available.
_spin "Installing Papirus icons for root..." \
    "tmp=\$(mktemp) && { if command -v curl >/dev/null 2>&1; then curl -fsSL --max-time 60 -o \"\$tmp\" https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh; else wget -qO \"\$tmp\" --timeout=60 https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh; fi; } && sudo env DESTDIR=/root/.local/share/icons sh \"\$tmp\"; rc=\$?; rm -f -- \"\$tmp\"; exit \$rc" \
    "$LOG_FILE"
_ok "Icons installed for root"

# ── Init pywal16 ─────────────────────────────────────────────────────────
# pywal reads the palette with `magick … -unique-colors txt:-`. ImageMagick 7
# ships a security policy that denies the TXT coder, in which case the command
# exits 0 with no output: pywal retries palette sizes, then gives up and
# ~/.cache/wal/colors.json is never written (wal "succeeds" with no result).
# The bundled bar script removes TXT from whatever IM policy is present.
# `wal -n` skips pywal's own wallpaper setting — this installer sets the
# wallpaper via awww, and letting pywal also set it can block forever.
_step "Initiating Pywal16"
_spin "Allowing pywal's ImageMagick TXT coder (if restricted)..." \
    "bash $SCRIPT_DIR/installer/hyprtk-bar/scripts/fix-imagemagick-policy.sh" \
    "$LOG_FILE"
_spin "Initializing pywal16..." "wal -n -i $SCRIPT_DIR/assets/Wallpapers/default.png" "$LOG_FILE"
_ok "pywal16 initiated"

_spin "Setting default wallpaper..." "cp $SCRIPT_DIR/assets/Wallpapers/default.png ~/.cache/current-wallpaper.png && sudo mkdir -p /root/.cache && sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png" "$LOG_FILE"
if type grub_wallpaper >/dev/null 2>&1; then
    _spin "Updating grub wallpaper..." "grub_wallpaper" "$LOG_FILE"
fi
# xdg-user-dirs-gtk-update needs a running desktop session; a headless/SSH run
# (or a VM with no display) makes it exit 1. Attempt both, but never fail the
# step over it.
_spin "Updating user directories..." "xdg-user-dirs-update --force || true; xdg-user-dirs-gtk-update --force || true" "$LOG_FILE"
_ok "Default wallpaper set"

# ── Confirm Hyprland config ──────────────────────────────────────────────
if ! $GUM confirm --prompt.foreground=5 "Configure Hyprland now?"; then
    echo -e "${MAGENTA}  Hyprland configuration skipped.${NC}"
    log "Hyprland configuration skipped by user"
else
    # ── Thunar xfconf ────────────────────────────────────────────────────
    _step "Launching Thunar to generate xfconf"
    # Thunar must run once to write its xfconf. Without a display it exits
    # immediately and `killall` finds nothing — don't fail the step for that.
    _spin "Generating xfconf..." "thunar >/dev/null 2>&1 & sleep 3; killall thunar 2>/dev/null || true" "$LOG_FILE"
    _ok "Thunar xfconf generated"

    # ── Bluetooth ────────────────────────────────────────────────────────
    _step "Enabling Bluetooth"
    if command -v systemctl >/dev/null 2>&1; then
        _spin "Enabling bluetooth..." "sudo systemctl start bluetooth && sudo systemctl enable bluetooth" "$LOG_FILE"
    elif command -v rc-service >/dev/null 2>&1; then
        # OpenRC (Alpine/Gentoo): service is `bluetooth`, enabled per runlevel.
        _spin "Enabling bluetooth..." "sudo rc-service bluetooth start 2>/dev/null || true; sudo rc-update add bluetooth default 2>/dev/null || true" "$LOG_FILE"
    elif command -v sv >/dev/null 2>&1 && [ -d /etc/sv ]; then
        # runit (Void): the service is /etc/sv/bluetoothd; enabling means
        # symlinking it into the runsvdir. /var/service is the standard link to
        # the runsvdir; fall back to the default dir when it is absent.
        _spin "Enabling bluetooth..." "sudo sh -c 'd=/var/service; [ -d \"\$d\" ] || d=/etc/runit/runsvdir/default; [ -d /etc/sv/bluetoothd ] && ln -sfn /etc/sv/bluetoothd \"\$d/bluetoothd\"; sv start bluetoothd 2>/dev/null || true'" "$LOG_FILE"
    else
        _warn "No supported init system for bluetooth — not enabled"
    fi
    _ok "Bluetooth enabled"

    # ── Cross-desktop autostart cleanup ──────────────────────────────────
    # uwsm sessions run systemd-xdg-autostart, so distro defaults for another
    # desktop (e.g. Fedora Xfce's dnfdragora-updater) also launch under
    # Hyprland and can crash. Suppress the known-bad ones per-user.
    _spin "Cleaning up cross-desktop autostart..." "bash $SCRIPT_DIR/installer/scripts/xdg-autostart-cleanup.sh" "$LOG_FILE"
    _ok "Cross-desktop autostart cleaned up"

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
    if command -v systemctl >/dev/null 2>&1; then
        _spin "Enabling cockpit..." "sudo cp $SCRIPT_DIR/configs/User-Management/manage-users.desktop /usr/share/applications/ && sudo systemctl enable --now cockpit.socket && sudo systemctl start cockpit.socket" "$LOG_FILE"
        _ok "Cockpit enabled"
    else
        _warn "cockpit requires systemd — not available on this system; skipping"
    fi

    # ── Samba ────────────────────────────────────────────────────────────
    _step "Enabling Samba"
    # Service names differ: Arch uses smb/nmb, most others smbd/nmbd, and
    # OpenRC (Alpine) the single `samba` service.
    if command -v systemctl >/dev/null 2>&1; then
        _spin "Enabling samba..." "sudo mkdir -p /etc/samba && sudo cp $SCRIPT_DIR/configs/smb/smb.conf /etc/samba/ && (sudo systemctl enable --now smb nmb 2>/dev/null || sudo systemctl enable --now smbd nmbd 2>/dev/null); true" "$LOG_FILE"
    elif command -v rc-service >/dev/null 2>&1; then
        _spin "Enabling samba..." "sudo mkdir -p /etc/samba && sudo cp $SCRIPT_DIR/configs/smb/smb.conf /etc/samba/ && (sudo rc-service samba start 2>/dev/null || true); (sudo rc-update add samba default 2>/dev/null || true); true" "$LOG_FILE"
    else
        _spin "Enabling samba..." "sudo mkdir -p /etc/samba && sudo cp $SCRIPT_DIR/configs/smb/smb.conf /etc/samba/; true" "$LOG_FILE"
    fi
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
        # btop config lives in a real ~/.config/btop (btop.conf is linked, the
        # pywal theme is a per-user link). Nothing generated is written into the
        # repo clone, and the repo never ships an absolute home path. pywal writes
        # the theme to ~/.cache/wal/btopwal.theme from the bundled template.
        _spin "Installing btop..." "if [ -L \"\$HOME/.config/btop\" ]; then rm -f \"\$HOME/.config/btop\"; fi; mkdir -p \"\$HOME/.config/btop/themes\" && ln -sfn \"$SCRIPT_DIR/configs/btop/btop.conf\" \"\$HOME/.config/btop/btop.conf\" && ln -sfn \"\$HOME/.cache/wal/btopwal.theme\" \"\$HOME/.config/btop/themes/btopwal.theme\"" "$LOG_FILE"
        _ok "General configs installed"

        # ── Re-init pywal16 ───────────────────────────────────────────
        _step "Re-Initiating Pywal16"
        if type wal_init >/dev/null 2>&1; then
            _spin "Running wal_init..." "wal_init" "$LOG_FILE"
        else
            _spin "Initializing pywal16..." "wal -n -i $SCRIPT_DIR/assets/Wallpapers/default.png" "$LOG_FILE"
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
        # swaylock-effects is AUR-only, so most families get plain swaylock,
        # which rejects the effects config (clock/timestr/datestr, fade-in,
        # effect-pixelate) and refuses to lock. Pick the variant the installed
        # binary accepts, and point ~/.config/swaylock/config at the
        # pywal-rendered config (configs/wal/templates/swaylock[-plain]-config)
        # so the lock screen follows the wallpaper; the static repo config is the
        # fallback when pywal has not rendered yet.
        if command -v swaylock >/dev/null 2>&1 && swaylock --help 2>&1 | grep -q -- '--effect-pixelate'; then
            _swaylock_src="$SCRIPT_DIR/configs/swaylock/config"
            _swaylock_rendered="$HOME/.cache/wal/swaylock-config"
        else
            _swaylock_src="$SCRIPT_DIR/configs/swaylock-plain/config"
            _swaylock_rendered="$HOME/.cache/wal/swaylock-plain-config"
        fi
        [ -f "$_swaylock_rendered" ] || _swaylock_rendered="$_swaylock_src"
        _spin "Installing swaylock..." "if [ -L ~/.config/swaylock ]; then rm -f ~/.config/swaylock; fi; mkdir -p ~/.config/swaylock; _installSymLink swaylock-config ~/.config/swaylock/config $_swaylock_rendered ~/.config/swaylock" "$LOG_FILE"
        _spin "Installing swappy..." "_installSymLink swappy ~/.config/swappy $SCRIPT_DIR/configs/swappy/ ~/.config" "$LOG_FILE"
        _spin "Installing hyprlogout..." "_installSymLink hyprlogout ~/.config/hyprlogout $SCRIPT_DIR/configs/hyprlogout/ ~/.config" "$LOG_FILE"
        _spin "Installing waypaper..." "_installSymLink waypaper ~/.config/waypaper $SCRIPT_DIR/configs/waypaper/ ~/.config" "$LOG_FILE"
        _spin "Installing zshrc..." "_installSymLink zshrc ~/.config/zshrc $SCRIPT_DIR/configs/zshrc/ ~/.config" "$LOG_FILE"
        _spin "Installing ohmyposh..." "_installSymLink ohmyposh ~/.config/ohmyposh $SCRIPT_DIR/configs/ohmyposh/ ~/.config" "$LOG_FILE"
        # matuwall reads ~/.config/matuwall/config.toml. Point that file at the
        # pywal-rendered config (configs/wal/templates/matuwall-config.toml) so
        # the picker follows the wallpaper; the static repo config is the
        # fallback when pywal has not rendered yet.
        _matuwall_rendered="$HOME/.cache/wal/matuwall-config.toml"
        [ -f "$_matuwall_rendered" ] || _matuwall_rendered="$SCRIPT_DIR/configs/matuwall/config.toml"
        _spin "Installing matuwall..." "if [ -L ~/.config/matuwall ]; then rm -f ~/.config/matuwall; fi; mkdir -p ~/.config/matuwall; _installSymLink matuwall-config ~/.config/matuwall/config.toml $_matuwall_rendered ~/.config/matuwall" "$LOG_FILE"
        _spin "Installing wob..." "_installSymLink wob ~/.config/wob $SCRIPT_DIR/configs/wob/ ~/.config" "$LOG_FILE"
        _spin "Creating ~/.local/bin..." "mkdir -p ~/.local/bin" "$LOG_FILE"
        _ok "Hyprland configs installed"

        # ── Preferred apps (XDG) ───────────────────────────────────────
        # Point XDG at the suite's file manager/browser so desktop integration
        # and hyprtk-bar's quick links resolve thunar/brave, not the distro's
        # defaults. The session terminal is $TERMINAL in hypr/environment.lua.
        _spin "Registering preferred apps..." "bash $SCRIPT_DIR/installer/scripts/set-default-apps.sh" "$LOG_FILE"
        _ok "Preferred apps registered"

        # ── ZSH ──────────────────────────────────────────────────────
        _step "Installing ZSH"
        _spin "Installing zsh..." "_installPackagesPacman zsh" "$LOG_FILE"
        # oh-my-zsh install needs interactive input - run without spin.
        # Fetch to a temp file and run it (avoids `sh -c "$(curl ...)"`, which
        # hides the fetched code and runs a partial download if the fetch fails).
        # Skip when already present: the upstream installer returns non-zero on
        # an existing install, which would otherwise be reported as a failure.
        if [ -d "$HOME/.oh-my-zsh" ]; then
            echo -e "${CYAN}  → ${WHITE}oh-my-zsh already installed${NC}"
        else
            echo -e "${CYAN}  → ${WHITE}Installing oh-my-zsh${NC}"
            tmp="$(mktemp)" && curl -fsSL --max-time 90 \
                https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
                -o "$tmp" && bash "$tmp" --unattended
            rc=$?
            rm -f -- "$tmp"
            if [ "$rc" -ne 0 ]; then
                _fail "oh-my-zsh install exited $rc (network?)"
            fi
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
        # chsh needs a password; use sudo (already authorised). Never fall back
        # to a non-root `chsh`: it prompts on /dev/tty, which is invisible under
        # the installer, so it would hang forever waiting for input.
        # Name the target user explicitly: `chsh` with no user argument changes
        # the *invoking* user's shell, which under sudo is root.
        # Prefer `usermod -s`: on openSUSE the elevation wrapper is run0-sudo,
        # whose own `-s` ("run a shell") flag shadows chsh's, and chsh also fails
        # under run0's PAM session; the leading `--` stops option parsing in the
        # wrapper either way. Fall back to chsh where usermod is unavailable.
        ZSH_BIN="$(command -v zsh || echo /bin/zsh)"
        _target_user="${SUDO_USER:-$(id -un)}"
        grep -qx "$ZSH_BIN" /etc/shells 2>/dev/null \
            || echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
        sudo -- usermod -s "$ZSH_BIN" "$_target_user" 2>/dev/null \
            || sudo -- chsh -s "$ZSH_BIN" "$_target_user" \
            || _fail "could not set the default shell to zsh"
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

        # ── hyprtk-usb (GUI) ────────────────────────────────────────
        _step "Installing hyprtk-usb"
        _spin "Installing hyprtk-usb..." "bash $SCRIPT_DIR/installer/hyprtk-usb/install.sh" "$LOG_FILE"
        _ok "hyprtk-usb installed (CLI/TUI zipapp + hyprtk-usb-gui)"

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
            # openSUSE uses run0/polkit (no classic sudo, no /etc/sudoers.d): skip
            # rather than fail — sudoers defaults don't apply there.
            _spin "Configuring sudoers..." \
                "command -v visudo >/dev/null 2>&1 || { echo 'no classic sudo/visudo (run0/polkit?) - sudoers defaults not applicable'; exit 0; }; sudo install -d -m 0750 /etc/sudoers.d && printf 'Defaults env_reset,pwfeedback\n' | sudo tee /etc/sudoers.d/99-hyprtk-defaults >/dev/null && sudo chmod 440 /etc/sudoers.d/99-hyprtk-defaults && sudo visudo -c >/dev/null 2>&1" \
                "$LOG_FILE"
        fi
        _ok "Sudoers configured"

        # ── Bar sudo access (passwordless) ──────────────────────────
        _step "Configuring Bar Sudo Access"
        echo -e "${CYAN}  → ${WHITE}Installing hyprtk-bar sudoers (passwordless sudo)${NC}"
        if sudo bash "$SCRIPT_DIR/installer/scripts/setup-sudoers.sh"; then
            _ok "Bar passwordless sudo configured"
        else
            _fail "Bar passwordless sudo not configured (see $LOG_FILE)"
        fi
    fi
fi

# ── Cleanup ────────────────────────────────────────────────────────────────
if [ -n "${HOME:-}" ]; then
    rm -rf -- "$HOME/dotfiles" 2>/dev/null || true
fi

# ── Completion ─────────────────────────────────────────────────────────────
log "=== hyprtk installation completed ==="
if [ "${#HYPRTK_FAILED[@]}" -gt 0 ]; then
    log "!!! ${#HYPRTK_FAILED[@]} step(s) FAILED:"
    local_fail=""
    for local_fail in "${HYPRTK_FAILED[@]}"; do
        log "!!!   - $local_fail"
    done
    echo ""
    echo -e "${RED}  ${#HYPRTK_FAILED[@]} step(s) did NOT complete cleanly:${NC}"
    for local_fail in "${HYPRTK_FAILED[@]}"; do
        echo -e "${YELLOW}    • $local_fail${NC}"
    done
    echo -e "${WHITE}  See ${CYAN}$LOG_FILE${WHITE} for the failing output.${NC}"
    echo ""
    sleep 4
fi
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
