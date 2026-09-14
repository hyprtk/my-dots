"""System monitor widget: CPU, RAM and disk usage (shown before the clock)."""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · sysmon
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import shutil

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib, Gtk  # noqa: E402

from .config import icon_size_for  # noqa: E402
from .monitor import SysMonitorDialog  # noqa: E402
from .popup import bind_hover_tooltip  # noqa: E402
from .widgets import Glyph, HoverButton  # noqa: E402

log = logging.getLogger("hyprtk_bar.sysmon")

_GB = 1024 ** 3


def _read_cpu_sample() -> tuple[int, int]:
    """Return (total, idle) CPU jiffies from /proc/stat."""
    try:
        with open("/proc/stat") as f:
            parts = f.readline().split()
        vals = [int(v) for v in parts[1:]]
        return sum(vals), vals[3] + vals[4]
    except (OSError, ValueError, IndexError):
        return 0, 0


def _read_mem() -> tuple[float, float, float]:
    """Return (used_pct, used_gb, total_gb)."""
    try:
        with open("/proc/meminfo") as f:
            data = {}
            for line in f:
                key, _, rest = line.partition(":")
                data[key] = int(rest.split()[0])
        total = data.get("MemTotal", 0)
        avail = data.get("MemAvailable", total - data.get("MemFree", 0))
        if total <= 0:
            return 0.0, 0.0, 0.0
        used = total - avail
        # meminfo values are in kilobytes; convert to bytes for the GB readout.
        return 100.0 * used / total, used * 1024 / _GB, total * 1024 / _GB
    except (OSError, ValueError):
        return 0.0, 0.0, 0.0


def _read_disk(path: str) -> tuple[float, float, float]:
    """Return (used_pct, used_gb, total_gb) for the given mount point."""
    try:
        usage = shutil.disk_usage(path)
        return 100.0 * usage.used / usage.total, usage.used / _GB, usage.total / _GB
    except OSError:
        return 0.0, 0.0, 0.0


class SysMon(HoverButton):
    """Compact CPU / RAM / disk readout with a hover tooltip."""

    def __init__(self, cfg: dict, ipc):
        super().__init__("sysmon", vertical=False, spacing=8)
        self._sys_cfg = cfg.get("sysmon") or {}
        self._interval = max(1, int(self._sys_cfg.get("interval", 2)))
        self._disk_path = self._sys_cfg.get("disk_path", "/")
        self._prev = _read_cpu_sample()
        self._labels: dict[str, Gtk.Label] = {}
        self._icons: list[Glyph] = []
        self._tip = ""
        font_cfg = cfg.get("font") or {}
        icon_size = icon_size_for(font_cfg.get("size", 16), font_cfg.get("icon_size", 0))

        for key, glyph in (
            ("cpu", "\uf2db"),  # fa-microchip
            ("mem", "\uefc5"),  # fa-memory (RAM)
            ("disk", "\U000f02ca"),  # md-harddisk
        ):
            item = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=3)
            img = Glyph(glyph, "accent-icon")
            img.set_pixel_size(icon_size)
            self._icons.append(img)
            item.pack_start(img, False, False, 0)
            label = Gtk.Label(label="--%")
            label.get_style_context().add_class("sysmon-value")
            item.pack_start(label, False, False, 0)
            self.box.pack_start(item, False, False, 0)
            self._labels[key] = label

        self._update()
        self._tick_id = GLib.timeout_add_seconds(self._interval, self._tick)
        bind_hover_tooltip(self, cfg, lambda: self._tip)

        # Left-click opens the Mission Center-style system monitor dialog.
        # Built lazily on first open — constructing the whole dialog (pages,
        # graphs, DMIDecode reads) at startup delays first paint.
        self._full_cfg = cfg
        self._monitor_enabled = bool(self._sys_cfg.get("monitor", True))
        self._popup = None

    def apply_font(self, font_size, icon_size=0) -> None:
        size = icon_size_for(font_size, icon_size)
        for img in self._icons:
            img.set_pixel_size(size)

    def _dialog(self) -> SysMonitorDialog | None:
        if not self._monitor_enabled:
            return None
        if self._popup is None:
            self._popup = SysMonitorDialog(self._full_cfg)
        return self._popup

    def _toggle_monitor(self) -> None:
        popup = self._dialog()
        if popup is None:
            return
        if popup.get_visible():
            popup.hide_popup()
        else:
            popup.show_above(self)

    def shutdown(self) -> None:
        if self._tick_id is not None:
            GLib.source_remove(self._tick_id)
            self._tick_id = None
        if self._popup is not None:
            if self._popup.get_visible():
                self._popup.hide_popup()
            self._popup.destroy()
            self._popup = None

    def _on_button_press(self, _widget, event):
        if event.button == 1:
            self._toggle_monitor()
        return True

    def _tick(self) -> bool:
        self._update()
        return GLib.SOURCE_CONTINUE

    def _update(self) -> None:
        cpu = self._cpu_pct()
        mem_pct, mem_used, mem_total = _read_mem()
        disk_pct, disk_used, disk_total = _read_disk(self._disk_path)

        for key, pct in (("cpu", cpu), ("mem", mem_pct), ("disk", disk_pct)):
            label = self._labels[key]
            label.set_text(f"{pct:.0f}%")
            self._apply_level(label, pct)

        self._tip = (
            f"CPU: {cpu:.0f}%\n"
            f"RAM: {mem_pct:.0f}% ({mem_used:.1f}/{mem_total:.1f} GB)\n"
            f"Disk: {disk_pct:.0f}% ({disk_used:.1f}/{disk_total:.1f} GB)"
        )

    def _cpu_pct(self) -> float:
        cur = _read_cpu_sample()
        prev = self._prev
        self._prev = cur
        total = cur[0] - prev[0]
        if total <= 0:
            return 0.0
        idle = cur[1] - prev[1]
        return 100.0 * (total - idle) / total

    @staticmethod
    def _apply_level(label: Gtk.Label, pct: float) -> None:
        ctx = label.get_style_context()
        if pct >= 90:
            ctx.add_class("high")
            ctx.remove_class("warn")
        elif pct >= 70:
            ctx.add_class("warn")
            ctx.remove_class("high")
        else:
            ctx.remove_class("high")
            ctx.remove_class("warn")