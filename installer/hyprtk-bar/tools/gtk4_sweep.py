#!/usr/bin/env python3
"""Phase-0 GTK version sweep for the hyprtk-bar GTK3 -> GTK4 port.

Rewrites each bar module's GObject-Introspection bootstrap so the toolkit
version is chosen in exactly one place (``hyprtk_bar/compat.py``). The old
block::

    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GtkLayerShell", "0.1")

    from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

becomes (``.`` for top-level modules, ``..`` inside ``menu/`` and ``desktop/``)::

    from .compat import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

``compat.py`` itself is never touched. The tool is idempotent: re-running it
is a no-op once a module already imports from ``.compat``.

Usage
-----
    python3 tools/gtk4_sweep.py --dry-run     # preview every change
    python3 tools/gtk4_sweep.py               # apply
    python3 tools/gtk4_sweep.py --root <dir>  # sweep a different package

Exit status: 0 on success, 1 when a module still has an un-rewritten GTK
bootstrap after the run (a parse gap worth looking at).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SKIP = {"compat.py"}

IMPORT_GI_RE = re.compile(r"^import gi\s*$")
REQUIRE_RE = re.compile(r"^\s*gi\.require_version\(")
FROM_RE = re.compile(
    r"^from gi\.repository import (?P<names>[^#\n]+?)\s*(?P<comment>#.*)?$"
)
LEFTOVER_GI_RE = re.compile(r"\bgi\.")


def find_bootstrap(lines: list[str]):
    """Locate the gi bootstrap.

    Returns ``(start, end, names)`` where ``start`` is the index of the
    ``import gi`` line and ``end`` is the index just past the
    ``from gi.repository import ...`` line, or ``None`` when the module has no
    bootstrap (or already imports from ``.compat``).
    """
    for i, line in enumerate(lines):
        if not IMPORT_GI_RE.match(line):
            continue
        j = i + 1
        while j < len(lines):
            stripped = lines[j].strip()
            if stripped == "" or stripped.startswith("#"):
                j += 1
                continue
            if REQUIRE_RE.match(lines[j]):
                j += 1
                continue
            break
        if j >= len(lines):
            continue
        match = FROM_RE.match(lines[j])
        if not match:
            continue
        names = match.group("names").strip()
        if not names or ".compat" in lines[j]:
            continue
        return i, j + 1, names
    return None


def sweep_file(path: Path, root: Path, dry_run: bool) -> bool:
    """Rewrite one module. Returns True when the file changed."""
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    boot = find_bootstrap(lines)
    if boot is None:
        return False

    start, end, names = boot
    depth = len(path.relative_to(root).parts) - 1
    prefix = "." * (depth + 1)
    new_line = f"from {prefix}compat import {names}  # noqa: E402\n"
    new_lines = lines[:start] + [new_line] + lines[end:]
    new_text = "".join(new_lines)

    # Guard: nothing else may still touch the bare `gi` module.
    leftover = LEFTOVER_GI_RE.search(new_text)
    if leftover:
        sys.stderr.write(
            f":: WARN {path}: still references 'gi.' at byte "
            f"{leftover.start()} after sweep\n"
        )

    if dry_run:
        removed = "".join(lines[start:end]).rstrip("\n")
        print(f"--- {path.relative_to(root)}")
        for line in removed.splitlines():
            print(f"  - {line}")
        print(f"  + {new_line.rstrip()}")
        return True

    path.write_text(new_text, encoding="utf-8")
    return True


def main() -> int:
    here = Path(__file__).resolve()
    default_root = here.parents[1] / "src" / "hyprtk_bar"
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--root", type=Path, default=default_root,
        help=f"package directory to sweep (default: {default_root})",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="preview without writing",
    )
    args = parser.parse_args()

    root: Path = args.root.resolve()
    if not root.is_dir():
        sys.stderr.write(f":: ERROR: not a directory: {root}\n")
        return 2

    modules = sorted(p for p in root.rglob("*.py") if p.name not in SKIP)
    changed = 0
    for path in modules:
        if sweep_file(path, root, args.dry_run):
            changed += 1
            if not args.dry_run:
                print(f"   sweep  {path.relative_to(root)}")

    # Post-check: no module except compat.py may keep a gi bootstrap.
    leftover = []
    for path in modules:
        lines = path.read_text(encoding="utf-8").splitlines()
        if find_bootstrap(lines) is not None:
            leftover.append(path.relative_to(root))

    verb = "would change" if args.dry_run else "changed"
    print(f"\n{verb} {changed} module(s); scanned {len(modules)}")
    if args.dry_run:
        return 0
    if leftover:
        sys.stderr.write(":: ERROR: un-swept bootstrap remains in:\n")
        for p in leftover:
            sys.stderr.write(f"     {p}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
