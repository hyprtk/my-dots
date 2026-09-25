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
        self._origin: tuple[int, int] = (0, 0)
        self._move_offset: tuple[int, int] = (0, 0)
        self._snap: dict | None = None
        self._bounds: tuple[int, int, int, int] | None = None
        self._fit_scale: float = 1.0
        self._content_scale: float = 1.0
        self._spacing_bases: dict[int, int] = {}

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

        # Widgets are click-through — they take no pointer input. The move
        # gesture is driven from Hyprland (Super + Shift + left mouse is a compositor
        # bind that signals the bar), because a layer-shell surface with
        # keyboard_mode=none never receives the Super modifier in GTK.
        self.connect("realize", self._on_realize)

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

    def on_content_scale(self, scale: float) -> None:
        """Scale fixed-size content (drawing areas, icons, spacings) to *scale*.

        The CSS font/padding sizes are scaled by :func:`build_widget_css`; this
        hook lets a widget scale the things CSS can't reach (cairo drawings,
        ``Glyph`` pixel sizes, box spacing) so the whole content fits a snap
        cell. Called on every theme/scale change.
        """

    def shutdown(self) -> None:
        """Stop timers/threads/processes; called before the window is destroyed."""

    # ── theming ──────────────────────────────────────────────────

    def apply_theme(self, palette: dict | None = None) -> None:
        if palette:
            self._palette = palette
        from .theme import build_widget_css, resolve_widget_palette

        palette = self._palette or resolve_widget_palette(self._cfg)
        scale = self._effective_scale()
        self._content_scale = float(scale or 1.0)
        try:
            css = build_widget_css(
                self.WIDGET_ID, palette, self._cfg, self._block, scale=scale
            )
            self._provider.load_from_data(css.encode())
        except GLib.Error:
            log.warning("failed to load CSS for widget %s", self.WIDGET_ID, exc_info=True)
        try:
            self._scale_spacings(self._content_scale)
        except Exception:
            log.exception("widget %s failed to scale spacings", self.WIDGET_ID)
        try:
            self.on_content_scale(self._content_scale)
        except Exception:
            log.exception("widget %s failed to scale content", self.WIDGET_ID)
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

    def _monitor_geometry(self) -> tuple[int, int, int, int]:
        """The primary monitor's ``(x, y, width, height)`` in logical pixels."""
        display = Gdk.Display.get_default()
        monitor = None
        if display is not None:
            monitor = display.get_primary_monitor() or display.get_monitor(0)
        if monitor is not None:
            geo = monitor.get_geometry()
            return geo.x, geo.y, geo.width, geo.height
        screen = Gdk.Screen.get_default()
        if screen is not None:
            return 0, 0, screen.get_width(), screen.get_height()
        return 0, 0, 1920, 1080

    def _monitor_size(self) -> tuple[int, int]:
        _x, _y, width, height = self._monitor_geometry()
        return width, height

    def natural_size(self) -> tuple[int, int]:
        """The widget's **minimum** size at its current (unscaled) content.

        The minimum (not the natural) is what the content can actually be
        squeezed to — using it for the snap cell means the cell is never smaller
        than the content, so a scaled widget never overflows its cell. Measured
        on the content root, not the window, so a ``size_request`` on the window
        doesn't mask the true content minimum.
        """
        minimum = self._root.get_preferred_size()[0]
        return (max(int(minimum.width), 1), max(int(minimum.height), 1))

    def set_snap_layout(self, width: int, height: int, scale: float, x_root: int, y_root: int) -> None:
        """Apply a snap-group cell: uniform size, content scale and absolute pos."""
        self._snap = {
            "width": int(width),
            "height": int(height),
            "scale": float(scale),
            "x": int(x_root),
            "y": int(y_root),
        }
        self._last_margins = None
        self._apply_geometry()
        self.apply_theme()

    def clear_snap_layout(self) -> None:
        if self._snap is None:
            return
        self._snap = None
        self._last_margins = None
        self._apply_geometry()
        self.apply_theme()

    def set_bounds(self, rect: tuple[int, int, int, int]) -> None:
        """Restrict the widget to *rect* (x0, y0, x1, y1) — the usable area."""
        self._bounds = tuple(int(v) for v in rect)
        self._last_margins = None
        self._apply_geometry()

    def set_fit_scale(self, scale: float) -> None:
        """Scale the widget's content down to fit the usable area."""
        scale = max(0.4, min(2.0, float(scale)))
        if abs(scale - self._fit_scale) < 0.01:
            return
        self._fit_scale = scale
        self._last_margins = None
        self.apply_theme()
        self._apply_geometry()

    def _scale_spacings(self, scale: float) -> None:
        """Scale every ``Gtk.Box`` spacing in the content tree by *scale*.

        Box spacing is not reachable from CSS, so without this the fixed gaps
        stop the content shrinking proportionally to the font scale.
        """
        stack = [self._root]
        while stack:
            widget = stack.pop()
            if isinstance(widget, Gtk.Box):
                key = id(widget)
                if key not in self._spacing_bases:
                    self._spacing_bases[key] = widget.get_spacing()
                widget.set_spacing(max(0, int(round(self._spacing_bases[key] * scale))))
            if isinstance(widget, Gtk.Container):
                stack.extend(widget.get_children())

    def _effective_scale(self) -> float | None:
        if self._snap:
            return float(self._snap.get("scale") or 1.0)
        if abs(self._fit_scale - 1.0) >= 0.01:
            return self._fit_scale
        return None

    def _apply_geometry(self) -> None:
        block = self._block
        snap = self._snap
        position = "free" if snap else str(block.get("position", "top-right"))
        mx = max(0, int(block.get("margin_x", 40) or 0))
        my = max(0, int(block.get("margin_y", 40) or 0))
        width = max(0, int(block.get("width", 0) or 0))
        height = max(0, int(block.get("height", 0) or 0))
        if snap:
            width = max(0, int(snap.get("width") or 0))
            height = max(0, int(snap.get("height") or 0))
        self.set_size_request(width if width else -1, height if height else -1)

        alloc = self.get_allocation()
        natural = self.get_preferred_size()[1]
        cur_w = alloc.width or natural.width or width or 200
        cur_h = alloc.height or natural.height or height or 120
        mon_x, mon_y, mon_w, mon_h = self._monitor_geometry()

        # The usable area: the monitor inset by the bar thickness (the border
        # widgets may not overlay). Defaults to the whole monitor.
        if self._bounds is not None:
            bx0, by0, bx1, by1 = self._bounds
        else:
            bx0, by0, bx1, by1 = mon_x, mon_y, mon_x + mon_w, mon_y + mon_h

        # Desired top-left (before clamping into the usable area).
        if snap:
            ox = int(snap.get("x") or 0)
            oy = int(snap.get("y") or 0)
        elif position == "free":
            ox, oy = mon_x + mx, mon_y + my
        else:
            x_mode, y_mode = _parse_position(position)
            if x_mode == "left":
                ox = mon_x + mx
            elif x_mode == "right":
                ox = mon_x + mon_w - cur_w - mx
            else:
                ox = mon_x + max(0, (mon_w - cur_w) // 2)
            if y_mode == "top":
                oy = mon_y + my
            elif y_mode == "bottom":
                oy = mon_y + mon_h - cur_h - my
            else:
                oy = mon_y + max(0, (mon_h - cur_h) // 2)

        # Clamp so the widget never overlays the bar / border.
        ox = max(bx0, min(ox, max(bx0, bx1 - cur_w)))
        oy = max(by0, min(oy, max(by0, by1 - cur_h)))

        for edge in (
            GtkLayerShell.Edge.TOP,
            GtkLayerShell.Edge.BOTTOM,
            GtkLayerShell.Edge.LEFT,
            GtkLayerShell.Edge.RIGHT,
        ):
            GtkLayerShell.set_anchor(self, edge, False)

        margins: dict = {}
        if snap:
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
            margins[GtkLayerShell.Edge.LEFT] = ox - mon_x
            margins[GtkLayerShell.Edge.TOP] = oy - mon_y
        else:
            x_mode, y_mode = _parse_position(position)
            if x_mode == "right":
                GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
                margins[GtkLayerShell.Edge.RIGHT] = mon_x + mon_w - cur_w - ox
            else:  # left / center
                GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
                margins[GtkLayerShell.Edge.LEFT] = ox - mon_x
            if y_mode == "bottom":
                GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
                margins[GtkLayerShell.Edge.BOTTOM] = mon_y + mon_h - cur_h - oy
            else:  # top / center
                GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
                margins[GtkLayerShell.Edge.TOP] = oy - mon_y
        self._origin = (ox, oy)

        key = tuple(sorted(margins.items()))
        if key == self._last_margins:
            return
        self._last_margins = key
        for edge, value in margins.items():
            GtkLayerShell.set_margin(self, edge, max(0, int(value)))

    # ── click-through ────────────────────────────────────────────

    def _on_realize(self, *_args) -> None:
        window = self.get_window()
        if window is None:
            return
        try:
            import cairo

            window.input_shape_combine_region(cairo.Region(), 0, 0)
        except Exception:
            log.debug("could not clear input region for widget %s", self.WIDGET_ID)

    # ── free placement (driven by the bar's Hyprland bind) ───────

    def begin_move(self, x_root: int, y_root: int) -> None:
        """Start a free move, keeping the grab point under the pointer."""
        self._move_offset = (x_root - self._origin[0], y_root - self._origin[1])

    def move_to(self, x_root: int, y_root: int) -> None:
        """Move the widget so the grab point follows the pointer, clamped."""
        mon_x, mon_y, mon_w, mon_h = self._monitor_geometry()
        alloc = self.get_allocation()
        cur_w = alloc.width or 1
        cur_h = alloc.height or 1
        nx = x_root - self._move_offset[0]
        ny = y_root - self._move_offset[1]
        nx = max(mon_x, min(nx, mon_x + mon_w - cur_w))
        ny = max(mon_y, min(ny, mon_y + mon_h - cur_h))
        self._block["position"] = "free"
        self._block["margin_x"] = nx - mon_x
        self._block["margin_y"] = ny - mon_y
        self._last_margins = None  # force the new margins through
        self._apply_geometry()

    def end_move(self) -> None:
        self._persist_position()

    def _persist_position(self) -> None:
        widgets = self._cfg.get("widgets")
        if isinstance(widgets, dict):
            widgets[self.WIDGET_ID] = self._block
        try:
            from .. import config as config_module

            config_module.save(self._cfg)
        except Exception:
            log.exception("could not persist position for widget %s", self.WIDGET_ID)
        try:
            from . import placement

            placement.set_widget(self.WIDGET_ID, self._block)
        except Exception:
            log.exception("could not persist placement for widget %s", self.WIDGET_ID)
