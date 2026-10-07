#!/usr/bin/env bash
# customize_airootfs.sh — runs *inside the build chroot* as root, after all
# packages are installed and just before the squashfs is produced.
#
# Responsibilities:
#   1. install the hyprtk fonts system-wide
#   2. install host-built AUR packages and matuwall
#   3. create the live user (home seeded from /etc/skel, which already contains
#      ~/hyprtk + the ~/.config symlinks for the preconfigured desktop)
#   4. run the one-time user setup (hyprtk-bar + pywal) so the ISO boots ready
#   5. enable the services and default to graphical.target (SDDM autologin)
set -euo pipefail

LIVE_USER="hyprtk"
LIVE_HOME="/home/$LIVE_USER"

log() { printf '[customize_airootfs] %s\n' "$*"; }

# ── 0. Staged overlay files ────────────────────────────────────────────────
# /etc/skel and /usr/lib/os-release cannot live in the airootfs overlay: archiso
# copies airootfs into the new root *before* pacstrap, so any path a package also
# owns (grml-zsh-config's /etc/skel/.zshrc, filesystem's /usr/lib/os-release)
# becomes a file conflict and aborts the install. They are staged under
# /usr/share/hyprtk-iso and installed here, once the packages are in place.
STAGE=/usr/share/hyprtk-iso
if [ -f "$STAGE/skel.tar" ]; then
    mkdir -p /etc/skel
    # -p keeps the exec bits the builder packed; --no-same-owner roots the files.
    tar --no-same-owner -xpf "$STAGE/skel.tar" -C /etc/skel
fi
if [ -f "$STAGE/os-release" ]; then
    cp -f "$STAGE/os-release" /usr/lib/os-release
fi

# mkarchiso copies the profile airootfs with --no-preserve=mode, so the exec
# bits on our overlay scripts are lost; re-assert them here.
chmod 0755 /usr/local/bin/hyprtk-first-run /usr/local/bin/hyprtk-deploy

# ── 1. Fonts ───────────────────────────────────────────────────────────────
if [ -d /etc/skel/hyprtk/assets/fonts ]; then
    mkdir -p /usr/share/fonts/hyprtk
    cp -rf /etc/skel/hyprtk/assets/fonts/. /usr/share/fonts/hyprtk/
fi
command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true

