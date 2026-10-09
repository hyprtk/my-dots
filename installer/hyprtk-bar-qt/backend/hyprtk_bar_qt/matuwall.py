"""Matuwall config (TOML) read/write for the Qt themer.

Ported from the GTK bar's ``themer.py`` matuwall section (toolkit-free). The
config is ``~/.config/matuwall/config.toml``, a symlink to the pywal-rendered
template; saving writes through the symlink and rewrites existing key lines in
the template (preserving comments and pywal placeholders).

Usage::

    python3 matuwall.py get
    python3 matuwall.py set --json '<json dict>'
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path

try:
    import tomllib as _tomllib
except ModuleNotFoundError:  # pragma: no cover
    try:
        import tomli as _tomllib
    except ModuleNotFoundError:
        _tomllib = None

MATUWALL_CONFIG = Path.home() / ".config" / "matuwall" / "config.toml"
MATUWALL_TEMPLATE = Path.home() / ".config" / "wal" / "templates" / "matuwall-config.toml"

# (section, title, [(key, label, kind[, choices])]) — matuwall 0.3.x schema.
SECTIONS = [
    ("general", "General", [
        ("directory", "Wallpaper Directory", "str"),
        ("backend", "Backend", "choice", ["auto", "awww", "sweetbg", "plasma", "command"]),
    ]),
    ("window", "Window", [
        ("preview", "Preview Wallpaper", "bool"),
        ("close_on_focus_loss", "Close On Focus Loss", "bool"),
        ("position", "Position", "choice", ["center", "left", "right", "top", "bottom"]),
        ("background", "Panel Background", "str"),
        ("margin", "Tile Margin", "int"),
        ("edge_margin", "Edge Margin", "int"),
        ("radius", "Panel Radius", "int"),
    ]),
    ("input", "Input", [("mouse", "Mouse Control", "bool")]),
    ("animation", "Animation", [
        ("navigation_ms", "Navigation (ms)", "int"),
        ("zoom_percent", "Zoom (%)", "int"),
    ]),
    ("grid", "Grid", [
        ("columns", "Columns", "int"),
        ("spacing", "Spacing", "int"),
        ("radius", "Tile Radius", "int"),
        ("border_width", "Border Width", "int"),
        ("shadow_width", "Shadow Width", "int"),
        ("ring_width", "Ring Width", "int"),
        ("visible_rows", "Visible Rows", "int"),
        ("carousel", "Carousel", "bool"),
        ("edge", "Edge Style", "choice", ["auto", "clip", "peek", "fade"]),
    ]),
    ("thumbnail", "Thumbnail", [("width", "Width", "int"), ("height", "Height", "int")]),
    ("colors", "Colors (pywal-driven)", [
        ("tile", "Tile", "str"), ("border", "Border", "str"), ("shadow", "Shadow", "str"),
        ("ring", "Ring", "str"), ("spinner", "Spinner", "str"),
    ]),
    ("backend.sweetbg", "Sweetbg Backend", [("args", "Extra args", "list")]),
    ("backend.awww", "Awww Backend", [("args", "Extra args", "list")]),
    ("backend.plasma", "Plasma Backend", [("args", "Extra args", "list")]),
    ("backend.command", "Command Backend", [("apply", "Apply ({path})", "str")]),
    ("hooks", "Hooks", [("on_apply", "On Apply", "list")]),
]

# Pywal-rendered keys: never written back into the template.
TEMPLATE_SKIP = {
    ("window", "background"), ("colors", "tile"), ("colors", "border"),
    ("colors", "shadow"), ("colors", "ring"), ("colors", "spinner"),
}


def toml_quote(value) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def toml_value(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_quote(v) for v in value) + "]"
    return toml_quote(value)


def toml_dumps(cfg: dict) -> str:
    """Serialise a one-level-nested config dict to TOML."""
    out: list[str] = []

    def emit(prefix: list[str], body: dict) -> None:
        scalars = [(k, v) for k, v in body.items() if not isinstance(v, dict)]
        tables = [(k, v) for k, v in body.items() if isinstance(v, dict)]
        if scalars or not tables:
            out.append("[{}]".format(".".join(prefix)))
            for key, value in scalars:
                out.append("{} = {}".format(key, toml_value(value)))
            out.append("")
        for key, sub in tables:
            emit(prefix + [key], sub)

    for key, value in cfg.items():
        if not isinstance(value, dict):
            out.append("{} = {}".format(key, toml_value(value)))
    for key, sub in cfg.items():
        if isinstance(sub, dict):
            emit([key], sub)
    return "\n".join(out).rstrip() + "\n"


def cfg_get(cfg: dict, section: str, key: str):
    node = cfg
    for part in section.split("."):
        if not isinstance(node, dict):
            return None
        node = node.get(part)
        if node is None:
            return None
    return node.get(key) if isinstance(node, dict) else None


def cfg_set(cfg: dict, section: str, key: str, value) -> None:
    node = cfg
    for part in section.split("."):
        node = node.setdefault(part, {})
    node[key] = value


def read() -> dict:
    if _tomllib is None or not MATUWALL_CONFIG.exists():
        return {}
    try:
        return _tomllib.loads(MATUWALL_CONFIG.read_text())
    except (OSError, ValueError):
        return {}


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".matuwall.", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def template_replacements(cfg: dict) -> dict:
    out = {}
    for section, _title, fields in SECTIONS:
        for field in fields:
            key = field[0]
            if (section, key) in TEMPLATE_SKIP:
                continue
            val = cfg_get(cfg, section, key)
            if val is None:
                continue
            rendered = toml_value(val)
            if "{" in rendered or "}" in rendered:
                continue
            out[(section, key)] = rendered
    return out


def update_template(replacements: dict) -> None:
    """Rewrite existing key lines in the pywal template, preserving comments."""
    if not replacements or not MATUWALL_TEMPLATE.exists():
        return
    try:
        lines = MATUWALL_TEMPLATE.read_text().splitlines()
    except OSError:
        return
    pending: dict[str, dict[str, str]] = {}
    for (section, key), value in replacements.items():
        pending.setdefault(section, {})[key] = value
    current = ""
    out = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            current = stripped[1:-1].strip()
            out.append(line)
            continue
        section = pending.get(current)
        if section:
            for key, value in list(section.items()):
                if re.match(rf"{re.escape(key)}\s*=", stripped):
                    indent = line[: len(line) - len(line.lstrip())]
                    out.append(f"{indent}{key} = {value}")
                    del section[key]
                    break
            else:
                out.append(line)
        else:
            out.append(line)
    _atomic_write(MATUWALL_TEMPLATE, "\n".join(out) + "\n")


def save(cfg: dict) -> None:
    _atomic_write(MATUWALL_CONFIG.resolve(), toml_dumps(cfg))
    update_template(template_replacements(cfg))


def fields_json() -> list:
    return [
        {"section": section, "title": title,
         "fields": [{"key": f[0], "label": f[1], "kind": f[2], "choices": (f[3] if len(f) > 3 else [])} for f in fields]}
        for section, title, fields in SECTIONS
    ]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="matuwall config read/write")
    sub = ap.add_subparsers(dest="action", required=True)
    sub.add_parser("get")
    setp = sub.add_parser("set")
    setp.add_argument("--json", required=True)
    args = ap.parse_args(argv)

    if args.action == "get":
        print(json.dumps({"config": read(), "sections": fields_json()}))
        return 0
    try:
        cfg = json.loads(args.json)
    except ValueError:
        print(json.dumps({"ok": False, "error": "bad json"}))
        return 1
    try:
        save(cfg)
    except OSError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1
    print(json.dumps({"ok": True}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
