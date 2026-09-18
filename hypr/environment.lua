-- ----------------------------------------------------- 
-- Environment Variables
-- ----------------------------------------------------- 

hl.env("WLR_NO_HARDWARE_CURSORS", "1")
hl.env("WLR_RENDERER_ALLOW_SOFTWARE", "1")
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")
hl.env("GTK_THEME", "Kripton-v40:dark")
hl.env("XDG_SESSION_TYPE", "wayland")
-- Preferred terminal for the session: hyprtk-bar's quick links (and other tools
-- that honour $TERMINAL) resolve this to the suite's terminal rather than the
-- distro default.
hl.env("TERMINAL", "alacritty")

