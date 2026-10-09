"""Config paths for hyprtk-bar-qt.

The Qt bar keeps its **own** config (``~/.config/hyprtk-bar-qt/config.json``),
separate from the GTK bar (``~/.config/hyprtk-bar/config.json``), which is only read once for migration, so the two bars are fully independent.
bars can be configured independently. ``seed_from_gtk`` migrates an existing
setup: it builds the Qt config from the GTK config and re-applies the Qt-only
keys the Qt bar owns (so a previously-configured Qt bar keeps its overrides).

Toolkit-free; importable both as a package module and when the file is run as a
script (``python3 paths.py``).
"""

from __future__ import annotations

import copy
import json
import os
import tempfile
from pathlib import Path

GTK_CONFIG = Path.home() / ".config" / "hyprtk-bar" / "config.json"
QT_CONFIG = Path.home() / ".config" / "hyprtk-bar-qt" / "config.json"

# The Qt bar owns its own trees (fully separate from the GTK bar):
#   ~/.config/hyprtk-bar-qt     config + themes + widget-themes
#   ~/.local/share/hyprtk-bar-qt  scripts + assets
#   ~/.cache/hyprtk-bar-qt      runtime caches
QT_CONFIG_DIR = QT_CONFIG.parent
QT_DATA = Path.home() / ".local" / "share" / "hyprtk-bar-qt"
QT_SCRIPTS = QT_DATA / "scripts"
QT_ASSETS = QT_DATA / "assets"
QT_CACHE = Path.home() / ".cache" / "hyprtk-bar-qt"
QT_THEMES = QT_CONFIG_DIR / "themes"
QT_WIDGET_THEMES = QT_CONFIG_DIR / "widget-themes"

# Keys the Qt bar owns that are NOT part of the shared GTK bar schema. These are
# carried over from a legacy Qt config when seeding; on a name clash the GTK
# value wins (``opacity``, ``animations``), since the GTK schema is what the bar
# actually renders from.
QT_ONLY_KEYS = (
    "clockFormat", "fontFamily", "fontSize", "animationDuration", "uiAnimations",
    "layoutLeft", "layoutCenter", "layoutRight",
    "wallpaperDir", "themeSource", "themeName", "themeBackground",
    "themeForeground", "themeAccent",
    "quicklinksLinks", "arcMenuPosition", "arcMenuItems", "menuPower",
    "sysmonInterval", "sysmonDataPoints", "sysmonDiskPath",
    "sysmonNetworkIface", "sysmonPages",
)


def _read(path: Path) -> dict:
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _write(path: Path, data: dict) -> bool:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".config.", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
        return True
    except OSError:
        return False


def seed_from_gtk(path: Path = QT_CONFIG) -> bool:
    """Migrate the Qt config from the GTK config.

    Returns True when the Qt config was (re)written. The GTK config supplies the
    full bar schema; any Qt-only keys from an existing legacy Qt config are
    re-applied on top. A Qt config that already carries the schema (has a
    top-level ``position``) is left untouched.
    """
    gtk = _read(GTK_CONFIG)
    if not gtk:
        return False

    existing = _read(path) if path.exists() else {}
    # Already migrated (has the bar schema) -> nothing to do.
    if existing and "position" in existing:
        return False

    merged = copy.deepcopy(gtk)
    for key in QT_ONLY_KEYS:
        if key in existing:
            merged[key] = existing[key]
    return _write(path, merged)


def main() -> int:
    seed_from_gtk()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
