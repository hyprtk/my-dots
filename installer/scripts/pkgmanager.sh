#!/bin/bash
# ── hyprtk multi-distro package-manager abstraction ─────────────────────────
# Sourced (never executed) by every hypr/packages/*.sh script, by
# installer/scripts/library.sh, and by the top-level 1-install.sh. It detects
# the host package manager and provides install / remove / query / AUR wrappers
# so the dotfiles install on any Linux distribution — the same portability model
# as hyprtk-bar/install.sh.
#
# Supported families:
#   Arch (pacman, +AUR via yay/paru)   Debian/Ubuntu (apt)
#   Fedora/RHEL (dnf)                  openSUSE (zypper)
#   Void (xbps)                        Alpine (apk)
#   Gentoo (emerge — lists only)       NixOS (nix — declarative)
# Unknown managers degrade gracefully: nothing is installed, the caller is told
# which packages to add manually.
# ─────────────────────────────────────────────────────────────────────────────

# ── Detection ───────────────────────────────────────────────────────────────
hyprtk_detect_pm() {
    command -v pacman       >/dev/null 2>&1 && { echo pacman; return; }
    command -v apt-get      >/dev/null 2>&1 && { echo apt;    return; }
    command -v dnf          >/dev/null 2>&1 && { echo dnf;    return; }
    command -v zypper       >/dev/null 2>&1 && { echo zypper; return; }
    command -v xbps-install >/dev/null 2>&1 && { echo xbps;   return; }
    command -v apk          >/dev/null 2>&1 && { echo apk;    return; }
    command -v emerge       >/dev/null 2>&1 && { echo emerge; return; }
    command -v nix          >/dev/null 2>&1 && { echo nix;    return; }
    echo none
}

HYPRTK_PM="${HYPRTK_PM:-$(hyprtk_detect_pm)}"
export HYPRTK_PM

# Human-readable name for the detected manager.
hyprtk_pm_name() {
    case "$HYPRTK_PM" in
        pacman) echo "Arch (pacman)" ;;
        apt)    echo "Debian/Ubuntu (apt)" ;;
        dnf)    echo "Fedora/RHEL (dnf)" ;;
        zypper) echo "openSUSE (zypper)" ;;
        xbps)   echo "Void (xbps)" ;;
        apk)    echo "Alpine (apk)" ;;
        emerge) echo "Gentoo (emerge)" ;;
        nix)    echo "NixOS (nix)" ;;
        *)      echo "unknown" ;;
    esac
}

# ── Root ────────────────────────────────────────────────────────────────────
# Alpine (and other doas-only systems) ship doas instead of sudo. When no real
# sudo binary is present, define a `sudo` compatibility function that maps the
# flags the dotfiles use onto doas, and export it so the `bash -c` subshells
# used by _spin/_run (and scripts invoked as `bash script.sh`) inherit it. This
# lets every existing `sudo ...` call site work unchanged. Never shadows a real
# sudo. POSIX-safe (no arrays) so it is also usable from /bin/sh scripts.
if ! type -P sudo >/dev/null 2>&1 && command -v doas >/dev/null 2>&1; then
    sudo() {
        while [ $# -gt 0 ]; do
            case "$1" in
                -v|--validate) doas true; return $? ;;
                -n|--non-interactive) shift ;;
                -E|--preserve-env|-H|-S|-k|--stdin) shift ;;
                -u|--user) shift; _hyprtk_su="$1"; shift; doas -u "$_hyprtk_su" "$@"; return $? ;;
                --) shift; break ;;
                -*) shift ;;
                *) break ;;
            esac
        done
        doas "$@"
    }
    export -f sudo 2>/dev/null || true
fi

# Run a command as root (directly when already root, else through sudo, then
# doas — the fallback matters in non-bash contexts where the shim above is not
# inherited).
hyprtk_run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    elif command -v doas >/dev/null 2>&1; then
        doas "$@"
    else
        echo "  ✗ need root to manage packages; neither sudo nor doas found" >&2
        return 1
    fi
}

