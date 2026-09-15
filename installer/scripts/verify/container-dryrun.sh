#!/bin/bash
# ── container-dryrun.sh — full installer dry-run inside a distro container ───
# The containerised counterpart of installer-dryrun.sh (which targets the 11
# Arch-based distros on the host). It boots a throwaway rootless-podman container
# for each package-manager family/variant and runs the *whole* installer with
# every mutating command stubbed, so the logic — distro detection, per-family
# package lists, hooks, symlinks — is exercised on the real distro without
# changing anything.
#
# Inside the container it:
#   * builds a sandbox $HOME with the repo at ~/hyprtk (code copied, the big
#     read-only asset trees symlinked), mirroring a real deployment;
#   * stubs every mutating command plus the family's package manager, and swaps
#     the bundled gum for a non-interactive stub;
#   * runs 1-install.sh with HYPRTK_DRYRUN=1 (pkg_install/aur_install print only)
#     and piped answers to the few `read` prompts;
#   * requires INSTALLATION COMPLETE, exit 0, and no FATAL/FAIL/SPIN FAILED/
#     RUN FAILED (or run-log errors).
#
# Usage (host):
#   container-dryrun.sh                 # all installable families
#   container-dryrun.sh --all           # + emerge/nix (advisory, large images)
#   container-dryrun.sh --family apt    # only the named family (repeatable)
# ─────────────────────────────────────────────────────────────────────────────
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PODMAN="${PODMAN:-podman}"
DRYRUN_TIMEOUT="${DRYRUN_TIMEOUT:-1800}"

INSTALL_FAMILIES=(pacman apt dnf zypper xbps apk)
ADVISORY_FAMILIES=(emerge nix)
INCLUDE_ADVISORY=0
SEL_FAMILIES=()

# ── In-container payload ────────────────────────────────────────────────────
if [ "${1:-}" = "--inside" ]; then
    FAMILY="${2:?family required}"
    SRC=/src
    SB="$(mktemp -d)"
    H="$SB/home"
    REPO="$H/hyprtk"
    STUB="$SB/stub"
    mkdir -p "$STUB" "$REPO" \
             "$H/.cache" "$H/Pictures" \
             "$H/Downloads/yay-git/src/hyprviz-bin" \
             "$H/.local/share/Matuwall/.venv/bin" \
             "$H/.local/share/hyprtk-bar/venv/bin"

    # Stubs: generic mutators + the family's own package manager.
    gen="sudo systemctl chsh grub-mkconfig grub-install update-grub update-initramfs
         dracut mkinitcpio wal thunar killall xdg-user-dirs-update
         xdg-user-dirs-gtk-update pip pip3 python3 update-desktop-database
         timedatectl git curl wget clear tput"
    case "$FAMILY" in
        pacman) fam="pacman yay paru makepkg" ;;
        apt)    fam="apt apt-get apt-cache add-apt-repository" ;;
        dnf)    fam="dnf" ;;
        zypper) fam="zypper" ;;
        xbps)   fam="xbps-install xbps-query xbps-remove" ;;
        apk)    fam="apk" ;;
        emerge) fam="emerge" ;;
        nix)    fam="nix nix-env" ;;
        *)      fam="" ;;
    esac
    for c in $gen $fam; do
        printf '#!/bin/sh\nexit 0\n' > "$STUB/$c"
        chmod +x "$STUB/$c"
    done

    # Non-interactive gum: confirm=yes; choose returns the family label (only
    # used when /etc/os-release is absent, e.g. the nix build image); spin runs
    # the wrapped command.
    cat > "$STUB/gum" <<'EOF'
