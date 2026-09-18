-- ----------------------------------------------------- 
-- Autostart
-- ----------------------------------------------------- 

hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon &")
    -- hyprsunset gamma provides screen brightness on monitors without a backlight
    hl.exec_cmd("hyprsunset --identity &")
    -- hyprtk-bar owns org.freedesktop.Notifications (built-in notification center)
    hl.exec_cmd("~/.local/bin/hyprtk-bar &")
    -- Cursor theme/size come from XCURSOR_THEME/XCURSOR_SIZE (see
    -- environment.lua). Do NOT call `hyprctl setcursor` here: it runs
    -- hyprcursor's GSettings/dconf lookup on the compositor's main thread, which
    -- blocks forever on systems with no D-Bus session bus (e.g. Void/runit) and
    -- leaves the session on a black screen.
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("wal -R -q")
    -- matuwall is a one-shot picker now (C/meson, no venv/GTK/LD_PRELOAD);
    -- it is launched on demand by hypr/scripts/matuwall-toggle.sh (SUPER+W).
    hl.exec_cmd("rm -f /tmp/wobpipe && mkfifo /tmp/wobpipe && tail -f /tmp/wobpipe | wob -c ~/.config/wob/wob.ini &")
    hl.exec_cmd("~/hyprtk/installer/scripts/lockscreentime.sh")
    hl.exec_cmd("~/hyprtk/hypr/scripts/wallpaper-restore.sh")
    hl.exec_cmd("~/hyprtk/hypr/scripts/wal-watcher.sh &")
    hl.exec_cmd("~/hyprtk/configs/gtk/gtk.sh")
    hl.exec_cmd("cat ~/.cache/wal/colors.Xresources > ~/.Xresources")
    hl.exec_cmd("~/hyprtk/installer/scripts/reset-sudo-attempts.sh")
    hl.exec_cmd("~/hyprtk/installer/scripts/bash-cleanup.sh")
    hl.exec_cmd("~/hyprtk/installer/scripts/set-timezone.sh")
    -- Register the session with D-Bus. On systemd `--systemd` also syncs the
    -- user manager; non-systemd (Void/runit) has no user manager, so fall back
    -- to the plain D-Bus activation environment update.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP 2>/dev/null || dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    -- polkit-gnome is absent on Fedora and dropped in Debian 13; the wrapper
    -- starts whichever agent (polkit-gnome / mate-polkit / lxpolkit) is present
    hl.exec_cmd("~/.config/hypr/scripts/polkit-agent.sh &")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("xhost +local:")
    hl.exec_cmd("hyprctl dismissnotify")
end)

