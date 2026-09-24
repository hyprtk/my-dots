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

from ..config import WIDGET_IDS

log = logging.getLogger("hyprtk_bar.desktop.manager")


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

    def __init__(self, cfg: dict):
        self._cfg = cfg
        self._wins: dict = {}
        self._blocks: dict[str, dict] = {}
        self._palette: dict | None = None
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
        for win in list(self._wins.values()):
            self._destroy(win)
        self._wins.clear()
        self._blocks.clear()
