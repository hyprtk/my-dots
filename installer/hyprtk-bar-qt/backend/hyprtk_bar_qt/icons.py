"""Papirus folder-colour state + presets, for the Qt themer Icons page.

Mirrors the GTK bar's icons page: detect the current Papirus-Dark folder colour,
list the 25 colour presets (with their folder SVGs), apply a preset or custom
hex via ``papirus-folders``, and run the pywal auto-match script.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
try:
    from .paths import QT_SCRIPTS
except ImportError:  # run as a script (python3 icons.py)
    from paths import QT_SCRIPTS
ICON_THEME_DIR = HOME / ".local" / "share" / "icons" / "Papirus-Dark" / "48x48" / "places"
PAPIRUS_FOLDERS = HOME / ".local" / "bin" / "papirus-folders"
PAPIRUS_FOLDERS_SH = HOME / ".local" / "share" / "icons" / "papirus-folders.sh"
CHANGE_ICONS_SH = QT_SCRIPTS / "change-icons.sh"

# (display label, papirus colour name) — mirrors the GTK bar's _COLOR_PRESETS.
PRESETS = [
    ("Adwaita", "adwaita"), ("Black", "black"), ("Blue", "blue"),
    ("Bluegrey", "bluegrey"), ("Breeze", "breeze"), ("Brown", "brown"),
    ("Carmine", "carmine"), ("Cyan", "cyan"), ("Darkcyan", "darkcyan"),
    ("Deeporange", "deeporange"), ("Green", "green"), ("Grey", "grey"),
    ("Indigo", "indigo"), ("Magenta", "magenta"), ("Nordic", "nordic"),
    ("Orange", "orange"), ("Palebrown", "palebrown"), ("Paleorange", "paleorange"),
    ("Pink", "pink"), ("Red", "red"), ("Teal", "teal"), ("Violet", "violet"),
    ("White", "white"), ("Yaru", "yaru"), ("Yellow", "yellow"),
]

# Preview folders (suffix, label) — mirrors the GTK bar's _PREVIEW_ICONS.
PREVIEW = [
    ("desktop", "Desktop"), ("documents", "Documents"), ("downloads", "Downloads"),
    ("music", "Music"), ("pictures", "Pictures"), ("projects", "Projects"),
    ("videos", "Videos"),
]

_HEX_RE = re.compile(r"^#?([0-9a-fA-F]{6})$")


def _folder_svg(color: str, suffix: str) -> str:
    """Path to ``folder-<color>-<suffix>.svg`` (falls back to folder-<suffix>)."""
    base = ICON_THEME_DIR
    for name in (f"folder-{color}-{suffix}.svg", f"folder-{suffix}.svg"):
        p = base / name
        if p.is_file():
            return str(p)
    return ""


def current() -> str:
    """Current Papirus-Dark folder colour name (or '' if unknown)."""
    folder = ICON_THEME_DIR / "folder.svg"
    try:
        if folder.is_symlink():
            target = os.path.basename(os.readlink(folder))
            stem = target[:-4] if target.endswith(".svg") else target
            if stem.startswith("folder-"):
                stem = stem[len("folder-"):]
            return stem
    except OSError:
        pass
    for _label, color in PRESETS:
        if (ICON_THEME_DIR / f"folder-{color}-pictures.svg").is_file():
            return color
    return ""


def presets() -> list[dict]:
    out = []
    for label, color in PRESETS:
        out.append({
            "name": color,
            "label": label,
            "svg": _folder_svg(color, "pictures"),
        })
    return out


def preview(color: str = "") -> list[dict]:
    c = color or current()
    out = []
    for suffix, label in PREVIEW:
        out.append({"label": label, "svg": _folder_svg(c, suffix)})
    return out


def _papirus_cmd() -> list[str] | None:
    if PAPIRUS_FOLDERS_SH.is_file():
        return ["bash", str(PAPIRUS_FOLDERS_SH)]
    if PAPIRUS_FOLDERS.is_file():
        return [str(PAPIRUS_FOLDERS)]
    return None


def _run_papirus(*args: str) -> bool:
    cmd = _papirus_cmd()
    if cmd is None:
        return False
    try:
        subprocess.Popen(cmd + list(args), start_new_session=True)
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def apply_preset(color: str) -> bool:
    if not color:
        return False
    return _run_papirus("-C", color, "-t", "Papirus-Dark")


def apply_hex(value: str) -> bool:
    m = _HEX_RE.match(str(value or "").strip())
    if not m:
        return False
    return _run_papirus("-C", m.group(1), "--theme", "Papirus-Dark")


def auto() -> bool:
    if not CHANGE_ICONS_SH.is_file():
        return False
    try:
        subprocess.Popen(["bash", str(CHANGE_ICONS_SH)], start_new_session=True)
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="papirus folder-colour state")
    sub = ap.add_subparsers(dest="action", required=True)
    sub.add_parser("current")
    sub.add_parser("presets")
    sub.add_parser("preview")
    p_preset = sub.add_parser("apply-preset")
    p_preset.add_argument("color")
    p_hex = sub.add_parser("apply-hex")
    p_hex.add_argument("hex")
    sub.add_parser("auto")
    args = ap.parse_args(argv)

    if args.action == "current":
        c = current()
        print(json.dumps({"color": c, "preview": preview(c)}))
        return 0
    if args.action == "presets":
        print(json.dumps({"presets": presets()}))
        return 0
    if args.action == "preview":
        print(json.dumps({"preview": preview()}))
        return 0
    if args.action == "apply-preset":
        ok = apply_preset(args.color)
    elif args.action == "apply-hex":
        ok = apply_hex(args.hex)
    else:
        ok = auto()
    print(json.dumps({"ok": bool(ok)}))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
