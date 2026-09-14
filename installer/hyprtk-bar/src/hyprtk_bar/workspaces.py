"""Workspace chips widget: click to switch workspace (a mini task view)."""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · workspaces
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import Gtk  # noqa: E402

from .popup import bind_hover_tooltip  # noqa: E402
from .widgets import HoverButton  # noqa: E402


class WorkspaceChip(HoverButton):
    def __init__(self, workspace_id: int, ipc, cfg: dict):
        super().__init__("workspace-chip", vertical=False, spacing=0)
        self._wid = workspace_id
        self._ipc = ipc
        self._label = Gtk.Label(label=str(workspace_id))
        self._label.set_xalign(0.5)
        self.box.pack_start(self._label, True, True, 0)
        bind_hover_tooltip(self, cfg, lambda: f"Workspace {self._wid}")

    def set_state(self, active: bool, occupied: bool) -> None:
        ctx = self.box.get_style_context()
        if active:
            ctx.add_class("active")
        else:
            ctx.remove_class("active")
        if occupied and not active:
            ctx.add_class("occupied")
        else:
            ctx.remove_class("occupied")

    def _on_button_press(self, _widget, event):
        if event.button == 1:
            self._ipc.focus_workspace(self._wid)
        return True


class Workspaces(Gtk.Box):
    def __init__(self, cfg: dict, ipc):
        super().__init__(spacing=4)
        self._bar_cfg = cfg
        self._cfg = cfg.get("workspaces") or {}
        self._ipc = ipc
        self._chips: dict[int, WorkspaceChip] = {}
        self._active = 1

    def update(self, workspaces: list, active_id: int) -> None:
        self._active = active_id
        ids = {w["id"] for w in workspaces if isinstance(w.get("id"), int) and w["id"] > 0}
        ids.add(active_id if active_id > 0 else 1)
        if self._cfg.get("show_empty"):
            ids |= set(range(1, int(self._cfg.get("max", 6)) + 1))
        ordered = sorted(ids)

        for wid in list(self._chips):
            if wid not in ordered:
                self._chips.pop(wid).destroy()
        for wid in ordered:
            if wid not in self._chips:
                chip = WorkspaceChip(wid, self._ipc, self._bar_cfg)
                self._chips[wid] = chip
                self.pack_start(chip, False, False, 0)

        for wid, chip in self._chips.items():
            chip.set_state(wid == active_id, wid in ids)
        self.show_all()