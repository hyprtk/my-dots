"""Hyprland IPC: hyprctl queries plus the live event socket (socket2).

The event socket is read on a background thread; handlers run on that thread,
so callers must marshal updates to the GTK main loop (e.g. GLib.idle_add).
Reconnects automatically if Hyprland restarts, firing "__connected__" so
subscribers can do a full refresh.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · ipc
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import json
import logging
import os
import re
import socket
import subprocess
import threading
import time
from pathlib import Path

log = logging.getLogger("hyprtk_bar.ipc")


class HyprIPC:
    """Query/compose with Hyprland and subscribe to its event socket."""

    def __init__(self) -> None:
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        if not sig:
            raise RuntimeError(
                "HYPRLAND_INSTANCE_SIGNATURE is not set (not running under Hyprland?)"
            )
        self._socket_path = self._find_socket(sig)
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._handlers: dict[str, list] = {}
        self._connect_handlers: list = []
        self._version: tuple[int, ...] | None = None

    @staticmethod
    def _find_socket(sig: str) -> Path:
        """Locate the socket2 path (moved to $XDG_RUNTIME_DIR in newer Hyprland)."""
        candidates = [Path(os.environ.get("XDG_RUNTIME_DIR", "")) / "hypr", Path("/tmp/hypr")]
        for base in candidates:
            path = base / sig / ".socket2.sock"
            if path.exists():
                return path
        return candidates[0] / sig / ".socket2.sock"

    # ── hyprctl ───────────────────────────────────────────────────

    def query(self, *args):
        """Run `hyprctl -j <args>` and return parsed JSON, or None on failure."""
        try:
            out = subprocess.run(
                ["hyprctl", "-j", *args], capture_output=True, text=True, timeout=5
            )
        except (subprocess.SubprocessError, OSError) as exc:
            log.warning("hyprctl %s failed: %s", args, exc)
            return None
        if out.returncode != 0:
            log.warning("hyprctl %s: %s", args, out.stderr.strip())
            return None
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            log.warning("hyprctl %s returned non-JSON", args)
            return None

    def dispatch(self, lua: str) -> bool:
        """Run `hyprctl dispatch <lua>` and return True on success.

        Hyprland >=0.55 replaced the old `dispatch workspace 2` syntax with Lua
        dispatcher expressions (e.g. `hl.dsp.focus({ workspace = 2 })`).
        """
        try:
            out = subprocess.run(
                ["hyprctl", "dispatch", lua], capture_output=True, text=True, timeout=5
            )
        except (subprocess.SubprocessError, OSError) as exc:
            log.warning("hyprctl dispatch failed: %s", exc)
            return False
        if out.returncode != 0:
            log.warning("hyprctl dispatch %r: %s", lua, out.stderr.strip())
        return out.returncode == 0

    def _hypr_version(self) -> tuple[int, ...]:
        """Cached Hyprland version tuple (e.g. ``(0, 56, 2)``); ``()`` if unknown."""
        if self._version is None:
            self._version = ()
            try:
                out = subprocess.run(
                    ["hyprctl", "version"], capture_output=True, text=True, timeout=5
                )
                m = re.search(r"(\d+)\.(\d+)\.(\d+)", out.stdout or "")
                if m:
                    self._version = tuple(int(x) for x in m.groups())
            except (subprocess.SubprocessError, OSError):
                pass
        return self._version

    @property
    def _lua_dispatch(self) -> bool:
        """True on Hyprland >=0.55, which uses the Lua dispatcher grammar."""
        return self._hypr_version() >= (0, 55, 0)

    # High-level dispatcher actions (Hyprland Lua API).
    def focus_workspace(self, workspace) -> bool:
        if self._lua_dispatch:
            return self.dispatch(f"hl.dsp.focus({{ workspace = {workspace} }})")
        return self.dispatch(f"workspace {workspace}")

    def focus_window(self, address: str) -> bool:
        if self._lua_dispatch:
            return self.dispatch(f'hl.dsp.focus({{ window = "address:{address}" }})')
        return self.dispatch(f"focuswindow address:{address}")

    def move_window(self, workspace, address: str) -> bool:
        if self._lua_dispatch:
            return self.dispatch(
                f'hl.dsp.window.move({{ workspace = "{workspace}", window = "address:{address}" }})'
            )
        return self.dispatch(f"movetoworkspace {workspace},address:{address}")

    def close_window(self, address: str) -> bool:
        if self._lua_dispatch:
            return self.dispatch(f'hl.dsp.window.close({{ window = "address:{address}" }})')
        return self.dispatch(f"closewindow address:{address}")

    # ── event socket ─────────────────────────────────────────────

    def on(self, event: str, callback) -> None:
        self._handlers.setdefault(event, []).append(callback)

    def on_connect(self, callback) -> None:
        self._connect_handlers.append(callback)

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(
            target=self._run, name="hypr-ipc", daemon=True
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                    sock.connect(str(self._socket_path))
                    log.info("connected to Hyprland event socket")
                    self._fire_connect()
                    sock.settimeout(0.5)
                    buf = b""
                    while not self._stop.is_set():
                        try:
                            chunk = sock.recv(4096)
                        except socket.timeout:
                            continue
                        except OSError:
                            break
                        if not chunk:
                            break
                        buf += chunk
                        while b"\n" in buf:
                            line, buf = buf.split(b"\n", 1)
                            self._handle_line(line.decode(errors="replace").strip())
            except (OSError, ConnectionError) as exc:
                log.info("event socket error: %s (reconnecting)", exc)
            except Exception:
                log.exception("event socket crashed")
            if not self._stop.is_set():
                time.sleep(1)

    def _fire_connect(self) -> None:
        for cb in list(self._connect_handlers):
            try:
                cb()
            except Exception:
                log.exception("connect handler failed")

    def _handle_line(self, line: str) -> None:
        if not line:
            return
        if ">>" in line:
            event, _, payload = line.partition(">>")
        else:
            event, payload = line, ""
        event = event.lower().strip()
        data = self._parse_event(event, payload)
        for cb in list(self._handlers.get(event, ())):
            try:
                cb(data)
            except Exception:
                log.exception("handler for %r failed", event)

    @staticmethod
    def _parse_event(event: str, payload: str) -> dict:
        def parts(n: int) -> list[str]:
            split = payload.split(",", n - 1)
            return split + [""] * (n - len(split))

        def to_int(s: str):
            try:
                return int(s)
            except ValueError:
                return None

        try:
            if event == "openwindow":
                cls, title, addr = parts(3)
                return {"class": cls, "title": title, "address": addr}
            if event == "closewindow":
                return {"address": payload}
            if event == "activewindowv2":
                return {"address": payload}
            if event == "activewindow":
                cls, title = parts(2)
                return {"class": cls, "title": title}
            if event == "windowtitlev2":
                addr, title = parts(2)
                return {"address": addr, "title": title}
            if event == "windowclassv2":
                addr, cls = parts(2)
                return {"address": addr, "class": cls}
            if event == "workspacev2":
                ws, name, mon = parts(3)
                return {"id": to_int(ws), "name": name, "monitor": mon}
            if event == "workspace":
                # Newer Hyprland emits just the id here; the name is in workspacev2.
                ws, name = parts(2)
                return {"id": to_int(ws), "name": name or None}
            if event == "focusedmon":
                mon, ws = parts(2)
                return {"monitor": mon, "workspace": to_int(ws)}
            if event == "movewindow":
                return {"address": payload}
            if event == "changefloatingmode":
                addr, mode = parts(2)
                return {"address": addr, "floating": mode == "1"}
            if event == "fullscreen":
                return {"state": payload}
        except Exception as exc:  # never let a malformed event kill the socket thread
            log.warning("could not parse %r event %r: %s", event, payload, exc)
        return {"raw": payload}