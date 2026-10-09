-- ----------------------------------------------------- 
-- Window rules
-- ----------------------------------------------------- 

hl.window_rule({
    name = "windowrule-1",
    match = {
        title = "(^(Microsoft-edge)$)",
    },
    float = false,
})

hl.window_rule({
    name = "windowrule-2",
    match = {
        title = "^(Brave-browser)$",
    },
    float = false,
    size = "600 400",
})

hl.window_rule({
    name = "windowrule-3",
    match = {
        title = "^(Chromium)$",
    },
    float = false,
})

hl.window_rule({
    name = "windowrule-4",
    match = {
        title = "^(pavucontrol)$",
    },
    float = false,
})

hl.window_rule({
    name = "windowrule-5",
    match = {
        title = "^(blueman-manager)$",
    },
    float = false,
})

-- Specific to launching floating terminal windows
hl.window_rule({
    name = "windowrule-6",
    match = {
        class = "floating",
    },
    float = true,
    size = "800 600",
})

-- Updates module: installupdates.sh relaunches itself in a terminal tagged
-- app-id/class "hyprtk-updates" (title "Hyprtk Updates") — float it instead of
-- tiling it full-screen. Two rules: class for Wayland-native app-ids, title for
-- terminals that only set the window title.
hl.window_rule({
    name = "windowrule-updates",
    match = {
        class = "hyprtk-updates",
    },
    float = true,
    center = true,
    size = "1000 650",
})

hl.window_rule({
    name = "windowrule-updates-title",
    match = {
        title = "^(Hyprtk Updates)$",
    },
    float = true,
    center = true,
    size = "1000 650",
})

