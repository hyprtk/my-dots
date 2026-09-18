#!/bin/bash
# hyprtk-pkglist
# ── system ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

case "$HYPRTK_PM" in
pacman)
    PKGS=(sddm blueman pacman-contrib fzf font-manager awesome-terminal-fonts
          otf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd eza
          python-pip python-psutil python-rich python-click xdg-desktop-portal-gtk
          xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring pcp
          pcp-gui gtk4-layer-shell hyprpicker)
    AUR=(bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek
         pamac-all libpamac-full pamac-cli tumbler-extra-thumbnailers)
    ;;
apt)
    PKGS=(sddm blueman fzf font-manager fonts-font-awesome fonts-firacode eza
          python3-pip python3-psutil python3-rich python3-click python3-venv
          xdg-desktop-portal-gtk xdg-user-dirs xdg-user-dirs-gtk os-prober
          policykit-1-gnome gnome-keyring libgtk4-layer-shell0 hyprpicker)
    ;;
dnf)
    # polkit-gnome is not packaged on Fedora; mate-polkit provides the agent.
    PKGS=(sddm blueman fzf font-manager fontawesome-fonts-all fira-code-fonts eza
          python3-pip python3-psutil python3-rich python3-click xdg-desktop-portal-gtk
          xdg-user-dirs xdg-user-dirs-gtk os-prober mate-polkit gnome-keyring
          gtk4-layer-shell hyprpicker)
    ;;
zypper)
    PKGS=(sddm blueman fzf font-manager fontawesome-fonts fira-code-fonts eza
          python3-pip python3-psutil python3-rich python3-click xdg-desktop-portal-gtk
          xdg-user-dirs           xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring
          libgtk4-layer-shell0 hyprpicker)
    ;;
xbps)
    PKGS=(sddm blueman fzf fontmanager font-awesome font-firacode eza python3-pip
          python3-psutil python3-rich python3-click xdg-desktop-portal-gtk
          xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring
          gtk4-layer-shell hyprpicker)
    ;;
apk)
    PKGS=(sddm blueman fzf font-manager font-awesome font-fira-code-nerd eza py3-pip
          py3-psutil py3-rich py3-click xdg-desktop-portal-gtk xdg-user-dirs
          xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring gtk4-layer-shell
          hyprpicker eudev eudev-openrc)
    ;;
esac

# Debian 13 dropped policykit-1-gnome; mate-polkit provides the agent there.
# (The session wrapper hypr/scripts/polkit-agent.sh finds whichever is present.)
if [ "$HYPRTK_PM" = apt ] && command -v apt-get >/dev/null 2>&1 \
    && ! apt-get install -s -y policykit-1-gnome >/dev/null 2>&1; then
    PKGS=("${PKGS[@]/policykit-1-gnome/mate-polkit}")
fi

if [ "${1:-}" = "--list" ]; then printf '%s ' "${PKGS[@]}" "${AUR[@]}"; echo; exit 0; fi

echo ""
echo " System Packages "
echo ""
pkg_install "${PKGS[@]}"
aur_install "${AUR[@]}"
echo ""

# Performance Co-Pilot PMDA modules are Arch-only.
if [ "$HYPRTK_PM" = pacman ]; then
    # shellcheck disable=SC2046
    pkg_install $(pacman -Ssq 'pcp-pmda-*' 2>/dev/null) || true
fi

# papirus-folders CLI — bundled with the dotfiles; fall back to the upstream
# installer fetched to a temp file (never a blind pipe-to-shell) off-tree.
if [ ! -x "$_PKGDIR/../../installer/standalone/papirus-folders" ]; then
    tmp="$(mktemp)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 60 https://git.io/papirus-folders-install -o "$tmp" 2>/dev/null || true
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp" --timeout=60 https://git.io/papirus-folders-install 2>/dev/null || true
    fi
    [ -s "$tmp" ] && env PREFIX="$HOME/.local" bash "$tmp" || \
        echo "  ! papirus-folders install skipped (no network / fetch failed)" >&2
    rm -f -- "$tmp"
fi
echo ""

