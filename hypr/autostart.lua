-- ── Autostart ─────────────────────────────────────────
-- by Kori Tk (2026)
-- ─────────────────────────────────────────────────────

local home = os.getenv("HOME")
local hyprtk = home .. "/hyprtk"

hl.on("hyprland.start", function()
    -- Portal environment
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

    -- Core daemons
    hl.exec_cmd("awww-daemon &")
    hl.exec_cmd("dunst")
    hl.exec_cmd("hypridle")

    -- Cursor
    hl.exec_cmd("hyprctl setcursor Adwaita 24")

    -- Clipboard
    hl.exec_cmd("wl-paste --watch cliphist store")

    -- System tray applets
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")

    -- Restore pywal theme
    hl.exec_cmd("wal -R -q")

    -- Wallpaper manager (matuwall)
    hl.exec_cmd("bash -c \"sleep 3 && cd ~/.local/share/Matuwall && source .venv/bin/activate && LD_PRELOAD=/usr/lib/libgtk4-layer-shell.so matuwall\"")

    -- Volume overlay (wob)
    hl.exec_cmd("bash -c 'rm -f /tmp/wobpipe && mkfifo /tmp/wobpipe && tail -f /tmp/wobpipe | wob -c ~/.config/wob/wob.ini &'")

    -- Wallpaper + pywal color distribution
    hl.exec_cmd(hyprtk .. "/hypr/scripts/wallpaper-restore.sh")
    hl.exec_cmd("bash -c 'sleep 2 && " .. hyprtk .. "/hypr/scripts/wal-watcher.sh &'")

    -- GTK theme
    hl.exec_cmd(hyprtk .. "/configs/gtk/gtk.sh")

    -- Xresources for legacy apps
    hl.exec_cmd("cat ~/.cache/wal/colors.Xresources > ~/.Xresources")

    -- System cleanup
    hl.exec_cmd(hyprtk .. "/installer/scripts/reset-sudo-attempts.sh")
    hl.exec_cmd(hyprtk .. "/installer/scripts/bash-cleanup.sh")
    hl.exec_cmd(hyprtk .. "/installer/scripts/set-timezone.sh")

    -- Polkit agent
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Dismiss startup notifications
    hl.exec_cmd("hyprctl dismissnotify")
end)
