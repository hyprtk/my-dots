"""L1 · construct — every top-level surface and every settings page builds.

A GTK4 port commonly dies here first (a removed constructor, a bad vfunc, a
gesture that no longer exists). No interaction yet: just build with the real
classes and confirm the widget tree exists.
"""
from __future__ import annotations

import pytest


def test_bar_builds(runtime, details):
    win = runtime.bar_win
    details["bar_widgets"] = sorted(getattr(runtime.bar, "_widgets", {}).keys())
    assert win is not None
    assert win._bar is not None
    assert runtime.bar._widgets, "bar has no widgets"


def test_settings_opens(runtime, details):
    settings = runtime.open_settings()
    assert settings is not None
    details["pages"] = list(getattr(settings, "_page_buttons", {}).keys())
    assert len(details["pages"]) == 9


def test_every_settings_page_builds(runtime, details):
    """Each page builds with at least one control (no empty/exception page)."""
    from harness.controls import enumerate_controls

    settings = runtime.open_settings()
    counts = {}
    for key in list(settings._page_buttons.keys()):
        settings._set_active_page(key)
        page = settings._stack.get_child_by_name(key)
        assert page is not None, f"page {key} missing from the stack"
        controls = enumerate_controls(page)
        counts[key] = len(controls)
    details["controls_per_page"] = counts
    empty = [k for k, n in counts.items() if n == 0]
    assert not empty, f"settings pages with no controls found: {empty}"


def test_arc_and_menu_overlays_build(runtime, details):
    details["arc"] = runtime.arc_win is not None
    details["menu"] = runtime.menu_win is not None
    assert runtime.arc_win is not None, "arc menu overlay did not build"
    assert runtime.menu_win is not None, "start menu did not build"


def test_desktop_widgets_all_build(runtime, details):
    """Enabling every desktop widget materializes one layer window each."""
    from harness.runtime import pump

    cfg = runtime.cfg
    for wid in ("clock", "weather", "visualizer", "disk", "network", "resources", "sysinfo"):
        cfg.setdefault("widgets", {}).setdefault(wid, {})["enabled"] = True
    cfg.setdefault("widgets", {})["enabled"] = True
    runtime.widget_mgr.reload(cfg)
    pump(120)
    keys = sorted(getattr(runtime.widget_mgr, "_wins", {}).keys())
    details["widget_windows"] = keys
    assert len(keys) == 7, f"expected 7 widget windows, got {keys}"


@pytest.mark.parametrize("cls_path", [
    "hyprtk_bar.themer.ThemerDialog",
    "hyprtk_bar.monitor.SysMonitorDialog",
    "hyprtk_bar.clipboard.CliphistDialog",
])
def test_aux_dialog_builds(cls_path, runtime, details):
    """Themer / system-monitor / clipboard-history dialogues construct."""
    module_name, cls_name = cls_path.rsplit(".", 1)
    module = __import__(module_name, fromlist=[cls_name])
    cls = getattr(module, cls_name)
    details["class"] = cls_path
    try:
        win = cls(runtime.cfg)
    except TypeError:
        win = cls(runtime.bar_win)
    assert win is not None
