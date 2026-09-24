"""Base class for desktop widgets: a themed, positioned layer-shell surface.

A desktop widget is a free-floating, transparent layer-shell window (like a
conky panel) that the bar process owns alongside the bar itself. Subclasses
build their content into :attr:`root` and re-render on theme changes via
:meth:`on_palette`.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.base
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")

from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

log = logging.getLogger("hyprtk_bar.desktop.base")

_LAYER_MAP = {
    "background": GtkLayerShell.Layer.BACKGROUND,
    "bottom": GtkLayerShell.Layer.BOTTOM,
    "top": GtkLayerShell.Layer.TOP,
}


def _layer_for(name: str):
    return _LAYER_MAP.get(str(name), GtkLayerShell.Layer.BOTTOM)


def _parse_position(position: str) -> tuple[str, str]:
    """``"top-right"`` -> ``("right", "top")``; ``"center"`` -> ``("center", "center")``."""
    if position == "center":
        return "center", "center"
    x = y = "center"
    for part in str(position).split("-"):
        if part in ("left", "right"):
            x = part
        elif part in ("top", "bottom"):
            y = part
    return x, y


class DesktopWidgetWindow(Gtk.Window):
    """A layer-shell surface hosting one desktop widget."""

    WIDGET_ID = "widget"

    def __init__(self, cfg: dict, block: dict):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self._cfg = cfg
        self._block = block or {}
        self._palette: dict | None = None
        self._provider = Gtk.CssProvider()
        self._geom_idle: int | None = None
        self._last_margins: tuple | None = None

        self.set_title(f"hyprtk-bar-widget-{self.WIDGET_ID}")
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_app_paintable(True)
        self.set_accept_focus(False)

        visual = self.get_screen().get_rgba_visual()
        if visual:
            self.set_visual(visual)

        self._root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        ctx = self._root.get_style_context()
        ctx.add_class("desktop-widget")
        ctx.add_class(f"widget-{self.WIDGET_ID}")
        self.add(self._root)

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_namespace(self, f"hyprtk-bar-widget-{self.WIDGET_ID}")
        GtkLayerShell.set_layer(self, _layer_for(self._block.get("layer", "bottom")))
        GtkLayerShell.set_exclusive_zone(self, -1)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)

        Gtk.StyleContext.add_provider_for_screen(
            self.get_screen(), self._provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )
        self.connect("size-allocate", self._on_size_allocate)

        self.build()
        self.apply_theme()

    # ── subclass hooks ───────────────────────────────────────────

    @property
    def root(self) -> Gtk.Box:
        return self._root

    def build(self) -> None:
        raise NotImplementedError

    def on_palette(self, palette: dict) -> None:
        """Re-render widget-specific colours after a theme change."""

    def shutdown(self) -> None:
        """Stop timers/threads/processes; called before the window is destroyed."""

    # ── theming ──────────────────────────────────────────────────

    def apply_theme(self, palette: dict | None = None) -> None:
        if palette:
            self._palette = palette
        from ..theme import resolve_palette
        from .theme import build_widget_css

        palette = self._palette or resolve_palette(self._cfg)
        try:
            css = build_widget_css(self.WIDGET_ID, palette, self._cfg, self._block)
            self._provider.load_from_data(css.encode())
        except GLib.Error:
            log.warning("failed to load CSS for widget %s", self.WIDGET_ID, exc_info=True)
        try:
            self.on_palette(palette)
        except Exception:
            log.exception("widget %s failed to apply palette", self.WIDGET_ID)

    # ── config reload ────────────────────────────────────────────

    def reload(self, cfg: dict, block: dict) -> None:
        """Adopt new config/placement without rebuilding the whole widget."""
        self._cfg = cfg
        self._block = block or {}
        GtkLayerShell.set_layer(self, _layer_for(self._block.get("layer", "bottom")))
        self._apply_geometry()
        self.apply_theme(self._palette)

    # ── geometry (anchors + margins) ─────────────────────────────

    def _on_size_allocate(self, *_args) -> None:
        # Defer margin changes out of the allocation pass (applying them inline
        # is overwritten by the pass already in flight).
        if self._geom_idle is None:
            self._geom_idle = GLib.idle_add(self._apply_geometry_idle)

    def _apply_geometry_idle(self) -> bool:
        self._geom_idle = None
        self._apply_geometry()
        return GLib.SOURCE_REMOVE

    def _monitor_size(self) -> tuple[int, int]:
        display = Gdk.Display.get_default()
        monitor = None
        if display is not None:
            monitor = display.get_primary_monitor() or display.get_monitor(0)
        if monitor is not None:
            geo = monitor.get_geometry()
            return geo.width, geo.height
        screen = Gdk.Screen.get_default()
        if screen is not None:
            return screen.get_width(), screen.get_height()
        return 1920, 1080

    def _apply_geometry(self) -> None:
        block = self._block
        position = str(block.get("position", "top-right"))
        mx = max(0, int(block.get("margin_x", 40) or 0))
        my = max(0, int(block.get("margin_y", 40) or 0))
        width = max(0, int(block.get("width", 0) or 0))
        height = max(0, int(block.get("height", 0) or 0))
        self.set_size_request(width if width else -1, height if height else -1)

        alloc = self.get_allocation()
        natural = self.get_preferred_size()[1]
        cur_w = alloc.width or natural.width or width or 200
        cur_h = alloc.height or natural.height or height or 120
        mon_w, mon_h = self._monitor_size()
        x_mode, y_mode = _parse_position(position)

        for edge in (
            GtkLayerShell.Edge.TOP,
            GtkLayerShell.Edge.BOTTOM,
            GtkLayerShell.Edge.LEFT,
            GtkLayerShell.Edge.RIGHT,
        ):
            GtkLayerShell.set_anchor(self, edge, False)

        margins: dict = {}
        if x_mode == "left":
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
            margins[GtkLayerShell.Edge.LEFT] = mx
        elif x_mode == "right":
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
            margins[GtkLayerShell.Edge.RIGHT] = mx
        else:
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
            margins[GtkLayerShell.Edge.LEFT] = max(0, (mon_w - cur_w) // 2)

        if y_mode == "top":
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
            margins[GtkLayerShell.Edge.TOP] = my
        elif y_mode == "bottom":
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
            margins[GtkLayerShell.Edge.BOTTOM] = my
        else:
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
            margins[GtkLayerShell.Edge.TOP] = max(0, (mon_h - cur_h) // 2)

        key = tuple(sorted(margins.items()))
        if key == self._last_margins:
            return
        self._last_margins = key
        for edge, value in margins.items():
            GtkLayerShell.set_margin(self, edge, value)
