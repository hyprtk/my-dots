"""Cairo history graphs for the system monitor dialog.

A rolling line + gradient-area graph drawn with cairo so the monitor pages get
real-time charts without pulling in a charting library. The newest value sits
at the right edge and history scrolls left, like Mission Center's graphs.

A graph can run in single-series mode (``push``, used by the Memory / Disks /
Network / GPU pages) or multi-series mode (``push_many``, used by the CPU page
to plot every thread/core at once).
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · graphs
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import re

import cairo

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import Gtk  # noqa: E402


def _parse_color(color: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    """Parse a #rgb/#rrggbb/#rrggbbaa/rgb()/rgba() color into (r, g, b, a)."""
    color = (color or "").strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})", color)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        r = int(h[0:2], 16) / 255.0
        g = int(h[2:4], 16) / 255.0
        b = int(h[4:6], 16) / 255.0
        if len(h) == 8:
            alpha = int(h[6:8], 16) / 255.0
        return (r, g, b, alpha)
    m = re.search(
        r"rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*([\d.]+))?\s*\)",
        color,
        re.I,
    )
    if m:
        return (
            float(m.group(1)) / 255.0,
            float(m.group(2)) / 255.0,
            float(m.group(3)) / 255.0,
            float(m.group(4)) if m.group(4) else alpha,
        )
    return (0.478, 0.635, 0.969, alpha)  # fallback blue


def _rgb_to_hsl(r: float, g: float, b: float) -> tuple[float, float, float]:
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2.0
    if mx == mn:
        return 0.0, 0.0, l
    d = mx - mn
    s = d / (2.0 - mx - mn) if l > 0.5 else d / (mx + mn)
    if mx == r:
        h = (g - b) / d + (6.0 if g < b else 0.0)
    elif mx == g:
        h = (b - r) / d + 2.0
    else:
        h = (r - g) / d + 4.0
    return h / 6.0, s, l


def _hsl_to_rgb(h: float, s: float, l: float) -> tuple[float, float, float]:
    def hue2rgb(p, q, t):
        if t < 0:
            t += 1
        if t > 1:
            t -= 1
        if t < 1 / 6:
            return p + (q - p) * 6 * t
        if t < 1 / 2:
            return q
        if t < 2 / 3:
            return p + (q - p) * (2 / 3 - t) * 6
        return p

    if s == 0:
        return l, l, l
    q = l * (1 + s) if l < 0.5 else l + s - l * s
    p = 2 * l - q
    return hue2rgb(p, q, h + 1 / 3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1 / 3)


def core_colors(base: str, n: int) -> list[str]:
    """``n`` harmonious colours derived from one accent (lightness sweep).

    Used to give each CPU core its own line in the per-thread graph while
    keeping the whole chart on the theme's hue.
    """
    r, g, b, _a = _parse_color(base, 1.0)
    h, s, _l = _rgb_to_hsl(r, g, b)
    colors = []
    for i in range(max(n, 1)):
        t = i / max(n - 1, 1)
        ll = min(max(0.45 + 0.4 * t, 0.1), 0.9)
        rr, gg, bb = _hsl_to_rgb(h, s, ll)
        colors.append(f"#{int(rr * 255):02x}{int(gg * 255):02x}{int(bb * 255):02x}")
    return colors


def _rounded_rect(cr, x: float, y: float, w: float, h: float, r: float) -> None:
    r = max(0.0, min(r, w / 2.0, h / 2.0))
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -1.5708, 0.0)
    cr.arc(x + w - r, y + h - r, r, 0.0, 1.5708)
    cr.arc(x + r, y + h - r, r, 1.5708, 3.14159)
    cr.arc(x + r, y + r, r, 3.14159, 4.71239)
    cr.close_path()


