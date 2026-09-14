"""Theming: resolve a palette (pywal + imported theme + config) and emit GTK CSS."""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · theme
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging

from .colors import contrast_fg as _contrast_fg, hover_color, rgba  # noqa: E402
from .config import load_pywal_colors  # noqa: E402
from .theme_import import parse_palette  # noqa: E402

log = logging.getLogger("hyprtk_bar.theme")


# Per-module glyph colors, drawn from the pywal palette so each module icon has
# a distinct colour. Applied for every theme source (pywal, imported theme
# theme, manual) — the glyph accents always follow the wallpaper palette.
MODULE_PYWAL_KEYS = {
    "start_button": "color5",    # mauve
    "quicklinks": "color6",      # sky / cyan
    "workspaces": "color4",      # sapphire / blue
    "tasklist": "color2",        # green
    "window": "color6",          # sky / cyan
    "updates": "color3",         # yellow
    "sysmon": "color2",          # green
    "kbstate": "color4",         # sapphire / blue
    "clock": "color5",           # mauve
    "notifications": "color1",   # red
    "tray": "color2",            # green
    "quicksettings": "color13",  # bright mauve
}

# CSS selectors for each glyph-bearing module's icon. Rules are emitted with
# their module's pywal colour so each icon renders distinct.
MODULE_GLYPH_SELECTORS = {
    "start_button": ".task-button.start .accent-icon",
    "quicklinks": ".quicklink-glyph",
    "sysmon": ".sysmon .accent-icon",
    "updates": ".updates .accent-icon",
    "kbstate": ".kbstate .kbstate-icon",
    "notifications": ".notif-button .accent-icon",
    "quicksettings": ".qs-button .accent-icon",
}


def _module_glyph_colors(pywal: dict) -> dict:
    """Map module id -> distinct glyph hex from the pywal palette.

    Falls back to the bar accent when a colour is missing, so every module still
    gets a colour even with an incomplete palette.
    """
    accent = pywal.get("color5") or pywal.get("color4") or "#7aa2f7"
    return {
        mid: (pywal.get(key) or accent)
        for mid, key in MODULE_PYWAL_KEYS.items()
    }


def resolve_palette(cfg: dict) -> dict:
    """Background/foreground/accent palette from the configured theme source.

    ``theme.source`` selects the source: ``pywal`` (live wallpaper palette),
    ``imported`` (a hyprtk imported theme, dynamic to its pywal import), or
    ``manual`` (colors from the config's ``theme`` block). The configured
    ``font`` block (family + size) is applied on top of every source.
    """
    theme = cfg.get("theme") or {}
    source = theme.get("source", "pywal" if cfg.get("use_pywal", True) else "manual")
    palette = {
        "background": theme.get("background", "#1a1b26"),
        "foreground": theme.get("foreground", "#c0caf5"),
        "accent": theme.get("accent", "#7aa2f7"),
        "hover": theme.get("hover", "rgba(255, 255, 255, 0.08)"),
        "running": theme.get("running", theme.get("accent", "#7aa2f7")),
    }

    if source != "manual":
        if source == "imported":
            imported = import_theme_palette(theme)
            if imported is not None:
                palette = imported

        if "background_alpha" not in palette:
            # pywal (also the fallback when an imported theme fails)
            pywal = load_pywal_colors()
            if pywal:
                palette["background"] = pywal.get("background") or palette["background"]
                palette["foreground"] = pywal.get("foreground") or palette["foreground"]
                palette["accent"] = pywal.get("color5") or pywal.get("color4") or palette["accent"]
                palette["running"] = palette["accent"]
                # 2px bar border drawn in the pywal accent color.
                palette["border_width"] = 2
                palette["border_color"] = palette["accent"]
    else:
        # manual: draw the same 2px border as pywal, coloured from the config
        # (defaults to the accent so the border follows it when unset).
        palette["border_width"] = 2
        palette["border_color"] = theme.get("border_color") or palette["accent"]

    # Per-module glyph colours always come from the pywal palette — every module
    # icon gets a distinct colour, and they re-tint on wallpaper change. This is
    # independent of the theme source (pywal / imported theme / manual).
    pywal = load_pywal_colors()
    if pywal:
        palette["module_colors"] = _module_glyph_colors(pywal)
        palette["red"] = pywal.get("color1") or "#f87171"
        palette["warn"] = pywal.get("color3") or "#facc15"
        palette["green"] = pywal.get("color2") or "#34d399"
        palette["sky"] = pywal.get("color6") or "#22d3ee"
    # These semantic colours are used unconditionally by the CSS (warn/danger
    # levels, drive/iface types), so make sure they exist even without a pywal
    # palette (e.g. a fresh system) and follow the wallpaper palette otherwise.
    palette.setdefault("red", "#f87171")
    palette.setdefault("warn", "#facc15")
    palette.setdefault("high", palette["red"])
    palette.setdefault("green", "#34d399")
    palette.setdefault("sky", "#22d3ee")

    # The configured font (family + size) applies to every theme source.
    font_cfg = cfg.get("font") or {}
    family = (font_cfg.get("family") or "").strip()
    if family:
        palette["font"] = family
    try:
        size = max(8, int(font_cfg.get("size", 16)))
    except (TypeError, ValueError):
        size = 16
    palette["font_size"] = size
    # Chips follow the configured base size too — an imported theme's
    # chip_font_size must not pin them to a stale size when the user changes it.
    palette["chip_font_size"] = size
    # Tasklist indicator dot scales with the icon size (~30% of the icon).
    try:
        icon_sz = max(14, int(font_cfg.get("icon_size") or 0))
    except (TypeError, ValueError):
        icon_sz = 0
    if not icon_sz:
        icon_sz = max(14, int(round(size * 1.25)))
    palette["dot_size"] = max(4, int(round(icon_sz * 0.30)))
    return palette


