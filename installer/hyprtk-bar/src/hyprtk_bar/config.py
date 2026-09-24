"""Configuration loading for hyprtk-bar.

Config lives at ~/.config/hyprtk-bar/config.json (JSON).
On first run a default config is written so the user can edit it.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · config
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import json
import logging
import os
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "hyprtk-bar"
CONFIG_PATH = CONFIG_DIR / "config.json"
CONFIG_BAK_PATH = CONFIG_DIR / "config.json.bak"
PYWAL_PATH = Path.home() / ".cache" / "wal" / "colors.json"

# Bundled scripts live next to the bar's source (standalone installs); the full
# hyprtk dotfiles are the fallback so both deployment modes work.
# ``HYPRTK_BAR_DATA_DIR`` lets a Nix/flatpak-style install point the bar at its
# read-only data (assets/scripts/themes) in the store, instead of deriving the
# location from ``__file__`` (which breaks once the package is unpacked into
# site-packages).
_DATA_DIR = os.environ.get("HYPRTK_BAR_DATA_DIR")
INSTALL_DIR = Path(_DATA_DIR) if _DATA_DIR else Path(__file__).resolve().parents[2]
SCRIPTS_DIR = INSTALL_DIR / "scripts"
HYPRTK_DIR = Path.home() / "hyprtk"


def resolve_script(name: str, *hyprtk_parts: str) -> Path:
    """A bundled script (standalone), falling back to the full-dotfiles path."""
    bundled = SCRIPTS_DIR / name
    if bundled.is_file():
        return bundled
    return HYPRTK_DIR.joinpath(*hyprtk_parts)


ROFI_SYNC_SH = resolve_script("sync-rofi-theme.sh", "installer", "hyprtk-bar", "scripts", "sync-rofi-theme.sh")

# Distro-agnostic update scripts (bundled with the standalone bar, with the
# full hyprtk dotfiles as the fallback). ``updates.sh`` counts pending updates
# for whatever package manager is detected; ``installupdates.sh`` applies them.
UPDATES_SH = resolve_script("updates.sh", "installer", "scripts", "updates.sh")
INSTALL_UPDATES_SH = resolve_script("installupdates.sh", "installer", "scripts", "installupdates.sh")

# Bundled toggle/quicklink scripts resolved the same way (standalone-first,
# dotfiles fallback). The quicklink defaults and start button point at these so
# a standalone install and a dotfiles deploy both work.
MENU_TOGGLE_SH = resolve_script("hyprtk-bar-menu-toggle.sh", "installer", "hyprtk-bar", "scripts", "hyprtk-bar-menu-toggle.sh")
APPSMENU_SH = resolve_script("appsmenu.sh", "installer", "hyprtk-bar", "scripts", "appsmenu.sh")
UPDATEWAL_AWWW_SH = resolve_script("updatewal-awww.sh", "installer", "hyprtk-bar", "scripts", "updatewal-awww.sh")
SSDETECT_SH = resolve_script("ssdetect.sh", "installer", "scripts", "ssdetect.sh")

log = logging.getLogger("hyprtk_bar.config")

# Module ids and their positions. The bar builds its widgets from ``layout``;
# drag & drop reorders the same set of module ids between the left/center/right
# sections, and the bar menu can show/hide individual modules.
MODULE_IDS = [
    "start_button",
    "quicklinks",
    "workspaces",
    "tasklist",
    "window",
    "updates",
    "sysmon",
    "kbstate",
    "clock",
    "notifications",
    "tray",
    "quicksettings",
]

MODULE_LABELS = {
    "start_button": "Start button",
    "quicklinks": "Quick links",
    "workspaces": "Workspaces",
    "tasklist": "Task list",
    "window": "Active window",
    "updates": "Package updates",
    "sysmon": "System monitor",
    "kbstate": "Keyboard state",
    "clock": "Clock",
    "notifications": "Notification center",
    "tray": "System tray",
    "quicksettings": "Quick settings",
}

DEFAULT_LAYOUT = {
    "left": ["start_button", "quicklinks", "tasklist", "window"],
    "center": ["workspaces"],
    "right": ["updates", "sysmon", "kbstate", "clock", "notifications", "tray", "quicksettings"],
}

# ── desktop widgets ──────────────────────────────────────────────
# Desktop widgets are free-floating layer-shell surfaces owned by the bar
# process (like conky), separate from the bar's own modules. Each one is
# enabled/placed independently from the settings window's "Widgets" page.
WIDGET_IDS = ["clock", "weather", "visualizer"]

WIDGET_LABELS = {
    "clock": "Clock",
    "weather": "Weather",
    "visualizer": "Audio visualizer",
}

WIDGET_LAYERS = ("background", "bottom", "top")

WIDGET_POSITIONS = (
    "free",
    "top-left", "top-center", "top-right",
    "center-left", "center", "center-right",
    "bottom-left", "bottom-center", "bottom-right",
)

CLOCK_STYLES = ("digital", "text", "dials")
VISUALIZER_STYLES = ("bars", "wave", "mirror", "dots", "glow")
VISUALIZER_COLOR_MODES = ("accent", "gradient", "pywal", "custom")
WEATHER_UNITS = ("metric", "imperial")

# Appearance carried by a clock theme file (see desktop/clock_theme.py). The
# widget's own config block overrides these keys.
DEFAULT_CLOCK_THEME = {
    "style": "digital",
    "font": "",
    "scale": 1.0,
    "opacity": 0.75,
    "radius": 16,
    "padding": 18,
    "background": "",
    "foreground": "",
    "accent": "",
    "time_format": "%H:%M",
    "date_format": "%A, %d %B",
    "show_date": True,
    "show_seconds": False,
    "digital": {"font_weight": "bold", "shadow": False},
    "text": {"uppercase": False},
    "dials": {"count": 1, "ring_thickness": 6, "ticks": True, "show_hands": True},
}

DEFAULT_LINKS = [
    {
        "id": "apps",
        "label": "Apps menu",
        "icon": "\uf00a",  # nf-fa-bars
        "command": str(APPSMENU_SH),
    },
    {
        "id": "terminal",
        "label": "Terminal",
        "icon": "\uf120",  # nf-fa-terminal
        "command": "",  # resolves the session's preferred terminal
    },
    {
        "id": "files",
        "label": "File manager",
        "icon": "\uf07c",  # nf-fa-folder_open_o
        "command": "",  # resolves the session's preferred file manager
    },
    {
        "id": "web",
        "label": "Web browser",
        "icon": "\uf0ac",  # nf-fa-globe
        "command": "",  # resolves the session's preferred web browser
    },
    {
        "id": "wallpaper",
        "label": "Wallpaper",
        "icon": "\uf03e",  # nf-fa-picture_o
        "command": "",  # opens the in-bar Theme Manager dialogue
        "command_right": str(UPDATEWAL_AWWW_SH),
    },
    {
        "id": "cliphist",
        "label": "Clipboard history",
        "icon": "\uf0ea",  # nf-fa-clipboard
        "command": "",  # opens the in-bar clipboard history dialogue
    },
    {
        "id": "screenshot",
        "label": "Screenshot",
        "icon": "\uf083",  # nf-fa-camera
        "command": str(SSDETECT_SH),
    },
]

DEFAULTS = {
    "position": "top",               # bottom | top
    "height": 38,                    # taskbar pill height in px
    "gap_in": 4,                     # transparent gap between the pill and app windows
    "gap_out": 4,                    # transparent gap between the pill and the screen edge
    "radius": 12,                    # pill corner radius
    "opacity": 0.75,                 # pill background alpha
    "width": "85%",                  # pill width: px int or "NN%" of the monitor
    "align": "center",               # pill placement when width < 100%: left|center|right
    "use_pywal": True,               # legacy: seed theme.source from this on first run
    "monitors": "primary",           # primary | all | [connector, ...] (e.g. ["DP-1", "HDMI-A-1"])
    "theme": {
        "source": "pywal",           # pywal | imported | manual
        "theme_name": "hyprtk-liquid-glass",  # rofi-variant hint (source=pywal keeps it dynamic)
        "background": "#1a1b26",
        "foreground": "#c0caf5",
        "accent": "#7aa2f7",
        "hover": "rgba(255, 255, 255, 0.08)",
        "running": "#7aa2f7",
        "border_color": "",          # manual border colour ("" = accent)
        "border_animation": True,    # animate the pill border color
    },
    "animations": {
        "mode": "high",              # low | high | custom
        "speed": 15,                 # custom border-animation speed (mode=custom)
    },
    "font": {
        "family": "",                # "" = system default font
        "size": 12,                  # base text size (px); module icons scale from it
        "icon_size": 0,              # 0 = auto (scales with the font size), else px
    },
    "layout": DEFAULT_LAYOUT,
    "themer": {
        "enabled": True,
        "wallpaper_dir": str(Path.home() / "Pictures" / "Wallpapers"),
    },
    "quicklinks": {
        "enabled": True,
        "glyph_font": "Symbols Nerd Font",
        "glyph_color": "accent",
        "icon_size": 0,
        "links": DEFAULT_LINKS,
    },
    "center": {
        "start_button": True,
        "start_icon": "view-grid-symbolic",
        "start_glyph": "\uf015",
        "start_command": str(MENU_TOGGLE_SH),
        "pinned": [],
    },
    "workspaces": {
        "enabled": True,
        "show_empty": True,          # render all workspace chips up to max
        "max": 5,                    # number of workspace chips to show
    },
    "clock": {
        "enabled": True,
        "format": "%H:%M",
        "date_format": "%a %d %b",
        "calendar": True,
    },
    "sysmon": {
        "enabled": True,
        "interval": 2,          # seconds between reads
        "disk_path": "/",       # mount point to monitor
        "monitor": True,        # left-click opens the Mission Center-style dialog
        "data_points": 60,      # history points per graph in the dialog
        "network_iface": "auto",  # auto | interface name for the Network page
        "pages": ["cpu", "memory", "disks", "network", "gpu", "apps"],
    },
    "updates": {
        "enabled": True,
        "interval": 60,         # seconds between update checks
        "script": str(UPDATES_SH),
        # installupdates.sh self-launches in a detected terminal, so the click
        # command is just the script itself (works on any distro/terminal).
        "install_command": str(INSTALL_UPDATES_SH),
    },
    "window": {
        "enabled": True,
        "max_length": 40,       # active-window title max chars
        "width": 220,           # fixed module width (px) so neighbors never shift
    },
    "tray": {
        "enabled": True,
        "icon_size": 20,
        "reset_nm_applet": True,   # kill + relaunch nm-applet on startup so it
                                   # re-registers with this bar's watcher
    },
    "quicksettings": {
        "enabled": True,
    },
    "notifications": {
        "enabled": True,
        "max_stored": 50,           # notifications kept in the center at once
        "default_timeout": 5000,    # ms a toast stays before auto-dismiss (0 = persist)
    },
    "arcmenu": {
        "enabled": True,            # the arc menu overlay is owned by the bar
        "position": "bottom-right", # top-left|top-center|top-right|bottom-left|bottom-center|bottom-right
        "shape": "circle",          # circle | square (square fans items on a square perimeter)
        "transparent": False,       # transparent button/item backgrounds (icons only)
        "follow_bar": True,         # mirror the bar's palette glass + text colours
        "use_pywal": True,          # theme FAB/items from pywal color5/color6
        "margin": 24,
        "radius": 140,
        "fab_size": 56,
        "item_size": 48,
        "animation_time": 300,      # ms
        "fab_icon": "view-grid-symbolic",
        "fab_glyph": "\uf00a",     # matches the apps quicklink (rofi launcher) glyph
        "glyph_size": 0,           # glyph px (0 = auto: half the button size)
        "fab_color": "#c084fc",     # mauve / color5 accent
        "item_color": "#22d3ee",    # sky / color6 accent
        "close_on_unfocus": False,
        "close_on_click": True,
        "items": [
            {"glyph": "\uf0ac", "command": "firefox", "tooltip": "Firefox"},
            {"glyph": "\uf120", "command": "alacritty", "tooltip": "Terminal"},
            {"glyph": "\uf07c", "command": "thunar", "tooltip": "Files"},
            {"glyph": "\uf1ec", "command": "qalculate-gtk", "tooltip": "Calculator"},
            {"glyph": "\uf013", "action": "settings", "tooltip": "Settings"},
        ],
    },
    "menu": {
        "enabled": True,            # the start menu is owned by the bar process
        "position": "auto",         # auto | top-left|top-center|top-right|center|bottom-*
        "align": "left",            # left | center | right
        "follow_bar": True,         # mirror the bar's palette; off = menu's own pywal
        "gap_in": 4,                # gap between the menu and the bar (px)
        "gap_out": 5,               # gap between the menu and the screen edge (px)
        "layout": "whisker",        # whisker | win7 | win11 | plasma
        "width": 920,
        "height": 580,
        "sidebar_width": 180,
        "recents_width": 230,
        "show_recents": True,
        "max_recents": 10,
        "favorites": [],
        "recents": [],
        "power": {
            "lock": "pidof swaylock hyprlock || swaylock || hyprlock",
            "logout": "hyprctl dispatch exit",
            "reboot": "systemctl reboot",
            "shutdown": "systemctl poweroff",
            "suspend": "systemctl suspend",
            "hibernate": "systemctl hibernate",
        },
    },
    "widgets": {
        "enabled": True,             # master switch for all desktop widgets
        "clock": {
            "enabled": True,
            "layer": "bottom",       # background | bottom | top
            "position": "top-right", # one of WIDGET_POSITIONS
            "margin_x": 40,
            "margin_y": 40,
            "width": 220,            # px (0 = auto)
            "height": 0,             # px (0 = auto)
            "style": "digital",      # digital | text | dials
            "theme": "default",      # clock theme file (assets/widgets/clock)
            "font": "",
            "scale": 1.0,
            "opacity": 0.75,
            "radius": 16,
            "padding": 18,
            "background": "",        # "" = follow the bar palette
            "foreground": "",
            "accent": "",
            "time_format": "%H:%M",
            "date_format": "%A, %d %B",
            "show_date": True,
            "show_seconds": False,
            "dial_count": 1,         # dials style: 1 | 3 (H/M/S rings)
            "ring_thickness": 6,
        },
        "weather": {
            "enabled": True,
            "layer": "bottom",
            "position": "top-left",
            "margin_x": 40,
            "margin_y": 40,
            "width": 280,
            "height": 0,
            "city": "London",
            "units": "metric",       # metric | imperial
            "refresh_minutes": 15,
            "opacity": 0.75,
            "radius": 16,
            "padding": 18,
            "background": "",
            "foreground": "",
            "accent": "",
            "show_icon": True,
            "show_temp": True,
            "show_condition": True,
            "show_feels_like": True,
            "show_humidity": True,
            "show_wind": True,
            "show_forecast": True,
            "forecast_days": 3,
        },
        "visualizer": {
            "enabled": False,
            "layer": "bottom",
            "position": "bottom-center",
            "margin_x": 40,
            "margin_y": 40,
            "width": 420,
            "height": 120,
            "style": "bars",         # bars | wave | mirror | dots | glow
            "bars": 48,
            "sensitivity": 1.0,
            "smoothing": 0.6,
            "color_mode": "pywal",     # accent | gradient | pywal | custom
            "color": "",
            "gradient_from": "",
            "gradient_to": "",
            "peak_dots": True,
            "orientation": "horizontal",  # horizontal | vertical
            "fps": 60,
            "source": "cava",        # cava | synthetic
            "cava_binary": "cava",
            "opacity": 0.6,
            "radius": 16,
            "padding": 12,
            "background": "",
        },
    },
}

# Path of the legacy standalone app's config, imported once into ``arcmenu``.
LEGACY_ARC_CONFIG = Path.home() / ".config" / "hyprtk-arc-menu" / "config.json"

# Path of the legacy standalone hyprtk-menu config, imported once into ``menu``.
LEGACY_MENU_CONFIG = Path.home() / ".config" / "hyprtk-menu" / "config.json"

# Defaults for the in-bar menu (hyprtk-menu merged into the bar process).
MENU_LAYOUTS = ("whisker", "win7", "win11", "plasma")


def _deep_merge(base: dict, override: dict) -> dict:
    """Return a copy of ``base`` with ``override`` applied recursively."""
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def validate(cfg: dict) -> dict:
    """Coerce/correct known config fields, falling back to defaults."""
    cfg = dict(cfg)
    # Legacy ``margin`` (symmetric inset) migrates to gap_in/gap_out.
    if "margin" in cfg and "gap_in" not in cfg and "gap_out" not in cfg:
        try:
            margin = max(0, int(cfg["margin"]))
        except (TypeError, ValueError):
            margin = DEFAULTS["gap_in"]
        cfg["gap_in"] = margin
        cfg["gap_out"] = margin
    valid = _deep_merge(DEFAULTS, cfg)

    if valid.get("position") not in ("bottom", "top"):
        log.warning("Unknown position %r, using bottom", valid.get("position"))
        valid["position"] = "bottom"

    for key in ("height", "gap_in", "gap_out", "radius"):
        try:
            valid[key] = max(0, int(valid.get(key, DEFAULTS[key])))
        except (TypeError, ValueError):
            valid[key] = DEFAULTS[key]

    try:
        valid["opacity"] = max(0.0, min(1.0, float(valid.get("opacity", 0.95))))
    except (TypeError, ValueError):
        valid["opacity"] = 0.95

    valid["width"] = _normalize_width(valid.get("width", "100%"))

    if valid.get("align") not in ("left", "center", "right"):
        log.warning("Unknown align %r, using center", valid.get("align"))
        valid["align"] = "center"

    valid["use_pywal"] = bool(valid.get("use_pywal", True))

    # ── monitors ─────────────────────────────────────────────────
    monitors = valid.get("monitors", "primary")
    if isinstance(monitors, list):
        valid["monitors"] = [str(m) for m in monitors if str(m).strip()]
    elif monitors not in ("primary", "all"):
        log.warning("Unknown monitors %r, using primary", monitors)
        valid["monitors"] = "primary"
    else:
        valid["monitors"] = monitors

    # ── notifications ────────────────────────────────────────────
    notif = valid.get("notifications")
    if not isinstance(notif, dict):
        valid["notifications"] = dict(DEFAULTS["notifications"])
    else:
        try:
            valid["notifications"]["max_stored"] = max(
                1, int(notif.get("max_stored", 50))
            )
        except (TypeError, ValueError):
            valid["notifications"]["max_stored"] = 50
        try:
            valid["notifications"]["default_timeout"] = max(
                0, int(notif.get("default_timeout", 5000))
            )
        except (TypeError, ValueError):
            valid["notifications"]["default_timeout"] = 5000
        valid["notifications"]["enabled"] = bool(notif.get("enabled", True))

    # ── font ─────────────────────────────────────────────────────
    font = valid.get("font")
    if not isinstance(font, dict):
        valid["font"] = dict(DEFAULTS["font"])
    else:
        valid["font"]["family"] = str(font.get("family", "") or "")
        try:
            valid["font"]["size"] = max(8, int(font.get("size", 16)))
        except (TypeError, ValueError):
            valid["font"]["size"] = 16
        try:
            valid["font"]["icon_size"] = max(0, int(font.get("icon_size", 0)))
        except (TypeError, ValueError):
            valid["font"]["icon_size"] = 0

    # ── theme source ─────────────────────────────────────────────
    theme = valid.get("theme") or {}
    source = theme.get("source")
    if source == "waybar":
        # legacy source value → imported
        source = "imported"
    if source not in ("pywal", "imported", "manual"):
        # migrate the legacy use_pywal flag into an explicit source
        source = "pywal" if valid.get("use_pywal", True) else "manual"
    theme["source"] = source
    # Migrate the old waybar_theme key to theme_name.
    if "waybar_theme" in theme and not theme.get("theme_name"):
        theme["theme_name"] = theme.pop("waybar_theme")
    theme.pop("waybar_theme", None)
    theme["theme_name"] = str(theme.get("theme_name", "") or "")
    valid["theme"] = theme

    # ── layout ───────────────────────────────────────────────────
    valid["layout"] = _normalize_layout(cfg, valid)

    center = valid.get("center") or {}
    raw_center = cfg.get("center")
    if isinstance(raw_center, dict) and "pinned" in raw_center:
        # Explicit pinned list (even empty) is honored as-is.
        center["pinned"] = (
            [p for p in raw_center["pinned"] if isinstance(p, dict)]
            if isinstance(raw_center["pinned"], list)
            else []
        )
    else:
        # Null / missing / empty center block means no pinned apps. The default
        # pinned set only ships with a fresh config (DEFAULTS written on first
        # run); an edited config is taken as the user's explicit choice.
        center["pinned"] = []
    valid["center"] = center

    # ── sysmon ───────────────────────────────────────────────────
    sysmon = valid.get("sysmon")
    if not isinstance(sysmon, dict):
        valid["sysmon"] = dict(DEFAULTS["sysmon"])
    else:
        sysmon["monitor"] = bool(sysmon.get("monitor", True))
        try:
            sysmon["data_points"] = max(10, min(600, int(sysmon.get("data_points", 60))))
        except (TypeError, ValueError):
            sysmon["data_points"] = 60
        try:
            sysmon["interval"] = max(1, int(sysmon.get("interval", 2)))
        except (TypeError, ValueError):
            sysmon["interval"] = 2
        sysmon["network_iface"] = str(
            sysmon.get("network_iface", "auto") or "auto"
        ).strip() or "auto"
        sysmon["disk_path"] = str(sysmon.get("disk_path", "/") or "/")
        pages = sysmon.get("pages")
        allowed = {"cpu", "memory", "disks", "network", "gpu", "apps"}
        if isinstance(pages, list):
            clean = [p for p in pages if p in allowed]
            if clean:
                sysmon["pages"] = clean

    for section in ("workspaces", "clock"):
        sub = valid.get(section)
        if not isinstance(sub, dict):
            valid[section] = dict(DEFAULTS[section])

    # ── themer ───────────────────────────────────────────────────
    themer = valid.get("themer")
    if not isinstance(themer, dict):
        valid["themer"] = dict(DEFAULTS["themer"])
    else:
        themer["enabled"] = bool(themer.get("enabled", True))
        wd = themer.get("wallpaper_dir")
        themer["wallpaper_dir"] = str(wd) if isinstance(wd, str) and wd else str(
            DEFAULTS["themer"]["wallpaper_dir"]
        )

    # ── arcmenu ──────────────────────────────────────────────────
    # First-run migration from the removed standalone hyprtk-arc-menu app.
    if not cfg.get("arcmenu") and LEGACY_ARC_CONFIG.is_file():
        try:
            legacy = json.loads(LEGACY_ARC_CONFIG.read_text())
        except (json.JSONDecodeError, OSError):
            legacy = {}
        if isinstance(legacy, dict) and legacy:
            legacy.pop("corner", None)
            valid["arcmenu"] = _validate_arcmenu(_deep_merge(DEFAULTS["arcmenu"], legacy))

    arcmenu = valid.get("arcmenu")
    if not isinstance(arcmenu, dict):
        valid["arcmenu"] = dict(DEFAULTS["arcmenu"])
    else:
        valid["arcmenu"] = _validate_arcmenu(arcmenu)

    # ── menu ─────────────────────────────────────────────────────
    # First-run migration from the removed standalone hyprtk-menu app.
    if not cfg.get("menu") and LEGACY_MENU_CONFIG.is_file():
        try:
            legacy = json.loads(LEGACY_MENU_CONFIG.read_text())
        except (json.JSONDecodeError, OSError):
            legacy = {}
        if isinstance(legacy, dict) and legacy:
            valid["menu"] = _validate_menu(_deep_merge(DEFAULTS["menu"], legacy))

    menu = valid.get("menu")
    if not isinstance(menu, dict):
        valid["menu"] = dict(DEFAULTS["menu"])
    else:
        valid["menu"] = _validate_menu(menu)

    # ── widgets ──────────────────────────────────────────────────
    widgets = valid.get("widgets")
    if not isinstance(widgets, dict):
        valid["widgets"] = _deep_merge(DEFAULTS["widgets"], {})
    else:
        valid["widgets"] = _validate_widgets(widgets)

    # ── command/script fields must always be strings ────────────────
    center = valid.get("center") or {}
    center["start_command"] = _str_field(center.get("start_command"), str(MENU_TOGGLE_SH))
    center["pinned"] = _clean_command_list(center.get("pinned") or [], ("class", "command", "icon"))

    ql = valid.get("quicklinks") or {}
    if isinstance(ql.get("links"), list):
        ql["links"] = _clean_command_list(
            ql["links"], ("id", "label", "icon", "command", "command_right", "command_middle")
        )

    upd = valid.get("updates") or {}
    upd["script"] = _str_field(upd.get("script"), str(UPDATES_SH))
    upd["install_command"] = _str_field(upd.get("install_command"), str(INSTALL_UPDATES_SH))

    # workspaces.max feeds range() at build time — clamp it to avoid absurd
    # chip counts from a hand-edited config.
    ws = valid.get("workspaces") or {}
    if isinstance(ws, dict):
        try:
            ws["max"] = max(1, min(20, int(ws.get("max", 5))))
        except (TypeError, ValueError):
            ws["max"] = 5

    return valid


def _str_field(value, default: str = "") -> str:
    """Coerce a config value to a string (commands must never be non-strings)."""
    if isinstance(value, str):
        return value
    if isinstance(value, (int, float)):
        return str(value)
    return default


def _clean_command_list(entries, keys):
    """Coerce each entry's command-ish keys to strings, dropping non-dicts."""
    cleaned = []
    for entry in entries or []:
        if not isinstance(entry, dict):
            continue
        for key in keys:
            entry[key] = _str_field(entry.get(key))
        cleaned.append(entry)
    return cleaned


