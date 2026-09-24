"""Desktop widget manager: builds, themes, reloads and tears down the widgets.

Owned by the bar process. The manager diffs the ``widgets`` config block on
reload — creating newly-enabled widgets, updating placement/options on existing
ones, and destroying ones that were disabled — so the settings window's Apply
button is all it takes to turn a widget on or off live.

It also owns **snap groups**: widgets that share a ``snap_group`` id are laid out
adjacent along ``snap_axis`` with a uniform cell (the largest member's size) and
their content scaled to fit. Dragging a widget near another snaps them together.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.manager
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib  # noqa: E402

from ..config import WIDGET_IDS

log = logging.getLogger("hyprtk_bar.desktop.manager")

# How often the cursor is polled while a widget is being dragged.
MOVE_POLL_MS = 16
# Drop a widget with its edge within this many px of another to snap them.
SNAP_DIST = 28
# Gap between widgets in a snap group.
SNAP_GAP = 10
# Content-scale bounds for a snapped cell (fit ratio, allowing some upscale).
SNAP_SCALE_MIN = 0.4
SNAP_SCALE_MAX = 2.0
# Leave a little headroom so rounding in the fit never lets content overflow.
SNAP_FIT_MARGIN = 0.97


def _widget_classes() -> dict:
    # Imported lazily so a broken widget module can't stop the bar from starting.
    from .clock import ClockWidget
    from .disk import DiskWidget
    from .network import NetworkWidget
    from .resources import ResourcesWidget
    from .sysinfo import SysInfoWidget
    from .visualizer import VisualizerWidget
    from .weather import WeatherWidget

    return {
        "clock": ClockWidget,
        "weather": WeatherWidget,
        "visualizer": VisualizerWidget,
        "disk": DiskWidget,
        "network": NetworkWidget,
        "resources": ResourcesWidget,
        "sysinfo": SysInfoWidget,
    }


class DesktopWidgetManager:
    """Creates and tracks one layer-shell window per enabled desktop widget."""

    def __init__(self, cfg: dict, ipc=None):
        self._cfg = cfg
        self._ipc = ipc
        self._wins: dict = {}
        self._blocks: dict[str, dict] = {}
        self._palette: dict | None = None
        self._move_win = None
        self._move_timer: int | None = None
        self._snap_idle: int | None = None
        self._snap_anchor = None
        self.reload(cfg)

    def reload(self, cfg: dict) -> None:
        self._cfg = cfg
        widgets = cfg.get("widgets") or {}
        enabled = bool(widgets.get("enabled", True))
        wanted: dict[str, dict] = {}
        if enabled:
            for wid in WIDGET_IDS:
                block = widgets.get(wid) or {}
                if block.get("enabled"):
                    wanted[wid] = block

        # Rebuild a widget when it is newly enabled or its block changed (a
        # style/source change needs a fresh widget — an in-place update cannot
        # swap a clock's layout or restart cava); destroy it when disabled.
        for wid in list(self._wins):
            if wid not in wanted or self._blocks.get(wid) != wanted.get(wid):
                if self._wins[wid] is self._move_win:
                    self.end_move()
                self._destroy(self._wins.pop(wid))
                self._blocks.pop(wid, None)

        classes = _widget_classes()
        for wid, block in wanted.items():
            if wid in self._wins:
                continue
            cls = classes.get(wid)
            if cls is None:
                continue
            try:
                win = cls(cfg, block)
                win.show_all()
                self._wins[wid] = win
                self._blocks[wid] = block
            except Exception:
                log.exception("failed to build widget %s", wid)

        if self._palette is not None:
            self.apply_theme(self._palette)
        self._schedule_snap_layout()

    def apply_theme(self, palette: dict) -> None:
        self._palette = palette
        for wid, win in self._wins.items():
            try:
                win.apply_theme(palette)
            except Exception:
                log.exception("failed to theme widget %s", wid)

    # ── free move (Hyprland ``Super + Shift + left mouse``) ──────
    #
    # A layer-shell surface with keyboard_mode=none never sees the Super
    # modifier in GTK, so the gesture is a compositor bind: Super+Shift+LMB
    # (press / release) runs a helper that signals the bar. The bar then polls
    # the cursor (cheap command-socket query) and moves the widget under it.

    def begin_move(self) -> None:
        if self._ipc is None:
            return
        pos = self._ipc.cursor_pos()
        if pos is None:
            return
        win = self._widget_at(*pos)
        if win is None:
            return
        if str(win._block.get("snap_group") or "").strip():
            self._detach(win)
        win.begin_move(*pos)
        self._move_win = win
        if self._move_timer is None:
            self._move_timer = GLib.timeout_add(MOVE_POLL_MS, self._poll_move)

    def _poll_move(self) -> bool:
        if self._move_win is None or self._ipc is None:
            self._move_timer = None
            return GLib.SOURCE_REMOVE
        pos = self._ipc.cursor_pos()
        if pos is not None:
            self._move_win.move_to(*pos)
        return GLib.SOURCE_CONTINUE

    def end_move(self) -> None:
        if self._move_timer is not None:
            GLib.source_remove(self._move_timer)
            self._move_timer = None
        win = self._move_win
        self._move_win = None
        if win is None:
            return
        try:
            win.end_move()
        except Exception:
            log.exception("widget end_move failed")
        self._maybe_snap(win)

    def _widget_at(self, x: int, y: int):
        for win in self._wins.values():
            ox, oy = win._origin
            alloc = win.get_allocation()
            if ox <= x < ox + (alloc.width or 0) and oy <= y < oy + (alloc.height or 0):
                return win
        return None

    # ── snapping ─────────────────────────────────────────────────

    def _rect(self, win) -> tuple[int, int, int, int]:
        alloc = win.get_allocation()
        return win._origin[0], win._origin[1], alloc.width or 0, alloc.height or 0

    def _detach(self, win) -> None:
        """Take *win* out of its snap group, freezing its on-screen position."""
        block = win._block
        if not str(block.get("snap_group") or "").strip():
            return
        mx, my, _w, _h = win._monitor_geometry()
        block["position"] = "free"
        block["margin_x"] = max(0, win._origin[0] - mx)
        block["margin_y"] = max(0, win._origin[1] - my)
        block["snap_group"] = ""
        self._persist()
        self._schedule_snap_layout()

    def _maybe_snap(self, win) -> None:
        """Join *win* to the nearest widget if their edges are close enough."""
        rect = self._rect(win)
        best = None
        for other in self._wins.values():
            if other is win:
                continue
            gap, axis = self._snap_axis(rect, self._rect(other))
            if gap is None:
                continue
            if best is None or gap < best[0]:
                best = (gap, axis, other)
        if best is None:
            return
        _gap, axis, other = best
        existing = str(other._block.get("snap_group") or "").strip()
        group = existing or self._new_group_id()
        if not existing:
            # New group: the target becomes the first member on the dropped axis.
            other._block["snap_group"] = group
            other._block["snap_axis"] = axis
            other._block.setdefault("snap_order", 0)
        # A joining widget follows the group's existing axis.
        win._block["snap_group"] = group
        win._block["snap_axis"] = str(other._block.get("snap_axis") or axis)
        win._block["snap_order"] = self._max_order(group) + 1
        self._snap_anchor = win
        self._persist()
        self._schedule_snap_layout()

    @staticmethod
    def _snap_axis(a, b):
        """Return (gap, axis) if *a* and *b* are adjacent, else (None, None)."""
        ax, ay, aw, ah = a
        bx, by, bw, bh = b
        hgap = max(ax, bx) - min(ax + aw, bx + bw)
        vgap = max(ay, by) - min(ay + ah, by + bh)
        v_overlap = min(ay + ah, by + bh) - max(ay, by)
        h_overlap = min(ax + aw, bx + bw) - max(ax, bx)
        h_ok = hgap <= SNAP_DIST and v_overlap > min(ah, bh) * 0.4
        v_ok = vgap <= SNAP_DIST and h_overlap > min(aw, bw) * 0.4
        if h_ok and (not v_ok or hgap <= vgap):
            return hgap, "horizontal"
        if v_ok:
            return vgap, "vertical"
        return None, None

    def _new_group_id(self) -> str:
        existing = {
            str(w._block.get("snap_group") or "").strip() for w in self._wins.values()
        }
        index = 1
        while f"g{index}" in existing:
            index += 1
        return f"g{index}"

    def _max_order(self, group: str) -> int:
        orders = [
            int(w._block.get("snap_order", 0) or 0)
            for w in self._wins.values()
            if str(w._block.get("snap_group") or "").strip() == group
        ]
        return max(orders) if orders else -1

    def _schedule_snap_layout(self) -> None:
        if self._snap_idle is None:
            self._snap_idle = GLib.timeout_add(30, self._snap_layout_idle)

    def _snap_layout_idle(self) -> bool:
        self._snap_idle = None
        self._apply_snap_layout()
        return GLib.SOURCE_REMOVE

    def _usable_rect(self):
        """The monitor inset by the bar thickness (the widget-free border)."""
        if not self._wins:
            return None
        mon_x, mon_y, mon_w, mon_h = next(iter(self._wins.values()))._monitor_geometry()
        inset = 0
        if self._ipc is not None:
            monitors = self._ipc.query("monitors")
            if isinstance(monitors, list) and monitors:
                mon = next((m for m in monitors if m.get("focused")), monitors[0])
                reserved = mon.get("reserved")
                if isinstance(reserved, list) and reserved:
                    try:
                        inset = max(int(v) for v in reserved)
                    except (TypeError, ValueError):
                        inset = 0
        inset = max(0, inset)
        return (mon_x + inset, mon_y + inset, mon_x + mon_w - inset, mon_y + mon_h - inset)

    def _apply_snap_layout(self) -> None:
        """Lay out every widget inside the usable area; snap groups get a uniform
        cell with content scaled to fit."""
        bounds = self._usable_rect()
        for win in self._wins.values():
            win.clear_snap_layout()
            win.set_fit_scale(1.0)
            if bounds is not None:
                win.set_bounds(bounds)
            win._apply_geometry()  # ensure _origin reflects the block position
        anchor = self._snap_anchor
        self._snap_anchor = None
        if not self._wins:
            return
        if bounds is not None:
            bx0, by0, bx1, by1 = bounds
        else:
            mx, my, mw, mh = next(iter(self._wins.values()))._monitor_geometry()
            bx0, by0, bx1, by1 = mx, my, mx + mw, my + mh
        bw, bh = bx1 - bx0, by1 - by0

        groups: dict[str, list] = {}
        for wid, win in self._wins.items():
            gid = str(win._block.get("snap_group") or "").strip()
            if gid:
                groups.setdefault(gid, []).append((wid, win))

        grouped: set = set()
        for gid, members in groups.items():
            members.sort(key=lambda m: (int(m[1]._block.get("snap_order", 0) or 0), m[0]))
            nat = []
            for wid, win in members:
                w = int(win._block.get("width", 0) or 0)
                h = int(win._block.get("height", 0) or 0)
                pw, ph = win.natural_size()
                nat.append((w or pw or 200, h or ph or 120))
            cell_w = max(n[0] for n in nat)
            cell_h = max(n[1] for n in nat)

            axis = str(members[0][1]._block.get("snap_axis") or "horizontal")
            count = len(members)
            # Shrink the whole cell so the group fits the usable area.
            total_w = count * cell_w + (count - 1) * SNAP_GAP
            total_h = count * cell_h + (count - 1) * SNAP_GAP
            fit = min(
                1.0,
                bw / total_w if total_w else 1.0,
                bh / total_h if total_h else 1.0,
            )
            cell_w = max(40, int(cell_w * fit))
            cell_h = max(30, int(cell_h * fit))
            total_w = count * cell_w + (count - 1) * SNAP_GAP
            total_h = count * cell_h + (count - 1) * SNAP_GAP

            # Anchor the group on the widget that was just dropped (so it stays
            # where the user put it); otherwise the first member.
            anchor_index = next((i for i, (_w, w) in enumerate(members) if w is anchor), 0)
            ref_x, ref_y = members[anchor_index][1]._origin
            if axis == "vertical":
                base_x = ref_x
                base_y = ref_y - anchor_index * (cell_h + SNAP_GAP)
                base_y = max(by0, min(base_y, by0 + bh - total_h))
                base_x = max(bx0, min(base_x, bx0 + bw - cell_w))
            else:
                base_x = ref_x - anchor_index * (cell_w + SNAP_GAP)
                base_y = ref_y
                base_x = max(bx0, min(base_x, bx0 + bw - total_w))
                base_y = max(by0, min(base_y, by0 + bh - cell_h))

            for i, (wid, win) in enumerate(members):
                scale = min(cell_w / max(nat[i][0], 1), cell_h / max(nat[i][1], 1))
                scale = max(SNAP_SCALE_MIN, min(SNAP_SCALE_MAX, scale)) * SNAP_FIT_MARGIN
                if axis == "vertical":
                    x, y = base_x, base_y + i * (cell_h + SNAP_GAP)
                else:
                    x, y = base_x + i * (cell_w + SNAP_GAP), base_y
                try:
                    win.set_snap_layout(cell_w, cell_h, scale, x, y)
                    grouped.add(id(win))
                except Exception:
                    log.exception("snap layout failed for widget %s", wid)

        # Standalone widgets: scale content down if it doesn't fit the area.
        for win in self._wins.values():
            if id(win) in grouped:
                continue
            pw, ph = win.natural_size()
            fit = min(1.0, bw / max(pw, 1), bh / max(ph, 1))
            win.set_fit_scale(max(SNAP_SCALE_MIN, fit))

    # ── teardown ─────────────────────────────────────────────────

    def _persist(self) -> None:
        try:
            from .. import config as config_module

            config_module.save(self._cfg)
        except Exception:
            log.exception("could not persist widget layout")

    @staticmethod
    def _destroy(win) -> None:
        try:
            win.shutdown()
        except Exception:
            log.exception("widget shutdown failed")
        try:
            win.destroy()
        except Exception:
            pass

    def shutdown(self) -> None:
        self.end_move()
        if self._snap_idle is not None:
            GLib.source_remove(self._snap_idle)
            self._snap_idle = None
        for win in list(self._wins.values()):
            self._destroy(win)
        self._wins.clear()
        self._blocks.clear()
