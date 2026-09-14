"""Central spawn/run helpers for hyprtk-bar.

Single place for argv/detach/timeout discipline so callers never hand a raw
string to a shell by accident.

Rules of thumb:
  * Have an argv list?  -> ``spawn_argv`` / ``run_checked``.
  * Have a command *line* (quoted args, ``~``)?  -> ``spawn_command_line``.
  * The string is *intentionally* a shell script (``&&``/``||``/``;``, ``~``
    mid-argument, redirections)?  -> ``run_shell`` — one explicit ``sh -c``.
  * Need stdout back?  -> ``run_checked`` (blocks; keep off the UI thread).
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · proc
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import os
import shlex
import shutil
import subprocess

import gi
gi.require_version("GLib", "2.0")

from gi.repository import GLib  # noqa: E402

log = logging.getLogger("hyprtk_bar.proc")


def _home_bin_path() -> str:
    """PATH with ~/.local/bin prepended (the bar runs with a minimal PATH)."""
    path = os.environ.get("PATH", "")
    home_bin = os.path.expanduser("~/.local/bin")
    if home_bin not in path.split(":"):
        return home_bin + ":" + path
    return path


def resolve_binary(name: str):
    """Resolve an executable name against PATH incl. ~/.local/bin."""
    if not name:
        return None
    return shutil.which(name, path=_home_bin_path())


def bootstrap_environment() -> None:
    """Make the bundled tools reachable for the bar and every child it spawns.

    Hyprland launches the bar with a minimal PATH, so prepend ~/.local/bin
    (where install.sh puts the bundled `wal` launcher) and export HYPRTK_WAL so
    the vendored pywal16 is found by shell scripts even when ~/.local/bin is
    absent from a child's PATH.
    """
    os.environ["PATH"] = _home_bin_path()
    if not os.environ.get("HYPRTK_WAL"):
        wal = resolve_binary("wal")
        if wal:
            os.environ["HYPRTK_WAL"] = wal


def spawn_argv(argv: list[str], working_directory: str = "") -> bool:
    """Spawn an argv list detached from the bar (GLib reaps the child).

    Prefer this over ``subprocess.Popen``: GLib installs a SIGCHLD handler and
    reaps children spawned here, so a long-running bar never accumulates
    zombies, and argv is never re-parsed by a shell.
    """
    if not argv:
        return False
    try:
        cwd = working_directory or os.path.expanduser("~")
        GLib.spawn_async(
            list(argv),
            working_directory=cwd,
            flags=GLib.SpawnFlags.SEARCH_PATH,
        )
        return True
    except GLib.Error as exc:
        log.warning("failed to spawn %r: %s", argv, exc)
        return False


def spawn_command_line(command: str) -> bool:
    """Spawn a full command line as argv — expands ``~``, resolves the binary.

    The rest of the line is shlex-split so quoted arguments keep their
    grouping (a plain string replace / GLib re-parse would split spaces
    inside quotes and break e.g. ``"/opt/My App/app" --flag``).
    """
    command = os.path.expanduser(command or "").strip()
    if not command:
        return False
    try:
        parts = shlex.split(command)
    except ValueError as exc:
        log.warning("failed to parse command line %r: %s", command, exc)
        return False
    if not parts:
        return False
    parts[0] = resolve_binary(parts[0]) or parts[0]
    return spawn_argv(parts)


def run_shell(command: str) -> bool:
    """Run a string through one explicit ``/bin/sh -c`` (detached).

    Only for strings that are intentionally shell: compound operators,
    redirections, ``~``/env expansion mid-argument. ``command`` is treated as
    the whole script — never concatenate into it.
    """
    command = command.strip()
    if not command:
        return False
    return spawn_argv(["/bin/sh", "-c", command])


def run_checked(argv: list[str], timeout: float = 10.0, **kwargs) -> str:
    """Run argv, capturing stdout; return "" on any failure.

    Blocks the caller — keep off the UI thread.
    """
    try:
        proc = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=timeout,
            **kwargs,
        )
        return proc.stdout or ""
    except (OSError, subprocess.SubprocessError, ValueError):
        return ""
