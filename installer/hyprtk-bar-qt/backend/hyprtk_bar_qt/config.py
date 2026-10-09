"""Reading the pywal palette (toolkit-free)."""

from __future__ import annotations

import json
from pathlib import Path

PYWAL_PATH = Path.home() / ".cache" / "wal" / "colors.json"


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
