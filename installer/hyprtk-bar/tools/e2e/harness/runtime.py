"""Build the real bar object graph headlessly.

This mirrors ``hyprtk_bar.__main__._run_window`` — bar window(s) + arc overlay +
start menu + desktop-widget manager, with the same callbacks wired — but takes a
fake IPC and never enters the main loop. Using the real classes (not stubs) is
the point: the settings-apply matrix must exercise the true code path, including
the ``arcmenu.enabled`` startup gate that hides the "re-enable does nothing" bug.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from hyprtk_bar import compat
from hyprtk_bar.app import BarWindow, select_monitors
from hyprtk_bar.arcmenu import ArcMenuWindow
from hyprtk_bar.menu.menu_window import MenuWindow


def _monitor():
    monitors = compat.monitors()
    if not monitors:
        return None
    for m in monitors:
        if compat.monitor_is_primary(m):
            return m
    return monitors[0]


@dataclass
class Runtime:
    cfg: dict
    ipc: object
    windows: list = field(default_factory=list)
    arc_win: object = None
    menu_win: object = None
    widget_mgr: object = None
    details: dict = field(default_factory=dict)

    @property
    def bar_win(self):
        return self.windows[0]

    @property
    def bar(self):
        return self.windows[0]._bar

    def open_settings(self, page: str | None = None):
        self.bar.open_settings(page)
        return self.bar._settings_win

    def teardown(self) -> None:
        for obj in (self.arc_win, self.menu_win, self.widget_mgr):
            for name in ("shutdown", "destroy"):
                fn = getattr(obj, name, None)
                if fn is not None:
                    try:
                        fn()
                        break
                    except Exception:
                        pass
        for win in self.windows:
            try:
                win.shutdown()
            except Exception:
                pass


def build_runtime(cfg: dict, ipc) -> Runtime:
    rt = Runtime(cfg=cfg, ipc=ipc)

    monitor = _monitor()
    win = BarWindow(cfg, monitor=monitor, ipc=ipc, is_primary=True, start_ipc=False)
    compat.show_all(win)
    rt.windows.append(win)
    rt.details["monitor"] = getattr(monitor, "__class__", None) and str(monitor)

    # Mirrors __main__._run_window's on-demand overlay creation: the callback is
    # always installed, creates the overlay on first need, and reloads/hides it.
    def ensure_arc():
        if rt.arc_win is None:
            rt.arc_win = ArcMenuWindow(cfg, on_settings=lambda: None)
            compat.show_all(rt.arc_win)
            win.add_theme_extra_callback(rt.arc_win.apply_bar_palette)
        return rt.arc_win

    def on_arc_config(_block) -> None:
        if (cfg.get("arcmenu") or {}).get("enabled", True):
            ensure_arc().reload_from_cfg()
        elif rt.arc_win is not None:
            rt.arc_win.reload_from_cfg()

    win._bar.set_arcmenu_callback(on_arc_config)
    if (cfg.get("arcmenu") or {}).get("enabled", True):
        ensure_arc()

    def ensure_menu():
        if rt.menu_win is None:
            rt.menu_win = MenuWindow(bar_cfg=cfg, on_settings=lambda: None)
        return rt.menu_win

    def on_menu_config(_block) -> None:
        if (cfg.get("menu") or {}).get("enabled", True):
            ensure_menu().reload_from_cfg()
        elif rt.menu_win is not None:
            rt.menu_win.reload_from_cfg()

    win._bar.set_menu_callback(lambda: ensure_menu().toggle())
    win._bar.set_menu_reload_callback(on_menu_config)
    if (cfg.get("menu") or {}).get("enabled", True):
        ensure_menu()

    from hyprtk_bar.desktop import DesktopWidgetManager

    rt.widget_mgr = DesktopWidgetManager(cfg, ipc)
    win.add_theme_extra_callback(rt.widget_mgr.apply_theme)
    win._bar.set_widgets_callback(lambda _block: rt.widget_mgr.reload(cfg))
    if win._palette_cache:
        rt.widget_mgr.apply_theme(win._palette_cache)

    return rt


def pump(ms: int = 60) -> None:
    """Run the GLib main loop for a bounded time (flush pending idle/timeouts)."""
    from hyprtk_bar.compat import GLib

    ctx = GLib.MainContext.default()
    done = {"t": False}

    def _stop():
        done["t"] = True
        return False

    GLib.timeout_add(ms, _stop)
    while not done["t"]:
        ctx.iteration(False)
