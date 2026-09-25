"""Side store for desktop-widget placement.

A widget's **placement** — its ``position``, ``margin_x`` / ``margin_y`` and
snap grouping (``snap_group`` / ``snap_axis`` / ``snap_order``) — is persisted
separately from the rest of the widget config, in
``~/.config/hyprtk-bar/widget-positions.json``.

The settings window edits appearance and behaviour; the drag gesture edits
placement. Keeping them apart means applying an appearance/behaviour change can
never reset a spot the user dragged a widget to: the store is overlaid on the
widgets on every reload, so its values win over anything the settings block
carried. The store is re-written whenever the manager or the settings UI moves a
widget, and after every reload, so it always mirrors the live layout.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.placement
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import json
import logging
from pathlib import Path

log = logging.getLogger("hyprtk_bar.desktop.placement")

POSITIONS_PATH = Path.home() / ".config" / "hyprtk-bar" / "widget-positions.json"

# The keys owned by the placement store (everything else belongs to config.json).
PLACEMENT_KEYS = (
    "position",
    "margin_x",
    "margin_y",
    "snap_group",
    "snap_axis",
    "snap_order",
)


def load() -> dict:
    """The stored placement per widget id; ``{}`` when absent/unreadable."""
    try:
        data = json.loads(POSITIONS_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _extract(block: dict) -> dict:
    return {key: block[key] for key in PLACEMENT_KEYS if key in block}


def save(store: dict) -> None:
    """Atomically write the whole store (tmp + replace)."""
    try:
        POSITIONS_PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp = POSITIONS_PATH.with_name(POSITIONS_PATH.name + ".tmp")
        tmp.write_text(json.dumps(store, indent=2, sort_keys=True) + "\n")
        tmp.replace(POSITIONS_PATH)
    except OSError:
        log.warning("could not write widget positions %s", POSITIONS_PATH, exc_info=True)


def write_blocks(blocks: dict) -> None:
    """Merge the placement of every block in *blocks* into the store.

    Blocks are keyed by widget id; a widget absent from *blocks* keeps its
    stored entry (so disabling and re-enabling one restores its spot).
    """
    store = load()
    for wid, block in blocks.items():
        if isinstance(block, dict):
            store[wid] = _extract(block)
    save(store)


def set_widget(wid: str, block: dict) -> None:
    """Write one widget's placement to the store."""
    if not isinstance(block, dict):
        return
    store = load()
    store[wid] = _extract(block)
    save(store)


def overlay(blocks: dict) -> None:
    """Apply stored placement onto *blocks* in place (store wins)."""
    store = load()
    for wid, block in blocks.items():
        stored = store.get(wid)
        if not isinstance(block, dict) or not isinstance(stored, dict):
            continue
        for key in PLACEMENT_KEYS:
            if key in stored:
                block[key] = stored[key]