# ── 2a. Host-built AUR packages ────────────────────────────────────────────
# Installed one file at a time: pacman treats `-U a b c` as a single
# transaction, so one package with an unresolvable dependency would abort the
# whole batch. Debug-symbol packages are skipped.
if compgen -G "/var/cache/hyprtk-aur/*.pkg.tar.*" >/dev/null; then
    log "installing AUR packages from /var/cache/hyprtk-aur"
    # pacman's disk-space check cannot resolve "/" inside the archiso chroot and
    # its keyring is not populated, so `pacman -U` aborts with "not enough free
    # disk space" / "required key missing from keyring". Both only bite when a
    # staged package needs dependencies pulled from the repos. Use a throwaway
    # pacman.conf (CheckSpace off, SigLevel Never) for these installs only, so
    # the ISO's /etc/pacman.conf is untouched.
    NOCS_CONF=/tmp/pacman-staged.conf
    sed -e 's/^CheckSpace/#CheckSpace/' \
        -e 's/^SigLevel.*/SigLevel = Never/' \
        -e 's/^\(LocalFileSigLevel\).*/\1 = Optional TrustAll/' \
        /etc/pacman.conf > "$NOCS_CONF"
    for _pkg in /var/cache/hyprtk-aur/*.pkg.tar.*; do
        case "$_pkg" in *-debug-*) continue ;; esac
        pacman -U --config "$NOCS_CONF" --noconfirm "$_pkg" \
            || log "WARN: failed to install $(basename "$_pkg")"
    done
    rm -f "$NOCS_CONF"
fi

# ── 2b. matuwall (built from source on the host) ───────────────────────────
if [ -d /var/cache/hyprtk/matuwall-root ]; then
    log "installing matuwall from staged build"
    cp -rf /var/cache/hyprtk/matuwall-root/. /
    command -v matuwall >/dev/null 2>&1 || ln -sf /usr/bin/matuwall /usr/local/bin/matuwall 2>/dev/null || true
fi

# ── 3. Live user ───────────────────────────────────────────────────────────
if ! id -u "$LIVE_USER" >/dev/null 2>&1; then
    log "creating live user $LIVE_USER (home seeded from /etc/skel)"
    useradd -m -u 1000 -g users \
        -G wheel,video,audio,input,network,storage,rfkill,power \
        -s /bin/zsh "$LIVE_USER"
fi
echo "$LIVE_USER:hyprtk" | chpasswd
# Root password for the live media (console/tty login; SDDM hides uid 0).
echo "root:toor" | chpasswd
chown -R "$LIVE_USER:users" "$LIVE_HOME"

# sudoers drop-in must have the right mode (git does not track 0440).
if [ -f /etc/sudoers.d/10-hyprtk-live ]; then
    chown root:root /etc/sudoers.d/10-hyprtk-live
    chmod 0440 /etc/sudoers.d/10-hyprtk-live
fi

# ── 4. One-time user setup (baked, so the live session is preconfigured) ───
# ImageMagick's policy must allow the TXT coder or pywal silently produces no
# palette. This touches a system file, so run it as root first.
if [ -x /etc/skel/hyprtk/installer/hyprtk-bar/scripts/fix-imagemagick-policy.sh ]; then
    bash /etc/skel/hyprtk/installer/hyprtk-bar/scripts/fix-imagemagick-policy.sh >/dev/null 2>&1 || true
fi

log "running first-login setup for $LIVE_USER (hyprtk-bar + pywal)"
runuser -u "$LIVE_USER" -- env \
    HOME="$LIVE_HOME" USER="$LIVE_USER" LOGNAME="$LIVE_USER" \
    PATH="$LIVE_HOME/.local/bin:/usr/local/bin:/usr/bin" \
    bash -c '
        set -u
        cd "$HOME" || exit 0
        bash "$HOME/hyprtk/installer/hyprtk-bar/install.sh" --no-deps \
            || echo "[customize] WARN: hyprtk-bar install did not finish"
        command -v wal >/dev/null 2>&1 \
            && wal -n -i "$HOME/hyprtk/assets/Wallpapers/default.png" >/dev/null 2>&1 || true
        cp -f "$HOME/hyprtk/assets/Wallpapers/default.png" \
              "$HOME/.cache/current-wallpaper.png" 2>/dev/null || true
        mkdir -p "$HOME/.local/share/hyprtk"
        touch "$HOME/.local/share/hyprtk/.first-run-done"
    ' || log "WARN: live-user setup did not finish cleanly"
chown -R "$LIVE_USER:users" "$LIVE_HOME"

# ── 5. SDDM theme (only when Sugar-Candy made it onto the image) ───────────
if [ -d /usr/share/sddm/themes/Sugar-Candy ]; then
    mkdir -p /usr/share/sddm/themes/Sugar-Candy/Backgrounds
    cp -f "$LIVE_HOME/.cache/current-wallpaper.png" \
          /usr/share/sddm/themes/Sugar-Candy/Backgrounds/current-wallpaper.png 2>/dev/null || true
    cp -f "$LIVE_HOME/hyprtk/configs/sddm/theme.conf" /usr/share/sddm/themes/Sugar-Candy/ 2>/dev/null || true
    printf '[Theme]\nCurrent=Sugar-Candy\n' > /etc/sddm.conf.d/20-hyprtk-theme.conf
    log "Sugar-Candy SDDM theme enabled"
else
    log "Sugar-Candy theme absent — SDDM keeps its default theme"
fi

# ── 6. Services + graphical boot ───────────────────────────────────────────
systemctl enable NetworkManager.service
systemctl enable bluetooth.service 2>/dev/null || true
systemctl enable systemd-timesyncd.service 2>/dev/null || true
systemctl enable sddm.service
systemctl set-default graphical.target

# gum on PATH for hyprtk-deploy (root's PATH does not include ~/.local/bin).
ln -sf /etc/skel/hyprtk/installer/standalone/gum /usr/local/bin/gum

# ── 7. Shrink the image: drop the staged build caches ──────────────────────
rm -rf /var/cache/hyprtk-aur /var/cache/hyprtk "$STAGE"

log "done"
