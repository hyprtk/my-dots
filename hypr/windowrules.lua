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

-- hyprtk-bar settings window (floating) — the CSS popup-box already draws the
-- 2px animated border; disable Hyprland's own compositor border so only one
-- border shows (mirrors the layer-shell dialogs which have no compositor border).
hl.window_rule({
    name = "windowrule-bar-settings",
    match = {
        title = "(^(hyprtk-bar settings)$)",
    },
    float = true,
    center = true,
    size = "620 580",
    border_size = 0,
})

-- hyprtk-bar About window (floating) — themed popup-box border, no compositor border.
hl.window_rule({
    name = "windowrule-bar-about",
    match = {
        title = "(^(hyprtk-bar about)$)",
    },
    float = true,
    center = true,
    size = "360 260",
    border_size = 0,
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

