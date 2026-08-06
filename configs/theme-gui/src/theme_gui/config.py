import json
from pathlib import Path

from . import paths

_DEFAULTS = {
    "last_page": "wallpaper",
    "window_width": 1100,
    "window_height": 700,
    "wallpaper_dir": str(Path.home() / "Pictures" / "Wallpapers"),
    "pywal_backend": "wal",
}


def _ensure():
    paths.THEME_GUI_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    if not paths.THEME_GUI_CONFIG.exists():
        paths.THEME_GUI_CONFIG.write_text(json.dumps(_DEFAULTS, indent=2))


def load() -> dict:
    _ensure()
    try:
        data = json.loads(paths.THEME_GUI_CONFIG.read_text())
    except (json.JSONDecodeError, OSError):
        data = {}
    merged = {**_DEFAULTS, **data}
    return merged


def save(data: dict):
    _ensure()
    paths.THEME_GUI_CONFIG.write_text(json.dumps(data, indent=2))