def _validate_arcmenu(arc: dict) -> dict:
    """Coerce/correct the ``arcmenu`` config block, falling back to defaults."""
    from .arcmenu import POSITIONS

    valid = _deep_merge(DEFAULTS["arcmenu"], arc)
    position = valid.get("position", "bottom-right")
    if position not in POSITIONS:
        log.warning("Unknown arcmenu position %r, using bottom-right", position)
        valid["position"] = "bottom-right"
    if valid.get("shape") not in ("circle", "square"):
        valid["shape"] = "circle"
    for key in ("transparent", "follow_bar", "use_pywal", "close_on_unfocus", "close_on_click"):
        valid[key] = bool(valid.get(key, False))
    valid["enabled"] = bool(valid.get("enabled", True))
    for key in ("margin", "radius", "fab_size", "item_size", "animation_time", "glyph_size"):
        try:
            valid[key] = max(0, int(valid.get(key, DEFAULTS["arcmenu"][key])))
        except (TypeError, ValueError):
            valid[key] = DEFAULTS["arcmenu"][key]
    if not isinstance(valid.get("items"), list):
        valid["items"] = list(DEFAULTS["arcmenu"]["items"])
    valid["fab_icon"] = _str_field(valid.get("fab_icon") or "view-grid-symbolic")
    valid["fab_glyph"] = _str_field(valid.get("fab_glyph") or "")
    valid["items"] = _clean_command_list(valid["items"], ("glyph", "command", "action", "tooltip"))
    return valid