# apt wrapper: non-interactive, config-file-tolerant and lock-tolerant.
# Mint and Ubuntu run background updaters (mintupdate / unattended-upgrades /
# packagekit / the apt-daily timers) that can hold the dpkg lock, and debconf or
# needrestart can prompt — neither is visible inside `gum spin`, so the install
# looks frozen ("stale"). DEBIAN_FRONTEND/NEEDRESTART_MODE suppress the prompts,
# DPkg::Lock::Timeout bounds the wait for the lock (instead of hanging forever),
# and the dpkg options keep pre-existing config files.
_apt() {
    hyprtk_run_root env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
        apt-get -o DPkg::Lock::Timeout=600 \
                -o Dpkg::Options::=--force-confdef \
                -o Dpkg::Options::=--force-confold "$@"
}

# Wait *visibly* for the dpkg/apt lock when a background updater holds it. Called
# before the package phase (outside the gum spinner) so an apt-locked install is
# announced rather than looking frozen; capped so it can never hang forever.
hyprtk_apt_wait_lock() {
    [ "$HYPRTK_PM" = apt ] || return 0
    command -v flock >/dev/null 2>&1 || return 0
    local waited=0 f
    for f in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock; do
        [ -e "$f" ] || continue
        while ! hyprtk_run_root flock -n "$f" true 2>/dev/null; do
            [ "$waited" -eq 0 ] && \
                echo "  ! apt is locked by a background updater (mintupdate/unattended-upgrades) — waiting…"
            sleep 5
            waited=$((waited + 5))
            if [ "$waited" -ge 600 ]; then
                echo "  ! apt still locked after ${waited}s — continuing anyway"
                return 0
            fi
        done
    done
    [ "$waited" -gt 0 ] && echo "  ✓ apt lock released (waited ${waited}s)"
    return 0
}

# openSUSE packages Python modules under versioned names (python313-psutil,
# python314-gobject) with no unversioned python3-* alias. Map a python3-FOO
# request to python3NN-FOO for the running interpreter; leave anything else (and
# any undeterminable prefix) untouched. Non-zypper callers never invoke this.
hyprtk_zypper_pyname() {
    case "$1" in
        python3-*)
            local py
            py="$(python3 -c 'import sys; print("python%d%d" % sys.version_info[:2])' 2>/dev/null || true)"
            if [ -n "$py" ]; then
                printf '%s\n' "${py}-${1#python3-}"
                return 0
            fi
            ;;
    esac
    printf '%s\n' "$1"
}

# ── Query ───────────────────────────────────────────────────────────────────# 0 when the named package is installed, 1 otherwise.
pkg_is_installed() {
    local p="$1"
    case "$HYPRTK_PM" in
        pacman) pacman -Qq "$p" >/dev/null 2>&1 ;;
        apt)    dpkg -s "$p" >/dev/null 2>&1 ;;
        dnf|zypper) rpm -q "$p" >/dev/null 2>&1 ;;
        xbps)   xbps-query "$p" >/dev/null 2>&1 ;;
        apk)    apk info -e "$p" >/dev/null 2>&1 ;;
        *)      return 1 ;;
    esac
}

