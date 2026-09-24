"""Hard-disk desktop widget: per-drive usage + aggregate read/write rates."""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.disk
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import Gtk  # noqa: E402

from ..widgets import Glyph  # noqa: E402
from .sampled import SampledWidget, clear, label, row  # noqa: E402


class DiskWidget(SampledWidget):
    WIDGET_ID = "disk"
    DEFAULT_REFRESH_S = 2

    def __init__(self, cfg: dict, block: dict):
        from ..monitor_data import DiskSampler

        self._sampler = DiskSampler(("/",))
        self._list: Gtk.Box | None = None
        self._rates: Gtk.Label | None = None
        super().__init__(cfg, block)

    def build_content(self) -> None:
        self._list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.root.pack_start(self._list, False, False, 0)
        if self._block.get("show_rates", True):
            self._rates = label("", "disk-rates")
            self.root.pack_start(self._rates, False, False, 0)

    def collect(self):
        from ..monitor_data import drives

        sample = self._sampler.sample()
        return {
            "drives": drives(),
            "read_bps": sample.get("read_bps", 0.0),
            "write_bps": sample.get("write_bps", 0.0),
        }

    def render(self, data) -> None:
        from ..monitor_data import fmt_bytes, fmt_rate

        if self._list is None:
            return
        clear(self._list)
        try:
            limit = max(1, int(self._block.get("drives_max", 3) or 3))
        except (TypeError, ValueError):
            limit = 3
        show_bar = self._block.get("show_bar", True)

        for drive in (data.get("drives") or [])[:limit]:
            cell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
            head = row(8)
            head.pack_start(Glyph(str(drive.get("glyph") or ""), "widget-icon"), False, False, 0)
            name = label(str(drive.get("model") or drive.get("name") or ""), "disk-name")
            name.set_ellipsize(3)  # Pango.EllipsizeMode.END
            head.pack_start(name, True, True, 0)
            used = float(drive.get("used_b") or 0)
            total = float(drive.get("size_b") or 0)
            frac = (used / total) if total > 0 else 0.0
            size = label(
                f"{fmt_bytes(used)} / {fmt_bytes(total)}" if total else "—",
                "disk-size",
            )
            head.pack_start(size, False, False, 0)
            cell.pack_start(head, False, False, 0)
            if show_bar and total > 0:
                bar = Gtk.ProgressBar()
                bar.get_style_context().add_class("widget-progress")
                bar.set_fraction(max(0.0, min(1.0, frac)))
                cell.pack_start(bar, False, False, 0)
            self._list.pack_start(cell, False, False, 0)
        self._list.show_all()

        if self._rates is not None:
            self._rates.set_text(
                f"\uf019  {fmt_rate(data.get('read_bps', 0.0))}    "
                f"\uf093  {fmt_rate(data.get('write_bps', 0.0))}"
            )