def _validate_menu(menu: dict) -> dict:
    """Coerce/correct the ``menu`` config block, falling back to defaults."""
    valid = _deep_merge(DEFAULTS["menu"], menu)
    valid["enabled"] = bool(valid.get("enabled", True))
    valid["follow_bar"] = bool(valid.get("follow_bar", True))
    layout = valid.get("layout", "whisker")
    if layout not in MENU_LAYOUTS:
        log.warning("Unknown menu layout %r, using whisker", layout)
        valid["layout"] = "whisker"
    if valid.get("align") not in ("left", "center", "right"):
        valid["align"] = "left"
    for key in ("gap_in", "gap_out", "width", "height", "sidebar_width", "recents_width", "max_recents"):
        try:
            valid[key] = max(0, int(valid.get(key, DEFAULTS["menu"][key])))
        except (TypeError, ValueError):
            valid[key] = DEFAULTS["menu"][key]
    valid["show_recents"] = bool(valid.get("show_recents", True))
    for key in ("favorites", "recents"):
        valid[key] = [str(x) for x in (valid.get(key) or []) if x]
    power = valid.get("power")
    if not isinstance(power, dict):
        valid["power"] = dict(DEFAULTS["menu"]["power"])
    else:
        for key in ("lock", "logout", "reboot", "shutdown", "suspend", "hibernate"):
            power[key] = _str_field(power.get(key), DEFAULTS["menu"]["power"][key])
        valid["power"] = power
    return valid


