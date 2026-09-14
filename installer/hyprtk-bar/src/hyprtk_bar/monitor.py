"""Mission Center-style system monitor dialog for hyprtk-bar.

Opened by left-clicking the sysmon module: a layer-shell panel floated above the
bar with a sidebar of resource pages (CPU / Memory / Disks / Network / GPU /
Apps) and live cairo graphs + readouts. All colours come from the bar's palette
(pywal / imported theme / manual) so the panel always matches the bar.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · monitor
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import json
import logging
import os
import subprocess
import threading

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib, Gtk  # noqa: E402

from . import monitor_data  # noqa: E402
from .config import PYWAL_PATH, load_pywal_colors  # noqa: E402
from .graphs import HistoryGraph, core_colors  # noqa: E402
from .popup import Popup, center_layer_dialog  # noqa: E402
from .theme import resolve_palette  # noqa: E402
from .widgets import Glyph, HoverButton  # noqa: E402

log = logging.getLogger("hyprtk_bar.monitor")

PAGES = [
    ("cpu", "\uf2db", "CPU"),          # fa-microchip
    ("memory", "\uefc5", "Memory"),    # fa-memory
    ("disks", "\U000f02ca", "Disks"),  # md-harddisk
    ("network", "\uf1eb", "Network"),  # fa-wifi
    ("gpu", "\uf03d", "GPU"),          # fa-video-camera
    ("apps", "\uf0ae", "Apps"),        # fa-tasks
]

# Per-page graph colours come from the pywal palette (matching the waybar-era
# colour assignments) and fall back to the bar accent when pywal is absent.
_PAGE_PYWAL_KEYS = {
    "cpu": "color5",
    "memory": "color4",
    "disks": "color3",
    "network": "color2",
    "gpu": "color6",
}

_PAGE_TITLES = {key: label for key, _glyph, label in PAGES}

POLL_SECONDS = 1
DIALOG_WIDTH = 940
DIALOG_HEIGHT = 640


class GraphCard(Gtk.Box):
    """A titled history graph with a live value readout."""

    def __init__(self, cfg: dict, title: str, color_key: str,
                 height: int = 56, scale: float | None = 100.0,
                 multi: bool = False):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.color_key = color_key
        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        label = Gtk.Label(label=title, xalign=0)
        label.get_style_context().add_class("mc-graph-title")
        head.pack_start(label, True, True, 0)
        self.value = Gtk.Label(label="--", xalign=1)
        self.value.get_style_context().add_class("mc-graph-value")
        head.pack_start(self.value, False, False, 0)
        self.pack_start(head, False, False, 0)
        data_points = (cfg.get("sysmon") or {}).get("data_points", 60)
        self.graph = HistoryGraph(
            color="#7aa2f7",
            height=height,
            max_points=data_points,
            scale=scale,
            multi=multi,
        )
        self.pack_start(self.graph, False, False, 0)

    def set_graph_color(self, color: str) -> None:
        self.graph.set_color(color)


class CoreList(Gtk.Box):
    """Per-core/thread usage laid out in a 2-column grid (no scrolling needed).

    Each core gets a thin progress bar + live %. The grid height is sized to
    the current core count so every core is visible at once; it only scrolls
    on absurdly large core counts that cannot fit the fixed panel.
    """

    ROW_HEIGHT = 20
    MAX_HEIGHT = 300

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        label = Gtk.Label(label="Cores / Threads", xalign=0)
        label.get_style_context().add_class("mc-graph-title")
        head.pack_start(label, True, True, 0)
        self._count = Gtk.Label(label="", xalign=1)
        self._count.get_style_context().add_class("mc-stat-value")
        head.pack_start(self._count, False, False, 0)
        self.pack_start(head, False, False, 0)

        self._rows: list[tuple[Gtk.Label, Gtk.ProgressBar, Gtk.Label]] = []
        self._grid = Gtk.Grid(row_spacing=2, column_spacing=20)
        self._scroller = Gtk.ScrolledWindow()
        self._scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._scroller.add(self._grid)
        self.pack_start(self._scroller, True, True, 0)

    def update(self, pcts: list[float]) -> None:
        n = len(pcts)
        while len(self._rows) < n:
            self._rows.append(self._make_row(len(self._rows)))
        for i, pct in enumerate(pcts):
            lbl, bar, val = self._rows[i]
            lbl.set_text(f"Core {i}")
            bar.set_fraction(max(0.0, min(float(pct) / 100.0, 1.0)))
            val.set_text(f"{pct:.0f}%")
        for i in range(n, len(self._rows)):
            row = self._rows[i][0].get_parent()
            if row is not None:
                row.hide()
        self._count.set_text(f"{n} threads")
        rows_needed = (n + 1) // 2
        height = min(self.MAX_HEIGHT, 14 + rows_needed * self.ROW_HEIGHT)
        self._scroller.set_size_request(-1, max(60, height))
        self._grid.show_all()

    def _make_row(self, index: int) -> tuple[Gtk.Label, Gtk.ProgressBar, Gtk.Label]:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        lbl = Gtk.Label(label=f"Core {index}", xalign=0)
        lbl.set_width_chars(6)
        lbl.get_style_context().add_class("mc-stat-label")
        row.pack_start(lbl, False, False, 0)
        bar = Gtk.ProgressBar()
        bar.get_style_context().add_class("mc-core-bar")
        bar.set_hexpand(True)
        bar.set_show_text(False)
        row.pack_start(bar, True, True, 0)
        val = Gtk.Label(label="--%", xalign=1)
        val.set_width_chars(4)
        val.get_style_context().add_class("mc-stat-value")
        row.pack_start(val, False, False, 0)
        self._grid.attach(row, index % 2, index // 2, 1, 1)
        return lbl, bar, val


class DimmSection(Gtk.Box):
    """Memory slot layout graphic: one card per DIMM slot (populated + size).

    Data comes from SMBIOS via dmidecode; the fetch needs root, so it is done
    once through sudo/pkexec (cached to ~/.cache/hyprtk-bar/dimm.json) in a
    background thread when the dialog is first opened — never at bar startup.
    """

    def __init__(self, cfg: dict):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self._cfg = cfg
        self._fetching = False
        self._rendered = False

        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        title = Gtk.Label(label="Memory Slots", xalign=0)
        title.get_style_context().add_class("mc-graph-title")
        head.pack_start(title, True, True, 0)
        self._summary = Gtk.Label(label="", xalign=1)
        self._summary.get_style_context().add_class("mc-stat-value")
        head.pack_start(self._summary, False, False, 0)
        refresh = Gtk.Button()
        refresh.get_style_context().add_class("mc-close")
        refresh.set_relief(Gtk.ReliefStyle.NONE)
        refresh.set_tooltip_text("Re-read DIMM slots")
        glyph = Glyph("\uf021", "mc-icon")  # fa-refresh
        glyph.set_pixel_size(12)
        refresh.add(glyph)
        refresh.connect("clicked", lambda *_: self.ensure_loaded(force=True))
        head.pack_start(refresh, False, False, 0)
        self.pack_start(head, False, False, 0)

        self._status = Gtk.Label(label="", xalign=0)
        self._status.get_style_context().add_class("mc-unavailable")
        self.pack_start(self._status, False, False, 0)

        self._slot_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self._slot_box.set_hexpand(True)
        self.pack_start(self._slot_box, False, False, 0)

    def ensure_loaded(self, force: bool = False) -> None:
        """Fetch + render the slot graphic if not already shown (idempotent)."""
        if self._rendered and not force:
            return
        if self._fetching:
            return
        if not force:
            cached = monitor_data.dimm_slots(use_cache=True)
            if cached:
                self._render(cached)
                return
        self._fetching = True
        self._status.set_text("Reading DIMM slots\u2026")
        threading.Thread(target=self._fetch_worker, daemon=True).start()

    def _fetch_worker(self) -> None:
        slots = monitor_data.dimm_slots(use_cache=False)
        GLib.idle_add(self._on_fetch_done, slots)

    def _on_fetch_done(self, slots) -> bool:
        self._fetching = False
        if slots:
            self._render(slots)
        else:
            self._status.set_text("DIMM info unavailable \u2014 click refresh")
        return GLib.SOURCE_REMOVE

    def _render(self, slots: list[dict]) -> None:
        self._rendered = True
        self._status.set_text("")
        for child in list(self._slot_box.get_children()):
            self._slot_box.remove(child)
        populated = sum(1 for s in slots if s["populated"])
        total = sum(s["size_gb"] or 0 for s in slots)
        self._summary.set_text(f"{populated} populated \u00b7 {total:.0f} GB")
        for slot in slots:
            self._slot_box.pack_start(self._make_card(slot), True, True, 0)
        self._slot_box.show_all()

    @staticmethod
    def _make_card(slot: dict) -> Gtk.Widget:
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        card.set_size_request(-1, 58)
        ctx = card.get_style_context()
        ctx.add_class("dimm-slot")
        ctx.add_class("populated" if slot["populated"] else "empty")

        line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        line.set_halign(Gtk.Align.CENTER)
        glyph = Glyph("\uefc5", "mc-icon")  # fa-memory (RAM)
        glyph.set_pixel_size(13)
        if not slot["populated"]:
            glyph.get_style_context().add_class("dimmed")
        line.pack_start(glyph, False, False, 0)
        size_label = Gtk.Label(label="", xalign=0.5)
        size_label.get_style_context().add_class("dimm-size")
        line.pack_start(size_label, False, False, 0)
        card.pack_start(line, True, True, 0)

        loc_label = Gtk.Label(label="", xalign=0.5)
        loc_label.get_style_context().add_class("dimm-loc")
        card.pack_start(loc_label, False, False, 0)

        if slot["populated"]:
            size_label.set_text(f"{slot['size_gb']:.0f} GB")
        else:
            size_label.set_text("Empty")
        loc_label.set_text(slot["locator"])
        return card


class DriveGrid(Gtk.Box):
    """Compact per-drive cards: type glyph + size + available, in 3 columns.

    Cards are compact (two short rows: type/size, then a usage bar + free) so
    every attached drive is visible without scrolling. Cards persist and only
    update labels each tick; the grid rebuilds only on hotplug. The full model
    is available as a hover tooltip.
    """

    COLUMNS = 3
    ROW_HEIGHT = 44
    MAX_HEIGHT = 360

    def __init__(self, on_select=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._on_select = on_select
        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        title = Gtk.Label(label="Drives", xalign=0)
        title.get_style_context().add_class("mc-graph-title")
        head.pack_start(title, True, True, 0)
        self._count = Gtk.Label(label="", xalign=1)
        self._count.get_style_context().add_class("mc-stat-value")
        head.pack_start(self._count, False, False, 0)
        self.pack_start(head, False, False, 0)

        self._cards: dict[str, dict] = {}
        self._order: list[str] = []
        self._grid = Gtk.Grid(row_spacing=6, column_spacing=10)
        self._scroller = Gtk.ScrolledWindow()
        self._scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._scroller.add(self._grid)
        self.pack_start(self._scroller, True, True, 0)

    def update(self, drives: list[dict]) -> None:
        names = [d["name"] for d in drives]
        if names != self._order:
            for child in list(self._grid.get_children()):
                self._grid.remove(child)
            self._cards.clear()
            self._order = names
            for i, d in enumerate(drives):
                self._cards[d["name"]] = self._make_card(d)
                self._grid.attach(
                    self._cards[d["name"]]["ev"],
                    i % self.COLUMNS, i // self.COLUMNS, 1, 1,
                )
            self._grid.show_all()

        for d in drives:
            self._set_card(self._cards.get(d["name"]), d)

        self._count.set_text(f"{len(drives)} drives")
        rows = (len(drives) + self.COLUMNS - 1) // self.COLUMNS
        height = min(self.MAX_HEIGHT, 14 + rows * self.ROW_HEIGHT)
        self._scroller.set_size_request(-1, max(60, height))

    def set_selected(self, name: str | None) -> None:
        for n, card in self._cards.items():
            ctx = card["box"].get_style_context()
            if n == name:
                ctx.add_class("selected")
            else:
                ctx.remove_class("selected")

    def _on_click(self, name: str) -> bool:
        if self._on_select is not None:
            self._on_select(name)
        return True

    @staticmethod
    def _set_hover(box: Gtk.Box, on: bool) -> None:
        ctx = box.get_style_context()
        if on:
            ctx.add_class("hover")
        else:
            ctx.remove_class("hover")

    def _make_card(self, drive: dict) -> dict:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        box.set_size_request(-1, DriveGrid.ROW_HEIGHT - 10)
        ctx = box.get_style_context()
        ctx.add_class("drive-card")
        ctx.add_class(drive["type_key"])

        ev = Gtk.EventBox()
        ev.set_visible_window(False)
        ev.add(box)
        ev.set_tooltip_text(f"{drive['name']} \u2014 {drive['model']}")
        ev.connect("button-press-event",
                   lambda _w, _e, n=drive["name"]: self._on_click(n))
        ev.connect("enter-notify-event",
                   lambda _w, _e, b=box: DriveGrid._set_hover(b, True) or False)
        ev.connect("leave-notify-event",
                   lambda _w, _e, b=box: DriveGrid._set_hover(b, False) or False)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        glyph = Glyph(drive["glyph"], "mc-icon")
        glyph.set_pixel_size(12)
        top.pack_start(glyph, False, False, 0)
        type_lbl = Gtk.Label(label=drive["type_label"], xalign=0)
        type_lbl.get_style_context().add_class("drive-type")
        top.pack_start(type_lbl, True, True, 0)
        size_lbl = Gtk.Label(label="", xalign=1)
        size_lbl.get_style_context().add_class("drive-size")
        top.pack_start(size_lbl, False, False, 0)
        box.pack_start(top, True, True, 0)

        bottom = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        bar = Gtk.ProgressBar()
        bar.get_style_context().add_class("mc-core-bar")
        bar.set_hexpand(True)
        bar.set_show_text(False)
        bottom.pack_start(bar, True, True, 0)
        free_lbl = Gtk.Label(label="", xalign=1)
        free_lbl.get_style_context().add_class("drive-free")
        bottom.pack_start(free_lbl, False, False, 0)
        box.pack_start(bottom, False, False, 0)

        return {
            "box": box,
            "ev": ev,
            "type": type_lbl,
            "size": size_lbl,
            "free": free_lbl,
            "bar": bar,
        }

    @staticmethod
    def _set_card(card: dict | None, drive: dict) -> None:
        if card is None:
            return
        card["size"].set_text(
            monitor_data.fmt_bytes(drive["size_b"]) if drive["size_b"] > 0 else "\u2014"
        )
        if drive["mounted"]:
            free_text = f"{monitor_data.fmt_bytes(drive['free_b'])} free"
        elif drive["size_b"] == 0:
            free_text = "No media"
        else:
            free_text = "not mounted"
        card["free"].set_text(free_text)
        denom = drive["used_b"] + drive["free_b"]
        card["bar"].set_fraction(
            max(0.0, min(drive["used_b"] / denom, 1.0)) if denom > 0 else 0.0
        )


class InterfaceList(Gtk.Box):
    """One row per network interface: type glyph, name/type, IP, down/up rates."""

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        title = Gtk.Label(label="Interfaces", xalign=0)
        title.get_style_context().add_class("mc-graph-title")
        head.pack_start(title, True, True, 0)
        self._count = Gtk.Label(label="", xalign=1)
        self._count.get_style_context().add_class("mc-stat-value")
        head.pack_start(self._count, False, False, 0)
        self.pack_start(head, False, False, 0)

        self._rows: dict[str, dict] = {}
        self._order: list[str] = []
        self._box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.pack_start(self._box, False, False, 0)

    def update(self, ifaces: list[dict]) -> None:
        names = [i["name"] for i in ifaces]
        if names != self._order:
            for child in list(self._box.get_children()):
                self._box.remove(child)
            self._rows.clear()
            self._order = names
            for iface in ifaces:
                row = self._make_row(iface)
                self._rows[iface["name"]] = row
                self._box.pack_start(row["box"], False, False, 0)
            self._box.show_all()
        for iface in ifaces:
            self._set_row(self._rows.get(iface["name"]), iface)
        self._count.set_text(f"{len(ifaces)} interfaces")

    def _make_row(self, iface: dict) -> dict:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.get_style_context().add_class("iface-row")
        glyph = Glyph(iface["glyph"], f"iface-{iface['type_key']}")
        glyph.set_pixel_size(13)
        row.pack_start(glyph, False, False, 0)
        name_lbl = Gtk.Label(label=iface["name"], xalign=0)
        name_lbl.get_style_context().add_class("iface-name")
        name_lbl.set_width_chars(9)
        row.pack_start(name_lbl, False, False, 0)
        type_lbl = Gtk.Label(label=iface["type"], xalign=0)
        type_lbl.get_style_context().add_class("iface-type")
        type_lbl.set_width_chars(9)
        row.pack_start(type_lbl, False, False, 0)
        ip_lbl = Gtk.Label(label="", xalign=0)
        ip_lbl.get_style_context().add_class("iface-ip")
        ip_lbl.set_width_chars(15)
        row.pack_start(ip_lbl, True, True, 0)

        down = Glyph("\uf063", "iface-down")  # fa-arrow-down
        down.set_pixel_size(10)
        down_lbl = Gtk.Label(label="", xalign=1)
        down_lbl.get_style_context().add_class("iface-rate")
        row.pack_start(down, False, False, 0)
        row.pack_start(down_lbl, False, False, 0)
        up = Glyph("\uf062", "iface-up")  # fa-arrow-up
        up.set_pixel_size(10)
        up_lbl = Gtk.Label(label="", xalign=1)
        up_lbl.get_style_context().add_class("iface-rate")
        row.pack_start(up, False, False, 0)
        row.pack_start(up_lbl, False, False, 0)
        return {"box": row, "ip": ip_lbl, "down": down_lbl, "up": up_lbl}

    @staticmethod
    def _set_row(row: dict | None, iface: dict) -> None:
        if row is None:
            return
        row["ip"].set_text(iface["ip"] or "\u2014")
        row["down"].set_text(monitor_data.fmt_rate(iface["down_bps"]))
        row["up"].set_text(monitor_data.fmt_rate(iface["up_bps"]))


class Readouts(Gtk.Grid):
    """A two-column grid of (icon, label, value) rows."""

    def __init__(self):
        super().__init__(row_spacing=6, column_spacing=28)
        self.vals: dict[str, Gtk.Label] = {}
        self.icons: dict[str, Glyph] = {}
        self._index = 0

    def add(self, key: str, glyph: str, label: str) -> None:
        cell = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        icon = Glyph(glyph, "mc-icon")
        icon.set_pixel_size(14)
        cell.pack_start(icon, False, False, 0)
        lbl = Gtk.Label(label=label, xalign=0)
        lbl.get_style_context().add_class("mc-stat-label")
        cell.pack_start(lbl, True, True, 0)
        val = Gtk.Label(label="--", xalign=1)
        val.get_style_context().add_class("mc-stat-value")
        cell.pack_start(val, False, False, 0)
        self.attach(cell, self._index % 2, self._index // 2, 1, 1)
        self._index += 1
        self.vals[key] = val
        self.icons[key] = icon


class SysMonitorDialog(Popup):
    """The Mission Center-style panel: sidebar + per-page graphs/readouts."""

    def __init__(self, cfg: dict):
        super().__init__(cfg, cfg.get("position", "bottom"))
        self._cfg = cfg
        self._timer = None
        self._active = ""
        self._cards: dict[str, GraphCard] = {}
        self._stat_vals: dict[str, Gtk.Label] = {}
        self._side_buttons: dict[str, HoverButton] = {}
        self._graph_color: dict[str, str] = {}
        self._last_wal_mtime = None
        self._gpu_unavailable = None
        self._apps_store = None
        self._selected_drive = None
        self._gpu_static_loaded = False
        self._gpu_fetching = False
        self._gpu_model = None
        self._gpu_detail = None
        self._gpu_clocks = None

        self._samplers = {
            "cpu": monitor_data.CpuSampler(),
            "disk": monitor_data.DiskSampler(
                (str((cfg.get("sysmon") or {}).get("disk_path", "/")),)
            ),
            "net": monitor_data.NetSampler(
                str((cfg.get("sysmon") or {}).get("network_iface", "auto"))
            ),
        }
        self._built_pages = set(self._pages_enabled())
        self._refresh_busy = False

        self._refresh_colors(force=True)

        # Fixed panel size: content natural size must never resize the popup.
        self._fixed_size = (DIALOG_WIDTH, DIALOG_HEIGHT)
        self.set_size_request(DIALOG_WIDTH, DIALOG_HEIGHT)
        self.content.set_size_request(DIALOG_WIDTH, DIALOG_HEIGHT)

        # ── header ────────────────────────────────────────────────
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        title = Gtk.Label(label="System Monitor", xalign=0)
        title.get_style_context().add_class("mc-title")
        header.pack_start(title, True, True, 0)
        close = Gtk.Button(label="\u00d7")
        close.get_style_context().add_class("mc-close")
        close.set_relief(Gtk.ReliefStyle.NONE)
        close.connect("clicked", lambda *_: self.hide_popup())
        header.pack_start(close, False, False, 0)
        self.content.pack_start(header, False, False, 0)

        # ── body: sidebar + stack ─────────────────────────────────
        body = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        sidebar.get_style_context().add_class("mc-sidebar")
        sidebar.set_size_request(132, -1)
        self._sidebar = sidebar

        self._stack = Gtk.Stack()
        self._stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self._stack.set_transition_duration(120)

        for key, glyph, label in PAGES:
            if key not in self._pages_enabled():
                continue
            sidebar.pack_start(self._build_side_button(key, glyph, label),
                               False, False, 0)
            self._stack.add_named(self._build_page(key), key)

        body.pack_start(sidebar, False, False, 0)
        body.pack_start(self._stack, True, True, 0)
        self.content.pack_start(body, True, True, 0)

        self._set_active(self._pages_enabled()[0])
        self.content.show_all()

    # ── config ────────────────────────────────────────────────────

    def _pages_enabled(self) -> list[str]:
        pages = (self._cfg.get("sysmon") or {}).get("pages")
        allowed = {p[0] for p in PAGES}
        if isinstance(pages, list):
            clean = [p for p in pages if p in allowed]
            if clean:
                return clean
        return [p[0] for p in PAGES]

    # ── sidebar ───────────────────────────────────────────────────

    def _build_side_button(self, key: str, glyph: str, label: str) -> HoverButton:
        btn = HoverButton("mc-sidebar-button", vertical=False, spacing=8)
        btn.set_size_request(-1, 30)
        icon = Glyph(glyph, "mc-icon")
        icon.set_pixel_size(14)
        btn.box.pack_start(icon, False, False, 0)
        lbl = Gtk.Label(label=label, xalign=0)
        lbl.get_style_context().add_class("mc-sidebar-label")
        btn.box.pack_start(lbl, True, True, 0)
        btn.connect("button-press-event",
                    lambda _w, _e, k=key: self._on_side(k) or False)
        self._side_buttons[key] = btn
        return btn

    def _on_side(self, key: str) -> None:
        if key != self._active:
            self._set_active(key)
            self.refresh()

    def _set_active(self, key: str) -> None:
        self._active = key
        for k, btn in self._side_buttons.items():
            box = btn.box
            if k == key:
                box.get_style_context().add_class("active")
            else:
                box.get_style_context().remove_class("active")
        self._stack.set_visible_child_name(key)

    # ── pages ─────────────────────────────────────────────────────

    def _build_page(self, key: str) -> Gtk.Widget:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        page.set_hexpand(True)
        page_title = Gtk.Label(label=_PAGE_TITLES[key], xalign=0)
        page_title.get_style_context().add_class("mc-page-title")
        page.pack_start(page_title, False, False, 0)

        if key == "cpu":
            self._build_cpu_page(page)
        elif key == "memory":
            self._build_memory_page(page)
        elif key == "disks":
            self._build_disks_page(page)
        elif key == "network":
            self._build_network_page(page)
        elif key == "gpu":
            self._build_gpu_page(page)
        elif key == "apps":
            self._build_apps_page(page)
        return page

    def _build_cpu_page(self, page: Gtk.Box) -> None:
        self._cards["cpu"] = GraphCard(
            self._cfg, "CPU usage (all threads)", "cpu", scale=100.0, multi=True
        )
        page.pack_start(self._cards["cpu"], False, False, 0)
        self._cards["cpu_temp"] = GraphCard(
            self._cfg, "Temperature", "cpu", height=40, scale=None
        )
        page.pack_start(self._cards["cpu_temp"], False, False, 0)

        stats = Readouts()
        stats.add("load", "\uf0e4", "Load average")
        stats.add("procs", "\uf0ae", "Processes")
        stats.add("threads", "\uf1b3", "Threads")
        stats.add("uptime", "\uf017", "Uptime")
        stats.add("freq", "\uf2db", "Current frequency")
        stats.add("freq_max", "\uf2db", "Max frequency")
        stats.add("temp", "\uf2c9", "CPU temperature")
        stats.add("model", "\uf2db", "Model")
        page.pack_start(stats, False, False, 0)
        self._stat_vals.update(stats.vals)

        self._core_list = CoreList()
        page.pack_start(self._core_list, False, False, 0)

    def _build_memory_page(self, page: Gtk.Box) -> None:
        self._cards["mem"] = GraphCard(self._cfg, "Memory usage", "memory", scale=100.0)
        page.pack_start(self._cards["mem"], False, False, 0)
        self._cards["swap"] = GraphCard(
            self._cfg, "Swap", "memory", height=40, scale=100.0
        )
        page.pack_start(self._cards["swap"], False, False, 0)

        stats = Readouts()
        stats.add("used", "\uefc5", "Used")
        stats.add("total", "\uefc5", "Total")
        stats.add("avail", "\uefc5", "Available")
        stats.add("buffers", "\uf187", "Buffers")
        stats.add("cached", "\uf07c", "Cached")
        stats.add("swap_used", "\uf0ec", "Swap used")
        stats.add("swap_total", "\uf0ec", "Swap total")
        page.pack_start(stats, False, False, 0)
        self._stat_vals.update(stats.vals)

        self._dimm = DimmSection(self._cfg)
        page.pack_start(self._dimm, False, False, 0)

    def _build_disks_page(self, page: Gtk.Box) -> None:
        self._cards["disk_usage"] = GraphCard(
            self._cfg, "Disk usage", "disks", height=40, scale=100.0
        )
        page.pack_start(self._cards["disk_usage"], False, False, 0)
        self._cards["disk_read"] = GraphCard(
            self._cfg, "Read rate", "disks", height=28, scale=None
        )
        page.pack_start(self._cards["disk_read"], False, False, 0)
        self._cards["disk_write"] = GraphCard(
            self._cfg, "Write rate", "disks", height=28, scale=None
        )
        page.pack_start(self._cards["disk_write"], False, False, 0)

        stats = Readouts()
        stats.add("disk_used", "\U000f02ca", "Used")
        stats.add("disk_rate", "\uf0ec", "Total I/O")
        page.pack_start(stats, False, False, 0)
        self._stat_vals.update(stats.vals)

        self._drive_grid = DriveGrid(on_select=self._on_drive_selected)
        page.pack_start(self._drive_grid, False, False, 0)

    def _build_network_page(self, page: Gtk.Box) -> None:
        self._cards["net_down"] = GraphCard(
            self._cfg, "Download", "network", height=40, scale=None
        )
        page.pack_start(self._cards["net_down"], False, False, 0)
        self._cards["net_up"] = GraphCard(
            self._cfg, "Upload", "network", height=32, scale=None
        )
        page.pack_start(self._cards["net_up"], False, False, 0)

        stats = Readouts()
        stats.add("iface", "\uf1eb", "Interface")
        stats.add("type", "\uf1eb", "Type")
        stats.add("ip", "\uf1eb", "IP address")
        stats.add("down", "\uf0ab", "Download")
        stats.add("up", "\uf0aa", "Upload")
        page.pack_start(stats, False, False, 0)
        self._stat_vals.update(stats.vals)
        # Interface/Type/IP icons follow the active interface's kind glyph.
        self._iface_stat_icons = [
            stats.icons["iface"], stats.icons["type"], stats.icons["ip"],
        ]

        self._iface_list = InterfaceList()
        page.pack_start(self._iface_list, False, False, 0)

    def _build_gpu_page(self, page: Gtk.Box) -> None:
        self._cards["gpu_util"] = GraphCard(
            self._cfg, "GPU usage", "gpu", height=48, scale=100.0
        )
        page.pack_start(self._cards["gpu_util"], False, False, 0)
        self._cards["gpu_vram"] = GraphCard(
            self._cfg, "VRAM", "gpu", height=32, scale=100.0
        )
        page.pack_start(self._cards["gpu_vram"], False, False, 0)

        info_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        self._gpu_model = Gtk.Label(label="", xalign=0)
        self._gpu_model.get_style_context().add_class("gpu-model")
        info_box.pack_start(self._gpu_model, False, False, 0)
        self._gpu_detail = Gtk.Label(label="", xalign=0)
        self._gpu_detail.get_style_context().add_class("mc-stat-label")
        info_box.pack_start(self._gpu_detail, False, False, 0)
        self._gpu_clocks = Gtk.Label(label="", xalign=0)
        self._gpu_clocks.get_style_context().add_class("mc-stat-label")
        info_box.pack_start(self._gpu_clocks, False, False, 0)
        page.pack_start(info_box, False, False, 0)

        unavailable = Gtk.Label(label="GPU monitoring unavailable", xalign=0)
        unavailable.get_style_context().add_class("mc-unavailable")
        unavailable.set_visible(False)
        self._gpu_unavailable = unavailable
        page.pack_start(unavailable, False, False, 0)

        stats = Readouts()
        stats.add("gpu_util", "\uf03d", "Utilization")
        stats.add("gpu_vram", "\uf03d", "VRAM")
        stats.add("gpu_temp", "\uf2c9", "Temperature")
        stats.add("power", "\uf0e7", "Power")
        stats.add("fan", "\uf021", "Fan")
        page.pack_start(stats, False, False, 0)
        self._stat_vals.update(stats.vals)

    def _build_apps_page(self, page: Gtk.Box) -> None:
        # Four views: user apps, system apps, user processes, system processes.
        # Apps = processes owning a compositor window; processes = everything
        # owned by that user (apps included). Rows carry their pid in column 0.
        self._apps_views: dict[str, Gtk.TreeView] = {}
        self._apps_stores: dict[str, Gtk.ListStore] = {}
        self._apps_iters: dict[str, dict[int, Gtk.TreeIter]] = {}
        self._uid = os.getuid()

        notebook = Gtk.Notebook()
        notebook.get_style_context().add_class("settings-notebook")
        for key, label in (
            ("user-apps", "User apps"),
            ("system-apps", "System apps"),
            ("user-procs", "User processes"),
            ("system-procs", "System processes"),
        ):
            store = Gtk.ListStore(int, str, str, str)
            tree = Gtk.TreeView(model=store)
            tree.get_style_context().add_class("mc-tree")
            for i, title in enumerate(("Process", "CPU", "Memory")):
                renderer = Gtk.CellRendererText()
                if i:
                    renderer.set_property("xalign", 1)
                col = Gtk.TreeViewColumn(title, renderer, text=i + 1)
                col.set_expand(i == 0)
                if i:
                    col.set_alignment(1)
                tree.append_column(col)
            tree.set_search_column(1)
            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            scroll.set_vexpand(True)
            scroll.add(tree)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            box.pack_start(scroll, True, True, 0)
            notebook.append_page(box, Gtk.Label(label=label))
            self._apps_views[key] = tree
            self._apps_stores[key] = store
        notebook.set_vexpand(True)
        page.pack_start(notebook, True, True, 0)

        # ── actions: kill / force-kill / launch the selected process ──
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        bar.get_style_context().add_class("mc-actions")
        self._apps_selection = Gtk.Label(label="Select a process", xalign=0)
        self._apps_selection.set_opacity(0.7)
        self._apps_selection.set_ellipsize(3)
        bar.pack_start(self._apps_selection, True, True, 0)
        launch_btn = Gtk.Button(label="Launch")
        launch_btn.connect("clicked", lambda *_: self._apps_launch())
        kill_btn = Gtk.Button(label="Kill")
        kill_btn.get_style_context().add_class("settings-btn")
        kill_btn.connect("clicked", lambda *_: self._apps_kill(force=False))
        force_btn = Gtk.Button(label="Force kill")
        force_btn.get_style_context().add_class("settings-btn")
        force_btn.connect("clicked", lambda *_: self._apps_kill(force=True))
        for b in (launch_btn, kill_btn, force_btn):
            bar.pack_start(b, False, False, 0)
        page.pack_start(bar, False, False, 0)

        self._apps_notebook = notebook
        notebook.connect("switch-page", lambda *_: self._update_apps())

    # ── apps actions ──────────────────────────────────────────────

    def _active_apps_tree(self) -> Gtk.TreeView:
        return self._apps_views[self._active_apps_key()]

    def _active_apps_key(self) -> str:
        page = self._apps_notebook.get_current_page()
        return ("user-apps", "system-apps", "user-procs", "system-procs")[page]

    def _selected_process(self):
        tree = self._active_apps_tree()
        selection = tree.get_selection()
        if selection is None:
            return None
        model, it = selection.get_selected()
        if it is None:
            return None
        return model[it]

    def _apps_launch(self) -> None:
        row = self._selected_process()
        if row is None:
            self._apps_toast("Select a process to launch")
            return
        pid = int(row[0])
        name = str(row[1])
        if monitor_data.launch_process(pid):
            self._apps_toast(f"Launched {name}")
        else:
            self._apps_toast(f"Nothing to launch for {name} (no command line)")

    def _apps_kill(self, force: bool) -> None:
        row = self._selected_process()
        if row is None:
            self._apps_toast("Select a process to kill")
            return
        pid = int(row[0])
        name = str(row[1])
        verb = "Force kill" if force else "Kill"
        if not self._confirm(f"{verb} {name} (PID {pid})?"):
            return
        if monitor_data.kill_process(pid, force=force):
            self._apps_toast(f"{verb}ed {name}")
        else:
            self._apps_toast(f"Could not {verb.lower()} {name} (permission?)")

    def _apps_toast(self, text: str) -> None:
        if self._apps_selection is not None:
            self._apps_selection.set_text(text)

    def _confirm(self, text: str) -> bool:
        dialog = Gtk.MessageDialog(
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.NONE,
            text=text,
        )
        dialog.format_secondary_text(
            "This will terminate the process. Unsaved work in it will be lost."
        )
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        ok = dialog.add_button("OK", Gtk.ResponseType.ACCEPT)
        ok.get_style_context().add_class("confirm-accept")
        dialog.set_default_response(Gtk.ResponseType.CANCEL)
        center_layer_dialog(dialog)
        response = dialog.run()
        dialog.destroy()
        return response == Gtk.ResponseType.ACCEPT

    # ── theming ───────────────────────────────────────────────────

    def _wal_mtime(self):
        try:
            return PYWAL_PATH.stat().st_mtime
        except OSError:
            return None

    def _refresh_colors(self, force: bool = False) -> None:
        """Re-derive per-page graph colours when the wallpaper palette changes."""
        mtime = self._wal_mtime()
        if not force and mtime == self._last_wal_mtime:
            return
        self._last_wal_mtime = mtime
        palette = resolve_palette(self._cfg)
        accent = palette.get("accent", "#7aa2f7")
        pywal = load_pywal_colors() or {}
        self._graph_color = {
            key: pywal.get(pk) or accent
            for key, pk in _PAGE_PYWAL_KEYS.items()
        }
        for card in self._cards.values():
            card.set_graph_color(self._graph_color.get(card.color_key, accent))

    # ── per-page updates ──────────────────────────────────────────

    @staticmethod
    def _level_label(label: Gtk.Label, pct: float) -> None:
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

    def _update_cpu(self, data: dict) -> None:
        if "cpu" in self._cards:
            card = self._cards["cpu"]
            cores = data["cores"]
            accent = self._graph_color.get("cpu") or "#7aa2f7"
            colors = core_colors(accent, len(cores))
            card.graph.set_series_colors(
                {f"core{i}": c for i, c in enumerate(colors)}
            )
            card.graph.push_many({f"core{i}": v for i, v in enumerate(cores)})
            card.value.set_text(f"{data['overall']:.0f}%")
            self._level_label(card.value, data["overall"])

        temp = data.get("temp_c")
        if "cpu_temp" in self._cards:
            if temp is not None:
                self._cards["cpu_temp"].graph.push(temp)
                self._cards["cpu_temp"].value.set_text(f"{temp:.0f}\u00b0C")

        self._stat_vals["load"].set_text(
            f"{data['load'][0]:.2f} {data['load'][1]:.2f} {data['load'][2]:.2f}"
        )
        self._stat_vals["procs"].set_text(str(data["processes"]))
        self._stat_vals["threads"].set_text(str(data["threads"]))
        self._stat_vals["uptime"].set_text(monitor_data.fmt_uptime(data["uptime_s"]))
        self._stat_vals["freq"].set_text(
            f"{data['freq_mhz']:,} MHz" if data["freq_mhz"] else "--"
        )
        self._stat_vals["freq_max"].set_text(
            f"{data['freq_max_mhz']:,} MHz" if data["freq_max_mhz"] else "--"
        )
        self._stat_vals["temp"].set_text(
            f"{temp:.0f}\u00b0C" if temp is not None else "--"
        )
        self._stat_vals["model"].set_text(data["model"] or "--")

        core_list = getattr(self, "_core_list", None)
        if core_list is not None:
            core_list.update(data["cores"])

    def _update_memory(self, data: dict) -> None:
        self._cards["mem"].graph.push(data["used_pct"])
        self._cards["mem"].value.set_text(f"{data['used_pct']:.0f}%")
        self._level_label(self._cards["mem"].value, data["used_pct"])
        self._cards["swap"].graph.push(data["swap_pct"])
        self._cards["swap"].value.set_text(f"{data['swap_pct']:.0f}%")
        self._stat_vals["used"].set_text(f"{data['used_gb']:.1f} / {data['total_gb']:.1f} GB")
        self._stat_vals["total"].set_text(f"{data['total_gb']:.1f} GB")
        self._stat_vals["avail"].set_text(f"{data['avail_gb']:.1f} GB")
        self._stat_vals["buffers"].set_text(f"{data['buffers_gb']:.2f} GB")
        self._stat_vals["cached"].set_text(f"{data['cached_gb']:.2f} GB")
        self._stat_vals["swap_used"].set_text(f"{data['swap_used_gb']:.2f} GB")
        self._stat_vals["swap_total"].set_text(f"{data['swap_total_gb']:.2f} GB")

    def _update_disks(self, data: dict, drives: list[dict] | None = None) -> None:
        grid = getattr(self, "_drive_grid", None)
        if drives is None:
            drives = monitor_data.drives()
        if grid is not None:
            grid.update(drives)

        target, changed = self._resolve_selected(drives)
        if grid is not None:
            grid.set_selected(self._selected_drive)

        # I/O rates for the SELECTED drive (0 when the device isn't active).
        dev_rate = None
        if target is not None:
            dev_rate = next(
                (d for d in data["devices"] if d["name"] == target["name"]), None
            )
        read_bps = dev_rate["read_bps"] if dev_rate else 0.0
        write_bps = dev_rate["write_bps"] if dev_rate else 0.0

        if changed:
            for key in ("disk_usage", "disk_read", "disk_write"):
                if key in self._cards:
                    self._cards[key].graph.clear()

        if "disk_read" in self._cards:
            self._cards["disk_read"].graph.push(read_bps)
            self._cards["disk_read"].value.set_text(monitor_data.fmt_rate(read_bps))
            self._cards["disk_write"].graph.push(write_bps)
            self._cards["disk_write"].value.set_text(monitor_data.fmt_rate(write_bps))
            self._stat_vals["disk_rate"].set_text(
                monitor_data.fmt_rate(read_bps + write_bps)
            )

        if target is not None and "disk_usage" in self._cards:
            denom = target["used_b"] + target["free_b"]
            pct = 100.0 * target["used_b"] / denom if denom > 0 else 0.0
            self._cards["disk_usage"].graph.push(pct)
            self._cards["disk_usage"].value.set_text(f"{target['name']} {pct:.0f}%")
            self._level_label(self._cards["disk_usage"].value, pct)
            self._stat_vals["disk_used"].set_text(
                f"{monitor_data.fmt_bytes(target['used_b'])} / "
                f"{monitor_data.fmt_bytes(target['size_b'])}"
                if target["mounted"] and denom > 0
                else "not mounted"
            )

    def _resolve_selected(self, drives: list[dict]) -> tuple[dict | None, bool]:
        """The drive the usage graph tracks, defaulting to the system drive."""
        sel = self._selected_drive
        target = next((d for d in drives if d["name"] == sel), None)
        if target is None:
            target = (
                next((d for d in drives if d.get("is_root")), None)
                or next(
                    (d for d in drives if d["used_b"] + d["free_b"] > 0), None
                )
                or (drives[0] if drives else None)
            )
        if target is None:
            return None, False
        changed = target["name"] != sel
        if changed:
            self._selected_drive = target["name"]
        return target, changed

    def _on_drive_selected(self, name: str) -> None:
        self._selected_drive = name
        if "disk_usage" in self._cards:
            self._cards["disk_usage"].graph.clear()
        self.refresh()

    def _update_network(self, data: dict) -> None:
        self._cards["net_down"].graph.push(data["down_bps"])
        self._cards["net_down"].value.set_text(monitor_data.fmt_rate(data["down_bps"]))
        self._cards["net_up"].graph.push(data["up_bps"])
        self._cards["net_up"].value.set_text(monitor_data.fmt_rate(data["up_bps"]))
        self._stat_vals["iface"].set_text(data["iface"] or "--")
        self._stat_vals["type"].set_text(data["type"] or "--")
        self._stat_vals["ip"].set_text(data["ip"] or "--")
        self._stat_vals["down"].set_text(monitor_data.fmt_rate(data["down_bps"]))
        self._stat_vals["up"].set_text(monitor_data.fmt_rate(data["up_bps"]))

        # Interface/Type/IP icons reflect the connected device (ethernet, wifi…).
        glyph = data.get("glyph") or "\uf1eb"
        for icon in getattr(self, "_iface_stat_icons", []):
            icon.set_text(glyph)

        iface_list = getattr(self, "_iface_list", None)
        if iface_list is not None:
            iface_list.update(data["all"])

    def _update_gpu(self, data: dict | None) -> None:
        if data is None:
            if self._gpu_unavailable is not None:
                self._gpu_unavailable.show()
            return
        if self._gpu_unavailable is not None:
            self._gpu_unavailable.hide()

        util = data.get("util_pct")
        if util is not None:
            self._cards["gpu_util"].graph.push(util)
            self._cards["gpu_util"].value.set_text(f"{util:.0f}%")
            self._level_label(self._cards["gpu_util"].value, util)
        self._stat_vals["gpu_util"].set_text(
            f"{util:.0f}%" if util is not None else "--"
        )

        vram_total = data.get("vram_total_gb")
        vram_used = data.get("vram_used_gb")
        if vram_total:
            vram_pct = 100.0 * (vram_used or 0) / vram_total
            self._cards["gpu_vram"].graph.push(vram_pct)
            self._cards["gpu_vram"].value.set_text(
                f"{vram_used:.1f} / {vram_total:.1f} GB"
            )
            self._stat_vals["gpu_vram"].set_text(
                f"{vram_used:.1f} / {vram_total:.1f} GB"
            )
        else:
            # Shared-memory Intel or a value the driver didn't report.
            self._cards["gpu_vram"].graph.push(0.0)
            self._cards["gpu_vram"].value.set_text("shared")
            self._stat_vals["gpu_vram"].set_text("shared (system RAM)")

        temps = data.get("temps") or {}
        temp = temps.get("edge") or temps.get("junction") or temps.get("temp")
        self._stat_vals["gpu_temp"].set_text(
            f"{temp:.0f}\u00b0C" if temp is not None else "--"
        )
        power = data.get("power_w")
        self._stat_vals["power"].set_text(
            f"{power:.0f} W" if power is not None else "--"
        )
        fan_pct = data.get("fan_pct")
        if fan_pct is not None:
            self._stat_vals["fan"].set_text(f"{fan_pct:.0f}%")
        else:
            fan = data.get("fan_rpm")
            self._stat_vals["fan"].set_text(f"{fan} RPM" if fan is not None else "--")

        if self._gpu_clocks is not None:
            clocks = []
            if data.get("core_mhz"):
                clocks.append(f"Core {data['core_mhz']:,} MHz")
            if data.get("mem_mhz"):
                clocks.append(f"Mem {data['mem_mhz']:,} MHz")
            if data.get("core_max_mhz"):
                clocks.append(f"Max {data['core_max_mhz']:,} MHz")
            self._gpu_clocks.set_text(" \u00b7 ".join(clocks))

    # ── GPU static info (model / manufacturer / units / max clock) ──

    def _ensure_gpu_info(self, force: bool = False) -> None:
        if self._gpu_static_loaded and not force:
            return
        if self._gpu_fetching:
            return
        if not force:
            info = monitor_data.gpu_static(use_cache=True)
            if info:
                self._apply_gpu_static(info)
                return
        self._gpu_fetching = True
        threading.Thread(target=self._gpu_static_worker, daemon=True).start()

    def _gpu_static_worker(self) -> None:
        info = monitor_data.gpu_static(use_cache=False)
        GLib.idle_add(self._on_gpu_static, info)

    def _on_gpu_static(self, info) -> bool:
        self._gpu_fetching = False
        if info:
            self._apply_gpu_static(info)
        return GLib.SOURCE_REMOVE

    def _apply_gpu_static(self, info: dict) -> None:
        self._gpu_static_loaded = True
        if self._gpu_model is not None:
            self._gpu_model.set_text(info.get("model") or "")
        if self._gpu_detail is not None:
            parts = [info.get("manufacturer") or ""]
            if info.get("units"):
                parts.append(f"{info['units']} compute units")
            if info.get("max_clock"):
                parts.append(f"{info['max_clock']:,} MHz max")
            self._gpu_detail.set_text(" \u00b7 ".join(p for p in parts if p))

    def _window_pids(self) -> set[int]:
        """PIDs owning windows on the compositor (refreshed once per poll)."""
        try:
            out = subprocess.run(
                ["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=5
            ).stdout
            data = json.loads(out)
            return {int(w["pid"]) for w in data if isinstance(w, dict) and w.get("pid")}
        except Exception:
            return set()

    def _update_apps(self) -> None:
        # Collect process rows off the GTK thread (the /proc walk + hyprctl
        # spawn are the slow part), then apply to the stores on the main thread.
        def _work() -> None:
            rows = monitor_data.top_processes(window_pids=self._window_pids())
            GLib.idle_add(self._apply_apps_rows, rows)

        threading.Thread(target=_work, daemon=True).start()

    def _apply_apps_rows(self, rows: list[dict]) -> bool:
        if not getattr(self, "_apps_stores", None):
            return GLib.SOURCE_REMOVE
        buckets = {
            "user-apps": [], "system-apps": [],
            "user-procs": [], "system-procs": [],
        }
        for r in rows:
            user = r.get("uid") == self._uid
            app = bool(r.get("is_app"))
            if user:
                buckets["user-procs"].append(r)
                if app:
                    buckets["user-apps"].append(r)
            else:
                buckets["system-procs"].append(r)
                if app:
                    buckets["system-apps"].append(r)
        for key, store in self._apps_stores.items():
            self._sync_apps_store(key, store, buckets[key])
        return GLib.SOURCE_REMOVE

    def _sync_apps_store(
        self, key: str, store: Gtk.ListStore, rows: list[dict]
    ) -> None:
        """Reconcile one apps store by pid, in place.

        The list must hold every running app/process across polls, so rows are
        updated where they are and only added/removed on change — never
        clear()-ed and rebuilt (which made quiet apps vanish and dropped the
        user's selection every second).
        """
        iters = self._apps_iters.setdefault(key, {})
        seen: set[int] = set()
        for r in rows:
            pid = r["pid"]
            seen.add(pid)
            mem = monitor_data.fmt_bytes(r["mem"]) if r["mem"] > 0 else "--"
            values = (r["name"], f"{r['cpu']:.1f}", mem)
            it = iters.get(pid)
            if it is None or not store.iter_is_valid(it):
                iters[pid] = store.append([pid, *values])
            else:
                store.set(it, 1, values[0], 2, values[1], 3, values[2])
        for pid in [p for p in iters if p not in seen]:
            it = iters.pop(pid)
            if store.iter_is_valid(it):
                store.remove(it)

    # ── refresh ───────────────────────────────────────────────────

    def refresh(self) -> None:
        self._refresh_colors()
        built = self._built_pages
        if self._refresh_busy:
            return
        self._refresh_busy = True

        # Collect all samples off the GTK thread: drives()/gpu()/top_processes()
        # spawn subprocesses (lsblk / nvidia-smi / hyprctl) that would stall the
        # UI on a 1s poll. Widget updates are applied back on the main thread.
        def _work() -> None:
            data = {}
            if "cpu" in built:
                data["cpu"] = self._samplers["cpu"].sample()
            if "memory" in built:
                data["memory"] = monitor_data.memory()
            if "disks" in built:
                data["disk"] = self._samplers["disk"].sample()
                data["drives"] = monitor_data.drives()
            if "network" in built:
                data["net"] = self._samplers["net"].sample()
            if "gpu" in built:
                data["gpu"] = monitor_data.gpu()
            if self._active == "apps" and "apps" in built:
                data["apps"] = monitor_data.top_processes(
                    window_pids=self._window_pids()
                )
            GLib.idle_add(self._apply_refresh, data)

        threading.Thread(target=_work, daemon=True).start()

    def _apply_refresh(self, data: dict) -> bool:
        self._refresh_busy = False
        if "cpu" in data:
            self._update_cpu(data["cpu"])
        if "memory" in data:
            self._update_memory(data["memory"])
        if "disk" in data:
            self._update_disks(data["disk"], data.get("drives"))
        if "net" in data:
            self._update_network(data["net"])
        if "gpu" in data:
            self._update_gpu(data["gpu"])
        if "apps" in data:
            self._apply_apps_rows(data["apps"])
        return GLib.SOURCE_REMOVE

    # ── lifecycle ─────────────────────────────────────────────────

    def show_above(self, widget) -> None:
        self.refresh()
        self._start_poll()
        super().show_above(widget)
        # First open: lazily read the DIMM slots (may prompt via pkexec once).
        dimm = getattr(self, "_dimm", None)
        if dimm is not None:
            dimm.ensure_loaded()
        # First open: fetch static GPU identity (rocminfo) in the background.
        self._ensure_gpu_info()

    def hide_popup(self) -> None:
        self._stop_poll()
        super().hide_popup()

    def _start_poll(self) -> None:
        if self._timer is None:
            self._timer = GLib.timeout_add_seconds(POLL_SECONDS, self._on_poll)

    def _stop_poll(self) -> None:
        if self._timer is not None:
            GLib.source_remove(self._timer)
            self._timer = None

    def _on_poll(self) -> bool:
        try:
            self.refresh()
        except Exception:
            log.exception("system monitor refresh failed")
        return GLib.SOURCE_CONTINUE