#!/usr/bin/env bash
cmd="${1:-}"; shift
case "$cmd" in
  spin)
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do shift; done
    [ $# -gt 0 ] && shift
    exec "$@"
    ;;
  choose) printf '%s\n' "${DRYRUN_DISTRO_NAME:-}"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
    chmod +x "$STUB/gum"

    case "$FAMILY" in
        emerge) DRYRUN_NAME="Gentoo" ;;
        nix)    DRYRUN_NAME="NixOS" ;;
        *)      DRYRUN_NAME="" ;;
    esac

    # Sandbox repo: copy the code, symlink the read-only bulk.
    cp -a "$SRC/1-install.sh" "$REPO/"
    cp -a "$SRC/installer" "$REPO/"
    cp -a "$SRC/hypr" "$REPO/"
    for f in LICENSE CHANGELOG cheatsheet.md README.md PLANNING.md PORTABILITY.md .zshrc .folder.png; do
        [ -e "$SRC/$f" ] && cp -a "$SRC/$f" "$REPO/" 2>/dev/null
    done
    ln -s "$SRC/assets"   "$REPO/assets"
    ln -s "$SRC/configs"  "$REPO/configs"
    ln -s "$SRC/distro"   "$REPO/distro"
    [ -e "$SRC/default.png" ] && ln -s "$SRC/default.png" "$REPO/default.png"
    rm -f "$REPO/installer/standalone/gum"
    cp "$STUB/gum" "$REPO/installer/standalone/gum"
    chmod +x "$REPO/installer/standalone/gum"

    # Fake app venvs (python3 is stubbed, so `python3 -m venv` is a no-op).
    for venv in "$H/.local/share/Matuwall/.venv" "$H/.local/share/hyprtk-bar/venv"; do
        printf 'home = /usr/bin\ninclude-system-site-packages = true\nversion = 3.14\n' > "$venv/pyvenv.cfg"
        for p in pip pip3 python python3; do
            printf '#!/bin/sh\nexit 0\n' > "$venv/bin/$p"; chmod +x "$venv/bin/$p"
        done
        printf '#!/bin/sh\n# no-op activate\n' > "$venv/bin/activate"
    done

    RUNLOG="$SB/run.log"
    # graphics-card reads 2 (AMD); fonts/wallpapers read n (skip clone); slack.
    printf '2\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\n' | \
        env HOME="$H" PATH="$STUB:$PATH" TERM=xterm HYPRTK_DRYRUN=1 \
            DRYRUN_DISTRO_NAME="$DRYRUN_NAME" \
            bash "$REPO/1-install.sh" >"$RUNLOG" 2>&1
    RC=$?

    LOG="$REPO/install.log"
    ERRORS=""
    advisory=0
    case "$FAMILY" in emerge | nix) advisory=1 ;; esac
    [ "$RC" -ne 0 ] && ERRORS="exit code $RC"
    if [ -f "$LOG" ]; then
        LERR="$(grep -E 'FATAL:|FAIL:|SPIN FAILED|RUN FAILED' "$LOG" 2>/dev/null)"
        # Gentoo/NixOS never install packages automatically (the installer and
        # the bar print guidance instead), so the bar's dependency step fails
        # there by design; tolerate SPIN/RUN FAILED but keep FATAL/FAIL.
        [ "$advisory" -eq 1 ] && \
            LERR="$(printf '%s\n' "$LERR" | grep -vE 'SPIN FAILED|RUN FAILED' | grep -v '^$')"
        [ -n "$LERR" ] && ERRORS="$ERRORS${ERRORS:+$'\n'}$LERR"
    fi
    if [ -f "$RUNLOG" ]; then
        RERR="$(grep -inE 'error|not found|no such file|traceback|command not found|denied|fatal' "$RUNLOG" 2>/dev/null \
                | grep -viE "Unable to symlink '/usr/bin/python'")"
        [ -n "$RERR" ] && ERRORS="$ERRORS${ERRORS:+$'\n'}[runlog] $RERR"
    fi
    # The visible "INSTALLATION COMPLETE" banner is drawn by the (silent) gum
    # stub; the durable marker is the completion line in install.log.
    grep -q 'hyprtk installation completed' "$LOG" 2>/dev/null || \
        ERRORS="$ERRORS${ERRORS:+$'\n'}completion marker missing from install.log"

    if [ -z "$ERRORS" ]; then
        rm -rf "$SB"
        if [ "$advisory" -eq 1 ]; then
            echo "[OK]   $FAMILY: install completed (advisory — package deps not installable)"
        else
            echo "[OK]   $FAMILY: install completed, exit 0, no errors"
        fi
        exit 0
    fi
    echo "[FAIL] $FAMILY:"
    while IFS= read -r l; do printf '        %s\n' "$l"; done <<< "$ERRORS"
    echo "        --- run.log (tail) ---"
    tail -n 30 "$RUNLOG" 2>/dev/null | while IFS= read -r l; do printf '        %s\n' "$l"; done
    echo "        --- install.log (tail) ---"
    tail -n 15 "$LOG" 2>/dev/null | while IFS= read -r l; do printf '        %s\n' "$l"; done
    rm -rf "$SB"
    exit 1
