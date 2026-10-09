"""Hyprland border-animation mirror for the bar (toolkit-free).

Ported from the GTK bar's ``hypr_animations.py``: reads the active
``animations-<mode>.lua`` (selected in ``hyprland.lua``) for its ``border`` /
``borderangle`` speed so the bar border animates at the same pace, or uses a
custom speed. ``python3 hypr_animations.py period`` prints
``{"period_ms": int|null}``.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

try:
    from .paths import QT_CONFIG
except ImportError:  # run as a script (python3 hypr_animations.py)
    from paths import QT_CONFIG

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
        out[leaf] = {
            "enabled": (enabled.group(1) if enabled else "true") == "true",
            "speed": int(speed.group(1)) if speed else None,
        }
    return out


def _file_border_animation(name: str) -> dict | None:
    d = _find_hypr_dir()
    if d is None:
        return None
    path = d / f"animations-{name}.lua"
    if not path.is_file():
        return None
    try:
        text = path.read_text()
    except OSError:
        text = ""
    m = _ANIM_ENABLED.search(text)
    if m and m.group(1) == "false":
        return None
    anims = _parse_animations(path)
    for leaf in ("borderangle", "border"):
        info = anims.get(leaf)
        if info and info.get("enabled") and info.get("speed"):
            return {"leaf": leaf, "speed": int(info["speed"]), "mode": name}
    return None


def border_animation(cfg: dict) -> dict | None:
    mode = str((cfg.get("animations") or {}).get("mode") or "high").lower()
    if mode == "custom":
        try:
            speed = max(1, int((cfg.get("animations") or {}).get("speed")))
        except (TypeError, ValueError):
            speed = None
        if not speed:
            return None
        return {"leaf": "custom", "speed": speed, "mode": "custom"}
    return _file_border_animation(mode) if mode in ("low", "high") else None


def _load_bar_config() -> dict:
    try:
        data = json.loads(QT_CONFIG.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def border_period_ms(cfg: dict | None = None) -> int | None:
    if cfg is None:
        cfg = _load_bar_config()
    if not (cfg.get("theme") or {}).get("border_animation", True):
        return None
    info = border_animation(cfg)
    if info is None or not info.get("speed"):
        return None
    return max(200, int(info["speed"] * 100))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Hyprland border-animation mirror")
    ap.add_argument("action", choices=("period", "mode", "colors", "border-size"))
    args = ap.parse_args(argv)

    if args.action == "period":
        print(json.dumps({"period_ms": border_period_ms()}))
    elif args.action == "mode":
        print(json.dumps({"file": active_animations_file()}))
    elif args.action == "border-size":
        print(json.dumps({"border_size": _border_size()}))
    else:
        print(json.dumps({"colors": _active_border_colors()}))
    return 0


def _active_border_colors() -> list[str] | None:
    try:
        data = json.loads((Path.home() / ".cache" / "wal" / "colors.json").read_text())
    except (OSError, json.JSONDecodeError):
        return None
    colors = data.get("colors") or {}
    c1, c2 = colors.get("color11"), colors.get("color4")
    if not c1 or not c2:
        return None
    norm = lambda c: c.strip() if str(c).startswith("#") else f"#{c}"
    return [norm(c1), norm(c2)]


def _border_size() -> int:
    try:
        out = subprocess.run(["hyprctl", "-j", "getoption", "general:border_size"],
                             capture_output=True, text=True, timeout=2)
        return max(1, int(json.loads(out.stdout).get("int", 2)))
    except (OSError, subprocess.SubprocessError, ValueError, TypeError):
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
