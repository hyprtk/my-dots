"""L2 · settings-apply matrix — the centre of gravity of this suite.

Two halves:

* ``test_settings_apply[page]`` — for every config-bound control on the page:
  isolate it, perturb it, click **Apply**, and check the result. Coverage is a
  first-class assertion: the number of controls exercised is recorded and the
  test fails if any control raises.
* targeted behaviour tests — the cross-surface effects that a "config changed but
  nothing happened" bug lives in (arc menu enable/disable is the worked example).

A change that is saved to config but produces *no live reaction* is the exact
failure mode this layer is built to expose.
"""
from __future__ import annotations

import copy

import pytest

from harness import apply as A
from harness.controls import enumerate_controls

PAGES = ["bar", "fonts", "themes", "animations", "arcmenu", "menu",
         "quicklinks", "modules", "widgets"]


def _config_controls(page):
    from harness.controls import Control  # noqa: F401

    return [c for c in enumerate_controls(page) if c.kind in A.CONFIG_KINDS]


@pytest.mark.parametrize("page_key", PAGES)
def test_settings_apply(page_key, make_runtime, details):
    """Perturb → Apply for every config control on the page.

    Built once per page (rebuilding the dialogue per control is needlessly slow
    and stresses GTK's measure loop); each control is perturbed, applied, then
    restored so the next control starts from the same baseline.

    The arc menu is disabled for the matrix so a single crash there cannot mask
    every other control; the arc-overlay behaviour has its own targeted tests.
    """
    from harness.runtime import pump

    rt = make_runtime({"arcmenu": {"enabled": False}})
    settings = rt.open_settings(page_key)
    page = settings._stack.get_child_by_name(page_key)
    controls = _config_controls(page)
    details["page"] = page_key
    details["control_count"] = len(controls)

    results = []
    failures = []
    for control in controls:
        if not A.control_enabled(control):
            results.append({"control": str(control), "status": "insensitive"})
            continue
        before_cfg = A.read_cfg()
        before = A.digest(rt)
        state = A.capture(control)
        note = A.perturb(control)
        error = None
        try:
            A.apply_dialogs(settings)
            pump(20)
        except Exception as exc:  # noqa: BLE001
            error = f"{type(exc).__name__}: {exc}"
        after_cfg = A.read_cfg()
        after = A.digest(rt)
        changed = A.cfg_diff(before_cfg, after_cfg)
        live = A.digest_delta(before, after)
        A.restore(control, state)
        status = "ok"
        if error:
            status = "apply-error"
            failures.append({"control": str(control), "error": error})
        elif not changed:
            status = "no-config-change"
        results.append({
            "control": str(control), "note": note, "status": status,
            "cfg_changed": changed[:12], "live_delta": live,
        })
    details["results"] = results
    details["failures"] = failures
    assert not failures, f"{page_key}: {len(failures)} control(s) raised on Apply: {failures}"


def test_apply_with_arcmenu_enabled_does_not_crash(make_runtime, details):
    """With the arc overlay live, a plain Apply must not raise.

    This is the worked-example bug: ``_on_apply`` reaches the arc overlay on
    every page, so a single broken call there breaks *all* settings.
    """
    rt = make_runtime()
    assert rt.arc_win is not None
    errors = []
    for page in ("bar", "fonts", "themes", "animations", "menu"):
        settings = rt.open_settings(page)
        ctl = next(iter(_config_controls(settings._stack.get_child_by_name(page))), None)
        if ctl is None:
            continue
        state = A.capture(ctl)
        A.perturb(ctl)
        try:
            A.apply_dialogs(settings)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{page}: {type(exc).__name__}: {exc}")
        A.restore(ctl, state)
    details["errors"] = errors
    assert not errors, "Apply raised with the arc overlay live: " + "; ".join(errors)


# ── targeted live-reaction behaviour ────────────────────────────────────────

