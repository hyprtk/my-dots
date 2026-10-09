"""Start-menu favourites / recents, stored in the Qt bar's own `menu` block.

Toolkit-free helpers the Qt start menu calls on launch and on a favourite
toggle. Writes are atomic; the file is the Qt bar's own config
(``~/.config/hyprtk-bar-qt/config.json``), separate from the GTK bar's.

Usage::

    python3 menu.py get
    python3 menu.py record <app-id>
    python3 menu.py favorite <app-id>
    python3 menu.py unfavorite <app-id>
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from copy import deepcopy
from pathlib import Path

try:
    from .paths import QT_CONFIG
except ImportError:  # run as a script (python3 menu.py)
    from paths import QT_CONFIG

BAR_CONFIG = QT_CONFIG

DEFAULT_MENU = {
    "layout": "whisker",
    "show_recents": True,
    "max_recents": 10,
    "favorites": [],
    "recents": [],
}


def record_recent(recents: list, app_id: str, max_items: int = 10) -> list:
    """New recents list: *app_id* newest-first, deduped, capped at *max_items*."""
    if not app_id:
        return list(recents or [])
    out = [app_id] + [r for r in (recents or []) if r != app_id]
    return out[:max(1, int(max_items))]


def toggle_favorite(favorites: list, app_id: str) -> list:
    favs = list(favorites or [])
    if app_id in favs:
        favs.remove(app_id)
    elif app_id:
        favs.append(app_id)
    return favs


def _read_bar() -> dict:
    try:
        data = json.loads(BAR_CONFIG.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def load_menu() -> dict:
    merged = deepcopy(DEFAULT_MENU)
    data = _read_bar().get("menu")
    if isinstance(data, dict):
        merged.update(data)
    merged["favorites"] = list(merged.get("favorites") or [])
    merged["recents"] = list(merged.get("recents") or [])
    return merged


def _write_bar(bar: dict) -> None:
    BAR_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(BAR_CONFIG.parent), prefix=".config.", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(bar, f, indent=2, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, BAR_CONFIG)


def _save_menu(menu: dict) -> None:
    bar = _read_bar()
    bar["menu"] = menu
    _write_bar(bar)


def record_launch(app_id: str) -> list:
    menu = load_menu()
    menu["recents"] = record_recent(menu["recents"], app_id, menu.get("max_recents", 10))
    _save_menu(menu)
    return menu["recents"]


def set_favorite(app_id: str, on: bool) -> list:
    menu = load_menu()
    menu["favorites"] = toggle_favorite(menu["favorites"], app_id)
    _save_menu(menu)
    return menu["favorites"]


def clear_recents() -> list:
    menu = load_menu()
    menu["recents"] = []
    _save_menu(menu)
    return []


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="start-menu favourites/recents")
    sub = ap.add_subparsers(dest="action", required=True)
    sub.add_parser("get")
    sub.add_parser("clear-recents")
    for name in ("record", "favorite", "unfavorite"):
        p = sub.add_parser(name)
        p.add_argument("id")
    args = ap.parse_args(argv)

    if args.action == "get":
        print(json.dumps(load_menu()))
        return 0
    if args.action == "clear-recents":
        print(json.dumps({"recents": clear_recents()}))
        return 0
    if args.action == "record":
        print(json.dumps({"recents": record_launch(args.id)}))
        return 0
    print(json.dumps({"favorites": set_favorite(args.id, args.action == "favorite")}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