def _clamp_int(value, lo: int, hi: int, default: int) -> int:
    try:
        return max(lo, min(hi, int(value)))
    except (TypeError, ValueError):
        return default


def _clamp_float(value, lo: float, hi: float, default: float) -> float:
    try:
        return max(lo, min(hi, float(value)))
    except (TypeError, ValueError):
        return default


def _validate_widgets(widgets: dict) -> dict:
    """Coerce/correct the ``widgets`` block, falling back to per-widget defaults.

    Every widget shares the placement/appearance keys (enabled, layer,
    position, margins, size, opacity, radius, padding, colors); the
    widget-specific keys are clamped by the per-widget branch below. A widget
    block the user omitted is materialized from DEFAULTS so the settings page
    always has a full record to edit.
    """
    valid = _deep_merge(DEFAULTS["widgets"], widgets)
    valid["enabled"] = bool(valid.get("enabled", True))

    for wid in WIDGET_IDS:
        block = valid.get(wid)
        if not isinstance(block, dict):
            block = dict(DEFAULTS["widgets"][wid])
        else:
            block = _deep_merge(DEFAULTS["widgets"][wid], block)

        block["enabled"] = bool(block.get("enabled", False))
        layer = str(block.get("layer", "bottom"))
        block["layer"] = layer if layer in WIDGET_LAYERS else "bottom"
        position = str(block.get("position", "top-right"))
        block["position"] = position if position in WIDGET_POSITIONS else "top-right"
        # ``free`` position uses margin_x/margin_y as an absolute top-left
        # offset on the monitor, so the range is wide enough for a 4K panel.
        block["margin_x"] = _clamp_int(block.get("margin_x"), 0, 8000, 40)
        block["margin_y"] = _clamp_int(block.get("margin_y"), 0, 8000, 40)
        block["width"] = _clamp_int(block.get("width"), 0, 4000, 0)
        block["height"] = _clamp_int(block.get("height"), 0, 4000, 0)
        block["opacity"] = _clamp_float(block.get("opacity"), 0.0, 1.0, 0.75)
        block["radius"] = _clamp_int(block.get("radius"), 0, 80, 16)
        block["padding"] = _clamp_int(block.get("padding"), 0, 80, 16)
        for key in ("background", "foreground", "accent"):
            block[key] = _str_field(block.get(key))

        if wid == "clock":
            block = _validate_widget_clock(block)
        elif wid == "weather":
            block = _validate_widget_weather(block)
        elif wid == "visualizer":
            block = _validate_widget_visualizer(block)
        valid[wid] = block
    return valid