def import_theme_palette(theme: dict) -> dict | None:
    """Import the configured hyprtk theme into a palette."""
    name = theme.get("theme_name")
    if not name:
        return None
    try:
        palette = parse_palette(name)
    except Exception as exc:  # never let a bad theme take down the bar
        log.warning("failed to import theme %r: %s", name, exc)
        return None
    if palette is not None:
        palette["theme_name"] = name
    return palette


def _padding_css(nums: list) -> str:
    return " ".join(f"{n:g}px" for n in nums)


def _vertical_padding(nums: list) -> float:
    if len(nums) == 1:
        return nums[0] * 2
    if len(nums) == 2:
        return nums[0] * 2
    if len(nums) == 3:
        return nums[0] + nums[2]
    return nums[0] + nums[2]


def gap_value(cfg: dict, key: str, default: int) -> int:
    """Coerce a gap config value to ``int >= 0``; ``default`` for missing/None.

    Unlike ``x or default``, a stored ``0`` is kept (0 is a valid gap).
    """
    value = cfg.get(key)
    if value is None or value == "":
        return default
    try:
        return max(0, int(value))
    except (TypeError, ValueError):
        return default


def pill_margins(cfg: dict) -> tuple[int, int, int, int]:
    """(top, right, bottom, left) CSS margins of the .taskbar pill.

    ``gap_out`` is always the side toward the screen edge and ``gap_in`` the
    side toward app windows, so the vertical margins flip with the bar's
    position. The left/right margins stay a small fixed inset (the pill's
    rounded ends never touch the screen edges).
    """
    gap_in = gap_value(cfg, "gap_in", 6)
    gap_out = gap_value(cfg, "gap_out", 6)
    h = 6
    if cfg.get("position") == "top":
        return gap_out, h, gap_in, h
    return gap_in, h, gap_out, h


