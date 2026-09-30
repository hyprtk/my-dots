"""Perturb a control, apply the settings dialogue, and fingerprint the result.

The matrix perturbs one control at a time so a failure names the exact switch
that broke, then records (a) whether the saved config changed and (b) which parts
of the live surface changed.
"""
from __future__ import annotations

import json

from hyprtk_bar import compat
from hyprtk_bar.compat import Gdk, Gtk

# Kinds that map onto the config (buttons/actions are exercised in L3 instead).
CONFIG_KINDS = {"check", "radio", "switch", "toggle", "spin", "scale", "combo", "entry", "color", "font"}

_NO_TOUCH = {"button", "font"}


def perturb(control) -> str | None:
    """Change *control* away from its current value; return a note or None."""
    kind = control.kind
    w = control.widget
    if kind in _NO_TOUCH:
        return None
    try:
        if kind in ("check", "switch", "toggle"):
            w.set_active(not bool(w.get_active()))
            return f"active -> {w.get_active()}"
        if kind == "radio":
            w.set_active(True)
            return "radio selected"
        if kind in ("spin", "scale"):
            cur = float(w.get_value())
            lo = w.get_adjustment().get_lower()
            hi = w.get_adjustment().get_upper()
            step = 1.0 if kind == "spin" else max(1.0, (hi - lo) / 10.0)
            nxt = cur + step
            if nxt > hi:
                nxt = max(lo, cur - step)
            w.set_value(nxt)
            return f"value {cur} -> {nxt}"
        if kind == "combo":
            model = w.get_model()
            n = model.get_n_items() if model is not None else 0
            active = w.get_active()
            nxt = (active + 1) if (n == 0 or active + 1 < n) else 0
            w.set_active(nxt)
            return f"index {active} -> {nxt}"
        if kind == "entry":
            w.set_text((w.get_text() or "") + "e2e")
            return "text appended"
        if kind == "color":
            rgba = Gdk.RGBA()
            rgba.parse("#123456")
            w.set_rgba(rgba)
            return "colour #123456"
    except Exception as exc:  # noqa: BLE001
        return f"perturb failed: {exc}"
    return None


def capture(control):
    """Snapshot a control's value so it can be restored after the apply."""
    w = control.widget
    kind = control.kind
    try:
        if kind in ("check", "switch", "toggle", "radio"):
            return ("active", bool(w.get_active()))
        if kind in ("spin", "scale"):
            return ("value", float(w.get_value()))
        if kind == "combo":
            return ("active", w.get_active())
        if kind == "entry":
            return ("text", w.get_text())
        if kind == "color":
            return ("rgba", w.get_rgba().to_string())
    except Exception:
        pass
    return None


def restore(control, state) -> None:
    """Undo a perturbation so the next control starts from a clean page."""
    if not state:
        return
    w = control.widget
    what, value = state
    try:
        if what == "active":
            w.set_active(value)
        elif what == "value":
            w.set_value(value)
        elif what == "text":
            w.set_text(value)
        elif what == "rgba":
            rgba = Gdk.RGBA()
            if rgba.parse(value):
                w.set_rgba(rgba)
    except Exception:
        pass


def digest(rt) -> dict:
    """A fingerprint of the live surfaces, for before/after comparison."""
    bar = rt.bar
    d = {
        "bar_widgets": sorted(getattr(bar, "_widgets", {}).keys()),
        "arc_window": rt.arc_win is not None,
        "arc_visible": bool(rt.arc_win is not None and rt.arc_win.get_visible()),
        "menu_window": rt.menu_win is not None,
        "menu_visible": bool(rt.menu_win is not None and rt.menu_win.get_visible()),
        "widget_windows": sorted(getattr(rt.widget_mgr, "_wins", {}).keys()),
        "bar_width": getattr(bar, "_width", None),
        "bar_align": getattr(bar, "_align", None),
        "bar_height": getattr(bar, "_last_height", None),
        "palette_scale": (rt.bar_win._palette_cache or {}).get("content_scale"),
    }
    return d


def digest_delta(before: dict, after: dict) -> list[str]:
    return [k for k in before if before.get(k) != after.get(k)]


def cfg_diff(before: dict, after: dict, prefix: str = "") -> list[str]:
    """Dotted paths whose value differs between two config dicts."""
    out = []
    for key in set(before) | set(after):
        a, b = before.get(key), after.get(key)
        path = f"{prefix}{key}"
        if isinstance(a, dict) and isinstance(b, dict):
            out.extend(cfg_diff(a, b, path + "."))
        elif a != b:
            out.append(path)
    return out


def read_cfg():
    from hyprtk_bar import config as config_module

    return json.loads(config_module.CONFIG_PATH.read_text())


def apply_dialogs(settings) -> None:
    settings._on_apply()


def control_enabled(control) -> bool:
    try:
        return bool(control.widget.get_sensitive())
    except Exception:
        return True
