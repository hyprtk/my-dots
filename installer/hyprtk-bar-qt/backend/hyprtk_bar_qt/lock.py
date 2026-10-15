"""Lock-screen settings reader/writer for the Qt themer.

Lists the settings of the active locker plus the hypridle idle daemon:

- **hyprlock** — the live pywal colours (``~/.cache/wal/hyprlock-colors.conf``,
  the ``$lock_*`` variables) and every block of ``~/.config/hypr/hyprlock.conf``
  (``general``, ``auth``, ``animations``, ``background``, ``input-field``,
  ``label`` …). The pywal ``$lock_*`` fallbacks and the ``source =`` plumbing in
  the conf are omitted from the conf group — they are represented by the live
  colours group instead.
- **hypridle** — every block of ``~/.config/hypr/hypridle.conf`` (``general`` +
  each ``listener``).

Falls back to the swaylock config (``~/.config/swaylock/config``) when hyprlock
is not the active locker.

Every setting records the file and line it came from, so an edit is written back
to exactly that line (guarded by a key match). Writing is restricted to the
known lock/idle files.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import tempfile
from collections import Counter
from pathlib import Path

HOME = Path.home()
SWAYLOCK = HOME / ".config" / "swaylock" / "config"
HYPRLOCK_CONF = HOME / ".config" / "hypr" / "hyprlock.conf"
HYPRLOCK_COLORS = HOME / ".cache" / "wal" / "hyprlock-colors.conf"
HYPRIDLE_CONF = HOME / ".config" / "hypr" / "hypridle.conf"

_HEX8 = re.compile(r"^#?[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$")
_RGB = re.compile(r"^rgba?\(\s*#?([0-9a-fA-F]{6,8})\s*\)$")
_BLOCK_OPEN = re.compile(r"^([\w.$-]+)\s*\{\s*$")
_KV = re.compile(r"^(\$?[\w.-]+)\s*=\s*(.*)$")

# Files an edit may touch (guards against a stray write to an arbitrary path).
def _writable() -> set[str]:
    return {str(p) for p in (SWAYLOCK, HYPRLOCK_CONF, HYPRLOCK_COLORS, HYPRIDLE_CONF)}


def _looks_color(value: str) -> bool:
    v = value.strip()
    return bool(_HEX8.match(v) or _RGB.match(v))


def _hyprlock_active() -> bool:
    # Mirror hypr/scripts/lock.sh: hyprlock only wins when the binary exists and
    # its config is present; otherwise the session uses swaylock.
    return HYPRLOCK_CONF.is_file() and shutil.which("hyprlock") is not None


def detect() -> tuple[str, Path | None]:
    if _hyprlock_active():
        return "hyprlock", HYPRLOCK_CONF
    if SWAYLOCK.is_file():
        return "swaylock", SWAYLOCK
    return "", None


def _strip_comment(line: str) -> str:
    # Drop a full-line or inline comment (only a '#' at start or after space),
    # so values like ``rgba(...) # was: …`` keep the value.
    return re.sub(r"(^|\s)#.*$", "", line).rstrip()


def _parse_sections(path: Path, skip_prefix: tuple[str, ...] = ("$",),
                    skip_keys: tuple[str, ...] = ("source",)) -> list[dict]:
    """Parse a hyprlang-style config into ordered ``{base, items}`` sections.

    Block headers (``name {``) open a section titled by the nesting path
    (``auth / fingerprint``); ``}`` closes it. ``key = value`` lines become
    items carrying the 1-based source line for write-back.
    """
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return []

    sections: list[dict] = []
    stack: list[str] = []

    def current() -> dict:
        title = " / ".join(stack) if stack else "general"
        if not sections or sections[-1]["base"] != title:
            sections.append({"base": title, "items": []})
        return sections[-1]

    for n, raw in enumerate(lines, 1):
        t = _strip_comment(raw).strip()
        if not t:
            continue
        m = _BLOCK_OPEN.match(t)
        if m:
            stack.append(m.group(1))
            sections.append({"base": " / ".join(stack), "items": []})
            continue
        if t == "}":
            if stack:
                stack.pop()
            continue
        kv = _KV.match(t)
        if not kv:
            continue
        key, val = kv.group(1), kv.group(2).strip()
        if key.startswith(skip_prefix) or key in skip_keys:
            continue
        current()["items"].append({
            "key": key,
            "label": key,
            "value": val,
            "color": _looks_color(val),
            "file": str(path),
            "line": n,
        })
    return sections


def _finalize(sections: list[dict]) -> list[dict]:
    """Drop empty sections and number repeated titles (label 1, listener 2 …)."""
    sections = [s for s in sections if s["items"]]
    counts = Counter(s["base"] for s in sections)
    seen: Counter[str] = Counter()
    out: list[dict] = []
    for s in sections:
        base = s["base"]
        seen[base] += 1
        title = f"{base} {seen[base]}" if counts[base] > 1 else base
        out.append({"title": title, "items": s["items"]})
    return out


def _colors_group() -> dict | None:
    sections = _finalize(_parse_sections(HYPRLOCK_COLORS, skip_prefix=(), skip_keys=()))
    if not sections:
        return None
    for item in sections[0]["items"]:
        item["label"] = item["key"].lstrip("$").replace("lock_", "")
    return {"title": "colours (pywal, live)", "path": str(HYPRLOCK_COLORS), "sections": sections}


def _conf_group(title: str, path: Path, **kw) -> dict | None:
    sections = _finalize(_parse_sections(path, **kw))
    if not sections:
        return None
    return {"title": title, "path": str(path), "sections": sections}


def read() -> dict:
    kind, path = detect()
    groups: list[dict] = []
    if kind == "hyprlock":
        for g in (_colors_group(), _conf_group("hyprlock.conf", HYPRLOCK_CONF),
                  _conf_group("hypridle.conf", HYPRIDLE_CONF)):
            if g:
                groups.append(g)
    elif kind == "swaylock":
        g = _conf_group("swaylock config", SWAYLOCK, skip_prefix=(), skip_keys=())
        if g:
            groups.append(g)

    items: list[dict] = [it for g in groups for s in g["sections"] for it in s["items"]]
    return {"kind": kind, "path": str(path) if path else "", "groups": groups, "items": items}


def _write_lines(path: Path, lines: list[str]) -> bool:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".lock.", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
        return True
    except OSError:
        return False


def _valid(key: str, value: str) -> bool:
    return not (any(c in key for c in "\n\r=") or any(c in value for c in "\n\r"))


def set_line(file: str, line: int, key: str, value: str) -> bool:
    """Replace the value on *file* line *line* (1-based), keeping the key.

    Refuses paths outside the known lock/idle files, a missing/foreign line, or
    injection in the key/value.
    """
    if file not in _writable() or not _valid(key, value):
        return False
    path = Path(file)
    if not path.is_file():
        return False
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return False
    if line < 1 or line > len(lines):
        return False
    orig = lines[line - 1]
    if "=" not in orig:
        return False
    lhs = orig.split("=", 1)[0].rstrip()
    if lhs.strip() != key.strip():
        return False  # the file changed under us — refuse a stale edit
    lines[line - 1] = f"{lhs} = {value}"
    return _write_lines(path, lines)


def set_value(key: str, value: str) -> bool:
    """Legacy first-match key replace, in the active lock config."""
    if not _valid(key, value):
        return False
    _kind, path = detect()
    if path is None or not path.is_file():
        return False
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return False
    found = False
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        if "=" in stripped and not stripped.startswith("#"):
            k = stripped.partition("=")[0].strip()
            if k == key:
                out.append(f"{k} = {value}")
                found = True
                continue
        out.append(line)
    if not found:
        out.append(f"{key} = {value}")
    return _write_lines(path, out)


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
    return _write_lines(SWAYLOCK, out)


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
    p_set.add_argument("--file", default="")
    p_set.add_argument("--line", type=int, default=0)
    p_set.add_argument("--key", default="")
    p_set.add_argument("--value", required=True)
    args = ap.parse_args(argv)

    if args.action == "read":
        print(json.dumps(read()))
        return 0
    if args.action == "sync-pywal":
        ok = sync_pywal()
        print(json.dumps({"ok": ok}))
        return 0 if ok else 1
    if args.file:
        ok = set_line(args.file, args.line, args.key, args.value)
    else:
        ok = set_value(args.key, args.value)
    print(json.dumps({"ok": ok}))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
