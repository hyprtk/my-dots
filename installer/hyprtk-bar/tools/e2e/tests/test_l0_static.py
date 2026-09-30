"""L0 · static checks — no widgets, fast, run under both stacks.

Catches the whole "GTK3 idiom survived the port" class without needing a click:
every module must import under the selected stack, and no GTK4-reachable code may
still call an API GTK4 removed.

Known-legacy escape hatches (explicit ``Gtk3`` builds kept for the GTK3 mode) are
allowlisted by enclosing function so the gate stays meaningful.
"""
from __future__ import annotations

import ast
import importlib
import pkgutil
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
SRC = REPO / "src" / "hyprtk_bar"

# Receiver/attribute patterns GTK4 deleted.
BANNED_DOTTED = {
    "Gtk.main": "Gtk.main() removed in GTK4",
    "Gtk.main_quit": "Gtk.main_quit() removed in GTK4",
    "Gtk.Menu": "Gtk.Menu removed in GTK4",
    "Gtk.EventBox": "Gtk.EventBox removed in GTK4",
    "Gtk.Container": "Gtk.Container removed in GTK4",
    "Gdk.EventType.DOUBLE_BUTTON_PRESS": "no such Gdk.EventType in GTK4",
}
BANNED_ATTRS = {
    "show_all": "Widget.show_all() removed in GTK4",
    "get_style_context": "StyleContext removed in GTK4",
    "begin_move_drag": "Window.begin_move_drag removed in GTK4",
    "format_secondary_text": "MessageDialog.format_secondary_text removed in GTK4",
    "get_allocated_width": "get_allocated_width() removed in GTK4",
    "get_allocated_height": "get_allocated_height() removed in GTK4",
}
# (file, enclosing function) pairs that are the documented GTK3 escape hatch.
ALLOW = {
    ("bar_menu.py", "build_bar_menu"),
    ("menus.py", "build_gtk3_menu"),
    ("tasklist.py", "_show_context_menu"),
}


def _modules():
    return sorted(
        info.name
        for info in pkgutil.walk_packages([str(SRC)], prefix="hyprtk_bar.")
    )


@pytest.mark.parametrize("name", _modules())
def test_import_module(name, details):
    """Every module imports cleanly under the active stack."""
    details["module"] = name
    importlib.import_module(name)


def test_compat_surface(details):
    """compat.py exposes the polyfills the ported modules rely on."""
    from hyprtk_bar import compat

    required = [
        "IS_GTK3", "IS_GTK4", "Gtk", "Gdk", "Gio", "GLib", "GtkLayerShell",
        "add", "add_class", "remove_class", "pack_start", "pack_end",
        "show", "hide", "show_all", "destroy", "children", "toplevel",
        "on_press", "on_key", "set_draw_func", "new_image_from_icon_name",
        "dialog_run", "set_secondary_text", "run_main", "quit_main",
        "new_raster", "raster_set_file", "new_raster_from_pixbuf",
    ]
    missing = [n for n in required if not hasattr(compat, n)]
    details["missing"] = missing
    assert not missing, f"compat is missing: {missing}"


def test_no_removed_gtk4_apis(details):
    """AST scan: no GTK4-reachable bar code still calls a removed API."""
    hits = []
    for path in sorted(SRC.rglob("*.py")):
        if path.name == "compat.py" or "__pycache__" in path.parts:
            continue
        rel = path.name if path.parent == SRC else str(path.relative_to(SRC))
        hits.extend(_scan(path, rel))
    details["hits"] = hits
    assert not hits, "removed GTK4 APIs still referenced:\n" + "\n".join(hits)


def _scan(path: Path, rel: str) -> list[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    annotations = _annotation_nodes(tree)
    found: list[str] = []

    def walk(node: ast.AST, funcs: tuple[str, ...]) -> None:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            funcs = funcs + (node.name,)
        if isinstance(node, ast.Attribute) and id(node) not in annotations:
            full = _dotted(node)
            recv = _dotted(node.value) if not isinstance(node.value, ast.Name) else node.value.id
            why = None
            if recv != "compat":
                if full in BANNED_DOTTED:
                    why = BANNED_DOTTED[full]
                elif node.attr in BANNED_ATTRS:
                    why = BANNED_ATTRS[node.attr]
            if why and (rel, funcs[-1] if funcs else "") not in ALLOW:
                found.append(f"{rel}:{node.lineno}: {full} ({funcs[-1] or '<module>'}) — {why}")
        for child in ast.iter_child_nodes(node):
            walk(child, funcs)

    walk(tree, ())
    return found


def _annotation_nodes(tree: ast.AST) -> set[int]:
    ids: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if node.returns is not None:
                ids.update(id(n) for n in ast.walk(node.returns))
            for arg in (*node.args.posonlyargs, *node.args.args, *node.args.kwonlyargs):
                if arg.annotation is not None:
                    ids.update(id(n) for n in ast.walk(arg.annotation))
        elif isinstance(node, ast.AnnAssign) and node.annotation is not None:
            ids.update(id(n) for n in ast.walk(node.annotation))
    return ids


def _dotted(node: ast.AST) -> str:
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return ".".join(reversed(parts))
