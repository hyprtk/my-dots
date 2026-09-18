#!/bin/bash
# ── sddmgrub ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

echo ""
echo " Configure sddm theme "
echo ""
if [ ! -d /etc/sddm.conf.d/ ]; then
    hyprtk_run_root mkdir -p /etc/sddm.conf.d
    echo "Folder /etc/sddm.conf.d created."
fi
echo ""
hyprtk_run_root cp "$_PKGDIR/../../configs/sddm/sddm.conf" /etc/sddm.conf.d/
echo "File /etc/sddm.conf.d/sddm.conf updated."
echo ""
cp "$_PKGDIR/../../default.png" ~/.cache/current-wallpaper.png
echo ""
# Sugar-Candy is AUR-only (sddm-theme-sugar-candy-git); non-Arch installs have
# no theme for sddm.conf's Current=Sugar-Candy. SDDM falls back to its embedded
# theme, so this is cosmetic — try upstream once, non-fatal.
SUGAR_THEME=/usr/share/sddm/themes/Sugar-Candy
if [ ! -d "$SUGAR_THEME" ] && command -v git >/dev/null 2>&1; then
    _tmp="$(mktemp -d)"
    if git clone --depth=1 https://framagit.org/MarianArlt/sddm-sugar-candy "$_tmp/Sugar-Candy" >/dev/null 2>&1; then
        hyprtk_run_root mkdir -p /usr/share/sddm/themes
        hyprtk_run_root cp -r "$_tmp/Sugar-Candy" "$SUGAR_THEME"
        echo "Installed the Sugar-Candy SDDM theme from upstream"
    fi
    rm -rf "$_tmp"
fi
if [ -d "$SUGAR_THEME" ]; then
    hyprtk_run_root cp ~/.cache/current-wallpaper.png "$SUGAR_THEME/Backgrounds/" 2>/dev/null || true
    hyprtk_run_root cp "$_PKGDIR/../../configs/sddm/theme.conf" "$SUGAR_THEME/" 2>/dev/null || true
    echo "Sugar-Candy theme assets updated."
else
    echo "Sugar-Candy theme not installed — SDDM will use its built-in theme."
fi
echo ""

# ── Cross-distro SDDM greeter fixes ────────────────────────────────────────
# SDDM 0.21 builds against Qt6, and its Wayland greeter is fragile on several
# distros (on a fresh Fedora the greeter session opens and closes instantly
# with no visible error). The X11 greeter is reliable wherever the X server is
# present, so keep Wayland on Arch (the known-good AUR theme + weston path) and
# use X11 everywhere else.
declare -A SDDM_QT6_COMPAT SDDM_XSERVER
SDDM_QT6_COMPAT[apt]="qml6-module-qt5compat-graphicaleffects qml6-module-qtquick-virtualkeyboard"
SDDM_QT6_COMPAT[dnf]="qt6-qt5compat qt6-qtvirtualkeyboard"
SDDM_QT6_COMPAT[zypper]="qt6-qt5compat-imports qt6-qtvirtualkeyboard-imports"
SDDM_QT6_COMPAT[xbps]="qt6-qt5compat qt6-virtualkeyboard"
SDDM_QT6_COMPAT[apk]="qt6-qt5compat qt6-qtvirtualkeyboard"
# X server + the input driver the greeter needs. Without an X input driver
# (e.g. Alpine ships xorg-server but no xf86-input-libinput), Xorg ignores every
# keyboard/pointer — "No input driver specified" — and the greeter cannot be
# typed into at all.
SDDM_XSERVER[apt]="xserver-xorg xserver-xorg-input-libinput"
SDDM_XSERVER[dnf]="xorg-x11-server-Xorg xorg-x11-drv-libinput"
SDDM_XSERVER[zypper]="xorg-x11-server xf86-input-libinput"
SDDM_XSERVER[xbps]="xorg-server xf86-input-libinput"
SDDM_XSERVER[apk]="xorg-server xf86-input-libinput"

_sddm_uses_qt6() {
    command -v sddm >/dev/null 2>&1 || return 1
    ldd "$(command -v sddm)" 2>/dev/null | grep -q 'libQt6'
}