def _validate_widget_clock(block: dict) -> dict:
    style = str(block.get("style", "digital"))
    block["style"] = style if style in CLOCK_STYLES else "digital"
    block["theme"] = _str_field(block.get("theme") or "default")
    block["font"] = _str_field(block.get("font"))
    block["scale"] = _clamp_float(block.get("scale"), 0.4, 3.0, 1.0)
    block["time_format"] = _str_field(block.get("time_format"), "%H:%M")
    block["date_format"] = _str_field(block.get("date_format"), "%A, %d %B")
    block["show_date"] = bool(block.get("show_date", True))
    block["show_seconds"] = bool(block.get("show_seconds", False))
    block["dial_count"] = _clamp_int(block.get("dial_count"), 1, 3, 1)
    block["ring_thickness"] = _clamp_int(block.get("ring_thickness"), 1, 24, 6)
    return block


def _validate_widget_weather(block: dict) -> dict:
    block["city"] = _str_field(block.get("city") or "London").strip() or "London"
    units = str(block.get("units", "metric"))
    block["units"] = units if units in WEATHER_UNITS else "metric"
    block["refresh_minutes"] = _clamp_int(block.get("refresh_minutes"), 5, 1440, 15)
    for key in (
        "show_icon", "show_temp", "show_condition", "show_feels_like",
        "show_humidity", "show_wind", "show_forecast",
    ):
        block[key] = bool(block.get(key, True))
    block["forecast_days"] = _clamp_int(block.get("forecast_days"), 0, 7, 3)
    return block


