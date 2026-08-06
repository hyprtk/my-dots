from __future__ import annotations

import re
from pathlib import Path

from . import paths


def parse_wal_colors() -> dict[str, str]:
    """Parse ~/.cache/wal/colors.sh into {color0..color15, background, foreground, cursor, wallpaper}."""
    result: dict[str, str] = {}
    # colors.sh has key=value format; colors file has raw hex only
    wal_sh = paths.WAL_CACHE / "colors.sh"
    wal_file = wal_sh if wal_sh.exists() else paths.WAL_COLORS
    if not wal_file.exists():
        return result
    for line in wal_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            key, _, val = line.partition("=")
            result[key.strip()] = val.strip().strip("'\"")
    return result


def hex_to_rgba(hex_color: str, alpha: int = 255) -> str:
    """Convert #RRGGBB or #RRGGBBAA to rgba() string."""
    h = hex_color.lstrip("#")
    if len(h) == 6:
        r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        return f"rgba({r},{g},{b},{alpha / 255:.2f})"
    if len(h) == 8:
        r, g, b, a = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), int(h[6:8], 16)
        return f"rgba({r},{g},{b},{a / 255:.2f})"
    return hex_color


def hex_to_gdk_rgba(hex_color: str) -> str:
    """Convert #RRGGBB to #RRGGBBFF (GDK4 format)."""
    h = hex_color.lstrip("#")
    if len(h) == 6:
        return f"#{h}FF"
    return hex_color


def strip_hex(hex_color: str) -> str:
    """Remove alpha from hex: #RRGGBBAA -> #RRGGBB."""
    h = hex_color.lstrip("#")
    if len(h) == 8:
        return f"#{h[:6]}"
    return hex_color


def get_color_name(index: int) -> str:
    names = [
        "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
        "bright-black", "bright-red", "bright-green", "bright-yellow",
        "bright-blue", "bright-magenta", "bright-cyan", "bright-white",
    ]
    return names[index] if 0 <= index < len(names) else f"color{index}"


def read_swaylock_config() -> dict[str, str]:
    """Parse swaylock config into {key: value} dict."""
    result: dict[str, str] = {}
    if not paths.SWAYLOCK_CONFIG.exists():
        return result
    for line in paths.SWAYLOCK_CONFIG.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            key, _, val = line.partition("=")
            result[key.strip()] = val.strip()
    return result


def write_swaylock_config(data: dict[str, str]):
    """Write swaylock config from dict."""
    paths.SWAYLOCK_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    for key, val in data.items():
        lines.append(f"{key}={val}")
    paths.SWAYLOCK_CONFIG.write_text("\n".join(lines) + "\n")


def parse_waybar_theme_style(style_path: Path) -> str:
    """Read a waybar style.css and return its content."""
    if style_path.exists():
        return style_path.read_text()
    return ""
