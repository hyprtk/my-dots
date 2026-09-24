"""Base for data-driven desktop widgets.

Subclasses sample a data source on a timer and render it into GTK widgets.
:meth:`collect` returns the data, :meth:`render` updates the built widgets. The
first sample runs during ``build`` so the widget is populated immediately.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.sampled
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib, Gtk  # noqa: E402

from .base import DesktopWidgetWindow  # noqa: E402

log = logging.getLogger("hyprtk_bar.desktop.sampled")


class SampledWidget(DesktopWidgetWindow):
    """A widget that samples data periodically and renders it."""

    DEFAULT_REFRESH_S = 2

    def __init__(self, cfg: dict, block: dict):
        self._timer_id: int | None = None
        super().__init__(cfg, block)

    # ── subclass hooks ───────────────────────────────────────────

    def build_content(self) -> None:
        """Build the widget's GTK content into ``self.root``."""
        raise NotImplementedError

    def collect(self):
        """Return the current data to render."""
        raise NotImplementedError

    def render(self, data) -> None:
        """Update the built widgets from *data*."""
        raise NotImplementedError

    def on_palette(self, palette: dict) -> None:
        """Re-colour any cairo-drawn bits after a theme change."""

    # ── lifecycle ────────────────────────────────────────────────

    def build(self) -> None:
        self.build_content()
        self._sample()
        self._start_timer()

    def _refresh_ms(self) -> int:
        try:
            seconds = int(
                self._block.get("refresh_seconds", self.DEFAULT_REFRESH_S)
                or self.DEFAULT_REFRESH_S
            )
        except (TypeError, ValueError):
            seconds = self.DEFAULT_REFRESH_S
        return max(250, seconds * 1000)

    def _start_timer(self) -> None:
        if self._timer_id is None:
            self._timer_id = GLib.timeout_add(self._refresh_ms(), self._tick)

    def _tick(self) -> bool:
        self._sample()
        return GLib.SOURCE_CONTINUE

    def _sample(self) -> None:
        try:
            data = self.collect()
        except Exception:
            log.exception("widget %s sample failed", self.WIDGET_ID)
            return
        try:
            self.render(data)
        except Exception:
            log.exception("widget %s render failed", self.WIDGET_ID)

    def shutdown(self) -> None:
        if self._timer_id is not None:
            GLib.source_remove(self._timer_id)
            self._timer_id = None


# ── small shared helpers ─────────────────────────────────────────

def label(text: str, css_class: str) -> Gtk.Label:
    widget = Gtk.Label(label=text)
    widget.get_style_context().add_class(css_class)
    widget.set_halign(Gtk.Align.START)
    widget.set_xalign(0)
    return widget


def row(spacing: int = 8) -> Gtk.Box:
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=spacing)
    box.set_halign(Gtk.Align.FILL)
    return box


def clear(box: Gtk.Box) -> None:
    for child in box.get_children():
        box.remove(child)