fi

# ── Host driver ─────────────────────────────────────────────────────────────
while [ "$#" -gt 0 ]; do
    case "$1" in
        --family) SEL_FAMILIES+=("$2"); shift 2 ;;
        --all)    INCLUDE_ADVISORY=1; shift ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "container-dryrun: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# rows: family|variant|image|bootstrap
_rows() {
    printf '%s\n' \
        "pacman|arch|docker.io/library/archlinux:latest|" \
        "apt|bookworm|docker.io/library/debian:bookworm|" \
        "apt|trixie|docker.io/library/debian:trixie|" \
        "apt|noble|docker.io/library/ubuntu:24.04|" \
        "apt|resolute|docker.io/library/ubuntu:26.04|" \
        "dnf|fedora|registry.fedoraproject.org/fedora:latest|" \
        "zypper|suse|registry.opensuse.org/opensuse/tumbleweed:latest|zypper --non-interactive --gpg-auto-import-keys refresh; zypper --non-interactive install -y gawk" \
        "xbps|void|docker.io/voidlinux/voidlinux:latest|printf 'repository=https://repo-default.voidlinux.org/current\\n' >/etc/xbps.d/00-repo.conf; xbps-install -Syu xbps; xbps-install -Sy bash" \
        "apk|alpine|docker.io/library/alpine:latest|apk add --no-cache bash" \
        "emerge|gentoo|docker.io/gentoo/stage3:latest|" \
        "nix|nixos|docker.io/nixos/nix:latest|nix-env -iA nixpkgs.gnused nixpkgs.gawk; printf 'NAME=\"NixOS\"\\nID=nixos\\nPRETTY_NAME=\"NixOS\"\\n' > /etc/os-release"
}

families=("${INSTALL_FAMILIES[@]}")
[ "$INCLUDE_ADVISORY" -eq 1 ] && families+=("${ADVISORY_FAMILIES[@]}")
[ "${#SEL_FAMILIES[@]}" -gt 0 ] && families=("${SEL_FAMILIES[@]}")

command -v "$PODMAN" >/dev/null 2>&1 || { echo "need podman" >&2; exit 2; }

PASS=0; FAIL=0
while IFS='|' read -r pm variant image boot; do
    sel=0
    for f in "${families[@]}"; do [ "$f" = "$pm" ] && sel=1; done
    [ "$sel" -eq 1 ] || continue

    echo "====================================================================="
    echo "  $pm / $variant  ($image)"
    echo "====================================================================="
    # Group the bootstrap so its output can be silenced without clobbering a
    # `>` redirect inside it (e.g. the nix row writing /etc/os-release).
    script="bash /src/installer/scripts/verify/container-dryrun.sh --inside $pm"
    if [ -n "$boot" ]; then
        inner="{ $boot; } >/dev/null 2>&1; $script"
    else
        inner="$script"
    fi
    out="$(timeout "$DRYRUN_TIMEOUT" "$PODMAN" run --rm -v "$ROOT:/src:ro" "$image" sh -c "$inner" 2>&1)"
    rc=$?
    echo "$out" | sed 's/^/  /'
    if [ "$rc" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi
    echo ""
done < <(_rows)

echo "====================================================================="
echo "  container dry-run: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
