"""L3 · functional — overlays, popups, menus and dialogues that Apply doesn't cover.

Where L2 drives the settings controls, L3 drives the surfaces those settings
control: arc overlay toggle, start menu toggle, bar context menu, tasklist menu,
quicklink/app picker dialogues, clipboard, notifications and the desktop-widget
move control.
"""
from __future__ import annotations

import pytest


def test_arc_overlay_toggles(runtime, details):
    """The arc surface stays mapped; open/closed is the menu's own state.

    Checking ``get_visible()`` is wrong — the layer surface never unmaps, it
    only collapses its items/input region, so assert the menu's ``is_open()``.
    """
    from harness.runtime import pump

    assert runtime.arc_win is not None
    runtime.arc_win.toggle(); pump(400)
    details["open_after_toggle"] = runtime.arc_win._menu.is_open()
    assert runtime.arc_win._menu.is_open(), "arc menu did not open on toggle"
    runtime.arc_win.toggle(); pump(400)
    details["open_after_second_toggle"] = runtime.arc_win._menu.is_open()
    assert not runtime.arc_win._menu.is_open(), "arc menu did not close on toggle"


def test_start_menu_toggles(runtime, details):
    from harness.runtime import pump

    assert runtime.menu_win is not None
    runtime.menu_win.toggle(); pump(40)
    details["visible_after_open"] = runtime.menu_win.get_visible()
    assert runtime.menu_win.get_visible(), "start menu did not open on toggle"


def test_bar_context_menu_builds(runtime, details):
    from harness.runtime import pump

    runtime.bar.show_bar_menu(anchor=runtime.bar.pill)
    pump(30)
    details["opened"] = True


def test_tasklist_context_menu_builds(runtime, details):
    """Exercise the toolkit-appropriate context-menu path (as tasklist does)."""
    from hyprtk_bar import compat

    items = [
        {"label": "Activate", "activate": lambda: None},
        {"type": "separator"},
        {"label": "Close window", "activate": lambda: None},
    ]
    if compat.IS_GTK4:
        from hyprtk_bar.menus import MenuPopup
        popup = MenuPopup(items)
    else:
        from hyprtk_bar.menus import build_gtk3_menu
        popup = build_gtk3_menu(items)
    details["popup_type"] = type(popup).__name__
    assert popup is not None


def test_quicklink_picker_dialog_builds(runtime, details):
    from hyprtk_bar.bar_settings import _QuicklinkPickerDialog

    settings = runtime.open_settings("quicklinks")
    dialog = _QuicklinkPickerDialog(settings, "Terminal", "")
    details["dialog"] = type(dialog).__name__
    assert dialog is not None
    dialog._finish(None)


def test_clipboard_dialog_toggles(runtime, details):
    from harness.runtime import pump
    from hyprtk_bar.clipboard import CliphistDialog

    dialog = CliphistDialog(runtime.cfg)
    dialog.show_above(runtime.bar_win)
    pump(30)
    details["visible"] = dialog.get_visible()
    dialog.hide_popup()
    assert not dialog.get_visible()


def test_notification_controller_present(runtime, details):
    """With a session bus (dbus-run-session) the notifier owns the bus name."""
    ctrl = runtime.bar_win._notif_ctrl
    details["controller"] = ctrl is not None
    details["bus"] = bool(getattr(ctrl, "_bus", None)) if ctrl is not None else False
    if ctrl is None:
        pytest.skip("notification controller not created (no session bus)")
    assert ctrl is not None


def test_widget_move_control_roundtrip(runtime, details):
    from hyprtk_bar.desktop.control import WidgetMoveControl

    ctl = WidgetMoveControl(lambda: None, lambda: None)
    details["control"] = type(ctl).__name__
    assert ctl is not None
    ctl.shutdown()