def _validate_widget_visualizer(block: dict) -> dict:
    style = str(block.get("style", "bars"))
    block["style"] = style if style in VISUALIZER_STYLES else "bars"
    block["bars"] = _clamp_int(block.get("bars"), 8, 256, 48)
    block["sensitivity"] = _clamp_float(block.get("sensitivity"), 0.1, 4.0, 1.0)
    block["smoothing"] = _clamp_float(block.get("smoothing"), 0.0, 0.95, 0.6)
    color_mode = str(block.get("color_mode", "gradient"))
    block["color_mode"] = (
        color_mode if color_mode in VISUALIZER_COLOR_MODES else "gradient"
    )
    for key in ("color", "gradient_from", "gradient_to"):
        block[key] = _str_field(block.get(key))
    block["peak_dots"] = bool(block.get("peak_dots", True))
    orientation = str(block.get("orientation", "horizontal"))
    block["orientation"] = "vertical" if orientation == "vertical" else "horizontal"
    block["fps"] = _clamp_int(block.get("fps"), 15, 120, 60)
    block["source"] = "synthetic" if str(block.get("source")) == "synthetic" else "cava"
    block["cava_binary"] = _str_field(block.get("cava_binary") or "cava")
    return block


def _normalize_width(value) -> str:
    """Return a canonical width: an int px string or a clamped "NN%" string."""
    if isinstance(value, (int, float)):
        return str(max(0, int(value)))
    value = str(value).strip()
    if value.endswith("%"):
        try:
            pct = max(0.0, min(100.0, float(value[:-1].strip())))
        except ValueError:
            log.warning("Bad width %r, using 100%%", value)
            return "100%"
        return f"{int(round(pct))}%"
    try:
        return str(max(0, int(value)))
    except ValueError:
        log.warning("Bad width %r, using 100%%", value)
        return "100%"


