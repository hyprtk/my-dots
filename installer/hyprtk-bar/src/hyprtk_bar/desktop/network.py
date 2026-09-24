"""Network desktop widget: interface, IP, up/down rates and a rate graph."""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.network
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import Gtk  # noqa: E402

from ..graphs import HistoryGraph  # noqa: E402
from ..widgets import Glyph  # noqa: E402
from .sampled import SampledWidget, label, row  # noqa: E402


class NetworkWidget(SampledWidget):
    WIDGET_ID = "network"
    DEFAULT_REFRESH_S = 1

    def __init__(self, cfg: dict, block: dict):
        from ..monitor_data import NetSampler

        self._sampler = NetSampler(str(block.get("interface") or "auto"))
        self._icon: Glyph | None = None
        self._name: Gtk.Label | None = None
        self._ip: Gtk.Label | None = None
        self._rates: Gtk.Label | None = None
        self._graph: HistoryGraph | None = None
        self._accent = "#7aa2f7"
        super().__init__(cfg, block)

    def build_content(self) -> None:
        head = row(8)
        self._icon = Glyph("\uf1eb", "widget-icon")
        head.pack_start(self._icon, False, False, 0)
        self._name = label("", "net-name")
        head.pack_start(self._name, True, True, 0)
        self.root.pack_start(head, False, False, 0)
        if self._block.get("show_ip", True):
            self._ip = label("", "net-ip")
            self.root.pack_start(self._ip, False, False, 0)
        if self._block.get("show_rates", True):
            self._rates = label("", "net-rates")
            self.root.pack_start(self._rates, False, False, 0)
        if self._block.get("show_graph", True):
            self._graph = HistoryGraph(color=self._accent, height=44, max_points=60, scale=None)
            self._graph.get_style_context().add_class("widget-graph")
            self.root.pack_start(self._graph, False, False, 0)

    def collect(self):
        return self._sampler.sample()

    def render(self, data) -> None:
        from ..monitor_data import fmt_rate

        if self._icon is not None:
            self._icon.set_text(str(data.get("glyph") or "\uf1eb"))
        if self._name is not None:
            self._name.set_text(str(data.get("iface") or "—"))
        if self._ip is not None:
            self._ip.set_text(str(data.get("ip") or "no address"))
        if self._rates is not None:
            self._rates.set_text(
                f"\uf019  {fmt_rate(data.get('down_bps', 0.0))}    "
                f"\uf093  {fmt_rate(data.get('up_bps', 0.0))}"
            )
        if self._graph is not None:
            self._graph.push(float(data.get("down_bps", 0.0)))

    def on_palette(self, palette: dict) -> None:
        self._accent = palette.get("accent", "#7aa2f7")
        if self._graph is not None:
            self._graph.set_color(self._accent)
