-- ----------------------------------------------------- 
--
-- ██   ██                  ██      ██               ██ ██
--░██  ██           ██   ██░██     ░░               ░██░░            █████
--░██ ██    █████  ░░██ ██ ░██      ██ ███████      ░██ ██ ███████  ██░░░██  ██████
--░████    ██░░░██  ░░███  ░██████ ░██░░██░░░██  ██████░██░░██░░░██░██  ░██ ██░░░░
--░██░██  ░███████   ░██   ░██░░░██░██ ░██  ░██ ██░░░██░██ ░██  ░██░░██████░░█████
--░██░░██ ░██░░░░    ██    ░██  ░██░██ ░██  ░██░██  ░██░██ ░██  ░██ ░░░░░██ ░░░░░██
--░██ ░░██░░██████  ██     ░██████ ░██ ███  ░██░░██████░██ ███  ░██  █████  ██████
--░░   ░░  ░░░░░░  ░░      ░░░░░   ░░ ░░░   ░░  ░░░░░░ ░░ ░░░   ░░  ░░░░░  ░░░░░░
--
-- by hyprtk (Kori Tk) (2026)
-- ----------------------------------------------------- 

local mainMod = "SUPER"

hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd("alacritty"))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("thunar"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("brave"))
hl.bind(mainMod .. " + CTRL + B", hl.dsp.exec_cmd("chromium"))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"), { description = "Toggle split" })
hl.bind(mainMod .. " + K", hl.dsp.layout("swapsplit"), { description = "Swapsplit" })
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("~/hyprtk/scripts/appsmenu.sh"))
hl.bind(mainMod .. " + X", hl.dsp.exit())
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("hyprctl reload"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("bash ~/hyprtk/hypr/scripts/matuwall-toggle.sh"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("hyprpicker"))

--##            added script to reset hyprland with hyprctl                ###
--##      after taking screenshot where the keybindings stop working       ###

hl.bind(mainMod .. " + PRINT", hl.dsp.exec_cmd("~/hyprtk/scripts/ssdetect.sh"))

-- for users who have mini keyboards with no PrintScr
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("~/hyprtk/scripts/ssdetect.sh"))

--##                                                                       ###

--##                Created new keybind for window toggle                  ###
--##                                                                       ###
--##hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" })) ###

hl.bind(mainMod .. " + V", function()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    -- Resize to your preferred dimensions in pixels
    hl.dispatch(hl.dsp.window.resize({ x = 1024, y = 768 }))
    -- Optional: Center the newly sized floating window
    hl.dispatch(hl.dsp.window.center())
end)
--##                                                                       ###

hl.bind(mainMod .. " + CTRL + Q", hl.dsp.exec_cmd("~/hyprtk/hyprlogout/logout.sh"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("~/hyprtk/scripts/updatewal-awww.sh"))
hl.bind(mainMod .. " + CTRL + W", hl.dsp.exec_cmd("~/hyprtk/scripts/wallpaper-awww.sh"))
hl.bind(mainMod .. " + CTRL + RETURN", hl.dsp.exec_cmd("~/hyprtk/scripts/applauncher.sh"))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("~/hyprtk/waybar/launch.sh"))
hl.bind(mainMod .. " + CTRL + F", hl.dsp.exec_cmd("~/hyprtk/scripts/filemanager.sh"))
hl.bind(mainMod .. " + CTRL + C", hl.dsp.exec_cmd("~/hyprtk/scripts/cliphist.sh"))
hl.bind(mainMod .. " + CTRL + T", hl.dsp.exec_cmd("~/hyprtk/waybar/themeswitcher.sh"))
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd("~/.config/hypr/scripts/wf-record-start.sh"))
hl.bind(mainMod .. " + ALT + Print", hl.dsp.exec_cmd("~/.config/hypr/scripts/wf-record-stop.sh"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/wf-record-start.sh"))
hl.bind(mainMod .. " + ALT + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/wf-record-stop.sh"))

hl.bind(mainMod .. " + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind(mainMod .. " + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind(mainMod .. " + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind(mainMod .. " + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind(mainMod .. " + 5", hl.dsp.focus({ workspace = 5 }))
hl.bind(mainMod .. " + 6", hl.dsp.focus({ workspace = 6 }))
hl.bind(mainMod .. " + 7", hl.dsp.focus({ workspace = 7 }))
hl.bind(mainMod .. " + 8", hl.dsp.focus({ workspace = 8 }))
hl.bind(mainMod .. " + 9", hl.dsp.focus({ workspace = 9 }))
hl.bind(mainMod .. " + 0", hl.dsp.focus({ workspace = 10 }))

hl.bind(mainMod .. " + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
hl.bind(mainMod .. " + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
hl.bind(mainMod .. " + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
hl.bind(mainMod .. " + SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
hl.bind(mainMod .. " + SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
hl.bind(mainMod .. " + SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
hl.bind(mainMod .. " + SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
hl.bind(mainMod .. " + SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
hl.bind(mainMod .. " + SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize())

hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))

hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set 100%"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 70%"), { repeating = true })

-- ----------------------------------------------------- 
-- Passthrough SUPER KEY to Virtual Machine
-- ----------------------------------------------------- 
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.submap("passthru"))
hl.define_submap("passthru", function()
    hl.bind("SUPER + Escape", hl.dsp.submap("reset"))
end)

-- ----------------------------------------------------- 
-- Application keybinds
-- -----------------------------------------------------

hl.bind(mainMod .. " + CTRL + U", hl.dsp.exec_cmd("pavucontrol"))
hl.bind(mainMod .. " + CTRL + P", hl.dsp.exec_cmd("pamac-manager"))
