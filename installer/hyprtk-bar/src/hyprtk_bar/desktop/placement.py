"""Side store for desktop-widget placement.

A widget's **placement** — its ``position``, ``margin_x`` / ``margin_y`` and
snap grouping (``snap_group`` / ``snap_axis`` / ``snap_order``) — is persisted
separately from the rest of the widget config, in
``~/.config/hyprtk-bar/widget-positions.json``.

The settings window edits appearance and behaviour; the drag gesture edits
placement. Keeping placement in its own file means applying an appearance change
can never reset a spot the user dragged a widget to — the settings Apply only
rewrites the placement a widget's controls actually edited.

``config.json`` stays **authoritative**: :func:`merge` only copies a stored value
onto a widget whose config is missing the key or still carries the built-in
default (i.e. a config that lost the user's custom placement). The store is
re-written on every drag/snap/detach and after every reload, so it always
mirrors the live layout.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.placement
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import json
import logging
import math

from ..config import (
    CONFIG_DIR,
    DEFAULTS,
    PLACEMENT_KEYS,
    WIDGET_POSITIONS,
    WIDGET_SNAP_AXES,
    write_json_atomic,
)

log = logging.getLogger("hyprtk_bar.desktop.placement")

POSITIONS_PATH = CONFIG_DIR / "widget-positions.json"

__all__ = ["POSITIONS_PATH", "PLACEMENT_KEYS", "load", "save", "write_blocks", "merge"]


def _reject_constant(name: str):
    raise ValueError(f"non-finite JSON constant: {name}")


def _int(value, lo: int, hi: int) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if isinstance(value, float) and not math.isfinite(value):
        return None
    return max(lo, min(hi, int(value)))


def _sanitize(raw: dict) -> dict:
    """Keep only known placement keys with in-range values."""
    out: dict = {}
    position = str(raw.get("position") or "")
    if position in WIDGET_POSITIONS:
        out["position"] = position
    for key in ("margin_x", "margin_y"):
        value = _int(raw.get(key), 0, 8000)
        if value is not None:
            out[key] = value
    snap_group = raw.get("snap_group")
    if snap_group is not None:
        out["snap_group"] = str(snap_group)[:64]
    axis = str(raw.get("snap_axis") or "")
    if axis in WIDGET_SNAP_AXES:
        out["snap_axis"] = axis
    snap_order = _int(raw.get("snap_order"), 0, 99)
    if snap_order is not None:
        out["snap_order"] = snap_order
    return out


def load() -> dict:
    """The stored placement per widget id; ``{}`` when absent/unreadable."""
    try:
        data = json.loads(POSITIONS_PATH.read_text(), parse_constant=_reject_constant)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {
        wid: _sanitize(block)
        for wid, block in data.items()
        if isinstance(block, dict)
    }


def save(store: dict) -> None:
    """Atomically write the whole store (0600, symlink-safe)."""
    try:
        write_json_atomic(POSITIONS_PATH, store)
    except OSError:
        log.warning("could not write widget positions %s", POSITIONS_PATH, exc_info=True)


def _extract(block: dict) -> dict:
    return {key: block[key] for key in PLACEMENT_KEYS if key in block}


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


def merge(blocks: dict) -> None:
    """Reconcile stored placement onto *blocks* in place (config authoritative).

    A stored value is used only when the block is missing the key, or when the
    block still holds the built-in default while the store holds something else
    (a config that lost the user's custom placement). An edited config always
    wins, so hand-editing ``config.json`` is not shadowed.
    """
    store = load()
    for wid, block in blocks.items():
        stored = store.get(wid)
        if not isinstance(block, dict) or not isinstance(stored, dict):
            continue
        defaults = DEFAULTS["widgets"].get(wid) or {}
        for key in PLACEMENT_KEYS:
            if key not in stored:
                continue
            if key not in block:
                block[key] = stored[key]
            elif block.get(key) == defaults.get(key) != stored[key]:
                block[key] = stored[key]