def _normalize_layout(raw: dict, valid: dict) -> dict:
    """Return a sanitized layout dict.

    If the user config carries an explicit ``layout``, sanitize it (known ids,
    no duplicates) and leave modules the user omitted out — the bar menu can
    add them back. Otherwise migrate the legacy ``*.enabled`` flags into a
    layout so existing configs keep their visible modules.
    """
    user_layout = raw.get("layout")
    if isinstance(user_layout, dict):
        seen: list[str] = []
        layout: dict[str, list[str]] = {}
        for section in ("left", "center", "right"):
            cleaned: list[str] = []
            for mid in user_layout.get(section) or []:
                if mid in MODULE_IDS and mid not in seen:
                    cleaned.append(mid)
                    seen.append(mid)
            layout[section] = cleaned
        return layout

    layout = {"left": [], "center": [], "right": []}
    center = valid.get("center") or {}
    workspaces = valid.get("workspaces") or {}
    clock = valid.get("clock") or {}
    sysmon = valid.get("sysmon") or {}
    tray = valid.get("tray") or {}
    qs = valid.get("quicksettings") or {}
    notif = valid.get("notifications") or {}
    win = valid.get("window") or {}

    if center.get("start_button", True):
        layout["center"].append("start_button")
    ql = valid.get("quicklinks") or {}
    if ql.get("enabled", True):
        layout["left"].append("quicklinks")
    if workspaces.get("enabled", True):
        layout["center"].append("workspaces")
    layout["center"].append("tasklist")
    if win.get("enabled", True):
        layout["center"].append("window")
    if sysmon.get("enabled", True):
        layout["right"].append("sysmon")
    if clock.get("enabled", True):
        layout["right"].append("clock")
    if notif.get("enabled", True):
        layout["right"].append("notifications")
    if tray.get("enabled", True):
        layout["right"].append("tray")
    if qs.get("enabled", True):
        layout["right"].append("quicksettings")
    return layout


