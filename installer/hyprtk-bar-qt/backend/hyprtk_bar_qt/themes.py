"""List the installed hyprtk bar themes and resolve one into a palette.

Thin CLI over ``theme_import`` for the Qt themer window: ``list`` returns the
theme names, ``palette <name>`` returns the resolved
background/foreground/accent/etc. as JSON.

Usage::

    python3 themes.py list
    python3 themes.py palette hyprtk-glass
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from hyprtk_bar_qt import theme_import
else:
    from . import theme_import

_RGBA_RE = re.compile(r"rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)")


def hexify(color) -> str:
    """Coerce a CSS colour to ``#rrggbb`` QML can parse (drops any alpha)."""
    if not isinstance(color, str):
        return color
    c = color.strip()
    if c.startswith("#"):
        return c[:7] if len(c) >= 7 else c
    m = _RGBA_RE.match(c)
    if m:
        r, g, b = (int(float(m.group(i))) for i in (1, 2, 3))
        return "#{:02x}{:02x}{:02x}".format(r, g, b)
    return c


def _theme_entry(name: str) -> dict:
    palette = theme_import.parse_palette(name) or {}
    out = {
        "background": hexify(palette.get("background", "#1e1e2e")),
        "foreground": hexify(palette.get("foreground", "#e5e7eb")),
        "accent": hexify(palette.get("accent", "#c084fc")),
    }
    return {"name": name, "palette": out}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="hyprtk bar themes for the Qt themer")
    sub = ap.add_subparsers(dest="action", required=True)
    sub.add_parser("list")
    pal = sub.add_parser("palette")
    pal.add_argument("name")
    sub.add_parser("installed")
    imp = sub.add_parser("import")
    imp.add_argument("path")
    rem = sub.add_parser("remove")
    rem.add_argument("name")
    args = ap.parse_args(argv)

    if args.action == "list":
        print(json.dumps({"themes": [_theme_entry(n) for n in theme_import.list_themes()]}))
        return 0
    if args.action == "installed":
        found = theme_import.find_installed_themes()
        print(json.dumps({"installed": [{"name": n, "path": str(p)} for n, p in found]}))
        return 0
    if args.action == "import":
        name = theme_import.import_theme(Path(args.path).expanduser())
        print(json.dumps({"ok": name is not None, "name": name}))
        return 0 if name else 1
    if args.action == "remove":
        ok = theme_import.remove_theme(args.name)
        print(json.dumps({"ok": bool(ok)}))
        return 0 if ok else 1

    palette = theme_import.parse_palette(args.name)
    print(json.dumps({"name": args.name, "palette": palette}))
    return 0 if palette else 1


if __name__ == "__main__":
    raise SystemExit(main())
