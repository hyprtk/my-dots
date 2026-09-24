"""Clock theme files: appearance presets for the clock desktop widget.

A clock theme is a small JSON file (``*.json``) that sets the clock's look —
``style`` (``digital`` / ``text`` / ``dials``), formats, fonts, colours and the
per-style tuning (``digital`` / ``text`` / ``dials`` sub-blocks). Themes are
loaded from the user directory first, then the bundled ones shipped with the
bar; a theme's values are overridden by the widget's own config block, so the
settings window always wins over the file.

Directories (highest priority first):
- ``~/.config/hyprtk-bar/widget-themes/clock/`` (user themes)
- ``<install>/assets/widgets/clock/`` (bundled, incl. ``default.json``)
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.clock_theme
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import json
import logging
from pathlib import Path

from ..config import DEFAULT_CLOCK_THEME, INSTALL_DIR

log = logging.getLogger("hyprtk_bar.desktop.clock_theme")

BUNDLED_DIR = INSTALL_DIR / "assets" / "widgets" / "clock"
USER_DIR = Path.home() / ".config" / "hyprtk-bar" / "widget-themes" / "clock"


def _search_dirs() -> list[Path]:
    return [d for d in (USER_DIR, BUNDLED_DIR) if d.is_dir()]


def list_clock_themes() -> list[str]:
    """Theme names available to pick from (user themes shadow bundled ones)."""
    names: list[str] = []
    for directory in _search_dirs():
        for path in sorted(directory.glob("*.json")):
            if path.stem not in names:
                names.append(path.stem)
    return names


def find_clock_theme(name: str) -> Path | None:
    """Resolve a theme name to a file, guarding against path traversal."""
    safe = Path(str(name)).name
    if not safe:
        return None
    for directory in _search_dirs():
        candidate = directory / f"{safe}.json"
        if candidate.is_file():
            return candidate
    return None


def load_clock_theme(name: str) -> dict:
    """Load a clock theme merged over the built-in defaults.

    A missing/corrupt file yields the defaults (plus a warning), so a bad theme
    never blanks the clock.
    """
    from ..config import _deep_merge

    theme = dict(DEFAULT_CLOCK_THEME)
    path = find_clock_theme(name)
    if path is None:
        return theme
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        log.warning("could not read clock theme %r: %s", name, exc)
        return theme
    if not isinstance(data, dict):
        return theme
    return _deep_merge(theme, data)


def save_clock_theme(name: str, data: dict) -> bool:
    """Write a user clock theme (used by the settings window's export, if any)."""
    safe = Path(str(name)).name
    if not safe:
        return False
    try:
        USER_DIR.mkdir(parents=True, exist_ok=True)
        (USER_DIR / f"{safe}.json").write_text(json.dumps(data, indent=2) + "\n")
        return True
    except OSError:
        log.warning("could not save clock theme %r", name, exc_info=True)
        return False