def _write_config(path: Path, data: dict) -> None:
    """Atomic write: tmp + os.replace, so a crash can't truncate the file."""
    tmp = path.with_name(path.name + ".tmp")
    try:
        tmp.write_text(json.dumps(data, indent=2) + "\n")
        os.replace(tmp, path)
    finally:
        try:
            tmp.unlink()
        except OSError:
            pass


def _backup_last_good() -> None:
    """Snapshot the current config.json as the recovery point."""
    try:
        if CONFIG_PATH.is_file():
            import shutil
            shutil.copy2(CONFIG_PATH, CONFIG_BAK_PATH)
    except OSError:
        pass


def load() -> dict:
    """Load config, restoring the last-good backup when the live one is lost.

    The live config is never silently replaced by defaults: if it is missing
    (e.g. lost during an interrupted update) or unreadable, the most recent
    ``config.json.bak`` is restored first, so customisations survive a bar
    update. Only a truly first run (no config and no backup) writes defaults.
    """
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    if not CONFIG_PATH.is_file():
        if CONFIG_BAK_PATH.is_file():
            try:
                backup = json.loads(CONFIG_BAK_PATH.read_text())
            except (json.JSONDecodeError, OSError):
                backup = None
            if backup is not None and isinstance(backup, dict):
                log.warning("config.json missing; restoring last-good backup")
                _write_config(CONFIG_PATH, backup)
                return validate(backup)
        # True first run: write defaults, then seed the backup too.
        save(DEFAULTS)
        _backup_last_good()
        return dict(DEFAULTS)

    try:
        raw = json.loads(CONFIG_PATH.read_text())
    except (json.JSONDecodeError, OSError) as exc:
        log.warning("config unreadable (%s); restoring last-good backup", exc)
        if CONFIG_BAK_PATH.is_file():
            try:
                backup = json.loads(CONFIG_BAK_PATH.read_text())
            except (json.JSONDecodeError, OSError):
                backup = None
            if backup is not None and isinstance(backup, dict):
                # Preserve the broken file for inspection, then restore.
                try:
                    os.replace(CONFIG_PATH, CONFIG_DIR / "config.json.corrupt")
                except OSError:
                    pass
                _write_config(CONFIG_PATH, backup)
                return validate(backup)
        return dict(DEFAULTS)

    # Keep a rolling last-good snapshot on every successful read.
    _backup_last_good()
    return validate(raw)


def save(cfg: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    # Keep the current config as the last-good backup before overwriting, then
    # write atomically. A failed/corrupt write is therefore always recoverable.
    _backup_last_good()
    try:
        _write_config(CONFIG_PATH, cfg)
    except OSError:
        log.warning("failed to save config")


def load_pywal_colors() -> dict | None:
    """Read ~/.cache/wal/colors.json; returns color map or None if unavailable."""
    try:
        data = json.loads(PYWAL_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    out = dict(data.get("colors") or {})
    special = data.get("special") or {}
    out["background"] = special.get("background")
    out["foreground"] = special.get("foreground")
    return out or None


def icon_size_for(font_size, icon_size=0) -> int:
    """Derive a module-icon pixel size.

    ``icon_size`` > 0 is used verbatim (manual override); otherwise the icon
    scales with the bar's base font size.
    """
    try:
        icon_size = int(icon_size)
    except (TypeError, ValueError):
        icon_size = 0
    if icon_size > 0:
        return max(8, icon_size)
    try:
        return max(8, int(round(int(font_size) * 1.25)))
    except (TypeError, ValueError):
        return 20