class HistoryGraph(Gtk.DrawingArea):
    """A rolling line/area chart, single- or multi-series.

    ``scale`` is a fixed ceiling for the y axis (e.g. 100 for a percentage);
    ``None`` autoscales to the highest observed value (used for byte/s rates).
    """

    def __init__(
        self,
        color: str = "#7aa2f7",
        height: int = 56,
        max_points: int = 60,
        scale: float | None = 100.0,
        radius: int = 8,
        multi: bool = False,
    ):
        super().__init__()
        self._series: dict[str, list[float]] = {}
        self._order: list[str] = []
        self._series_colors: dict[str, str] = {}
        self._max_points = max(10, int(max_points))
        self._scale = scale
        self._radius = radius
        self._color = color
        self._multi = multi
        self.set_size_request(-1, max(28, int(height)))
        self.set_hexpand(True)
        self.connect("draw", self._on_draw)

    def set_color(self, color: str) -> None:
        self._color = color
        self.queue_draw()

    def set_scale(self, scale: float | None) -> None:
        self._scale = scale
        self.queue_draw()

    def set_series_colors(self, mapping: dict[str, str]) -> None:
        self._series_colors.update(mapping)
        self.queue_draw()

    def push(self, value: float) -> None:
        """Push a value to the single default series."""
        self.push_many({"_default": value})

    def push_many(self, mapping: dict[str, float]) -> None:
        """Push one value per named series (e.g. a CPU core each)."""
        for name, value in mapping.items():
            try:
                v = float(value)
            except (TypeError, ValueError):
                v = 0.0
            if name not in self._series:
                self._series[name] = []
                self._order.append(name)
            values = self._series[name]
            values.append(v)
            overflow = len(values) - self._max_points
            if overflow > 0:
                del values[:overflow]
        self.queue_draw()

    def clear(self) -> None:
        self._series.clear()
        self._order.clear()
        self._series_colors.clear()
        self.queue_draw()

    def _on_draw(self, _widget, cr) -> bool:
        alloc = self.get_allocation()
        w, h = alloc.width, alloc.height
        if w <= 4 or h <= 4:
            return True

        # subtle inset panel behind the chart
        _rounded_rect(cr, 0, 0, w, h, self._radius)
        cr.set_source_rgba(1.0, 1.0, 1.0, 0.04)
        cr.fill()

        series = [(name, self._series[name]) for name in self._order]
        if not series:
            return True

        scale = self._scale
        if scale is None:
            scale = max(1.0, max(v for _n, vals in series for v in vals))
        if scale <= 0:
            scale = 1.0

        pad = 3.0
        x0, y0 = pad, pad
        xw, yh = w - pad * 2, h - pad * 2
        max_len = max(len(vals) for _n, vals in series)
        if max_len < 2:
            return True
        slot = self._max_points - 1

        def x_at(i: int) -> float:
            return x0 + i * (xw / slot if slot > 0 else 1)

        def y_at(v: float) -> float:
            ratio = min(max(v / scale, 0.0), 1.0)
            return y0 + (1.0 - ratio) * yh

        # single-series: gradient area fill + a thicker line
        if len(series) == 1 and series[0][0] == "_default":
            vals = series[0][1]
            r, g, b, _a = _parse_color(self._color, 1.0)

            cr.move_to(x_at(0), y_at(vals[0]))
            for i in range(1, len(vals)):
                cr.line_to(x_at(i), y_at(vals[i]))
            cr.line_to(x_at(len(vals) - 1), y0 + yh)
            cr.line_to(x_at(0), y0 + yh)
            cr.close_path()
            grad = cairo.LinearGradient(x0, y0, x0, y0 + yh)
            grad.add_color_stop_rgba(0.0, r, g, b, 0.32)
            grad.add_color_stop_rgba(1.0, r, g, b, 0.02)
            cr.set_source(grad)
            cr.fill()

            cr.move_to(x_at(0), y_at(vals[0]))
            for i in range(1, len(vals)):
                cr.line_to(x_at(i), y_at(vals[i]))
            cr.set_line_width(2.0)
            cr.set_line_join(cairo.LINE_JOIN_ROUND)
            cr.set_source_rgba(r, g, b, 0.95)
            cr.stroke()
            return True

        # multi-series: one thin line per series (no fills — they'd stack opaque)
        for name, vals in series:
            r, g, b, _a = _parse_color(self._series_colors.get(name, self._color), 1.0)
            cr.move_to(x_at(0), y_at(vals[0]))
            for i in range(1, len(vals)):
                cr.line_to(x_at(i), y_at(vals[i]))
            cr.set_line_width(1.5)
            cr.set_line_join(cairo.LINE_JOIN_ROUND)
            cr.set_source_rgba(r, g, b, 0.9)
            cr.stroke()

        return True