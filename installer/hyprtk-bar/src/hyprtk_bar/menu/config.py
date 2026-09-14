"""Configuration for the in-bar menu (hyprtk-menu merged into hyprtk-bar).

The menu's settings now live inside the bar's config under a ``menu`` block
(the bar is the owning process). This module reads/writes that block so the
menu shares the bar's config file instead of its own ``~/.config/hyprtk-menu``.

When the bar process runs, ``set_bar_cfg()`` is given the bar's in-memory
config dict so the menu sees the same (possibly freshly migrated) ``menu``
block the bar uses — never a stale file read.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · config
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────


import json
import os
import tempfile
from copy import deepcopy

BAR_CONFIG_FILE = os.path.expanduser("~/.config/hyprtk-bar/config.json")
BAR_THEMES_DIR = os.path.expanduser("~/.config/hyprtk-bar/themes")
PYWAL_PATH = os.path.expanduser("~/.cache/wal/colors.json")

LAYOUTS = ("whisker", "win7", "win11", "plasma")

# In-memory bar config (set by the bar process). Falls back to the file.
_bar_cfg: dict | None = None


def set_bar_cfg(cfg: dict) -> None:
    global _bar_cfg
    _bar_cfg = cfg


DEFAULT_CONFIG = {
    "position": "auto",
    "align": "left",
    "follow_bar": True,   # mirror the bar's palette (glass + text); off = menu's own pywal
    "gap_in": 4,     # gap between the menu and the bar when following it (px)
    "gap_out": 5,    # gap between the menu and the screen edge (px)
    "layout": "whisker",
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
}


def _read_bar_config():
    if isinstance(_bar_cfg, dict):
        return _bar_cfg
    try:
        with open(BAR_CONFIG_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def load_config():
    """Load the menu block from the bar config, deep-merging with defaults."""
    config = deepcopy(DEFAULT_CONFIG)
    bar = _read_bar_config()
    if not isinstance(bar, dict):
        return config
    data = bar.get("menu")
    if not isinstance(data, dict):
        return config
    for key, value in data.items():
        config[key] = value
    power = data.get("power")
    if isinstance(power, dict):
        config["power"].update(power)
    return config


def save_config(config):
    """Write the menu block back into the bar config.

    When running inside the bar, route through the bar's own config.save() so
    the last-good backup (config.json.bak) is kept and validation runs — a
    single write path for the file instead of two competing ones. Falls back
    to an atomic write when used standalone.
    """
    # Update the in-memory bar dict in place (the bar reads from it live).
    if isinstance(_bar_cfg, dict):
        _bar_cfg["menu"] = config
    try:
        from .. import config as bar_config
        bar_config.save(_bar_cfg if isinstance(_bar_cfg, dict) else bar_config.load())
        return
    except Exception:
        pass
    bar = _read_bar_config()
    if not isinstance(bar, dict):
        bar = {}
    bar["menu"] = config
    os.makedirs(os.path.dirname(BAR_CONFIG_FILE), exist_ok=True)
    try:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(BAR_CONFIG_FILE),
                                   prefix=".config.", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(bar, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, BAR_CONFIG_FILE)
    except OSError:
        try:
            os.unlink(tmp)
        except (OSError, UnboundLocalError):
            pass


def load_bar_theme() -> dict:
    """The bar's ``theme`` block (source + theme_name + manual colors)."""
    bar = _read_bar_config()
    if not isinstance(bar, dict):
        return {}
    theme = bar.get("theme")
    return theme if isinstance(theme, dict) else {}


def load_pywal_colors() -> dict | None:
    """Read ~/.cache/wal/colors.json into a ``{name: hex}`` map, or None.

    Delegates to the top-level config's reader so the two never diverge.
    """
    from .. import config as _bar_config

    return _bar_config.load_pywal_colors()
