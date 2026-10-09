"""A minimal rofi-based folder picker for the Qt bars' "browse" buttons.

No zenity/kdialog is assumed on the target systems, but rofi is (the bar already
depends on it). Navigate directories with rofi's dmenu and print the chosen
folder path on stdout (exit 0); exit 1 on cancel.

Usage::

    python3 pickdir.py [start_dir]
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROFI_ARGS = ["-dmenu", "-i", "-no-custom"]


def _rofi(prompt: str, entries: list[str], config: str = "") -> str | None:
    cmd = ["rofi", *ROFI_ARGS, "-p", prompt]
    if config and os.path.isfile(config):
        cmd += ["-config", config]
    try:
        proc = subprocess.run(cmd, input="\n".join(entries),
                              capture_output=True, text=True)
    except OSError:
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.rstrip("\n")


def _rofi_config() -> str:
    for p in ("~/.config/rofi/config.rasi", "~/.config/rofi/config",
              "~/hyprtk/configs/rofi/config.rasi"):
        path = Path(p).expanduser()
        if path.is_file():
            return str(path)
    return ""


def pick(start: str | None, config: str = "") -> str | None:
    cur = Path(start).expanduser() if start else Path.home()
    if not cur.is_dir():
        cur = Path.home()
    cur = cur.resolve()
    while True:
        try:
            dirs = sorted(
                d.name for d in cur.iterdir()
                if d.is_dir() and not d.name.startswith(".")
            )
        except OSError:
            dirs = []
        entries = ["\uf00c  Use this folder", "\uf062  .. (up)"] + dirs
        sel = _rofi("Select folder: " + str(cur), entries, config)
        if sel is None:
            return None
        if sel.endswith("Use this folder"):
            return str(cur)
        if sel.endswith("(up)"):
            if cur.parent != cur:
                cur = cur.parent
            continue
        cand = cur / sel
        if cand.is_dir():
            cur = cand


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    start = argv[0] if argv else None
    chosen = pick(start, _rofi_config())
    if chosen is None:
        return 1
    print(chosen)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
