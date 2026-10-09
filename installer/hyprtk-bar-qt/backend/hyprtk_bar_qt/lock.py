"""Lock-screen settings reader/writer for the Qt themer.

Supports both the live swaylock config (``~/.config/swaylock/config``) and the
migrated hyprlock colours (``~/.cache/wal/hyprlock-colors.conf``): lists the
config's ``key=value`` settings (marking colour-looking values) and writes an
edited value back to the same file.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

HOME = Path.home()
SWAYLOCK = HOME / ".config" / "swaylock" / "config"
HYPRLOCK_CONF = HOME / ".config" / "hypr" / "hyprlock.conf"
HYPRLOCK_COLORS = HOME / ".cache" / "wal" / "hyprlock-colors.conf"

_HEX8 = re.compile(r"^#?[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$")


def detect() -> tuple[str, Path | None]:
    if HYPRLOCK_CONF.is_file():
        return "hyprlock", HYPRLOCK_COLORS if HYPRLOCK_COLORS.is_file() else None
    if SWAYLOCK.is_file():
        return "swaylock", SWAYLOCK
    return "", None


def _looks_color(value: str) -> bool:
    return bool(_HEX8.match(value.strip()))


def read() -> dict:
    kind, path = detect()
    items: list[dict] = []
    if path is not None:
        try:
            for line in path.read_text().splitlines():
                s = line.strip()
                if not s or s.startswith("#") or "=" not in s:
                    continue
                key, _, val = s.partition("=")
                key = key.strip()
                val = val.strip()
                # hyprlock colour vars are prefixed $lock_.
                label = key.replace("$lock_", "") if key.startswith("$lock_") else key
                items.append({"key": key, "label": label, "value": val, "color": _looks_color(val)})
        except OSError:
            pass
    return {"kind": kind, "path": str(path) if path else "", "items": items}


def set_value(key: str, value: str) -> bool:
    kind, path = detect()
    if path is None or not path.is_file():
        return False
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return False
    out = []
    found = False
    for line in lines:
        stripped = line.strip()
        if "=" in stripped and not stripped.startswith("#"):
            k = stripped.partition("=")[0].strip()
            if k == key:
                out.append(f"{key}={value}")
                found = True
                continue
        out.append(line)
    if not found:
        out.append(f"{key}={value}")
    try:
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text("\n".join(out) + "\n")
        os.replace(tmp, path)
        return True
    except OSError:
        return False


# swaylock colour key -> (pywal index, append a "44" alpha suffix). Indices are
# the 0-based pywal palette; the alpha keeps the translucent inside/line fills
# while the ring/text/backspace stays opaque. Mirrors the GTK bar's themer.
_SWAYLOCK_COLOR_MAP: list[tuple[str, int, bool]] = [
    ("ring-color", 6, False), ("ring-clear-color", 4, False),
    ("ring-wrong-color", 1, False), ("ring-ver-color", 5, False),
    ("ring-caps-lock-color", 5, False),
    ("inside-color", 0, True), ("inside-clear-color", 4, True),
    ("inside-wrong-color", 1, True), ("inside-ver-color", 5, True),
    ("inside-caps-lock-color", 5, True),
    ("key-hl-color", 6, True),
    ("text-color", 7, False), ("text-clear-color", 4, False),
    ("text-ver-color", 5, False), ("text-wrong-color", 1, False),
    ("bs-hl-color", 1, False),
    ("line-color", 6, True), ("line-clear-color", 4, True),
    ("line-wrong-color", 1, True), ("line-ver-color", 5, True),
    ("line-caps-lock-color", 5, True),
    ("caps-lock-key-hl-color", 5, True),
    ("caps-lock-bs-hl-color", 5, True),
    ("text-caps-lock-color", 5, False),
]


def _wal_hex() -> list[str]:
    """The 16 live pywal colours, bare ``RRGGBB`` (no ``#``), or [] if absent."""
    try:
        from .pywal import palette
    except ImportError:  # run as a script
        from pywal import palette
    colors = palette().get("colors") or []
    return [str(c).lstrip("#").lower() for c in colors if c]


def sync_swaylock() -> bool:
    """Write the live pywal colours into the swaylock config, in place.

    Only the colour keys are replaced (missing ones appended); comments, bare
    flags and the non-colour settings are left untouched, so the lock follows
    the wallpaper palette without clobbering font/effect/indicator options.
    """
    colors = _wal_hex()
    if len(colors) < 8 or not SWAYLOCK.is_file():
        return False
    replacements = {
        key: f"{colors[idx]}{'44' if keep_alpha else ''}"
        for key, idx, keep_alpha in _SWAYLOCK_COLOR_MAP
    }
    try:
        lines = SWAYLOCK.read_text().splitlines()
    except OSError:
        return False
    seen: set[str] = set()
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        key = stripped.split("=", 1)[0].strip() if "=" in stripped else ""
        if key in replacements:
            out.append(f"{key}={replacements[key]}")
            seen.add(key)
        else:
            out.append(line)
    for key, value in replacements.items():
        if key not in seen:
            out.append(f"{key}={value}")
    try:
        tmp = SWAYLOCK.with_suffix(SWAYLOCK.suffix + ".tmp")
        tmp.write_text("\n".join(out) + "\n")
        os.replace(tmp, SWAYLOCK)
        return True
    except OSError:
        return False


def sync_pywal() -> bool:
    """Re-tint the active lock config from the live pywal palette.

    swaylock colours are written in place; hyprlock reads its colours from the
    pywal-rendered ``~/.cache/wal/hyprlock-colors.conf`` (regenerated by the
    ``wal`` run), so there is nothing to write here.
    """
    kind, _path = detect()
    if kind == "swaylock":
        return sync_swaylock()
    return True


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="lock-screen settings")
    sub = ap.add_subparsers(dest="action", required=True)
    sub.add_parser("read")
    sub.add_parser("sync-pywal")
    p_set = sub.add_parser("set")
    p_set.add_argument("--key", required=True)
    p_set.add_argument("--value", required=True)
    args = ap.parse_args(argv)

    if args.action == "read":
        print(json.dumps(read()))
        return 0
    if args.action == "sync-pywal":
        ok = sync_pywal()
        print(json.dumps({"ok": ok}))
        return 0 if ok else 1
    ok = set_value(args.key, args.value)
    print(json.dumps({"ok": ok}))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
