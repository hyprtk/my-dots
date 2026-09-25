"""Audio visualizer desktop widget.

Audio levels come from ``cava`` in raw-ascii mode: the widget writes a small
cava config, spawns ``cava -p <conf>`` and reads one ``;``-separated frame per
line on a worker thread. When cava is missing the widget falls back to a
synthetic animation so the surface still renders (useful on a fresh system and
for previewing the effects).

Effects (``style``): ``bars``, ``wave``, ``mirror``, ``dots`` and ``glow``,
drawn with cairo. Colours come from the bar palette (``accent`` / ``gradient`` /
``pywal``) or explicit overrides (``custom``).
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.visualizer
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import math
import os
import random
import stat
import subprocess
import threading
import time
from pathlib import Path

import cairo

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib, Gtk  # noqa: E402

from ..colors import hex_to_rgb  # noqa: E402
from .base import DesktopWidgetWindow  # noqa: E402

log = logging.getLogger("hyprtk_bar.desktop.visualizer")

CAVA_CONF_PATH = Path.home() / ".cache" / "hyprtk-bar" / "cava-hyprtk.conf"


def _resolve_binary(name: str) -> str | None:
    """Resolve a configured binary to a safe absolute path.

    ``cava_binary`` comes from the (shareable) config, so a poisoned ``PATH`` or
    a config pointing at an attacker-writable program must not make the bar run
    it. Returns ``None`` for anything that isn't a regular, executable,
    non-group/world-writable file.
    """
    name = str(name or "").strip()
    if not name:
        return None
    if os.sep in name:
        path = os.path.abspath(os.path.expanduser(name))
    else:
        import shutil

        path = shutil.which(name) or ""
    if not path:
        return None
    try:
        info = os.stat(path)
    except OSError:
        return None
    if not stat.S_ISREG(info.st_mode) or not os.access(path, os.X_OK):
        return None
    if info.st_mode & 0o022:  # group/world writable
        return None
    return path


def _write_cava_config(bars: int, fps: int) -> Path:
    CAVA_CONF_PATH.parent.mkdir(parents=True, exist_ok=True)
    CAVA_CONF_PATH.write_text(
        "[general]\n"
        f"bars = {max(8, int(bars))}\n"
        f"framerate = {max(15, int(fps))}\n"
        "autosens = 1\n"
        "lower_cutoff_freq = 50\n"
        "higher_cutoff_freq = 10000\n\n"
        "[output]\n"
        "method = raw\n"
        "raw_target = /dev/stdout\n"
        "data_format = ascii\n"
        "ascii_max_range = 100\n"
        "channels = mono\n\n"
        "[smoothing]\n"
        "monstercat = 1\n"
        "waves = 0\n"
        "noise_reduction = 0.77\n"
    )
    return CAVA_CONF_PATH


def _parse_frame(line: str) -> list[float]:
    """One raw-ascii cava frame (``"0;12;34;…"``) -> normalised levels."""
    values = []
    for token in line.strip().split(";"):
        token = token.strip()
        if not token:
            continue
        try:
            values.append(max(0.0, min(1.0, int(token) / 100.0)))
        except ValueError:
            return []
    return values


class CavaSource:
    """Spawns cava and streams normalised bar values to ``on_values``."""

    def __init__(self, binary: str, bars: int, fps: int, on_values):
        self._binary = binary
        self._bars = bars
        self._fps = fps
        self._on_values = on_values
        self._proc: subprocess.Popen | None = None
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()

    def start(self) -> bool:
        try:
            conf = _write_cava_config(self._bars, self._fps)
            self._proc = subprocess.Popen(
                [self._binary, "-p", str(conf)],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            log.info("cava unavailable (%s); using synthetic levels", exc)
            self._proc = None
            return False
        self._thread = threading.Thread(target=self._read, daemon=True)
        self._thread.start()
        return True

    def _read(self) -> None:
        proc = self._proc
        if proc is None or proc.stdout is None:
            return
        try:
            for line in proc.stdout:
                if self._stop.is_set():
                    break
                values = _parse_frame(line)
                if values:
                    # Store on the reader thread; the widget's own timer pulls
                    # it. A GLib.idle_add per frame would flood the main loop.
                    self._on_values(values)
        except (OSError, ValueError):
            pass
        finally:
            self._stop.set()

    def stop(self) -> None:
        self._stop.set()
        proc = self._proc
        if proc is not None and proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=1)
            except (OSError, subprocess.SubprocessError):
                try:
                    proc.kill()
                except OSError:
                    pass
        self._proc = None


class VisualizerWidget(DesktopWidgetWindow):
    WIDGET_ID = "visualizer"

    def __init__(self, cfg: dict, block: dict):
        self._timer_id: int | None = None
        self._alive = True
        self._source: CavaSource | None = None
        self._values: list[float] = []
        self._levels: list[float] = []
        self._peaks: list[float] = []
        self._pending: list[float] | None = None
        self._pending_lock = threading.Lock()
        self._last_levels: list[float] | None = None
        self._last_peaks: list[float] | None = None
        self._synthetic = False
        self._area: Gtk.DrawingArea | None = None
        self._c1 = (0.75, 0.52, 0.99)
        self._c2 = (0.13, 0.83, 0.93)
        self._frame = 0
        super().__init__(cfg, block)

    # ── build ────────────────────────────────────────────────────

    def build(self) -> None:
        block = self._block
        bars = max(8, int(block.get("bars", 48) or 48))
        width = int(block.get("width", 420) or 420)
        height = int(block.get("height", 120) or 120)
        padding = max(0, int(block.get("padding", 12) or 12))
        self._values = [0.0] * bars
        self._levels = [0.0] * bars
        self._peaks = [0.0] * bars

        self._area = Gtk.DrawingArea()
        self._area.set_size_request(max(40, width - 2 * padding), max(30, height - 2 * padding))
        self._area.set_hexpand(True)
        self._area.set_vexpand(True)
        self._area.get_style_context().add_class("visualizer-area")
        self._area.connect("draw", self._on_draw)
        self.root.pack_start(self._area, True, True, 0)

        self._start_source()
        fps = max(15, min(120, int(block.get("fps", 60) or 60)))
        self._timer_id = GLib.timeout_add(max(8, 1000 // fps), self._tick)

    def _start_source(self) -> None:
        if str(self._block.get("source", "cava")) == "synthetic":
            self._synthetic = True
            return
        binary = _resolve_binary(self._block.get("cava_binary") or "cava")
        if binary is None:
            log.info("cava binary not usable; using synthetic levels")
            self._synthetic = True
            return
        source = CavaSource(binary, len(self._values), int(self._block.get("fps", 60) or 60), self._on_values)
        if source.start():
            self._source = source
            self._synthetic = False
        else:
            self._synthetic = True

    # ── data ─────────────────────────────────────────────────────

    def _on_values(self, values: list[float]) -> None:
        """Called on the cava reader thread; just stash the frame."""
        with self._pending_lock:
            self._pending = values

    def _resample(self, values: list[float]) -> None:
        """Resample cava's bar count onto the configured bar count."""
        n = len(self._values)
        if n == 0:
            return
        if len(values) == n:
            self._values = list(values)
        else:
            self._values = [
                values[min(len(values) - 1, int(i * len(values) / n))] for i in range(n)
            ]

    def _synthetic_frame(self) -> None:
        t = time.time()
        n = len(self._values)
        for i in range(n):
            base = 0.5 + 0.5 * math.sin(t * 2.4 + i * 0.32)
            envelope = 0.55 + 0.45 * math.sin(t * 0.9 + i * 0.07)
            value = max(0.0, base * envelope) * 0.85
            value += random.uniform(0.0, 0.12)
            self._values[i] = min(1.0, value)

    def _tick(self) -> bool:
        with self._pending_lock:
            pending = self._pending
            self._pending = None
        if pending is not None:
            self._resample(pending)
        self._frame += 1
        if self._synthetic:
            self._synthetic_frame()
        sensitivity = float(self._block.get("sensitivity", 1.0) or 1.0)
        smoothing = float(self._block.get("smoothing", 0.6) or 0.6)
        for i, value in enumerate(self._values):
            target = min(1.0, value * sensitivity)
            current = self._levels[i]
            # fast attack, smoothed decay (the classic cava look)
            if target >= current:
                current = target
            else:
                current = target + (current - target) * smoothing
            self._levels[i] = max(0.0, min(1.0, current))
            self._peaks[i] = max(self._peaks[i] - 0.012, self._levels[i])
        # Redraw only when the picture actually changes — a silent cava stream
        # settles, after which the widget stops repainting entirely.
        levels = [round(v, 3) for v in self._levels]
        peaks = [round(v, 3) for v in self._peaks]
        if levels != self._last_levels or peaks != self._last_peaks:
            self._last_levels = levels
            self._last_peaks = peaks
            if self._area is not None:
                self._area.queue_draw()
        return GLib.SOURCE_CONTINUE

    def on_palette(self, palette: dict) -> None:
        self._resolve_colors(palette)
        if self._area is not None:
            self._area.queue_draw()

    def _resolve_colors(self, palette: dict) -> None:
        block = self._block
        mode = str(block.get("color_mode", "gradient"))
        accent = palette.get("accent", "#c084fc")
        sky = palette.get("sky", "#22d3ee")
        if mode == "custom":
            first = block.get("color") or block.get("gradient_from") or accent
            second = block.get("gradient_to") or first
        elif mode == "gradient":
            first = block.get("gradient_from") or accent
            second = block.get("gradient_to") or sky
        elif mode == "pywal":
            from ..config import load_pywal_colors

            pywal = load_pywal_colors() or {}
            first = pywal.get("color5") or accent
            second = pywal.get("color6") or sky
        else:  # accent
            first = second = accent
        self._c1 = _rgb(second)
        self._c2 = _rgb(first)

    # ── drawing ──────────────────────────────────────────────────

    def _on_draw(self, _widget, cr) -> bool:
        alloc = self._area.get_allocation()
        w, h = alloc.width, alloc.height
        if w <= 4 or h <= 4 or not self._levels:
            return True
        # Vertical orientation is the horizontal drawing rotated 90°, so the
        # effects don't each need an axis-swapped implementation.
        if str(self._block.get("orientation", "horizontal")) == "vertical":
            cr.translate(w, 0)
            cr.rotate(math.pi / 2)
            w, h = h, w
        style = str(self._block.get("style", "bars"))
        if style == "wave":
            self._draw_wave(cr, w, h)
        elif style == "mirror":
            self._draw_mirror(cr, w, h)
        elif style == "dots":
            self._draw_dots(cr, w, h)
        elif style == "glow":
            self._draw_bars(cr, w, h, glow=True)
        else:
            self._draw_bars(cr, w, h, glow=False)
        return True

    def _bar_geometry(self, w: int, h: int):
        n = len(self._levels)
        gap = max(1.0, w * 0.004)
        slot = w / n
        width = max(1.0, slot - gap)
        return n, slot, width

    def _gradient(self, cr, y0: float, y1: float):
        grad = cairo.LinearGradient(0, y0, 0, y1)
        grad.add_color_stop_rgb(0.0, *self._c1)
        grad.add_color_stop_rgb(1.0, *self._c2)
        return grad

    def _draw_bars(self, cr, w: int, h: int, glow: bool) -> None:
        n, slot, width = self._bar_geometry(w, h)
        show_peaks = bool(self._block.get("peak_dots", True))
        # One gradient per frame (was one per bar, ~48x): the ramp maps colour by
        # vertical position across the whole surface.
        grad = self._gradient(cr, 0, h)
        for i, level in enumerate(self._levels):
            bar_h = max(1.0, level * (h - 4))
            x = i * slot + (slot - width) / 2
            y = h - bar_h
            if glow:
                cr.set_source_rgba(self._c1[0], self._c1[1], self._c1[2], 0.22)
                _rounded(cr, x - 1.5, y - 2, width + 3, bar_h + 4, width / 2)
                cr.fill()
            cr.set_source(grad)
            _rounded(cr, x, y, width, bar_h, min(width / 2, 3))
            cr.fill()
            if show_peaks:
                py = max(1.0, y - 3)
                cr.set_source_rgba(*self._c1, 0.9)
                cr.arc(x + width / 2, py, max(1.0, width / 4), 0, 2 * math.pi)
                cr.fill()

    def _draw_mirror(self, cr, w: int, h: int) -> None:
        n, slot, width = self._bar_geometry(w, h)
        mid = h / 2
        cr.set_source(self._gradient(cr, 0, h))
        for i, level in enumerate(self._levels):
            bar_h = max(1.0, level * (h / 2 - 2))
            x = i * slot + (slot - width) / 2
            _rounded(cr, x, mid - bar_h, width, bar_h * 2, min(width / 2, 3))
            cr.fill()

    def _draw_dots(self, cr, w: int, h: int) -> None:
        n, slot, _width = self._bar_geometry(w, h)
        radius = max(1.5, min(slot / 2.4, h / 6))
        for i, level in enumerate(self._levels):
            cy = h - max(radius, level * (h - 2 * radius)) - radius
            cx = i * slot + slot / 2
            cr.set_source_rgba(self._c2[0], self._c2[1], self._c2[2], 0.25 + 0.75 * level)
            cr.arc(cx, cy, radius, 0, 2 * math.pi)
            cr.fill()

    def _draw_wave(self, cr, w: int, h: int) -> None:
        n = len(self._levels)
        if n < 2:
            return
        step = w / (n - 1)
        points = [
            (i * step, h - max(1.0, level * (h - 4)))
            for i, level in enumerate(self._levels)
        ]
        cr.move_to(points[0][0], h)
        for x, y in points:
            cr.line_to(x, y)
        cr.line_to(points[-1][0], h)
        cr.close_path()
        grad = self._gradient(cr, 0, h)
        grad.add_color_stop_rgba(0.0, self._c1[0], self._c1[1], self._c1[2], 0.35)
        grad.add_color_stop_rgba(1.0, self._c2[0], self._c2[1], self._c2[2], 0.03)
        cr.set_source(grad)
        cr.fill()
        cr.move_to(points[0][0], points[0][1])
        for x, y in points[1:]:
            cr.line_to(x, y)
        cr.set_line_width(2.0)
        cr.set_line_join(cairo.LINE_JOIN_ROUND)
        cr.set_source_rgb(*self._c1)
        cr.stroke()

    # ── teardown ─────────────────────────────────────────────────

    def shutdown(self) -> None:
        self._alive = False
        if self._timer_id is not None:
            GLib.source_remove(self._timer_id)
            self._timer_id = None
        if self._source is not None:
            self._source.stop()
            self._source = None


def _rgb(color: str) -> tuple[float, float, float]:
    r, g, b = hex_to_rgb(color) or (255, 255, 255)
    return r / 255, g / 255, b / 255


def _rounded(cr, x: float, y: float, w: float, h: float, r: float) -> None:
    r = max(0.0, min(r, w / 2, h / 2))
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 1.5 * math.pi)
    cr.close_path()
