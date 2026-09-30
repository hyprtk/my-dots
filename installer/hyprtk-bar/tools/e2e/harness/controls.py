"""Enumerate the interactive controls in a built settings widget tree.

The settings-apply matrix must not miss a single control, so it discovers them
from the live widget tree rather than from a hand-maintained list. Each control
gets a human label (from its neighbouring label / own text) so a failure in
``e2e-output.html`` names the exact switch that broke.
"""
from __future__ import annotations

from dataclasses import dataclass

from hyprtk_bar import compat
from hyprtk_bar.compat import Gtk


@dataclass
class Control:
    path: str
    kind: str
    label: str
    widget: object

    def __str__(self) -> str:
        return f"{self.kind}:{self.label or self.path}"


def _is(widget, name: str) -> bool:
    cls = getattr(Gtk, name, None)
    return cls is not None and isinstance(widget, cls)


def kind_of(widget) -> str | None:
    if _is(widget, "CheckButton"):
        return "radio" if _radio(widget) else "check"
    if compat.is_radio(widget):
        return "radio"
    if _is(widget, "Switch"):
        return "switch"
    if _is(widget, "SpinButton"):
        return "spin"
    if _is(widget, "Scale"):
        return "scale"
    if _is(widget, "ComboBoxText"):
        return "combo"
    if _is(widget, "ColorButton"):
        return "color"
    if _is(widget, "FontButton"):
        return "font"
    if _is(widget, "Entry"):
        return "entry"
    if _is(widget, "ToggleButton"):
        return "toggle"
    if _is(widget, "Button"):
        return "button"
    return None


def _radio(widget) -> bool:
    try:
        return compat.is_radio(widget)
    except Exception:
        return False


def _label_for(widget, ancestors: list) -> str:
    """A nearby label: the widget's own text, else the first label in its row."""
    for getter in ("get_label", "get_text"):
        fn = getattr(widget, getter, None)
        if callable(fn):
            try:
                text = fn()
                if text:
                    return str(text).strip()
            except Exception:
                pass
    for parent in reversed(ancestors):
        text = _first_label(parent)
        if text:
            return text
    return ""


def _first_label(widget, depth: int = 0) -> str:
    if depth > 3:
        return ""
    for child in _children(widget):
        if _is(child, "Label"):
            try:
                text = child.get_text()
            except Exception:
                text = ""
            if text:
                return str(text).strip()
        nested = _first_label(child, depth + 1)
        if nested:
            return nested
    return ""


def _children(widget):
    try:
        return list(compat.children(widget))
    except Exception:
        return []


def enumerate_controls(root) -> list[Control]:
    out: list[Control] = []

    def walk(widget, path: str, ancestors: list) -> None:
        kind = kind_of(widget)
        if kind:
            out.append(Control(path=path, kind=kind, label=_label_for(widget, ancestors), widget=widget))
        for i, child in enumerate(_children(widget)):
            walk(child, f"{path}/{i}", ancestors + [widget])

    walk(root, "root", [])
    return out
