"""hyprtk-bar entry point.

The bar is a plain always-running GTK window (layer-shell surface) driven by
``compat.run_main()`` — a GLib.MainLoop on GTK4 (which removed ``Gtk.main``),
or ``Gtk.main()`` under the GTK3 escape hatch. A SIGTERM quits it cleanly. Only
one instance is allowed — a flock in $XDG_RUNTIME_DIR prevents duplicate bars
stacking (e.g. from duplicate autostart entries).
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · __main__
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import argparse
import fcntl
import json
import logging
import os
import signal
import sys
import threading
from pathlib import Path

from . import compat  # noqa: E402
from .compat import GLib, GLibUnix, Gtk  # noqa: E402

from . import proc  # noqa: E402
from .app import BarWindow, select_monitors
from .arcmenu import ArcMenuWindow  # noqa: E402
from .config import load as load_config
from .ipc import HyprIPC
from .menu.menu_window import MenuWindow  # noqa: E402

_lock_file = None

# How often (seconds) the surface watchdog checks for the bar's own layer
# surface, and how many consecutive misses it requires before self-healing.
_WATCHDOG_INTERVAL_S = 30
_WATCHDOG_STRIKES = 2


def _acquire_lock() -> bool:
    """Take an exclusive flock; returns False if another bar is already running."""
    global _lock_file
    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    # Per-uid name + O_NOFOLLOW + 0600: the /tmp fallback is world-writable, so a
    # symlink must not be followable there.
    path = Path(runtime) / f"hyprtk-bar-{os.getuid()}.lock"
    try:
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    except OSError:
        return False
    try:
        _lock_file = os.fdopen(fd, "w")
        fcntl.flock(_lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        _lock_file.seek(0)
        _lock_file.truncate()
        _lock_file.write(str(os.getpid()))
        _lock_file.flush()
        return True
    except (OSError, ValueError):
        # Another instance holds the lock, or the fdopen/flock failed — close the
        # fd so it is not leaked (the bar can reach here again in-process).
        try:
            _lock_file.close()
        except Exception:
            pass
        _lock_file = None
        return False


def _print_config() -> None:
    print(json.dumps(load_config(), indent=2))


def _add_unix_signal(priority: int, signum: int, handler, user_data=None) -> int:
    """Register a Unix-signal handler, tolerating GLib binding drift.

    ``g_unix_signal_add`` is a C macro, so what GLib exposes via introspection
    depends on the GLib/PyGObject versions installed: newer typelibs export
    ``GLibUnix.signal_add``; some older ones only bind the deprecated
    ``GLibUnix.signal_add_full``; the oldest expose only
    ``GLib.unix_signal_add``. A bind failure here aborts startup, so the bar
    must cope with all three. Prefer ``signal_add`` where it exists — probing
    ``signal_add_full`` emits a deprecation warning on newer stacks.
    """
    if hasattr(GLibUnix, "signal_add"):
        return GLibUnix.signal_add(priority, signum, handler, user_data)
    if hasattr(GLibUnix, "signal_add_full"):
        return GLibUnix.signal_add_full(priority, signum, handler, user_data)
    return GLib.unix_signal_add(priority, signum, handler, user_data)


def _start_surface_watchdog(ipc) -> None:
    """Self-heal if the compositor drops the bar's layer surface.

    After a long session lock, Hyprland can leave the bar's ``wl_surface`` gone
    (unmapped/destroyed) while the process keeps running — the bar then never
    reappears on unlock. This polls ``hyprctl layers`` for our own surface and,
    if it is missing ``_WATCHDOG_STRIKES`` times in a row, restarts the bar
    process (the same path as the manual kill-and-restart, but automatic).

    The check runs on a worker thread (``hyprctl`` can block up to its timeout);
    the surface is still reported by ``hyprctl layers`` while the session is
    locked, so the watchdog only fires once the surface is genuinely gone.
    """
    state = {"strikes": 0, "healed": False}

    def _self_heal() -> bool:
        if state["healed"]:
            return GLib.SOURCE_REMOVE
        state["healed"] = True
        launcher = os.path.expanduser("~/.local/bin/hyprtk-bar")
        if proc.spawn_argv(["/bin/sh", "-c", 'sleep 1; exec "$@"', "sh", launcher]):
            logging.warning(
                "hyprtk-bar layer surface vanished; restarting to restore the bar"
            )
            compat.quit_main()
        return GLib.SOURCE_REMOVE

    def _tick() -> bool:
        def _check() -> None:
            layers = ipc.query("layers")
            if layers is None:
                return
            pid = str(os.getpid())
            present = any(
                l.get("namespace") == "hyprtk-bar" and str(l.get("pid")) == pid
                for mon in layers.values()
                for group in mon.get("levels", {}).values()
                for l in group
            )
            if present:
                state["strikes"] = 0
                return
            state["strikes"] += 1
            if state["strikes"] >= _WATCHDOG_STRIKES:
                GLib.idle_add(_self_heal)

        threading.Thread(target=_check, daemon=True).start()
        return True

    GLib.timeout_add_seconds(_WATCHDOG_INTERVAL_S, _tick)


def _run_window() -> int:
    if not _acquire_lock():
        logging.warning("another hyprtk-bar is already running; exiting")
        return 1
    cfg = load_config()

    # One Hyprland IPC + event-socket thread shared by all per-monitor bars.
    ipc = HyprIPC()
    monitors = select_monitors(cfg)
    if not monitors:
        logging.warning("no monitors available; giving up")
        return 1

    windows = []
    for i, monitor in enumerate(monitors):
        is_primary = i == 0 or compat.monitor_is_primary(monitor)
        win = BarWindow(
            cfg,
            monitor=monitor,
            ipc=ipc,
            is_primary=is_primary,
            start_ipc=(i == 0),
        )
        compat.show_all(win)
        windows.append(win)
    logging.info("started %d bar(s) on %d monitor(s)", len(windows), len(monitors))

    primary = next((w for w in windows if w.is_primary), windows[0])

    # The arc menu overlay is owned by the bar process and toggled by SIGUSR2 (a
    # Hyprland keybinding signals the running bar). It is created on demand:
    # enabling it from settings when it was off at startup must work, so the
    # ``set_arcmenu`` callback creates the overlay if it does not exist yet, and
    # only then reloads/hides it.
    arc_win = None

    def ensure_arc():
        """Create the arc overlay on first need; return it (or None)."""
        nonlocal arc_win
        if arc_win is None:
            arc_win = ArcMenuWindow(
                cfg, on_settings=lambda: _open_arc_settings(windows)
            )
            compat.show_all(arc_win)
            primary.add_theme_extra_callback(arc_win.apply_bar_palette)
            if primary._palette_cache:
                arc_win.apply_bar_palette(primary._palette_cache)
            logging.info("started arc menu overlay")
        return arc_win

    def on_arc_config(_block) -> None:
        if (cfg.get("arcmenu") or {}).get("enabled", True):
            ensure_arc().reload_from_cfg()
        elif arc_win is not None:
            arc_win.reload_from_cfg()  # enabled off → hides the overlay

    primary._bar.set_arcmenu_callback(on_arc_config)
    if (cfg.get("arcmenu") or {}).get("enabled", True):
        ensure_arc()

    # The start menu (hyprtk-menu) is likewise owned by the bar process, toggled
    # by SIGUSR1 and by the bar's start button; it starts HIDDEN (the start
    # button / keybind reveals it). Created on demand for the same reason as the
    # arc overlay: enabling it from settings must work without a restart.
    menu_win = None

    def ensure_menu():
        nonlocal menu_win
        if menu_win is None:
            menu_win = MenuWindow(
                bar_cfg=cfg, on_settings=lambda: _open_menu_settings(windows)
            )
            logging.info("started start menu")
        return menu_win

    def on_menu_config(_block) -> None:
        if (cfg.get("menu") or {}).get("enabled", True):
            ensure_menu().reload_from_cfg()
        elif menu_win is not None:
            menu_win.reload_from_cfg()

    primary._bar.set_menu_callback(lambda: ensure_menu().toggle())
    primary._bar.set_menu_reload_callback(on_menu_config)
    if (cfg.get("menu") or {}).get("enabled", True):
        ensure_menu()

    # Desktop widgets (clock / weather / visualizer) are likewise owned by the
    # bar process: free-floating layer-shell surfaces, enabled and placed from
    # the settings window's "Widgets" page. The manager diffs the config on
    # Apply, so toggling one is live. It is always created (even when the
    # master switch starts off) so enabling widgets from settings works without
    # a restart.
    from .desktop import DesktopWidgetManager

    widget_mgr = DesktopWidgetManager(cfg, ipc)
    primary.add_theme_extra_callback(widget_mgr.apply_theme)
    primary._bar.set_widgets_callback(lambda _block: widget_mgr.reload(cfg))
    if primary._palette_cache:
        widget_mgr.apply_theme(primary._palette_cache)
    logging.info("started %d desktop widget(s)", len(widget_mgr._wins))

    def on_sigterm(*_args):
        compat.quit_main()
        return GLib.SOURCE_REMOVE

    def on_sigusr2(*_args):
        if arc_win is not None:
            arc_win.toggle()
        return GLib.SOURCE_CONTINUE

    def on_sigusr1(*_args):
        if menu_win is not None:
            menu_win.toggle()
        return GLib.SOURCE_CONTINUE

    def on_sighup(*_args):
        _toggle_clipboard(windows)
        return GLib.SOURCE_CONTINUE

    # Desktop-widget move: the Hyprland Super+LMB bind runs
    # hyprtk-bar-widget-move.sh, which writes start/stop to a FIFO the bar
    # watches (a FIFO, not a signal — GTK never sees the Super modifier on a
    # keyboard_mode=none layer surface, and GLib signal sources don't accept
    # real-time signals). The bar then polls the cursor and moves the widget
    # under it.
    from .desktop.control import WidgetMoveControl

    move_control = WidgetMoveControl(widget_mgr.begin_move, widget_mgr.end_move)

    _add_unix_signal(GLib.PRIORITY_DEFAULT, signal.SIGTERM, on_sigterm)
    _add_unix_signal(GLib.PRIORITY_DEFAULT, signal.SIGUSR2, on_sigusr2)
    _add_unix_signal(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, on_sigusr1)
    _add_unix_signal(GLib.PRIORITY_DEFAULT, signal.SIGHUP, on_sighup)

    # Recover from the compositor dropping the bar's layer surface after a long
    # session lock (surface gone, process alive) by restarting automatically.
    _start_surface_watchdog(ipc)

    try:
        compat.run_main()
    finally:
        if arc_win is not None:
            arc_win.destroy()
        if menu_win is not None:
            menu_win.destroy()
        move_control.shutdown()
        if widget_mgr is not None:
            widget_mgr.shutdown()
        for win in windows:
            win.shutdown()
    return 0


def _open_arc_settings(windows) -> None:
    """Open the bar settings dialogue on the Arc Menu tab."""
    primary = next((w for w in windows if w.is_primary), windows[0])
    primary._bar.open_settings("arcmenu")


def _open_menu_settings(windows) -> None:
    """Open the bar settings dialogue on the Menu tab."""
    primary = next((w for w in windows if w.is_primary), windows[0])
    primary._bar.open_settings("menu")


def _toggle_clipboard(windows) -> None:
    """Toggle the in-bar clipboard history dialogue (SIGHUP).

    Finds the cliphist quick-link button on the primary bar and toggles its
    CliphistDialog — the same path the button's own click handler uses.
    """
    from .quicklinks import CliphistLinkButton

    primary = next((w for w in windows if w.is_primary), windows[0])
    quicklinks = primary._bar._widgets.get("quicklinks")
    if quicklinks is None:
        return
    for button in getattr(quicklinks, "_buttons", []):
        if isinstance(button, CliphistLinkButton):
            popup = button._dialog()
            if popup.get_visible():
                popup.hide_popup()
            else:
                popup.show_above(button)
            break


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="hyprtk-bar",
        description="HYPRTK taskbar for Hyprland (GTK4 + layer shell).",
    )
    parser.add_argument(
        "--print-config",
        action="store_true",
        help="Print the resolved config as JSON and exit.",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Enable debug logging."
    )
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s: %(message)s",
    )

    if args.print_config:
        _print_config()
        return 0

    proc.bootstrap_environment()
    return _run_window()


if __name__ == "__main__":
    sys.exit(main())