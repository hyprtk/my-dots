"""Bridge the dotfiles' bar keybinds to the Qt bar.

The GTK bar's toggle scripts read the bar PID from
``$XDG_RUNTIME_DIR/hyprtk-bar-qt-<uid>.lock`` and send it a signal:

    SIGUSR1 → start menu   (Super+Space)
    SIGUSR2 → arc menu     (Super+Ctrl+M)
    SIGHUP  → clipboard    (Super+Ctrl+C)

The Qt bar has no PID file of its own, so this helper claims that lock file
when no live bar owns it, handles the three signals, and streams the matching
command to the bar (which flips the corresponding surface). Dying with the bar
(PDEATHSIG) keeps the lock file honest.
"""

from __future__ import annotations

import ctypes
import json
import os
import signal
import sys
import time
from pathlib import Path

SIGNALS = {
    signal.SIGUSR1: "menu",
    signal.SIGUSR2: "arc",
    signal.SIGHUP: "clipboard",
}


def lock_path() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(runtime) / f"hyprtk-bar-qt-{os.getuid()}.lock"


def _alive(pid: int) -> bool:
    return pid > 0 and os.path.isdir(f"/proc/{pid}")


def claim_lock(path: Path) -> bool:
    """Write our PID unless a live bar already owns the lock file."""
    try:
        owner = int(path.read_text().strip())
        if owner != os.getpid() and _alive(owner):
            return False
    except (OSError, ValueError):
        pass
    try:
        path.write_text(str(os.getpid()))
        return True
    except OSError:
        return False


def _arm_parent_death() -> None:
    try:
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        libc.prctl(1, signal.SIGTERM, 0, 0, 0)  # PR_SET_PDEATHSIG
    except Exception:
        pass


def main(argv: list[str] | None = None) -> int:
    parent = os.getppid()
    _arm_parent_death()
    if os.getppid() != parent:
        return 0

    claim_lock(lock_path())

    def emit(cmd: str):
        def handler(_signum, _frame):
            print(json.dumps({"cmd": cmd}), flush=True)
        return handler

    for sig, cmd in SIGNALS.items():
        signal.signal(sig, emit(cmd))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    raise SystemExit(main())
