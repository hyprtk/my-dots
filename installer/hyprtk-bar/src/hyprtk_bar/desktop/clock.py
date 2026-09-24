"""Clock desktop widget.

Three looks, selected by the ``style`` key (or a clock theme file):

- ``digital`` — a large numeric time with an optional date line.
- ``text``    — the time spelled out in words (``half past three``).
- ``dials``   — a cairo-drawn clock: one analog face with hands, or three
  concentric H/M/S progress rings.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.clock
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import datetime
import math

import cairo

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib, Gtk  # noqa: E402

from ..colors import hex_to_rgb  # noqa: E402
from .base import DesktopWidgetWindow  # noqa: E402
from .clock_theme import load_clock_theme  # noqa: E402

_ONES = [
    "twelve", "one", "two", "three", "four", "five", "six",
    "seven", "eight", "nine", "ten", "eleven",
]
_MINUTES = {
    0: "o'clock", 5: "five past", 10: "ten past", 15: "quarter past",
    20: "twenty past", 25: "twenty five past", 30: "half past",
    35: "twenty five to", 40: "twenty to", 45: "quarter to",
    50: "ten to", 55: "five to",
}


def time_in_words(now: datetime.datetime) -> str:
    """A 12-hour, rounded-to-5-minutes spelling of the time."""
    hour = now.hour % 12
    minute = now.minute
    rounded = (minute + 2) // 5 * 5
    if rounded >= 60:
        rounded = 0
        hour = (hour + 1) % 12
    if rounded == 0:
        return f"{_ONES[hour]} o'clock"
    phrase = _MINUTES.get(rounded)
    if phrase is None:
        return f"{_ONES[hour]} {rounded}"
    if rounded > 30:
        return f"{phrase} {_ONES[(hour + 1) % 12]}"
    return f"{phrase} {_ONES[hour]}"


class ClockWidget(DesktopWidgetWindow):
    WIDGET_ID = "clock"

    def __init__(self, cfg: dict, block: dict):
        self._timer_id: int | None = None
        self._labels: dict[str, Gtk.Label] = {}
        self._area: Gtk.DrawingArea | None = None
        self._dial_base = 150
        self._merged_cache: dict | None = None
        self._fg = "#ffffff"
        self._accent = "#c084fc"
        self._dim = (1.0, 1.0, 1.0, 0.25)
        super().__init__(cfg, block)

    # ── build ────────────────────────────────────────────────────

    def _merged(self) -> dict:
        """The theme file merged under the widget's config block (cached).

        Called on every tick/frame, so the file read + merge happens once per
        config change rather than once per second.
        """
        if self._merged_cache is not None:
            return self._merged_cache
        from ..config import _deep_merge

        theme = load_clock_theme(str(self._block.get("theme") or "default"))
        merged = _deep_merge(theme, self._block)
        # The flat config keys map onto the nested per-style block.
        dials = dict(merged.get("dials") or {})
        dials["count"] = int(merged.get("dial_count", dials.get("count", 1)) or 1)
        dials["ring_thickness"] = int(
            merged.get("ring_thickness", dials.get("ring_thickness", 6)) or 6
        )
        merged["dials"] = dials
        self._merged_cache = merged
        return merged

    def build(self) -> None:
        self._style = str(self._merged().get("style", "digital"))
        if self._style == "text":
            self._build_text()
        elif self._style == "dials":
            self._build_dials()
        else:
            self._build_digital()

        interval = 1000
        if self._style == "dials" and self._merged().get("show_seconds"):
            interval = 200
        self._update()
        self._timer_id = GLib.timeout_add(interval, self._tick)

    def _build_digital(self) -> None:
        self._labels["time"] = self._label("clock-time", "--:--")
        self._labels["date"] = self._label("clock-date", "")
        self.root.pack_start(self._labels["time"], False, False, 0)
        self.root.pack_start(self._labels["date"], False, False, 0)

    def _build_text(self) -> None:
        self._labels["words"] = self._label("clock-words", "…")
        self._labels["date"] = self._label("clock-date", "")
        self.root.pack_start(self._labels["words"], False, False, 0)
        self.root.pack_start(self._labels["date"], False, False, 0)

    def _build_dials(self) -> None:
        dials = self._merged().get("dials") or {}
        count = max(1, min(3, int(dials.get("count", 1) or 1)))
        size = 150 if count == 1 else 168
        self._dial_base = size
        self._area = Gtk.DrawingArea()
        self._area.set_size_request(size, size)
        self._area.set_halign(Gtk.Align.CENTER)
        self._area.connect("draw", self._draw_dials)
        self.root.pack_start(self._area, False, False, 0)
        if self._merged().get("show_date", True):
            self._labels["date"] = self._label("clock-date", "")
            self.root.pack_start(self._labels["date"], False, False, 0)
        if count == 3:
            rows = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            rows.set_halign(Gtk.Align.CENTER)
            for key, label in (("h", "H"), ("m", "M"), ("s", "S")):
                cell = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
                name = self._label("clock-dial-label", label)
                value = self._label("clock-dial-value", "--")
                cell.pack_start(name, False, False, 0)
                cell.pack_start(value, False, False, 0)
                rows.pack_start(cell, False, False, 0)
                self._labels[key] = value
            self.root.pack_start(rows, False, False, 0)

    @staticmethod
    def _label(css_class: str, text: str) -> Gtk.Label:
        label = Gtk.Label(label=text)
        label.get_style_context().add_class(css_class)
        label.set_justify(Gtk.Justification.CENTER)
        return label

    # ── update ───────────────────────────────────────────────────

    def _tick(self) -> bool:
        self._update()
        return GLib.SOURCE_CONTINUE

    def _update(self) -> None:
        merged = self._merged()
        now = datetime.datetime.now()
        if self._style == "text":
            words = time_in_words(now)
            if merged.get("text", {}).get("uppercase"):
                words = words.upper()
            self._labels["words"].set_text(words)
        elif self._style == "digital":
            fmt = merged.get("time_format") or "%H:%M"
            if merged.get("show_seconds") and "%S" not in fmt:
                fmt = f"{fmt}:%S"
            self._labels["time"].set_text(now.strftime(fmt))
        date = self._labels.get("date")
        if date is not None:
            if merged.get("show_date", True):
                date.set_text(now.strftime(merged.get("date_format") or "%A, %d %B"))
            else:
                date.set_text("")
        if self._style == "dials":
            if self._area is not None:
                self._area.queue_draw()
            if self._labels.get("h") is not None:
                self._labels["h"].set_text(f"{now.hour:02d}")
                self._labels["m"].set_text(f"{now.minute:02d}")
                self._labels["s"].set_text(f"{now.second:02d}")

    def on_palette(self, palette: dict) -> None:
        self._fg = palette.get("foreground", "#ffffff")
        self._accent = palette.get("accent", "#c084fc")
        self._dim = (1.0, 1.0, 1.0, 0.25)
        if self._area is not None:
            self._area.queue_draw()

    def on_content_scale(self, scale: float) -> None:
        if self._area is not None:
            size = max(24, int(round(self._dial_base * scale)))
            self._area.set_size_request(size, size)

    # ── cairo dials ──────────────────────────────────────────────

    @staticmethod
    def _rgba(color: str, alpha: float = 1.0):
        rgb = hex_to_rgb(color) or (255, 255, 255)
        return (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, alpha)

    def _draw_dials(self, _widget, cr) -> bool:
        alloc = self._area.get_allocation()
        w, h = alloc.width, alloc.height
        cx, cy = w / 2, h / 2
        radius = min(w, h) / 2 - 6
        if radius <= 4:
            return True
        dials = self._merged().get("dials") or {}
        thickness = max(1, int(dials.get("ring_thickness", 6) or 6))
        now = datetime.datetime.now()

        # faint full ring for the face
        cr.set_line_width(thickness)
        cr.set_source_rgba(*self._rgba(self._fg, 0.14))
        cr.arc(cx, cy, radius, 0, 2 * math.pi)
        cr.stroke()

        count = max(1, min(3, int(dials.get("count", 1) or 1)))
        if count == 1 and dials.get("show_hands", True):
            self._draw_ticks(cr, cx, cy, radius, thickness)
            self._draw_hands(cr, cx, cy, radius, now, dials)
        else:
            self._draw_rings(cr, cx, cy, radius, thickness, count, now)
        return True

    def _draw_ticks(self, cr, cx, cy, radius, thickness) -> None:
        for i in range(60):
            angle = math.radians(i * 6 - 90)
            major = i % 5 == 0
            inner = radius - (9 if major else 5)
            x1 = cx + math.cos(angle) * inner
            y1 = cy + math.sin(angle) * inner
            x2 = cx + math.cos(angle) * (radius - 2)
            y2 = cy + math.sin(angle) * (radius - 2)
            cr.set_line_width(2 if major else 1)
            cr.set_source_rgba(*self._rgba(self._fg, 0.55 if major else 0.25))
            cr.move_to(x1, y1)
            cr.line_to(x2, y2)
            cr.stroke()

    def _draw_hands(self, cr, cx, cy, radius, now, dials) -> None:
        seconds = now.second + now.microsecond / 1e6
        minutes = now.minute + seconds / 60
        hours = (now.hour % 12) + minutes / 60
        for fraction, length, width, color in (
            (hours / 12, radius * 0.5, 5, self._fg),
            (minutes / 60, radius * 0.72, 3.5, self._fg),
            (seconds / 60, radius * 0.82, 1.6, self._accent),
        ):
            angle = fraction * 2 * math.pi - math.pi / 2
            cr.set_line_width(width)
            cr.set_line_cap(cairo.LINE_CAP_ROUND)
            cr.set_source_rgba(*self._rgba(color, 0.95))
            cr.move_to(cx, cy)
            cr.line_to(
                cx + math.cos(angle) * length,
                cy + math.sin(angle) * length,
            )
            cr.stroke()
        cr.set_source_rgba(*self._rgba(self._accent, 0.95))
        cr.arc(cx, cy, max(2.5, radius * 0.04), 0, 2 * math.pi)
        cr.fill()

    def _draw_rings(self, cr, cx, cy, radius, thickness, count, now) -> None:
        seconds = now.second + now.microsecond / 1e6
        minutes = now.minute + seconds / 60
        hours = (now.hour % 12) + minutes / 60
        fractions = [hours / 12, minutes / 60, seconds / 60][:count]
        colors = [self._accent, self._fg, self._accent]
        gap = thickness + 3
        for index, fraction in enumerate(fractions):
            r = radius - index * gap
            if r <= 4:
                break
            cr.set_line_width(thickness)
            cr.set_line_cap(cairo.LINE_CAP_ROUND)
            cr.set_source_rgba(*self._rgba(colors[index], 0.9))
            cr.arc(cx, cy, r, -math.pi / 2, -math.pi / 2 + fraction * 2 * math.pi)
            cr.stroke()

    # ── teardown ─────────────────────────────────────────────────

    def shutdown(self) -> None:
        if self._timer_id is not None:
            GLib.source_remove(self._timer_id)
            self._timer_id = None