# ── Alpine: device manager, OpenRC services, XDG_RUNTIME_DIR ───────────────
# Alpine defaults to busybox mdev, which never applies the elogind udev rules,
# so the DRM device is not tagged `master-of-seat`; elogind then reports
# CanGraphical=no and SDDM never starts a greeter (the seat has no graphics).
# eudev (via its udev/udev-trigger/udev-settle services) tags the DRM card and
# makes the graphical seat work. Enabled on next boot. Also enable the OpenRC
# services the desktop needs (dbus, elogind, sddm) — Alpine enables none of
# them for us. And provide an XDG_RUNTIME_DIR fallback for logins that do not
# go through PAM/elogind (busybox login is not PAM-aware, so a plain tty login
# gets no runtime dir, and Hyprland refuses to start without one).
if [ "$HYPRTK_PM" = apk ]; then
    if command -v rc-update >/dev/null 2>&1; then
        hyprtk_run_root rc-update del mdev sysinit 2>/dev/null || true
        for _svc_ru in "udev sysinit" "udev-trigger sysinit" "udev-settle sysinit"; do
            # shellcheck disable=SC2086
            hyprtk_run_root rc-update add $_svc_ru 2>/dev/null || true
        done
        hyprtk_run_root rc-update add udev-postmount default 2>/dev/null || true
        hyprtk_run_root rc-update add dbus default 2>/dev/null || true
        hyprtk_run_root rc-update add elogind default 2>/dev/null || true
        hyprtk_run_root rc-update add sddm default 2>/dev/null || true
        echo "  ! eudev + dbus/elogind/sddm enabled — reboot so the graphical seat works"
    fi
fi

# ── Void: runit services ────────────────────────────────────────────────────
# Void ships service directories under /etc/sv but enables nothing, so dbus,
# elogind, polkit and SDDM never start — there is no seat and no greeter on the
# next boot. On runit, "enabling" is a symlink into the runsvdir.
if [ "$HYPRTK_PM" = xbps ]; then
    if command -v sv >/dev/null 2>&1; then
        _svdir="/var/service"
        [ -d "$_svdir" ] || _svdir="/etc/runit/runsvdir/default"
        for _svc_x in udevd dbus elogind polkitd sddm; do
            [ -d "/etc/sv/$_svc_x" ] && \
                hyprtk_run_root ln -sfn "/etc/sv/$_svc_x" "$_svdir/$_svc_x"
        done
        echo "  ! udev/dbus/elogind/polkitd/sddm enabled (runit) — reboot so the graphical seat works"
    fi
fi

# ── XDG_RUNTIME_DIR fallback (non-systemd) ──────────────────────────────────
# For logins that bypass PAM/elogind (a plain busybox tty login on OpenRC, or a
# runit agetty), no runtime dir is created and Hyprland refuses to start without
# one. Prefer the elogind-managed dir, else a private per-user directory.
if [ "$HYPRTK_PM" = apk ] || [ "$HYPRTK_PM" = xbps ]; then
    _xdg_pd="/etc/profile.d/99-xdg-runtime-dir.sh"
    _xdg_tmp="$(mktemp)"
    cat > "$_xdg_tmp" <<'XDGEOF'
# hyprtk: ensure XDG_RUNTIME_DIR for logins that bypass PAM/elogind (OpenRC
# busybox login, runit agetty). Prefer the elogind-managed dir, else a private
# per-user directory.
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    if [ -d "/run/user/$(id -u)" ]; then
        XDG_RUNTIME_DIR="/run/user/$(id -u)"
    else
        XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/xdg-runtime-$(id -u)"
        [ -d "$XDG_RUNTIME_DIR" ] || mkdir -m 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
    fi
    [ -d "$XDG_RUNTIME_DIR" ] && export XDG_RUNTIME_DIR
fi
XDGEOF
    hyprtk_run_root mkdir -p /etc/profile.d
    hyprtk_run_root cp "$_xdg_tmp" "$_xdg_pd"
    hyprtk_run_root chmod 0644 "$_xdg_pd"
    rm -f "$_xdg_tmp"
fi
echo ""