# ── Install ─────────────────────────────────────────────────────────────────
# Install a list of distro-native package names. A single unavailable name would
# otherwise abort an apt/dnf/pacman transaction, so the batch is attempted first
# and any failure is retried one package at a time, warning only for the names
# that are genuinely missing. HYPRTK_DRYRUN=1 just prints the list.
pkg_install() {
    [ "$#" -eq 0 ] && return 0
    local pkgs=("$@")
    if [ -n "${HYPRTK_DRYRUN:-}" ]; then
        printf '%s\n' "${pkgs[@]}"
        return 0
    fi

    local batch_ok=1
    case "$HYPRTK_PM" in
        pacman) hyprtk_run_root pacman -S --noconfirm --needed "${pkgs[@]}" || batch_ok=0 ;;
        apt)    _apt install -y "${pkgs[@]}" || batch_ok=0 ;;
        dnf)    hyprtk_run_root dnf install -y "${pkgs[@]}" || batch_ok=0 ;;
        zypper)
            local -a zpkgs=()
            local zq
            for zq in "${pkgs[@]}"; do
                zpkgs+=("$(hyprtk_zypper_pyname "$zq")")
            done
            hyprtk_run_root zypper --non-interactive install "${zpkgs[@]}" || batch_ok=0 ;;
        xbps)   hyprtk_run_root xbps-install -Sy "${pkgs[@]}" || batch_ok=0 ;;
        apk)    hyprtk_run_root apk add --no-cache "${pkgs[@]}" || batch_ok=0 ;;
        emerge)
            echo "  ! Gentoo: emerge these, then rerun with --no-deps: ${pkgs[*]}" >&2
            return 0 ;;
        nix)
            echo "  ! NixOS: add these to your configuration: ${pkgs[*]}" >&2
            return 0 ;;
        *)
            echo "  ! No supported package manager — install manually: ${pkgs[*]}" >&2
            return 0 ;;
    esac
    [ "$batch_ok" -eq 1 ] && return 0

    # Batch failed — isolate the offenders, keep the rest installed.
    local p failed=0
    for p in "${pkgs[@]}"; do
        case "$HYPRTK_PM" in
            pacman) hyprtk_run_root pacman -S --noconfirm --needed "$p" >/dev/null 2>&1 ;;
            apt)    _apt install -y "$p" >/dev/null 2>&1 ;;
            dnf)    hyprtk_run_root dnf install -y "$p" >/dev/null 2>&1 ;;
            zypper) hyprtk_run_root zypper --non-interactive install "$(hyprtk_zypper_pyname "$p")" >/dev/null 2>&1 ;;
            xbps)   hyprtk_run_root xbps-install -Sy "$p" >/dev/null 2>&1 ;;
            apk)    hyprtk_run_root apk add --no-cache "$p" >/dev/null 2>&1 ;;
        esac || { echo "  ! package unavailable: $p" >&2; failed=1; }
    done
    return "$failed"
}

# ── Remove ──────────────────────────────────────────────────────────────────
# Best-effort removal; never fatal (a package that isn't there is fine).
pkg_remove() {
    [ "$#" -eq 0 ] && return 0
    local pkgs=("$@")
    if [ -n "${HYPRTK_DRYRUN:-}" ]; then
        printf 'remove %s\n' "${pkgs[*]}"
        return 0
    fi
    case "$HYPRTK_PM" in
        pacman) hyprtk_run_root pacman -Rns --noconfirm "${pkgs[@]}" 2>/dev/null || true ;;
        apt)    _apt remove -y "${pkgs[@]}" 2>/dev/null || true ;;
        dnf)    hyprtk_run_root dnf remove -y "${pkgs[@]}" 2>/dev/null || true ;;
        zypper) hyprtk_run_root zypper --non-interactive remove "${pkgs[@]}" 2>/dev/null || true ;;
        xbps)   hyprtk_run_root xbps-remove -Ry "${pkgs[@]}" 2>/dev/null || true ;;
        apk)    hyprtk_run_root apk del "${pkgs[@]}" 2>/dev/null || true ;;
        *)      : ;;
    esac
    return 0
}

# ── AUR (Arch only) ─────────────────────────────────────────────────────────
aur_helper() {
    command -v yay  >/dev/null 2>&1 && { echo yay;  return; }
    command -v paru >/dev/null 2>&1 && { echo paru; return; }
    echo ""
}

aur_available() { [ "$HYPRTK_PM" = pacman ] && [ -n "$(aur_helper)" ]; }

# Install Arch User Repository packages. On any non-Arch family (or with no AUR
# helper) this is a warning, not a failure — each caller supplies the distro
# equivalents in its own PKGS list.
aur_install() {
    [ "$#" -eq 0 ] && return 0
    local pkgs=("$@")
    if [ -n "${HYPRTK_DRYRUN:-}" ]; then
        printf '%s\n' "${pkgs[@]}"
        return 0
    fi
    if [ "$HYPRTK_PM" != pacman ]; then
        echo "  ! AUR-only packages skipped on $HYPRTK_PM: ${pkgs[*]}" >&2
        return 0
    fi
    local h
    h="$(aur_helper)"
    if [ -z "$h" ]; then
        echo "  ! no AUR helper (yay/paru) found — install manually: ${pkgs[*]}" >&2
        return 0
    fi
    "$h" -S --noconfirm --needed "${pkgs[@]}" || {
        local p
        for p in "${pkgs[@]}"; do
            "$h" -S --noconfirm --needed "$p" >/dev/null 2>&1 \
                || echo "  ! AUR package unavailable: $p" >&2
        done
    }
    return 0
}

