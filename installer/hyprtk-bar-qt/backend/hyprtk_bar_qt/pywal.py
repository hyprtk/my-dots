"""Live pywal palette + saved colour schemes, for the Qt themer.

Reads the 16-colour palette pywal writes to ``~/.cache/wal`` (colors.sh first,
then colors.json) plus the special colours, lists the saved schemes in
``~/.cache/wal/schemes``, and can apply a scheme or re-run wal. Toolkit-free.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
WAL_CACHE = HOME / ".cache" / "wal"
COLORS_SH = WAL_CACHE / "colors.sh"
COLORS_JSON = WAL_CACHE / "colors.json"
SCHEMES_DIR = WAL_CACHE / "schemes"
WAL_FILE = WAL_CACHE / "wal"

# pywal colour0..15 → human names.
NAMES = [
    "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
    "bright black", "bright red", "bright green", "bright yellow",
    "bright blue", "bright magenta", "bright cyan", "bright white",
]

_HEX_RE = re.compile(r"#?([0-9a-fA-F]{6})")


def _norm(value: str) -> str:
    m = _HEX_RE.search(str(value or ""))
    return "#" + m.group(1).lower() if m else ""


def _wal_binary() -> str:
    return os.environ.get("HYPRTK_WAL") or shutil.which("wal") or "wal"


def _from_sh() -> dict:
    """Parse ``key='#hex'`` lines from colors.sh."""
    out: dict[str, str] = {}
    try:
        text = COLORS_SH.read_text()
    except OSError:
        return out
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip().removeprefix("export ").strip()
        val = val.strip().strip('"').strip("'")
        hexv = _norm(val)
        if hexv:
            out[key] = hexv
    return out


def _from_json() -> dict:
    """Parse pywal16's colors.json ({special, colors})."""
    try:
        data = json.loads(COLORS_JSON.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    out: dict[str, str] = {}
    for key, val in (data.get("colors") or {}).items():
        hexv = _norm(val)
        if hexv:
            out[key] = hexv
    for key, val in (data.get("special") or {}).items():
        hexv = _norm(val)
        if hexv:
            out[key] = hexv
    return out


def palette() -> dict:
    """The live palette: ``colors`` (16), ``names``, and special colours."""
    raw = _from_sh() or _from_json()
    colors = [raw.get(f"color{i}", "") for i in range(16)]
    return {
        "colors": colors,
        "names": NAMES,
        "background": raw.get("background", ""),
        "foreground": raw.get("foreground", ""),
        "cursor": raw.get("cursor", ""),
        "wallpaper": current_wallpaper() or "",
    }


def current_wallpaper() -> str | None:
    try:
        val = WAL_FILE.read_text().strip()
    except OSError:
        return None
    return val or None


def schemes(limit: int = 30) -> list[dict]:
    """Saved pywal schemes, sorted by filename (first ``limit``)."""
    try:
        entries = sorted(SCHEMES_DIR.iterdir())
    except OSError:
        return []
    out = []
    for p in entries:
        if p.is_file():
            name = p.name
            if name.endswith(".json"):
                name = name[:-5]
            out.append({"name": name, "path": str(p)})
        if len(out) >= limit:
            break
    return out


def apply_scheme(path: str) -> bool:
    if not path or not os.path.isfile(path):
        return False
    try:
        subprocess.Popen([_wal_binary(), "--theme", path], start_new_session=True)
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def rerun(directory: str = "") -> bool:
    """Re-run wal on a directory (or the current wallpaper with ``-R``)."""
    wal = _wal_binary()
    try:
        if directory and os.path.isdir(os.path.expanduser(directory)):
            subprocess.Popen([wal, "-i", os.path.expanduser(directory)], start_new_session=True)
        else:
            subprocess.Popen([wal, "-R", "-q"], start_new_session=True)
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="pywal palette + schemes")
    sub = ap.add_subparsers(dest="action", required=True)
    sub.add_parser("palette")
    sub.add_parser("schemes")
    sub.add_parser("current")
    p_scheme = sub.add_parser("apply-scheme")
    p_scheme.add_argument("path")
    p_rerun = sub.add_parser("rerun")
    p_rerun.add_argument("directory", nargs="?", default="")
    args = ap.parse_args(argv)

    if args.action == "palette":
        print(json.dumps(palette()))
        return 0
    if args.action == "schemes":
        print(json.dumps({"schemes": schemes()}))
        return 0
    if args.action == "current":
        print(json.dumps({"current": current_wallpaper()}))
        return 0
    if args.action == "apply-scheme":
        ok = apply_scheme(args.path)
        print(json.dumps({"ok": ok}))
        return 0 if ok else 1
    ok = rerun(args.directory)
    print(json.dumps({"ok": ok}))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
