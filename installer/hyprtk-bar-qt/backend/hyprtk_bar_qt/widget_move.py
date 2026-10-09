"""Desktop-widget move control channel (a FIFO).

Hyprland binds ``Super + Shift + left mouse`` (press -> ``start``, release ->
``stop``) to ``hyprtk-bar-qt-widget-move``, which writes to the bar's control
FIFO. The Qt bar watches that same FIFO (via this streamer) and drives the
cursor-polling move itself — the same model (and the same FIFO) as the GTK bar,
so the one existing keybind drives whichever bar is running.

Streams one JSON line per command: ``{"cmd": "start"|"stop"}``.
"""

from __future__ import annotations

import ctypes
import json
import os
import select
import signal
import stat
import sys
import time
from pathlib import Path

# Shared with the GTK bar so the existing Super+Shift+left bind reaches the Qt
# bar too (only one bar runs at a time).
FIFO_NAME = "hyprtk-bar-qt-widget-move.fifo"


def fifo_path() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(runtime) / FIFO_NAME


def ensure_fifo(path: Path) -> bool:
    try:
        os.mkfifo(path, 0o600)
        return True
    except FileExistsError:
        pass
    except OSError:
        return False
    try:
        info = os.lstat(path)
    except OSError:
        return False
    if not stat.S_ISFIFO(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        try:
            os.unlink(path)
            os.mkfifo(path, 0o600)
        except OSError:
            return False
    return True


def _arm_parent_death() -> None:
    """Ask the kernel to SIGTERM us if the bar (our parent) dies.

    Quickshell does not always reap Process children on exit, so without this a
    killed bar leaves an orphaned reader on the FIFO (and, with several, a race
    over which reader receives a command).
    """
    try:
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        PR_SET_PDEATHSIG = 1
        libc.prctl(PR_SET_PDEATHSIG, signal.SIGTERM, 0, 0, 0)
    except Exception:
        pass


def main(argv: list[str] | None = None) -> int:
    parent = os.getppid()
    _arm_parent_death()
    # If the parent already died between fork and prctl, exit now.
    if os.getppid() != parent:
        return 0

    path = fifo_path()
    if not ensure_fifo(path):
        return 1
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    except OSError:
        return 1
    try:
        while True:
            try:
                ready, _, _ = select.select([fd], [], [], 1.0)
            except InterruptedError:
                continue
            if not ready:
                continue
            data = os.read(fd, 256)
            if not data:
                # All writers closed; reopen the read end without a busy loop.
                os.close(fd)
                time.sleep(0.05)
                try:
                    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
                except OSError:
                    return 1
                continue
            for line in data.decode("utf-8", "replace").splitlines():
                cmd = line.strip()
                if cmd in ("start", "stop", "toggle"):
                    print(json.dumps({"cmd": cmd}), flush=True)
    except KeyboardInterrupt:
        return 0
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(path)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