# ── Ubuntu-family third-party apt repos ─────────────────────────────────────
# A PPA is normally added with `add-apt-repository`, but that needs
# software-properties-common and a working Launchpad API — which is not always
# available (and fails outright in minimal/containerised Ubuntu & Mint). These
# helpers add a PPA by its signing key + a sources.list.d entry instead, which
# needs only curl + apt itself.

# The Ubuntu codename of the host. Linux Mint sets VERSION_CODENAME to its own
# name (e.g. "zena") but UBUNTU_CODENAME to the base release ("noble"), and a
# PPA is keyed by the Ubuntu codename.
hyprtk_ubuntu_codename() {
    local c
    c=$(grep -E '^UBUNTU_CODENAME=' /etc/os-release 2>/dev/null | head -1 | cut -d= -f2 | tr -d "\"'")
    [ -n "$c" ] || c=$(grep -E '^VERSION_CODENAME=' /etc/os-release 2>/dev/null | head -1 | cut -d= -f2 | tr -d "\"'")
    printf '%s' "$c"
}

# True on Ubuntu and its derivatives (Mint, Pop, elementary, Zorin, …).
hyprtk_is_ubuntu_family() {
    [ -r /etc/os-release ] || return 1
    local id like
    id=$(grep -E '^ID=' /etc/os-release | head -1 | cut -d= -f2 | tr -d "\"'")
    like=$(grep -E '^ID_LIKE=' /etc/os-release | head -1 | cut -d= -f2 | tr -d "\"'")
    case "$id $like" in
        *ubuntu*) return 0 ;;
    esac
    return 1
}

# Add a Launchpad PPA explicitly. $1 = user/archive, $2 = signing key
# fingerprint, $3 = components (default "main"). Returns non-zero if the key
# could not be fetched or the codename is unknown.
hyprtk_apt_add_ppa() {
    local ppa="$1" key="$2" comps="${3:-main}"
    local name codename keyring
    name="$(printf '%s' "$ppa" | tr '/' '-')"
    codename="$(hyprtk_ubuntu_codename)"
    [ -n "$codename" ] || { echo "  ! $ppa: cannot determine the Ubuntu codename" >&2; return 1; }
    keyring="/etc/apt/keyrings/ppa-$name.asc"
    pkg_install curl ca-certificates
    hyprtk_run_root install -d -m 0755 /etc/apt/keyrings
    if ! curl -fsSL --max-time 60 \
            "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$key" -o "$keyring" 2>/dev/null; then
        echo "  ! $ppa: could not fetch the signing key" >&2
        return 1
    fi
    printf 'deb [signed-by=%s] https://ppa.launchpadcontent.net/%s/ubuntu %s %s\n' \
        "$keyring" "$ppa" "$codename" "$comps" \
        | hyprtk_run_root tee "/etc/apt/sources.list.d/$name.list" >/dev/null
    _apt update || true
    return 0
}

# ── Extra repositories ──────────────────────────────────────────────────────
# Some packages the dotfiles need live outside the base repos. Enable the
# standard extra repo per family (idempotent, best-effort):
#   dnf  → RPMFusion free + nonfree (NVIDIA, mesa-*-freeworld, unrar)
#   apt  → Debian contrib/non-free/non-free-firmware (nvidia, unrar, intel-media)
#   xbps → current/nonfree (nvidia, unrar)
#   apk  → none exists; Alpine genuinely has no NVIDIA/unrar packages.

# Debian proper (incl. Kali/Parrot-style derivatives), NOT the Ubuntu family
# (Ubuntu already ships universe/multiverse/restricted).
hyprtk_is_debian_family() {
    [ -r /etc/os-release ] || return 1
    local id like
    id=$(grep -E '^ID=' /etc/os-release | head -1 | cut -d= -f2 | tr -d "\"'")
    like=$(grep -E '^ID_LIKE=' /etc/os-release | head -1 | cut -d= -f2 | tr -d "\"'")
    case "$id $like" in *ubuntu*|*mint*) return 1 ;; esac
    case "$id" in debian) return 0 ;; esac
    case "$like" in *debian*) return 0 ;; esac
    return 1
}

