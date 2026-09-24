"""External control channel for desktop widgets (a FIFO the move helper writes).

Hyprland binds ``Super + Shift + left mouse`` (press / release) to
``hyprtk-bar-widget-move.sh``, which writes ``start`` / ``stop`` to a FIFO this
class watches. A FIFO is used rather than a Unix signal because GLib's signal
sources only accept a fixed set (SIGHUP/SIGINT/SIGTERM/SIGUSR1/SIGUSR2/
SIGWINCH) and the bar already uses all of the useful ones.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.control
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import os
from pathlib import Path

import gi
gi.require_version("GLib", "2.0")

from gi.repository import GLib  # noqa: E402

log = logging.getLogger("hyprtk_bar.desktop.control")

FIFO_NAME = "hyprtk-bar-widget-move.fifo"


def fifo_path() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(runtime) / FIFO_NAME


class WidgetMoveControl:
    """Watches the move FIFO and calls ``on_start`` / ``on_stop`` on commands."""

    def __init__(self, on_start, on_stop):
        self._on_start = on_start
        self._on_stop = on_stop
        self._path = fifo_path()
        self._fd: int | None = None
        self._source: int | None = None
        self._open()

    def _open(self) -> None:
        try:
            os.mkfifo(self._path, 0o600)
        except FileExistsError:
            pass
        except OSError:
            log.warning("could not create control fifo %s", self._path, exc_info=True)
            return
        try:
            # O_NONBLOCK so the read end opens immediately with no writer.
            self._fd = os.open(self._path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            log.warning("could not open control fifo %s", self._path, exc_info=True)
            self._fd = None
            return
        # Keep the read end open for the process lifetime: a FIFO reader at EOF
        # still receives a later writer's data, so there is no reopen window in
        # which the helper's write could block.
        self._source = GLib.io_add_watch(
            self._fd, GLib.PRIORITY_DEFAULT, GLib.IO_IN, self._on_read
        )

    def _on_read(self, fd, _condition) -> bool:
        try:
            data = os.read(fd, 256)
        except OSError:
            return GLib.SOURCE_CONTINUE
        if not data:
            # All writers closed (EOF); the reader stays open for the next one.
            return GLib.SOURCE_CONTINUE
        for line in data.decode(errors="replace").splitlines():
            self._handle(line.strip())
        return GLib.SOURCE_CONTINUE

    def _handle(self, command: str) -> None:
        if command == "start":
            self._on_start()
        elif command == "stop":
            self._on_stop()

    def shutdown(self) -> None:
        if self._source is not None:
            GLib.source_remove(self._source)
            self._source = None
        if self._fd is not None:
            try:
                os.close(self._fd)
            except OSError:
                pass
            self._fd = None
        try:
            os.unlink(self._path)
        except OSError:
            pass
