-- ─────────────────────────────────────────────────────────────────
--   HYPRTK · Hyprland
--   Part of the Hyprtk desktop suite · github.com/hyprtk
-- ─────────────────────────────────────────────────────────────────

-- ----------------------------------------------------- 
-- Autostart & Environment
-- ----------------------------------------------------- 
require("environment")
require("autostart")

-- ----------------------------------------------------- 
-- Load configuration files
-- ----------------------------------------------------- 
require("input")
require("monitors")
require("window")
require("decoration")
require("layouts")
require("misc")
require("keybindings")
require("windowrules")
require("nvidia")

-- ----------------------------------------------------- 
-- Animation
-- ----------------------------------------------------- 
-- require("animations-low")
require("animations-high")