hyprtk_dnf_enable_rpmfusion() {
    [ "$HYPRTK_PM" = dnf ] || return 0
    rpm -q rpmfusion-free-release >/dev/null 2>&1 \
        && rpm -q rpmfusion-nonfree-release >/dev/null 2>&1 && return 0
    local rel
    rel="$(rpm -E %fedora 2>/dev/null)"
    [ -n "$rel" ] || { echo "  ! cannot determine the Fedora release for RPMFusion" >&2; return 1; }
    echo "  Enabling RPMFusion (free + nonfree) for Fedora $rel"
    hyprtk_run_root dnf install -y \
        "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${rel}.noarch.rpm" \
        "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${rel}.noarch.rpm" \
        || { echo "  ! RPMFusion could not be enabled" >&2; return 1; }
}

hyprtk_apt_enable_nonfree() {
    [ "$HYPRTK_PM" = apt ] || return 0
    hyprtk_is_debian_family || return 0
    local f changed=0
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
        [ -f "$f" ] || continue
        if grep -qE '^Components:' "$f"; then
            grep -qE '^Components:.*\bnon-free\b' "$f" && continue
            hyprtk_run_root sed -i -E 's/^(Components:.*)$/\1 contrib non-free non-free-firmware/' "$f"
            changed=1
        elif grep -qE '^(deb|deb-src)[[:space:]]' "$f"; then
            grep -q 'non-free' "$f" && continue
            hyprtk_run_root sed -i -E \
                's/^((deb|deb-src)[[:space:]]+[^ ]+[[:space:]]+[^ ]+[[:space:]]+[^ ]+)(.*)$/\1 contrib non-free non-free-firmware\3/' "$f"
            changed=1
        fi
    done
    if [ "$changed" = 1 ]; then
        echo "  Enabled Debian contrib/non-free/non-free-firmware"
        hyprtk_run_root apt-get update -qq || true
    fi
    return 0
}

hyprtk_xbps_enable_nonfree() {
    [ "$HYPRTK_PM" = xbps ] || return 0
    local conf=/etc/xbps.d/10-nonfree.conf
    [ -f "$conf" ] && return 0
    local base
    base=$(grep -rhoE 'repository=https?://[^ ]*/current' /usr/share/xbps.d /etc/xbps.d 2>/dev/null \
           | head -1 | cut -d= -f2)
    [ -n "$base" ] || base=https://repo-default.voidlinux.org/current
    echo "  Enabling the Void nonfree repo"
    printf 'repository=%s/nonfree\n' "$base" | hyprtk_run_root tee "$conf" >/dev/null
    hyprtk_run_root xbps-install -S || true
    return 0
}

hyprtk_enable_extra_repos() {
    case "$HYPRTK_PM" in
        dnf)  hyprtk_dnf_enable_rpmfusion ;;
        apt)  hyprtk_apt_enable_nonfree ;;
        xbps) hyprtk_xbps_enable_nonfree ;;
        *)    return 0 ;;
    esac
}

# Export every helper so they survive the `bash -c` subshells the installer uses
# for `gum spin` steps. Without this, `pkg_install` runs but its helpers
# (`_apt`, `hyprtk_zypper_pyname`, …) are "command not found" there, so the
# package name is dropped and the install silently does nothing (e.g. the zsh
# step on apt/zypper). Exported via `export -f`; harmless elsewhere.
export -f hyprtk_detect_pm hyprtk_pm_name hyprtk_run_root _apt \
    hyprtk_apt_wait_lock hyprtk_zypper_pyname pkg_is_installed pkg_install \
    pkg_remove aur_helper aur_available aur_install hyprtk_ubuntu_codename \
    hyprtk_is_ubuntu_family hyprtk_apt_add_ppa hyprtk_is_debian_family \
    hyprtk_dnf_enable_rpmfusion hyprtk_apt_enable_nonfree \
    hyprtk_xbps_enable_nonfree hyprtk_enable_extra_repos 2>/dev/null || true
