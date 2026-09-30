"""A drop-in ``HyprIPC`` for tests: same public surface, canned Hyprland data.

The bar's widgets read live desktop state through ``HyprIPC``. Under the headless
sway session there is no Hyprland, so this stands in. It records every dispatch
so tests can assert a click reached Hyprland, and it lets tests push synthetic
socket events with ``emit()``.
"""
from __future__ import annotations

from typing import Callable

MONITORS = [{
    "id": 0, "name": "HEADLESS-1", "description": "headless e2e monitor",
    "width": 1920, "height": 1080, "x": 0, "y": 0, "scale": 1.0, "focused": True,
    "activeWorkspace": {"id": 1, "name": "1"},
    "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080}, "model": "e2e",
}]

WORKSPACES = [
    {"id": i, "name": str(i), "monitor": "HEADLESS-1", "windows": 0, "hasfullscreen": False}
    for i in range(1, 6)
]

CLIENTS = [{
    "address": "0xdeadbeef", "class": "Alacritty", "title": "e2e terminal",
    "workspace": {"id": 1, "name": "1"}, "monitor": 0, "focusHistoryID": 0,
    "mapped": True, "hidden": False, "floating": False,
}]

LAYERS = {"HEADLESS-1": {"levels": {
    "0": [{"namespace": "hyprtk-bar", "pid": 0, "x": 0, "y": 0, "w": 1920, "h": 40}],
    "1": [], "2": [], "3": []}}}


class FakeIPC:
    """Records dispatches; answers Hyprland queries from the canned fixtures."""

    def __init__(self) -> None:
        self.dispatches: list[str] = []
        self.commands: list[str] = []
        self.handlers: dict[str, list[Callable]] = {}
        self.started = False

    # ── HyprIPC surface ─────────────────────────────────────────
    def query(self, *args):
        cmd = args[0] if args else ""
        return {
            "clients": CLIENTS,
            "workspaces": WORKSPACES,
            "monitors": MONITORS,
            "activewindow": {"class": "Alacritty", "title": "e2e terminal",
                             "address": "0xdeadbeef"},
            "layers": LAYERS,
        }.get(cmd, {})

    def dispatch(self, lua: str) -> bool:
        self.dispatches.append(lua)
        return True

    def command(self, cmd: str) -> str | None:
        self.commands.append(cmd)
        if cmd == "cursorpos":
            return "960, 540"
        return "ok"

    def cursor_pos(self):
        return (960, 540)

    def focus_workspace(self, workspace) -> bool:
        return self.dispatch(f"hl.dsp.focus({{ workspace = {workspace} }})")

    def focus_window(self, address: str) -> bool:
        return self.dispatch(f'hl.dsp.focus({{ window = "address:{address}" }})')

    def move_window(self, workspace, address: str) -> bool:
        return self.dispatch(f"hl.dsp.window.move({{ workspace={workspace}, window=address:{address} }})")

    def close_window(self, address: str) -> bool:
        return self.dispatch(f'hl.dsp.window.close({{ window = "address:{address}" }})')

    # ── event socket ────────────────────────────────────────────
    def on(self, event: str, callback) -> None:
        self.handlers.setdefault(event, []).append(callback)

    def on_connect(self, callback) -> None:
        self.handlers.setdefault("__connected__", []).append(callback)

    def start(self) -> None:
        self.started = True

    def stop(self) -> None:
        self.started = False

    def emit(self, event: str, data: dict | None = None) -> None:
        for cb in list(self.handlers.get(event, ())):
            cb(data or {})

    def emit_connect(self) -> None:
        for cb in list(self.handlers.get("__connected__", ())):
            cb()
