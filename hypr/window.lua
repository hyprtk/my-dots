-- ── Window Rules (colors from pywal) ──────────────────
-- by Kori Tk (2026)
-- Reads colors from ~/.cache/wal/colors-hyprland.lua
-- ─────────────────────────────────────────────────────

local function load_colors_from_file(filename)
    local colors = {}
    local file, err = io.open(filename, "r")
    if not file then
        return nil, "Could not open " .. filename .. ": " .. (err or "unknown error")
    end

    for line in file:lines() do
        local name, value = line:match('^%s*local%s+(%w+)%s*=%s*"rgb%((%x+)%)"%s*$')
        if name and value then
            colors[name] = "rgb(" .. value .. ")"
        end
    end
    file:close()
    return colors
end

local home = os.getenv("HOME")
if not home then
    error("HOME environment variable not set")
end

local colors_path = home .. "/.cache/wal/colors-hyprland.lua"
local colors, err = load_colors_from_file(colors_path)
if not colors then
    -- Fallback to sensible defaults if pywal colors not available
    colors = {
        color11 = "rgb(c2c4c7)",
        color4 = "rgb(136,192,208)",
        color7 = "rgb(a5adc8)",
        color1 = "rgb(243,139,168)",
    }
end

local active_color1 = colors.color11 or "rgb(c2c4c7)"
local active_color2 = colors.color4 or "rgb(136,192,208)"
local inactive_color1 = colors.color7 or "rgb(a5adc8)"
local inactive_color2 = colors.color1 or "rgb(243,139,168)"

hl.config({
    general = {
        gaps_in  = 3,
        gaps_out = 3,
        border_size = 2,
        col = {
            active_border   = {
                colors = { active_color1, active_color2 },
                angle  = 45
            },
            inactive_border = {
                colors = { inactive_color1, inactive_color2 },
                angle  = 45
            },
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    }
})
