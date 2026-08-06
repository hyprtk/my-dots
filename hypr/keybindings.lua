-- ── Keybindings ───────────────────────────────────────
-- by Kori Tk (2026)
-- ─────────────────────────────────────────────────────

local mainMod = "SUPER"
local home = os.getenv("HOME")
local hyprtk = home .. "/hyprtk"

-- -----------------------------------------------------
-- Core
-- -----------------------------------------------------
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd("alacritty"))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("thunar"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("brave"))
hl.bind(mainMod .. " + CTRL + B", hl.dsp.exec_cmd("chromium"))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"), { description = "Toggle split" })
hl.bind(mainMod .. " + K", hl.dsp.layout("swapsplit"), { description = "Swapsplit" })
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(hyprtk .. "/installer/scripts/appsmenu.sh"))
hl.bind(mainMod .. " + X", hl.dsp.exit())
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("hyprctl reload"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("hyprpicker"))

-- -----------------------------------------------------
-- Directional focus
-- -----------------------------------------------------
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- -----------------------------------------------------
-- Window management
-- -----------------------------------------------------
hl.bind(mainMod .. " + V", function()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    hl.dispatch(hl.dsp.window.resize({ x = 1024, y = 768 }))
    hl.dispatch(hl.dsp.window.center())
end)

hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))

-- -----------------------------------------------------
-- Workspaces
-- -----------------------------------------------------
for i = 1, 5 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- -----------------------------------------------------
-- Mouse
-- -----------------------------------------------------
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize())

-- -----------------------------------------------------
-- Applications
-- -----------------------------------------------------
hl.bind(mainMod .. " + CTRL + Q", hl.dsp.exec_cmd(hyprtk .. "/configs/hyprlogout/logout.sh"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(hyprtk .. "/installer/scripts/updatewal-awww.sh"))
hl.bind(mainMod .. " + CTRL + W", hl.dsp.exec_cmd(hyprtk .. "/installer/scripts/wallpaper-awww.sh"))
hl.bind(mainMod .. " + CTRL + RETURN", hl.dsp.exec_cmd(hyprtk .. "/installer/scripts/appsmenu.sh"))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd(hyprtk .. "/configs/waybar/launch.sh"))
hl.bind(mainMod .. " + CTRL + F", hl.dsp.exec_cmd(hyprtk .. "/installer/scripts/filemanager.sh"))
hl.bind(mainMod .. " + CTRL + C", hl.dsp.exec_cmd(hyprtk .. "/installer/scripts/cliphist.sh"))
hl.bind(mainMod .. " + CTRL + T", hl.dsp.exec_cmd(hyprtk .. "/configs/waybar/themeswitcher.sh"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("bash " .. hyprtk .. "/hypr/scripts/matuwall-toggle.sh"))

-- -----------------------------------------------------
-- Screenshots
-- -----------------------------------------------------
hl.bind(mainMod .. " + PRINT", hl.dsp.exec_cmd(hyprtk .. "/installer/scripts/ssdetect.sh"))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd(hyprtk .. "/installer/scripts/ssdetect.sh"))

-- -----------------------------------------------------
-- Screen recording
-- -----------------------------------------------------
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd("~/.config/hypr/scripts/wf-record-start.sh"))
hl.bind(mainMod .. " + ALT + Print", hl.dsp.exec_cmd("~/.config/hypr/scripts/wf-record-stop.sh"))
hl.bind(mainMod .. " + SHIFT + p", hl.dsp.exec_cmd("~/.config/hypr/scripts/wf-record-start.sh"))
hl.bind(mainMod .. " + ALT + p", hl.dsp.exec_cmd("~/.config/hypr/scripts/wf-record-stop.sh"))

-- -----------------------------------------------------
-- Passthrough (for VMs)
-- -----------------------------------------------------
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.submap("passthru"))
hl.define_submap("passthru", function()
    hl.bind("SUPER + Escape", hl.dsp.submap("reset"))
end)

-- -----------------------------------------------------
-- Hardware keys
-- -----------------------------------------------------
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set 5%+"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { repeating = true })

-- -----------------------------------------------------
-- Utilities
-- -----------------------------------------------------
hl.bind(mainMod .. " + CTRL + U", hl.dsp.exec_cmd("pavucontrol"))
hl.bind(mainMod .. " + CTRL + P", hl.dsp.exec_cmd("pacseek"))
