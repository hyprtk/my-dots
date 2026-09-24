"""Desktop widget manager: builds, themes, reloads and tears down the widgets.

Owned by the bar process. The manager diffs the ``widgets`` config block on
reload — creating newly-enabled widgets, updating placement/options on existing
ones, and destroying ones that were disabled — so the settings window's Apply
button is all it takes to turn a widget on or off live.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.manager
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib  # noqa: E402

from ..config import WIDGET_IDS

log = logging.getLogger("hyprtk_bar.desktop.manager")

# How often the cursor is polled while a widget is being dragged.
MOVE_POLL_MS = 16


def _widget_classes() -> dict:
    # Imported lazily so a broken widget module can't stop the bar from starting.
    from .clock import ClockWidget
    from .visualizer import VisualizerWidget
    from .weather import WeatherWidget

    return {
        "clock": ClockWidget,
        "weather": WeatherWidget,
        "visualizer": VisualizerWidget,
    }


class DesktopWidgetManager:
    """Creates and tracks one layer-shell window per enabled desktop widget."""

    def __init__(self, cfg: dict, ipc=None):
        self._cfg = cfg
        self._ipc = ipc
        self._wins: dict = {}
        self._blocks: dict[str, dict] = {}
        self._palette: dict | None = None
        self._move_win = None
        self._move_timer: int | None = None
        self.reload(cfg)

    def reload(self, cfg: dict) -> None:
        self._cfg = cfg
        widgets = cfg.get("widgets") or {}
        enabled = bool(widgets.get("enabled", True))
        wanted: dict[str, dict] = {}
        if enabled:
            for wid in WIDGET_IDS:
                block = widgets.get(wid) or {}
                if block.get("enabled"):
                    wanted[wid] = block

        # Rebuild a widget when it is newly enabled or its block changed (a
        # style/source change needs a fresh widget — an in-place update cannot
        # swap a clock's layout or restart cava); destroy it when disabled.
        for wid in list(self._wins):
            if wid not in wanted or self._blocks.get(wid) != wanted.get(wid):
                if self._wins[wid] is self._move_win:
                    self.end_move()
                self._destroy(self._wins.pop(wid))
                self._blocks.pop(wid, None)

        classes = _widget_classes()
        for wid, block in wanted.items():
            if wid in self._wins:
                continue
            cls = classes.get(wid)
            if cls is None:
                continue
            try:
                win = cls(cfg, block)
                win.show_all()
                self._wins[wid] = win
                self._blocks[wid] = block
            except Exception:
                log.exception("failed to build widget %s", wid)

        if self._palette is not None:
            self.apply_theme(self._palette)

    def apply_theme(self, palette: dict) -> None:
        self._palette = palette
        for wid, win in self._wins.items():
            try:
                win.apply_theme(palette)
            except Exception:
                log.exception("failed to theme widget %s", wid)

    # ── free move (Hyprland ``Super + Shift + left mouse``) ──────
    #
    # A layer-shell surface with keyboard_mode=none never sees the Super
    # modifier in GTK, so the gesture is a compositor bind: Super+Shift+LMB (press /
    # release) runs a helper that signals the bar. The bar then polls the
    # cursor (cheap command-socket query) and moves the widget under it.

    def begin_move(self) -> None:
        if self._ipc is None:
            return
        pos = self._ipc.cursor_pos()
        if pos is None:
            return
        win = self._widget_at(*pos)
        if win is None:
            return
        win.begin_move(*pos)
        self._move_win = win
        if self._move_timer is None:
            self._move_timer = GLib.timeout_add(MOVE_POLL_MS, self._poll_move)

    def _poll_move(self) -> bool:
        if self._move_win is None or self._ipc is None:
            self._move_timer = None
            return GLib.SOURCE_REMOVE
        pos = self._ipc.cursor_pos()
        if pos is not None:
            self._move_win.move_to(*pos)
        return GLib.SOURCE_CONTINUE

    def end_move(self) -> None:
        if self._move_timer is not None:
            GLib.source_remove(self._move_timer)
            self._move_timer = None
        win = self._move_win
        self._move_win = None
        if win is not None:
            try:
                win.end_move()
            except Exception:
                log.exception("widget end_move failed")

    def _widget_at(self, x: int, y: int):
        for win in self._wins.values():
            ox, oy = win._origin
            alloc = win.get_allocation()
            if ox <= x < ox + (alloc.width or 0) and oy <= y < oy + (alloc.height or 0):
                return win
        return None

    @staticmethod
    def _destroy(win) -> None:
        try:
            win.shutdown()
        except Exception:
            log.exception("widget shutdown failed")
        try:
            win.destroy()
        except Exception:
            pass

    def shutdown(self) -> None:
        self.end_move()
        for win in list(self._wins.values()):
            self._destroy(win)
        self._wins.clear()
        self._blocks.clear()
