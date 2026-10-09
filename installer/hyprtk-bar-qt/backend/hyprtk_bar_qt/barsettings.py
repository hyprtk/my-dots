"""Read/write the Qt bar's own config for the settings window.

The Qt bar reads its own ``~/.config/hyprtk-bar-qt/config.json`` (top-level bar
geometry, font, animations, theme, layout and the module / arcmenu / menu /
widgets blocks), separate from the GTK bar's config. This applies small JSON
patches atomically.

Usage::

    python3 barsettings.py get
    python3 barsettings.py set --json '{"height": 38}'
    python3 barsettings.py set --json '{"arcmenu": {"radius": 140}}'
"""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path

try:
    from .paths import QT_CONFIG
except ImportError:  # run as a script (python3 barsettings.py)
    from paths import QT_CONFIG

BAR_CONFIG = QT_CONFIG


def load() -> dict:
    try:
        data = json.loads(BAR_CONFIG.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def deep_merge(base: dict, patch: dict) -> dict:
    """Recursively merge *patch* into *base* (patch wins); returns *base*."""
    for key, value in (patch or {}).items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            deep_merge(base[key], value)
        else:
            base[key] = value
    return base


def apply(patch: dict, path: Path = BAR_CONFIG) -> bool:
    try:
        current = json.loads(path.read_text())
        if not isinstance(current, dict):
            current = {}
    except (OSError, json.JSONDecodeError):
        current = {}
    deep_merge(current, patch or {})
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".config.", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(current, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
        return True
    except OSError:
        return False


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Qt bar config editor")
    sub = ap.add_subparsers(dest="action", required=True)
    sub.add_parser("get")
    sp = sub.add_parser("set")
    sp.add_argument("--json", required=True)
    args = ap.parse_args(argv)

    if args.action == "get":
        print(json.dumps(load()))
        return 0
    try:
        patch = json.loads(args.json)
    except ValueError:
        print(json.dumps({"ok": False, "error": "bad json"}))
        return 1
    ok = apply(patch)
    print(json.dumps({"ok": ok}))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
