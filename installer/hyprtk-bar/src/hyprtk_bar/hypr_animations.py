"""Hyprland border animation mirror for the bar.

The bar's border is normally a static accent color. Hyprland itself animates
window borders (``border`` / ``borderangle`` leaves) and the speed/style of
those animations is chosen at runtime by which animations file is enabled in
``hyprland.lua`` (``animations-high`` vs ``animations-low``). This module
mirrors that decision so the bar border animates at the same pace.

The active animations file is detected by reading ``hyprland.lua`` for a
non-commented ``require("animations-...")``; the file's ``border`` and
``borderangle`` ``hl.animation`` blocks supply the speed. Pure stdlib — no
GTK, so it is trivially testable.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · hypr_animations
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import re
from pathlib import Path

log = logging.getLogger("hyprtk_bar.hypr_animations")

HYPR_DIRS = (
    Path.home() / ".config" / "hypr",
    Path.home() / "hyprtk" / "hypr",
)

_ANIM_BLOCK = re.compile(r"hl\.animation\(\{(.*?)\}\)", re.DOTALL)
_REQ = re.compile(r'require\(\s*["\']animations-([\w-]+)["\']\s*\)')
_ANIM_ENABLED = re.compile(r"animations\s*=\s*\{\s*enabled\s*=\s*(true|false)", re.DOTALL)


def _find_hypr_dir() -> Path | None:
    for d in HYPR_DIRS:
        if (d / "hyprland.lua").is_file():
            return d
    return None


def active_animations_file() -> str | None:
    """Name of the animations file Hyprland loads (``high``/``low``/None).

    ``hyprland.lua`` lists the files via ``require("animations-...")`` with the
    inactive one commented out; the first non-comment require wins.
    """
    d = _find_hypr_dir()
    if d is None:
        return None
    try:
        text = (d / "hyprland.lua").read_text()
    except OSError:
        return None
    for line in text.splitlines():
        if line.lstrip().startswith("--"):
            continue
        m = _REQ.search(line)
        if m:
            return m.group(1).lower()
    return None


def _parse_animations(path: Path) -> dict:
    """Parse ``hl.animation`` blocks into {leaf: {enabled, speed, bezier, style}}."""
    try:
        text = path.read_text()
    except OSError:
        return {}
    out: dict = {}
    for block in _ANIM_BLOCK.finditer(text):
        body = block.group(1)
        leaf_m = re.search(r'leaf\s*=\s*["\']([\w]+)["\']', body)
        if not leaf_m:
            continue
        leaf = leaf_m.group(1)
        speed = re.search(r"speed\s*=\s*(\d+)", body)
        enabled = re.search(r"enabled\s*=\s*(true|false)", body)
        bezier = re.search(r'bezier\s*=\s*["\']([\w]+)["\']', body)
        style = re.search(r'style\s*=\s*["\']([\w %]+)["\']', body)
        out[leaf] = {
            "enabled": (enabled.group(1) if enabled else "true") == "true",
            "speed": int(speed.group(1)) if speed else None,
            "bezier": bezier.group(1) if bezier else None,
            "style": style.group(1) if style else None,
        }
    return out


def border_animation(cfg: dict | None = None) -> dict | None:
    """Border animation mirror for the bar, or None when disabled.

    ``cfg`` selects the mode via ``animations.mode``:
    - ``"low"`` / ``"high"`` — read the matching ``animations-<mode>.lua``
      file's ``borderangle``/``border`` speed, so the bar animates at that
      Hyprland preset's pace.
    - ``"custom"`` — use ``animations.speed`` directly, independent of the
      hypr config.

    Returns ``{"speed": int, "leaf": str, "mode": str}`` or None when the
    relevant file is unavailable, animations are disabled there, or a custom
    speed is missing/invalid.
    """
    mode = "high"
    if cfg is not None:
        mode = str((cfg.get("animations") or {}).get("mode") or "high").lower()
        if mode == "custom":
            try:
                speed = max(1, int((cfg.get("animations") or {}).get("speed")))
            except (TypeError, ValueError):
                speed = None
            if not speed:
                return None
            return {"leaf": "custom", "speed": speed, "mode": "custom"}
    if mode in ("low", "high"):
        return _file_border_animation(mode)
    return None


def _load_bar_config() -> dict:
    """Read the bar config file (best effort) into a dict."""
    import json

    try:
        data = json.loads((Path.home() / ".config" / "hyprtk-bar" / "config.json").read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def border_period_ms(cfg: dict | None = None) -> int | None:
    """Bar border-animation period in ms, or None when border animation is off.

    Mirrors ``border_animation`` but returns the loop period Hyprland uses
    (``speed * 100`` ms per loop, clamped to a 200 ms floor). When ``cfg`` is
    omitted the bar config file is read. Returns None when animations are
    disabled, ``theme.border_animation`` is off, or the preset/custom speed is
    unavailable.
    """
    if cfg is None:
        cfg = _load_bar_config()
    if not (cfg.get("theme") or {}).get("border_animation", True):
        return None
    info = border_animation(cfg)
    if info is None or not info.get("speed"):
        return None
    return max(200, int(info["speed"] * 100))


def _file_border_animation(name: str) -> dict | None:
    """Border mirror config from a specific ``animations-<name>.lua`` file."""
    d = _find_hypr_dir()
    if d is None:
        return None
    path = d / f"animations-{name}.lua"
    if not path.is_file():
        return None
    anims = _parse_animations(path)
    # Respect a global ``animations.enabled = false`` in the same file.
    try:
        text = path.read_text()
    except OSError:
        text = ""
    m = _ANIM_ENABLED.search(text)
    if m and m.group(1) == "false":
        return None
    # The looping gradient border is ``borderangle``; ``border`` is the
    # active/inactive color transition. Prefer borderangle's speed.
    for leaf in ("borderangle", "border"):
        info = anims.get(leaf)
        if info and info.get("enabled") and info.get("speed"):
            return {"leaf": leaf, "speed": int(info["speed"]), "mode": name}
    return None


# ── active border colours (mirrors Hyprland's window.lua) ───────

def active_border_colors() -> tuple[str, str] | None:
    """The two ``active_border`` colours Hyprland uses, as ``#rrggbb``.

    ``window.lua`` reads ``~/.cache/wal/colors-hyprland.lua`` and sets
    ``active_border = { color11, color4 }``. The borderangle loop rotates the
    gradient between exactly these two colours — return them (hex, ``#``
    prefixed) or None when the palette is unavailable.
    """
    import json

    try:
        data = json.loads((Path.home() / ".cache" / "wal" / "colors.json").read_text())
    except (OSError, json.JSONDecodeError):
        return None
    colors = data.get("colors") or {}
    c1 = colors.get("color11")
    c2 = colors.get("color4")
    if not c1 or not c2:
        return None
    def _norm(c: str) -> str:
        c = c.strip()
        return c if c.startswith("#") else f"#{c}"
    return _norm(c1), _norm(c2)


def lerp_color(c1: str, c2: str, t: float) -> str:
    """Linear interpolation between two ``#rrggbb`` colours (t in 0..1)."""
    def _rgb(c: str) -> tuple[int, int, int]:
        h = c.lstrip("#")
        if len(h) == 3:
            h = "".join(ch * 2 for ch in h)
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    try:
        r1, g1, b1 = _rgb(c1)
        r2, g2, b2 = _rgb(c2)
    except ValueError:
        return c1
    t = max(0.0, min(1.0, t))
    return "#{:02x}{:02x}{:02x}".format(
        int(round(r1 + (r2 - r1) * t)),
        int(round(g1 + (g2 - g1) * t)),
        int(round(b1 + (b2 - b1) * t)),
    )