def test_layout_hide_module_is_live(make_runtime, details):
    """Removing a module from the layout unpacks it from every bar section.

    ``bar._widgets`` is a cache (kept so re-enabling need not rebuild), so the
    live signal is the widget's presence in the section boxes, not in the cache.
    """
    from harness.runtime import pump
    from hyprtk_bar import compat

    rt = make_runtime()
    bar = rt.bar
    clock = bar._widgets.get("clock")
    assert clock is not None

    def packed():
        return any(clock in compat.children(s.box) for s in bar._sections.values())

    assert packed(), "clock not packed at startup"
    layout = {k: list(v) for k, v in (rt.cfg.get("layout") or {}).items()}
    layout["right"] = [m for m in layout.get("right", []) if m != "clock"]
    bar._menu_actions()["apply_layout"](layout)
    pump(40)
    details["packed_after"] = packed()
    assert not packed(), "hiding clock left it packed in the bar"


def test_widget_enable_is_live(make_runtime, details):
    """Enabling a desktop widget creates its window without a restart."""
    from harness.runtime import pump

    rt = make_runtime()
    assert "visualizer" not in rt.widget_mgr._wins
    block = copy.deepcopy(rt.cfg["widgets"])
    block["visualizer"]["enabled"] = True
    rt.bar._menu_actions()["set_widgets"](block)
    pump(80)
    details["widget_windows"] = sorted(rt.widget_mgr._wins.keys())
    assert "visualizer" in rt.widget_mgr._wins, "enabling visualizer did not create its window"


def test_arcmenu_disable_then_reenable_is_live(make_runtime, details):
    """Disabling then re-enabling the arc menu must restore the overlay."""
    from harness.runtime import pump

    rt = make_runtime()
    assert rt.arc_win is not None, "arc overlay missing at startup"
    actions = rt.bar._menu_actions()

    off = copy.deepcopy(rt.cfg["arcmenu"]); off["enabled"] = False
    actions["set_arcmenu"](off); pump(60)
    details["after_disable"] = rt.arc_win.get_visible()
    assert not rt.arc_win.get_visible(), "arc overlay still visible after disable"

    on = copy.deepcopy(rt.cfg["arcmenu"]); on["enabled"] = True
    actions["set_arcmenu"](on); pump(60)
    details["after_reenable"] = rt.arc_win.get_visible()
    assert rt.arc_win.get_visible(), "arc overlay did NOT come back after re-enable"


def test_arcmenu_enable_when_started_disabled(make_runtime, details):
    """Enabling the arc menu when it was off at startup must create the overlay."""
    from harness.runtime import pump

    rt = make_runtime({"arcmenu": {"enabled": False}})
    details["arc_win_at_start"] = rt.arc_win is not None
    on = copy.deepcopy(rt.cfg["arcmenu"]); on["enabled"] = True
    rt.bar._menu_actions()["set_arcmenu"](on)
    pump(60)
    details["arc_win_after_enable"] = rt.arc_win is not None
    assert rt.arc_win is not None and rt.arc_win.get_visible(), \
        "arc overlay was never created when enabled at runtime"


def test_menu_disable_then_reenable_is_live(make_runtime, details):
    """Disabling then re-enabling the start menu must restore it."""
    from harness.runtime import pump

    rt = make_runtime()
    assert rt.menu_win is not None
    actions = rt.bar._menu_actions()

    off = copy.deepcopy(rt.cfg["menu"]); off["enabled"] = False
    actions["set_menu"](off); pump(40)
    details["menu_after_disable"] = rt.menu_win is not None
    on = copy.deepcopy(rt.cfg["menu"]); on["enabled"] = True
    actions["set_menu"](on); pump(40)
    details["menu_after_reenable"] = rt.menu_win is not None
    assert rt.menu_win is not None, "start menu gone after disable/enable"


@pytest.mark.parametrize("value,key", [("top", "position"), ("55", "height")])
def test_bar_geometry_actions_apply(make_runtime, value, key, details):
    rt = make_runtime()
    rt.bar._menu_actions()[f"set_{'position' if key == 'position' else 'height'}"](value)
    details["cfg"] = rt.cfg.get(key)
    assert str(rt.cfg.get(key)) == value
