"""Processor / RAM desktop widget: CPU load, memory, swap, temp and load avg."""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.resources
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import Gtk  # noqa: E402

from ..graphs import HistoryGraph  # noqa: E402
from .sampled import SampledWidget, label, row  # noqa: E402


def _bar() -> Gtk.ProgressBar:
    bar = Gtk.ProgressBar()
    bar.get_style_context().add_class("widget-progress")
    return bar


class ResourcesWidget(SampledWidget):
    WIDGET_ID = "resources"
    DEFAULT_REFRESH_S = 1

    def __init__(self, cfg: dict, block: dict):
        from ..monitor_data import CpuSampler

        self._cpu = CpuSampler()
        self._cpu_val: Gtk.Label | None = None
        self._cpu_bar: Gtk.ProgressBar | None = None
        self._graph: HistoryGraph | None = None
        self._ram_val: Gtk.Label | None = None
        self._ram_bar: Gtk.ProgressBar | None = None
        self._swap_val: Gtk.Label | None = None
        self._swap_bar: Gtk.ProgressBar | None = None
        self._meta: Gtk.Label | None = None
        self._multi = bool(block.get("show_cores", False))
        self._accent = "#7aa2f7"
        super().__init__(cfg, block)

    def build_content(self) -> None:
        if self._block.get("show_cpu", True):
            head = row(8)
            head.pack_start(label("CPU", "res-key"), False, False, 0)
            self._cpu_val = label("--", "res-val")
            self._cpu_val.set_halign(Gtk.Align.END)
            self._cpu_val.set_xalign(1)
            head.pack_end(self._cpu_val, False, False, 0)
            self.root.pack_start(head, False, False, 0)
            self._cpu_bar = _bar()
            self.root.pack_start(self._cpu_bar, False, False, 0)
            self._graph = HistoryGraph(
                color=self._accent, height=44, max_points=60, scale=100.0,
                multi=self._multi,
            )
            self._graph.get_style_context().add_class("widget-graph")
            self.root.pack_start(self._graph, False, False, 0)

        if self._block.get("show_ram", True):
            head = row(8)
            head.pack_start(label("RAM", "res-key"), False, False, 0)
            self._ram_val = label("--", "res-val")
            self._ram_val.set_halign(Gtk.Align.END)
            self._ram_val.set_xalign(1)
            head.pack_end(self._ram_val, False, False, 0)
            self.root.pack_start(head, False, False, 0)
            self._ram_bar = _bar()
            self.root.pack_start(self._ram_bar, False, False, 0)

        if self._block.get("show_swap", True):
            head = row(8)
            head.pack_start(label("Swap", "res-key"), False, False, 0)
            self._swap_val = label("--", "res-val")
            self._swap_val.set_halign(Gtk.Align.END)
            self._swap_val.set_xalign(1)
            head.pack_end(self._swap_val, False, False, 0)
            self.root.pack_start(head, False, False, 0)
            self._swap_bar = _bar()
            self.root.pack_start(self._swap_bar, False, False, 0)

        if self._block.get("show_temp", True) or self._block.get("show_load", True):
            self._meta = label("", "res-meta")
            self.root.pack_start(self._meta, False, False, 0)

    def collect(self):
        from ..monitor_data import memory

        return {"cpu": self._cpu.sample(full=False), "mem": memory()}

    def render(self, data) -> None:
        cpu = data.get("cpu") or {}
        mem = data.get("mem") or {}
        if self._cpu_val is not None:
            self._cpu_val.set_text(f"{cpu.get('overall', 0.0):.0f}%")
        if self._cpu_bar is not None:
            self._cpu_bar.set_fraction(max(0.0, min(1.0, cpu.get("overall", 0.0) / 100.0)))
        if self._graph is not None:
            cores = cpu.get("cores") or []
            if self._multi and cores:
                self._graph.push_many({f"c{i}": v for i, v in enumerate(cores)})
            else:
                self._graph.push(float(cpu.get("overall", 0.0)))

        if self._ram_val is not None:
            self._ram_val.set_text(
                f"{mem.get('used_gb', 0.0):.1f} / {mem.get('total_gb', 0.0):.0f} GiB"
            )
        if self._ram_bar is not None:
            self._ram_bar.set_fraction(max(0.0, min(1.0, mem.get("used_pct", 0.0) / 100.0)))
        if self._swap_val is not None:
            self._swap_val.set_text(
                f"{mem.get('swap_used_gb', 0.0):.1f} / {mem.get('swap_total_gb', 0.0):.0f} GiB"
            )
        if self._swap_bar is not None:
            self._swap_bar.set_fraction(max(0.0, min(1.0, mem.get("swap_pct", 0.0) / 100.0)))

        if self._meta is not None:
            parts = []
            temp = cpu.get("temp_c")
            if self._block.get("show_temp", True) and temp is not None:
                parts.append(f"{temp:.0f}°C")
            load = cpu.get("load") or ()
            if self._block.get("show_load", True) and load:
                parts.append("load " + " ".join(f"{v:.2f}" for v in load[:3]))
            self._meta.set_text("   ".join(parts))

    def on_content_scale(self, scale: float) -> None:
        if self._graph is not None:
            self._graph.set_size_request(-1, max(16, int(round(44 * scale))))
        self._sample()

    def on_palette(self, palette: dict) -> None:
        self._accent = palette.get("accent", "#7aa2f7")
        if self._graph is not None:
            if self._multi:
                from ..graphs import core_colors

                n = max(1, len(self._graph._series) or 8)
                self._graph.set_series_colors(
                    {f"c{i}": c for i, c in enumerate(core_colors(self._accent, n))}
                )
            else:
                self._graph.set_color(self._accent)
