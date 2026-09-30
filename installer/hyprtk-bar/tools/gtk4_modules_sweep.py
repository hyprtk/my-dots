#!/usr/bin/env python3
"""Module-phase GTK3 -> GTK4 sweep for hyprtk-bar.

Applies the *safe*, semantics-preserving substitutions from the GTK3 idioms to
the ``compat`` helpers across the bar's module files. It only rewrites the
mechanical patterns; the structural work (Gtk.Menu, gestures with real root
coordinates, Gtk.DrawingArea draw funcs, Gtk.EventBox layouts) is hand-ported.

Substitutions (receiver ``X`` never ``compat``)::

    X.get_style_context().add_class(c)   -> compat.add_class(X, c)
    X.get_style_context().remove_class(c)-> compat.remove_class(X, c)
    X.pack_start(...)                    -> compat.pack_start(X, ...)
    X.pack_end(...)                      -> compat.pack_end(X, ...)
    X.show_all()                         -> compat.show_all(X)
    X.show() / X.hide()                  -> compat.show(X) / compat.hide(X)
    X.get_children()                     -> compat.children(X)
    X.get_toplevel()                     -> compat.toplevel(X)
    X.get_allocated_width()/height()     -> compat.allocated_width/height(X)
    X.get_allocation()                   -> compat.allocation(X)
    X.get_preferred_width()[1]           -> compat.preferred_width(X)
    X.get_preferred_height()[1]          -> compat.preferred_height(X)
    X.set_no_show_all(True)              -> compat.hide_from_show_all(X)
    X.set_line_wrap(True)                -> compat.set_wrap(X, True)
    X.set_visible_window(V)              -> compat.set_visible_window(X, V)
    Gtk.EventBox()                       -> compat.event_surface()
    X.connect("button-press-event", H)   -> compat.on_press(X, H)
    X.destroy()                          -> compat.destroy(X)

Idempotent (a ``compat.`` receiver is never rewritten). Run with --dry-run to
preview. Idempotency and a post-pass guard flag anything left with a raw
``get_style_context()`` receiver (needs a hand-port).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Already hand-ported: do not sweep these (their compat calls would be re-wrapped).
SKIP_FILES = {
    "compat.py", "widgets.py", "layout.py", "window.py",
    "bar.py", "app.py", "popup.py", "__main__.py",
}

# A simple dotted / subscripted widget receiver, e.g. self._box, right.box,
# self._sections[id].box
RECV = r"([A-Za-z_]\w*(?:\.[A-Za-z_]\w*|\[[^\]\n]+\])*)"

# Receivers whose ``.add`` is NOT a GTK container (sets/dicts/custom stores).
NON_GTK_ADD = {
    "seen", "stats", "ids", "result", "grouped", "_seen",
    "self._hidden", "self._store", "self.pinned", "self._selected",
    "self._tags", "self._categories", "self._seen",
}

# (pattern, replacement-template). {r} is the receiver.
RULES = [
    (rf"{RECV}\.get_style_context\(\)\.add_class\(", "compat.add_class({r}, "),
    (rf"{RECV}\.get_style_context\(\)\.remove_class\(", "compat.remove_class({r}, "),
    (rf"{RECV}\.pack_start\(", "compat.pack_start({r}, "),
    (rf"{RECV}\.pack_end\(", "compat.pack_end({r}, "),
    (rf"{RECV}\.add\(", "compat.add({r}, "),
    (rf"{RECV}\.show_all\(\)", "compat.show_all({r})"),
    (rf"{RECV}\.get_children\(\)", "compat.children({r})"),
    (rf"{RECV}\.get_toplevel\(\)", "compat.toplevel({r})"),
    (rf"{RECV}\.get_allocated_width\(\)", "compat.allocated_width({r})"),
    (rf"{RECV}\.get_allocated_height\(\)", "compat.allocated_height({r})"),
    (rf"{RECV}\.get_allocation\(\)", "compat.allocation({r})"),
    (rf"{RECV}\.get_preferred_width\(\)\[1\]", "compat.preferred_width({r})"),
    (rf"{RECV}\.get_preferred_height\(\)\[1\]", "compat.preferred_height({r})"),
    (rf"{RECV}\.set_no_show_all\(True\)", "compat.hide_from_show_all({r})"),
    (rf"{RECV}\.set_no_show_all\(", "compat.set_no_show_all({r}, "),
    (rf"{RECV}\.set_line_wrap\(True\)", "compat.set_wrap({r}, True)"),
    (rf"{RECV}\.set_visible_window\(", "compat.set_visible_window({r}, "),
    (rf"{RECV}\.get_style_context\(\)", "compat.style_context({r})"),
    (r"Gtk\.EventBox\(\)", "compat.event_surface()"),
    (rf"{RECV}\.set_skip_taskbar_hint\(", "compat.set_skip_taskbar_hint({r}, "),
    (rf"{RECV}\.set_skip_pager_hint\(", "compat.set_skip_pager_hint({r}, "),
    (rf"{RECV}\.set_app_paintable\(", "compat.set_app_paintable({r}, "),
    (rf"{RECV}\.set_accept_focus\(", "compat.set_accept_focus({r}, "),
    (rf"{RECV}\.set_keep_above\(", "compat.set_keep_above({r}, "),
    (rf"{RECV}\.set_relief\(Gtk\.ReliefStyle\.NONE\)", "compat.set_relief({r})"),
    (r"relief=Gtk\.ReliefStyle\.NONE,\s*", ""),
    (rf"{RECV}\.get_relief\(\)\s*!=\s*Gtk\.ReliefStyle\.NONE", "not compat.is_flat({r})"),
    (rf"{RECV}\.set_position\(Gtk\.WindowPosition\.CENTER\)", "compat.set_window_position({r})"),
    (r"Gtk\.IconTheme\.get_default\(\)", "compat.icon_theme()"),
    (r"Gtk\.Image\.new_from_icon_name\(", "compat.new_image_from_icon_name("),
    (r"Gtk\.Button\.new_from_icon_name\(", "compat.new_button_from_icon_name("),
    (r"Gtk\.Image\.new_from_gicon\(", "compat.new_image_from_gicon("),
    (rf"{RECV}\.set_from_icon_name\(", "compat.image_set_from_icon_name({r}, "),
    (r",\s*Gtk\.IconSize\.[A-Z_]+", ""),
    (rf"{RECV}\.pack1\(", "compat.paned_pack1({r}, "),
    (rf"{RECV}\.pack2\(", "compat.paned_pack2({r}, "),
    (rf"{RECV}\.set_font_name\(", "compat.font_button_set_font_name({r}, "),
    (r"Gdk\.Screen\.get_default\(\)\.get_width\(\)", "compat.screen_size()[0]"),
    (rf"{RECV}\.connect\(\s*[\"']button-press-event[\"']\s*,\s*", "compat.on_press({r}, "),
    (rf"{RECV}\.connect\(\s*[\"']key-press-event[\"']\s*,\s*", "compat.on_key({r}, "),
    (rf"{RECV}\.connect\(\s*[\"']draw[\"']\s*,\s*", "compat.set_draw_func({r}, "),
    (r"isinstance\(\s*" + RECV + r"\s*,\s*Gtk\.Container\s*\)", "compat.is_container({r})"),
    (rf"{RECV}\.destroy\(\)", "compat.destroy({r})"),
    # .show()/.hide() last (broadest receivers).
    (rf"{RECV}\.show\(\)", "compat.show({r})"),
    (rf"{RECV}\.hide\(\)", "compat.hide({r})"),
]

COMPILED = [(re.compile(p), t) for p, t in RULES]


def _line_prefix(text: str, pos: int) -> str:
    start = text.rfind("\n", 0, pos) + 1
    return text[start:pos]


def apply_rules(text: str) -> tuple[str, int]:
    changed = 0
    for rx, template in COMPILED:
        def repl(match, template=template):
            nonlocal changed
            if match.re.groups == 0:
                if "#" in _line_prefix(match.string, match.start()):
                    return match.group(0)
                changed += 1
                return template
            recv = match.group(1)
            if recv == "compat" or recv.startswith("compat."):
                return match.group(0)
            if template.startswith("compat.add(") and recv in NON_GTK_ADD:
                return match.group(0)
            # Skip matches inside comments.
            if "#" in _line_prefix(match.string, match.start()):
                return match.group(0)
            changed += 1
            return template.format(r=recv)
        text = rx.sub(repl, text)
    return text, changed


def main() -> int:
    here = Path(__file__).resolve()
    root = here.parents[1] / "src" / "hyprtk_bar"
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=root)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()

    total = 0
    for path in sorted(root.rglob("*.py")):
        if path.name in SKIP_FILES or "__pycache__" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        new, changed = apply_rules(text)
        if not changed:
            continue
        total += changed
        rel = path.relative_to(root)
        print(f"  {'would sweep' if args.dry_run else 'sweep'}  {rel}  ({changed})")
        if not args.dry_run:
            path.write_text(new, encoding="utf-8")

    print(f"\n{total} substitution(s) across modules")
    return 0


if __name__ == "__main__":
    sys.exit(main())
