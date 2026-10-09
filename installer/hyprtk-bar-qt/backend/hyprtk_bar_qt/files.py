"""Directory listing for the start menu's Plasma file browser.

Toolkit-free: returns a directory's entries (name, path, is_dir, size) with
directories first, hidden files skipped, sorted case-insensitively.

Usage::

    python3 files.py list <path>
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


def list_dir(path: str) -> dict:
    """Entries of *path* (dirs first, hidden skipped), or an empty list."""
    base = Path(os.path.expanduser(path or "~"))
    entries = []
    try:
        for entry in base.iterdir():
            if entry.name.startswith("."):
                continue
            try:
                is_dir = entry.is_dir()
                size = 0 if is_dir else entry.stat().st_size
            except OSError:
                continue
            entries.append({
                "name": entry.name,
                "path": str(entry),
                "is_dir": is_dir,
                "size": size,
            })
    except OSError:
        pass
    entries.sort(key=lambda e: (not e["is_dir"], e["name"].lower()))
    try:
        parent = str(base.resolve().parent)
    except OSError:
        parent = str(base)
    return {"path": str(base), "parent": parent, "entries": entries}


# XDG user-dirs key → friendly label + default subfolder name.
_XDG_DIRS = [
    ("DESKTOP", "Desktop"),
    ("DOCUMENTS", "Documents"),
    ("DOWNLOAD", "Downloads"),
    ("MUSIC", "Music"),
    ("PICTURES", "Pictures"),
    ("PUBLICSHARE", "Public"),
    ("TEMPLATES", "Templates"),
    ("VIDEOS", "Videos"),
]


def xdg_places() -> list[dict]:
    """The user's XDG places that exist (from ~/.config/user-dirs.dirs).

    Only directories inside ``$HOME`` are returned, in the standard XDG order.
    Falls back to the conventional subfolder names when user-dirs.dirs is absent.
    """
    home = Path.home()
    conf = home / ".config" / "user-dirs.dirs"
    wanted: dict[str, str] = {}
    try:
        text = conf.read_text()
    except OSError:
        text = ""
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("XDG_") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()[4:]
        if key.endswith("_DIR"):
            key = key[:-4]
        val = val.strip().strip('"').replace("$HOME", str(home))
        wanted[key] = val
    out = []
    for key, label in _XDG_DIRS:
        path = wanted.get(key) or str(home / label)
        try:
            inside_home = os.path.commonpath([os.path.abspath(path), str(home)]) == str(home)
        except ValueError:
            inside_home = False
        if inside_home and os.path.isdir(path):
            out.append({"label": label, "path": path})
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="directory listing for the menu browser")
    sub = ap.add_subparsers(dest="action", required=True)
    lst = sub.add_parser("list")
    lst.add_argument("path", nargs="?", default="~")
    sub.add_parser("xdg-places")
    args = ap.parse_args(argv)

    if args.action == "xdg-places":
        print(json.dumps({"places": xdg_places()}))
        return 0
    print(json.dumps(list_dir(args.path)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
