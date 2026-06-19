-- window.lua
-- Reads colors from ~/.cache/wal/colors-hyprland.lua and applies them to Hyprland's border settings.
-- No fallback values are provided; missing variables will cause errors.

local function load_colors_from_file(filename)
    local colors = {}
    local file, err = io.open(filename, "r")
    if not file then
        error("Could not open " .. filename .. ": " .. err)
    end

    for line in file:lines() do
        -- Match lines like:  local color0 = "rgb(212c4f)"
        local name, value = line:match('^%s*local%s+(%w+)%s*=%s*"rgb%((%x+)%)"%s*$')
        if name and value then
            colors[name] = "rgb(" .. value .. ")"
        end
    end
    file:close()
    return colors
end

-- Build the full path to the colors file
local home = os.getenv("HOME")
local colors_path = home and home .. "/.cache/wal/colors-hyprland.lua"
if not colors_path then
    error("HOME environment variable not set")
end

-- Load the colors (will error if file is missing or unreadable)
local colors = load_colors_from_file(colors_path)

-- Choose which color variables to use for borders.
-- These names must exist in the colors file; no fallback is provided.
local active_color1 = colors.color11
local active_color2 = colors.color4
local inactive_color = colors.color8

hl.config({
    general = {
        gaps_in  = 3,
        gaps_out = 10,
        border_size = 3,
        col = {
            active_border   = {
                colors = { active_color1, active_color2 },
                angle  = 45
            },
            inactive_border = inactive_color,
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    }
})