if [ "$HYPRTK_PM" != pacman ]; then
    [ -n "${SDDM_XSERVER[$HYPRTK_PM]:-}" ] && pkg_install ${SDDM_XSERVER[$HYPRTK_PM]} || true
    hyprtk_run_root mkdir -p /etc/sddm.conf.d
    # zz- so it overrides the copied sddm.conf (shared with the Arch look).
    printf '[General]\nDisplayServer=x11\n' \
        | hyprtk_run_root tee /etc/sddm.conf.d/zz-hyprtk-display.conf >/dev/null
    echo "SDDM greeter set to X11 (off-Arch)."

    # Sugar-Candy is written for Qt5; under a Qt6 SDDM its Qt5-only imports
    # stop the theme loading. Install the Qt5-compat QML modules and rewrite
    # the imports to their Qt6 equivalents (idempotent).
    if [ -d "$SUGAR_THEME" ] && _sddm_uses_qt6; then
        [ -n "${SDDM_QT6_COMPAT[$HYPRTK_PM]:-}" ] && pkg_install ${SDDM_QT6_COMPAT[$HYPRTK_PM]} || true
        hyprtk_run_root find "$SUGAR_THEME" -name '*.qml' -exec \
            sed -i -e 's/import QtGraphicalEffects 1\.0/import Qt5Compat.GraphicalEffects/' \
                   -e 's/import QtQuick\.VirtualKeyboard [0-9.]*/import QtQuick.VirtualKeyboard/' {} +
        # SDDM 0.21 runs the Qt6 greeter (sddm-greeter-qt6). The upstream theme
        # metadata carries no QtVersion, so SDDM looks for the Qt5 greeter
        # (/usr/bin/sddm-greeter), does not find it, and silently falls back to
        # its built-in theme. Declare QtVersion=6 so Sugar-Candy is used.
        if [ -f "$SUGAR_THEME/metadata.desktop" ] \
            && ! grep -q '^QtVersion=' "$SUGAR_THEME/metadata.desktop" 2>/dev/null; then
            printf 'QtVersion=6\n' | hyprtk_run_root tee -a "$SUGAR_THEME/metadata.desktop" >/dev/null
        fi
        # Greeter fixes for the user field (Components/Input.qml):
        #  1. the user-icon Button has no background override, so Qt6's default
        #     style paints a black square behind the icon → give it a transparent
        #     background;
        #  2. the login handler reads the username TextField, whose ForceLastUser
        #     binding is empty at click time under Qt6 (login then authenticates
        #     with an empty username and always fails) → fall back to the user
        #     selector's current text.
        _sddm_input_qml="$SUGAR_THEME/Components/Input.qml"
        if [ -f "$_sddm_input_qml" ]; then
            if ! grep -q 'hyprtk: transparent user-icon background' "$_sddm_input_qml"; then
                hyprtk_run_root sed -i \
                    's#\(icon.source: Qt.resolvedUrl("../Assets/User.svgz")\)#\1; background: Rectangle { color: "transparent" } // hyprtk: transparent user-icon background#' \
                    "$_sddm_input_qml"
            fi
            if ! grep -q 'hyprtk: robust login' "$_sddm_input_qml"; then
                hyprtk_run_root sed -i \
                    's#onClicked:.*#onClicked: { var u = (username.text !== "" ? username.text : selectUser.currentText); if (config.AllowBadUsernames == "false") u = u.toLowerCase(); sddm.login(u, password.text, sessionSelect.selectedSession); } // hyprtk: robust login#' \
                    "$_sddm_input_qml"
            fi
            echo "Sugar-Candy user field patched (icon background + robust login)."
        fi
        echo "Sugar-Candy theme patched for Qt6."
    fi
fi

# ── D-Bus session bus for the compositor session ───────────────────────────
# systemd distros get a per-session D-Bus bus from pam_systemd. Non-systemd
# ones (Void/runit, Alpine/OpenRC) start none at all, which breaks
# GSettings/dconf (e.g. hyprcursor's cursor-theme lookup — a compositor
# deadlock), xdg-desktop-portal and the notification daemon. Route the session
# through a wrapper that starts `dbus-run-session` only when there is no bus
# (a no-op on systemd, where DBUS_SESSION_BUS_ADDRESS is already set).
#
# Gated to the non-systemd families on purpose: on Arch/Fedora/Debian/openSUSE
# the session file is package-owned and needs no change, so leave it untouched.
case "$HYPRTK_PM" in
apk|xbps)
    _sess_wrapper="$_PKGDIR/../../installer/scripts/hyprtk-session.sh"
    if [ -f "$_sess_wrapper" ]; then
        hyprtk_run_root install -Dm755 "$_sess_wrapper" /usr/local/bin/hyprtk-session
        for _sess in /usr/share/wayland-sessions/hyprland.desktop \
                     /usr/local/share/wayland-sessions/hyprland.desktop; do
            [ -f "$_sess" ] || continue
            _exec="$(sed -n 's/^Exec=//p' "$_sess" | head -1)"
            [ -n "$_exec" ] || continue
            case "$_exec" in */hyprtk-session\ *) continue ;; esac
            hyprtk_run_root sed -i "s|^Exec=.*|Exec=/usr/local/bin/hyprtk-session $_exec|" "$_sess"
            echo "D-Bus session launcher: $_sess"
        done
    fi
    ;;
esac
echo ""
hyprtk_run_root cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png 2>/dev/null || true
echo ""
echo " Configure grub theme "
echo ""
# Only touch GRUB when this machine actually boots GRUB; never wipe
# /usr/share/grub/themes (dropping GRUB_THEME makes GRUB_BACKGROUND apply).
if command -v grub-mkconfig >/dev/null 2>&1 && [ -f /boot/grub/grub.cfg ]; then
    echo " Enable OS-Prober "
    hyprtk_run_root sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    echo ""
    hyprtk_run_root sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
    hyprtk_run_root sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub
    hyprtk_run_root sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub
    hyprtk_run_root sed -i '/^GRUB_THEME=/d' /etc/default/grub
    echo ""
    echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"' | hyprtk_run_root tee -a /etc/default/grub >/dev/null
    echo -e 'GRUB_COLOR_NORMAL="white/black"' | hyprtk_run_root tee -a /etc/default/grub >/dev/null
    echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' | hyprtk_run_root tee -a /etc/default/grub >/dev/null
    echo ""
    hyprtk_run_root grub-mkconfig -o /boot/grub/grub.cfg
    echo ""
    echo " Disable OS-Prober "
    hyprtk_run_root sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    echo ""
    echo " GRUB & SDDM Updated with current wallpaper "
else
    echo " GRUB not detected (no grub-mkconfig / boot/grub/grub.cfg) - skipping GRUB steps "
fi
