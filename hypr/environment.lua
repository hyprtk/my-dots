-- ── Environment ───────────────────────────────────────
-- by Kori Tk (2026)
-- ─────────────────────────────────────────────────────

-- Wayland environment
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XCURSOR_SIZE", "24")

-- GTK theme
hl.env("GTK_THEME", "Kripton-v40:dark")

-- Qt Wayland support
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")

-- Electron/Chromium Wayland
hl.env("OZONE_PLATFORM", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Mozilla Wayland
hl.env("MOZ_ENABLE_WAYLAND", "1")
