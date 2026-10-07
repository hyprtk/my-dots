"""The hyprtk palette, resolved from the running hyprtk-bar theme.

Mirrors ``hyprtk_usb.ui`` (and, beneath it, the bar's own ``resolve_palette``),
so the ISO Creator's GTK window matches the rest of the desktop: a pywal-driven
dark panel with mauve (color5) accents and cyan (color6) surface tints.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass


@dataclass
class Palette:
    accent: str = "#c084fc"   # mauve (color5)
    accent2: str = "#22d3ee"  # sky (color6)
    fg: str = "#e5e7eb"       # foreground
    dim: str = "#6b7280"      # muted foreground
    bg: str = "#1e1e2e"       # background
    err: str = "#f38ba8"      # color1
    warn: str = "#f9e2af"     # color3
    opacity: float = 0.92     # panel background alpha (the bar's `opacity`)
    theme_name: str = ""      # active hyprtk-bar theme profile
    source: str = "pywal"     # hyprtk-bar theme source


def _read_json(path: str) -> dict:
    try:
        with open(path) as f:
            return json.load(f) or {}
    except Exception:
        return {}


def load_palette() -> Palette:
    home = os.path.expanduser("~")
    p = Palette()
    bar = _read_json(os.path.join(home, ".config", "hyprtk-bar", "config.json"))
    theme = bar.get("theme") or {}
    source = str(theme.get("source") or "pywal")
    wal = _read_json(os.path.join(home, ".cache", "wal", "colors.json"))
    # pywal16's colors.json is nested: {special: {...}, colors: {color0..15}}.
    wal_colors = wal.get("colors") or {}
    wal_special = wal.get("special") or {}

    def color(key: str, fallback: str) -> str:
        v = wal_colors.get(key)
        return v if isinstance(v, str) and v.strip() else fallback

    def special(key: str, fallback: str) -> str:
        v = wal_special.get(key)
        return v if isinstance(v, str) and v.strip() else fallback

    p.bg = theme.get("background") or p.bg
    p.fg = theme.get("foreground") or p.fg
    p.accent = theme.get("accent") or p.accent

    if source == "pywal":
        p.bg = special("background", p.bg)
        p.fg = special("foreground", p.fg)
        p.accent = color("color5", color("color4", p.accent))

    p.accent2 = color("color6", p.accent2)
    p.err = color("color1", p.err)
    p.warn = color("color3", p.warn)
    p.dim = color("color8", p.dim)
    try:
        p.opacity = float(bar.get("opacity", p.opacity))
    except (TypeError, ValueError):
        pass
    p.theme_name = str(theme.get("theme_name") or "")
    p.source = source
    return p


def human_bytes(n: float) -> str:
    step = float(1024)
    val = float(n)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(val) < step:
            return f"{val:.0f} {unit}" if unit == "B" else f"{val:.1f} {unit}"
        val /= step
    return f"{val:.1f} PiB"