def build_css(palette: dict, cfg: dict) -> str:
    top_m, right_m, bottom_m, left_m = pill_margins(cfg)
    radius = palette.get("border_radius", cfg.get("radius", 12))
    height = cfg.get("height", 42)
    # The imported theme's background alpha (if any) maps to the bar opacity;
    # otherwise the configured opacity applies.
    opacity = palette.get("background_alpha", cfg.get("opacity", 0.95))

    bg = rgba(palette["background"], opacity)
    hover = hover_color(palette["hover"])
    accent = palette["accent"]
    running = palette["running"]
    fg = palette["foreground"]
    warn = palette.get("warn", "#facc15")
    danger = palette.get("high", palette.get("red", "#f87171"))
    green = palette.get("green", "#34d399")
    sky = palette.get("sky", "#22d3ee")
    dot_size = palette.get("dot_size", 6)
    font = palette.get("font")
    font_rule = f"  font-family: {font};\n" if font else ""
    font_size = palette.get("font_size")
    font_size_rule = f"  font-size: {font_size:g}px;\n" if font_size else ""
    glyph_font = "Symbols Nerd Font"
    try:
        glyph_font = ((cfg.get("quicklinks") or {}).get("glyph_font") or "").strip() or glyph_font
    except AttributeError:
        pass
    # Quicklink glyph color: a palette key (accent/fg/running) or an explicit
    # color. Defaults to the pywal accent, matching the other icon modules.
    glyph_color = accent
    try:
        gcolor = ((cfg.get("quicklinks") or {}).get("glyph_color") or "").strip()
        if gcolor:
            glyph_color = {
                "accent": accent,
                "fg": fg,
                "foreground": fg,
                "running": running,
            }.get(gcolor, gcolor)
    except AttributeError:
        pass

    border_rule = ""
    extra_v = 0.0
    border_width = palette.get("border_width")
    border_color = palette.get("border_color")
    if border_width and border_color:
        border_rule = f"  border: {border_width:g}px solid {border_color};\n"
        extra_v += 2 * border_width
    # Optional drop shadow / specular highlight carried over from the imported
    # theme's `window#waybar` box-shadow (e.g. a liquid-glass rim + shadow).
    bar_shadow_rule = ""
    bar_shadow = palette.get("bar_shadow")
    if bar_shadow:
        bar_shadow_rule = f"  box-shadow: {' '.join(bar_shadow.split())};\n"
    # Popups (notification center, quick settings, toasts, previews) and the
    # right-click menu use the theme's background/foreground/border. Popups stay
    # mostly opaque for readability but carry the theme's border and color.
    popup_alpha = max(opacity, 0.9)
    popup_border_rule = border_rule if (border_width and border_color) else ""
    menu_border = border_color or rgba(palette["foreground"], 0.18)
    padding_rule = ""
    padding = palette.get("padding")
    if padding:
        padding_rule = f"  padding: {_padding_css(padding)};\n"
        extra_v += _vertical_padding(padding)
    min_height = max(20, int(round(height - extra_v)))

    # ── workspace chips (#workspaces button) ─────────────────────
    chip_padding_rule = ""
    chip_padding = palette.get("chip_padding")
    if chip_padding:
        chip_padding_rule = f"  padding: {_padding_css(chip_padding)};\n"
    else:
        chip_padding_rule = "  padding: 0 10px;\n"
    chip_radius = palette.get("chip_radius", max(radius - 6, 4))
    chip_border_rule = ""
    chip_bw = palette.get("chip_border_width")
    chip_bc = palette.get("chip_border_color")
    if chip_bw and chip_bc:
        chip_border_rule = f"  border: {chip_bw:g}px solid {chip_bc};\n"
    chip_bg_rule = ""
    chip_bg = palette.get("chip_bg")
    if chip_bg:
        chip_bg_rule = f"  background-color: {chip_bg};\n"
    chip_fg_rule = ""
    chip_fg = palette.get("chip_fg")
    if chip_fg:
        chip_fg_rule = f"  color: {chip_fg};\n"
    chip_fs_rule = ""
    chip_fs = palette.get("chip_font_size")
    if chip_fs:
        chip_fs_rule = f"  font-size: {chip_fs:g}px;\n"
    chip_fw_rule = ""
    chip_fw = palette.get("chip_font_weight")
    if chip_fw:
        chip_fw_rule = f"  font-weight: {chip_fw};\n"

    # active chip (focused)
    active_bg = palette.get("active_bg", accent)
    if "active_bg" in palette and "active_fg" in palette:
        active_fg_final = palette["active_fg"]
    else:
        active_fg_final = _contrast_fg(active_bg)
    occupied_fg = palette.get("occupied_fg", accent)
    # Optional specular glow on the focused workspace chip (imported theme's
    # `#workspaces button.active` box-shadow).
    active_shadow_rule = ""
    active_shadow = palette.get("active_shadow")
    if active_shadow:
        active_shadow_rule = f"  box-shadow: {' '.join(active_shadow.split())};\n"

    # Per-module glyph colours (from pywal). Each glyph-bearing module gets its
    # own accent so the icons read as distinct; these re-tint on wallpaper
    # change because they come from the live pywal palette.
    module_colors = palette.get("module_colors") or {}
    module_rules = ""
    for mid, selector in MODULE_GLYPH_SELECTORS.items():
        color = module_colors.get(mid)
        if color:
            module_rules += f"{selector} {{ color: {color}; }}\n"

    return f"""
.taskbar {{
  background-color: {bg};
  border-radius: {radius}px;
  margin: {top_m}px {right_m}px {bottom_m}px {left_m}px;
  min-height: {min_height}px;
  color: {fg};
{font_size_rule}{border_rule}{bar_shadow_rule}{padding_rule}{font_rule}}}
.task-button {{ padding: 2px 6px; border-radius: {max(radius - 6, 4)}px; }}
.task-button.hover {{ background-color: {hover}; }}
.quicklink-glyph {{ color: {glyph_color}; font-family: {glyph_font}; }}
.accent-icon {{ color: {accent}; }}
{module_rules}
.tray-button {{ padding: 2px 6px; border-radius: {max(radius - 6, 4)}px; }}
.tray-button.hover {{ background-color: {hover}; }}
.dimmed {{ opacity: 0.45; }}
.task-dot {{
  min-width: {dot_size}px;
  min-height: {dot_size}px;
  border-radius: {dot_size // 2}px;
  background-color: {rgba(palette["foreground"], 0.55)};
}}
.task-button.active .task-dot {{
  min-width: {min(dot_size + 2, dot_size * 2)}px;
  min-height: {min(dot_size + 2, dot_size * 2)}px;
  background-color: {accent};
}}
.workspace-chip {{
  min-height: {max(height - 12, 16)}px;
  border-radius: {chip_radius}px;
  color: {chip_fg or fg};
{chip_padding_rule}{chip_border_rule}{chip_bg_rule}{chip_fs_rule}{chip_fw_rule}}}
.workspace-chip.hover {{ background-color: {hover}; }}
.workspace-chip.occupied {{ color: {occupied_fg}; }}
.workspace-chip.active {{
  background-color: {active_bg};
  color: {active_fg_final};
{active_shadow_rule}}}
.divider {{
  min-width: 1px;
  min-height: 22px;
  border-radius: 1px;
  background-color: {rgba(palette["foreground"], 0.25)};
}}
.clock {{ padding: 0 10px; border-radius: {max(radius - 6, 4)}px; }}
.clock.hover {{ background-color: {hover}; }}
.clock-label {{ font-weight: bold; font-size: inherit; }}
.clock-date {{ opacity: 0.85; font-size: inherit; }}
.kbstate {{ padding: 0 8px; border-radius: {max(radius - 6, 4)}px; }}
.kbstate.hover {{ background-color: {hover}; }}
.kbstate-icon {{ color: {fg}; }}
.kbstate-icon.on {{ color: {accent}; }}
.kbstate-icon.off {{ opacity: 0.35; }}
.window {{ padding: 2px 10px; border-radius: {max(radius - 6, 4)}px; }}
.window.hover {{ background-color: {hover}; }}
.window label {{ font-size: inherit; }}
.sysmon {{ padding: 2px 8px; border-radius: {max(radius - 6, 4)}px; }}
.sysmon.hover {{ background-color: {hover}; }}
.sysmon-value {{ font-size: inherit; }}
.sysmon-value.warn {{ color: {warn}; }}
.sysmon-value.high {{ color: {danger}; }}
.updates {{ padding: 2px 8px; border-radius: {max(radius - 6, 4)}px; }}
.updates.hover {{ background-color: {hover}; }}
.updates-value {{ font-size: inherit; }}
.updates-value.warn {{ color: {warn}; }}
.updates-value.high {{ color: {danger}; }}
.popup-row {{ padding: 6px 8px; border-radius: 6px; }}
.popup-row.hover {{ background-color: {hover}; }}
.popup-title {{ font-weight: bold; padding-bottom: 4px; }}
.tooltip-label {{ font-size: 12px; }}
.popup-box {{
  background-color: {rgba(palette["background"], popup_alpha)};
  border-radius: {radius}px;
  padding: 8px;
  color: {fg};
{popup_border_rule}}}
menu {{
  background-color: {rgba(palette["background"], 0.97)};
  border: 1px solid {menu_border};
  border-radius: {max(radius - 2, 6)}px;
  padding: 4px;
  color: {fg};
}}
menu menuitem {{ padding: 6px 14px; border-radius: 4px; color: {fg}; }}
menu menuitem:hover {{ background-color: {hover}; color: {fg}; }}
menu separator {{
  background-color: {rgba(palette["foreground"], 0.15)};
  min-height: 1px;
  margin: 3px 6px;
}}
.qs-button {{ padding: 2px 6px; border-radius: {max(radius - 6, 4)}px; }}
.qs-button.hover {{ background-color: {hover}; }}
.qs-title {{ font-weight: bold; padding-bottom: 6px; }}
.qs-row {{ padding: 6px 8px; border-radius: 6px; }}
.qs-row.hover {{ background-color: {hover}; }}
/* Switches / scales: the GTK theme paints these with its own
   ``background-image`` (SVG/gradient) assets, which sit ON TOP of any
   ``background-color`` we set — so the control kept the GTK accent instead of
   the pywal/imported palette. Reset the image/shadow and drive the colour. */
.qs-switch, .settings-switch {{
  min-width: 34px;
  min-height: 18px;
  border-radius: 9px;
  border: none;
  box-shadow: none;
  background-image: none;
  background-color: {rgba(palette["foreground"], 0.22)};
}}
.qs-switch slider, .settings-switch slider {{
  min-width: 14px;
  min-height: 14px;
  border-radius: 7px;
  margin: 2px;
  border: none;
  box-shadow: none;
  background-image: none;
  background-color: {fg};
}}
.qs-switch:checked, .settings-switch:checked {{
  background-image: none;
  background-color: {accent};
}}
.qs-switch:checked slider, .settings-switch:checked slider {{
  background-image: none;
  background-color: {_contrast_fg(accent)};
}}
.qs-scale trough, .settings-scale trough {{
  min-height: 4px;
  border-radius: 2px;
  border: none;
  box-shadow: none;
  background-image: none;
  background-color: {rgba(palette["foreground"], 0.22)};
}}
.qs-scale highlight, .settings-scale highlight {{
  min-height: 4px;
  border-radius: 2px;
  border: none;
  box-shadow: none;
  background-image: none;
  background-color: {accent};
}}
.qs-scale slider, .settings-scale slider {{
  min-width: 12px;
  min-height: 12px;
  border-radius: 6px;
  border: none;
  box-shadow: none;
  background-image: none;
  background-color: {fg};
}}
.notif-button {{ padding: 2px 6px; border-radius: {max(radius - 6, 4)}px; }}
.notif-button.hover {{ background-color: {hover}; }}
.notif-dot {{
  background-color: {accent};
  color: {active_fg_final};
  font-size: 9px;
  font-weight: bold;
  min-width: 14px;
  min-height: 14px;
  border-radius: 7px;
  padding: 0 3px;
}}
.notif-title {{ font-weight: bold; padding-bottom: 6px; }}
.notif-row {{
  background-color: {rgba(palette["foreground"], 0.05)};
  border-radius: 8px;
  padding: 8px;
}}
.notif-app {{ font-size: 11px; opacity: 0.85; }}
.notif-time {{ font-size: 9px; opacity: 0.6; }}
.notif-summary {{ font-weight: bold; }}
.notif-body {{ font-size: 11px; opacity: 0.9; }}
.notif-action {{
  min-height: 24px;
  padding: 0 8px;
  border-radius: 6px;
  background-color: {rgba(palette["accent"], 0.18)};
  color: {fg};
}}
.notif-clear {{ min-height: 24px; padding: 0 10px; border-radius: 6px; }}
.cliphist-header {{ padding-bottom: 4px; }}
.cliphist-search {{ border-radius: 6px; }}
.cliphist-row {{
  background-color: {rgba(palette["foreground"], 0.05)};
  border-radius: 8px;
  padding: 4px 6px;
}}
.cliphist-row:hover {{ background-color: {hover}; }}
.cliphist-preview {{ font-size: 12px; color: {fg}; }}
.cliphist-del {{
  min-width: 24px;
  min-height: 24px;
  padding: 0 4px;
  border-radius: 6px;
  color: {fg};
  background-color: transparent;
}}
.cliphist-del:hover {{ background-color: {rgba(palette["red"], 0.22)}; }}
.cliphist-empty {{ color: {rgba(palette["foreground"], 0.55)}; font-size: 12px; }}
.mc-title {{ font-weight: bold; font-size: 15px; }}
.mc-close {{ min-width: 24px; min-height: 24px; padding: 0 4px; border-radius: 6px; color: {fg}; background-color: transparent; }}
.mc-close:hover {{ background-color: {hover}; }}
.mc-sidebar {{ padding: 4px; border-radius: 8px; background-color: {rgba(palette["foreground"], 0.05)}; }}
.mc-sidebar-button {{ padding: 5px 8px; border-radius: 6px; }}
.mc-sidebar-button.hover {{ background-color: {hover}; }}
.mc-sidebar-button.active {{ background-color: {accent}; color: {active_fg_final}; }}
.mc-sidebar-label {{ font-size: 13px; }}
.mc-icon {{ color: {accent}; }}
.mc-sidebar-button.active .mc-icon {{ color: {active_fg_final}; }}
.mc-page-title {{ font-weight: bold; font-size: 14px; padding-bottom: 2px; }}
/* Settings dialogue — reuses the monitor's sidebar/stack chrome so the
   dialogue matches the system monitor's look and the theme re-applies cleanly.
   Standard GTK widgets (spinbuttons/entries/buttons) still get the theme fg/bg
   via the settings window's override pass; these classes drive the chrome. */
.settings-title {{ font-weight: bold; font-size: 14px; }}
.settings-label {{ font-size: 13px; }}
.settings-value {{ font-weight: bold; }}
.settings-section {{ background-color: {rgba(palette["foreground"], 0.04)}; border-radius: 8px; padding: 8px; }}
.settings-section-title {{ font-size: 11px; opacity: 0.85; font-weight: bold; }}
.settings-apply {{
  background-color: {accent}; color: {active_fg_final};
  border-radius: 6px; padding: 5px 14px; font-weight: bold; border: none;
}}
.settings-apply:hover {{ background-color: {rgba(accent, 0.85)}; }}
/* Dialogue chrome buttons / rows — transparent like the monitor's, so no
   opaque GTK button blocks appear. */
.settings-btn {{
  color: {fg}; background-color: transparent; border: none; border-radius: 6px;
  padding: 4px 10px;
}}
.settings-btn:hover {{ background-color: {hover}; }}
.settings-btn:active, .settings-btn:checked {{ color: {accent}; }}
/* Inputs (spinbuttons / entries) — translucent fill so they read as inputs
   without an opaque block; text follows the theme. The internal entry and the
   up/down buttons of a spinbutton need their own rules: the GTK theme
   hard-colours those nodes and teals the arrow when active. */
.settings-input {{
  color: {fg}; background-color: {rgba(palette["foreground"], 0.07)};
  border: 1px solid {rgba(palette["foreground"], 0.18)}; border-radius: 5px;
}}
.settings-input entry {{
  background-image: none;
  background-color: {rgba(palette["foreground"], 0.07)};
  color: {fg};
  border-color: {rgba(palette["foreground"], 0.18)};
}}
.settings-input:focus, .settings-input entry:focus {{ border-color: {accent}; }}
.settings-input button {{
  background-image: none; background-color: transparent;
  border: none; box-shadow: none; color: {fg};
}}
.settings-input image {{ color: {fg}; }}
.settings-input image:hover, .settings-input image:active {{ color: {accent}; }}
/* Check / radio indicators: the GTK theme draws these with its own PNG assets,
   so they kept the theme colour. Recolour GTK's symbolic indicators with the
   palette fg (unchecked) / accent (checked) instead. */
.settings-check, .settings-radio {{
  color: {fg}; background-color: transparent;
}}
.settings-check check, .settings-radio radio {{
  -gtk-icon-source: -gtk-icontheme('checkbox-symbolic');
  background-image: none; border: none; box-shadow: none;
  color: {rgba(palette["foreground"], 0.6)};
}}
.settings-radio radio {{ -gtk-icon-source: -gtk-icontheme('radio-symbolic'); }}
.settings-check:checked check {{
  -gtk-icon-source: -gtk-icontheme('checkbox-checked-symbolic');
  color: {accent};
}}
.settings-radio:checked radio {{
  -gtk-icon-source: -gtk-icontheme('radio-checked-symbolic');
  color: {accent};
}}
.settings-check:checked, .settings-radio:checked {{ color: {accent}; }}
/* Arc Menu settings widgets — notebook tabs and colour buttons use the theme
   fg/accent so the page matches the rest of the dialogue. The notebook's
   internal ``stack`` node paints the GTK theme's opaque base_color by default
   (``notebook > stack:not(:only-child)``) — make it transparent so the
   popup-box's themed background shows through the page area. */
.settings-notebook {{ background-color: transparent; }}
.settings-notebook header {{ background-color: transparent; }}
.settings-notebook > stack {{ background-color: transparent; }}
.settings-notebook tab {{
  padding: 4px 12px; border-radius: 6px; color: {fg};
}}
.settings-notebook tab:hover {{ background-color: {hover}; }}
.settings-notebook tab:checked {{
  background-color: {rgba(accent, 0.18)}; color: {accent};
}}
.settings-color {{
  color: {fg}; background-color: transparent;
  border: 1px solid {rgba(palette["foreground"], 0.18)}; border-radius: 5px;
}}
.settings-color:hover {{ border-color: {accent}; }}
/* ListBox (arc menu item list, item-dialog app list) paints the GTK theme's
   opaque bg by default — make it transparent so the popup-box theme shows.
   The GTK theme also recolours a selected row's text (often black); override
   that with the accent + contrast colour like the monitor's tree. */
.settings-list, .settings-list row {{ background-color: transparent; }}
.settings-list row:selected {{ background-color: {accent}; color: {active_fg_final}; }}
/* The bar-settings window is frameless + transparent; strip any GTK theme
   frame/outline so its only border is the popup-box's 2px animated one. */
.settings-window {{
  border: none; outline-style: none; outline-width: 0;
  box-shadow: none; background-color: transparent;
}}
/* GTK themes style the CSD ``decoration`` node with a margin + drop shadow
   (e.g. Kripton: margin 10px, box-shadow). That draws a second frame around a
   decorated/frameless dialog. The bar's windows never want it — neutralize it
   so only the popup-box border shows. */
decoration {{
  margin: 0;
  box-shadow: none;
  border: none;
  border-radius: 0;
}}
/* Keyboard focus: a visible ring so tab-key navigation is not invisible.
   The GTK theme suppresses the default focus outline, so redraw it with the
   accent for every focusable control inside the bar's popups/dialogues. */
.settings-btn:focus, .notif-action:focus, .notif-clear:focus, .cliphist-del:focus,
.mc-close:focus, .mc-sidebar-button:focus, .qs-row:focus, .popup-row:focus,
.wallpaper-thumb:focus, .settings-list row:focus {{
  outline-style: solid;
  outline-width: 2px;
  outline-offset: -2px;
  outline-color: {accent};
}}
.mc-graph-title {{ font-size: 11px; opacity: 0.85; }}
.mc-graph-value {{ font-weight: bold; }}
.mc-graph-value.warn {{ color: {warn}; }}
.mc-graph-value.high {{ color: {danger}; }}
.mc-stat-label {{ font-size: 12px; opacity: 0.85; }}
.mc-stat-value {{ font-weight: bold; font-size: 12px; }}
.mc-core-bar trough {{ min-height: 6px; border-radius: 3px; background-color: {rgba(palette["foreground"], 0.15)}; }}
.mc-core-bar trough progress {{ min-height: 6px; border-radius: 3px; background-color: {accent}; }}
.dimm-slot {{ border-radius: 8px; padding: 6px; border: 1px solid {rgba(palette["foreground"], 0.18)}; background-color: {rgba(palette["foreground"], 0.04)}; }}
.dimm-slot.populated {{ border: 1px solid {accent}; background-color: {rgba(accent, 0.14)}; }}
.dimm-size {{ font-weight: bold; font-size: 13px; }}
.dimm-slot.populated .dimm-size {{ color: {accent}; }}
.dimm-slot.empty .dimm-size {{ opacity: 0.45; font-size: 11px; }}
.dimm-loc {{ font-size: 11px; opacity: 0.75; }}
.drive-card {{ border-radius: 8px; padding: 4px 8px; border: 1px solid {rgba(palette["foreground"], 0.15)}; background-color: {rgba(palette["foreground"], 0.04)}; }}
.drive-card.hover {{ background-color: {hover}; }}
.drive-card.selected {{ border: 1px solid {accent}; background-color: {rgba(accent, 0.16)}; }}
.drive-type {{ font-size: 11px; font-weight: bold; opacity: 0.9; }}
.drive-size {{ font-size: 11px; font-weight: bold; }}
.drive-free {{ font-size: 11px; opacity: 0.75; }}
.drive-card.nvme .mc-icon {{ color: {accent}; }}
.drive-card.hdd .mc-icon {{ color: {warn}; }}
.drive-card.ssd .mc-icon {{ color: {green}; }}
.drive-card.usb .mc-icon {{ color: {sky}; }}
.drive-card.reader .mc-icon {{ opacity: 0.45; }}
.iface-row {{ padding: 3px 6px; border-radius: 6px; }}
.iface-name {{ font-weight: bold; font-size: 11px; }}
.iface-type {{ font-size: 11px; opacity: 0.8; }}
.iface-ip {{ font-size: 11px; }}
.iface-rate {{ font-size: 11px; font-weight: bold; }}
.iface-eth {{ color: {accent}; }}
.iface-wifi {{ color: {sky}; }}
.iface-virt {{ color: {rgba(palette["foreground"], 0.55)}; }}
.iface-down {{ color: {sky}; }}
.iface-up {{ color: {green}; }}
.gpu-model {{ font-weight: bold; font-size: 13px; }}
.mc-unavailable {{ font-size: 12px; opacity: 0.7; }}
.mc-tree {{ background-color: transparent; }}
.mc-tree header button {{ background-color: transparent; color: {fg}; border: none; }}
.mc-tree view {{ background-color: {rgba(palette["foreground"], 0.05)}; color: {fg}; border-radius: 8px; }}
.mc-tree row:nth-child(even) {{ background-color: {rgba(palette["foreground"], 0.03)}; }}
.mc-tree row:selected {{ background-color: {accent}; color: {active_fg_final}; }}
/* Themer dialogue: wallpaper preview thumbnail + 2-column thumb grid */
.wallpaper-preview {{
  border: 1px solid {rgba(palette["foreground"], 0.25)};
  border-radius: 8px;
  background-color: {rgba(palette["foreground"], 0.05)};
}}
.wallpaper-thumb {{
  border: 1px solid {rgba(palette["foreground"], 0.12)};
  border-radius: 6px;
  padding: 0;
}}
.wallpaper-thumb:hover {{ border-color: {accent}; }}
"""