"""Taskbar buttons: pinned + running apps grouped by class (Win11-style).

Each app is one button with a running/active indicator. Left-click focuses the
most recent window (or minimizes the focused one), middle-click closes, and
hover/right-click opens a floating preview popup listing the app's windows.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · tasklist
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import re

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")

from gi.repository import Gio, GLib, Gtk, Pango  # noqa: E402

from . import config as config_module  # noqa: E402
from .config import icon_size_for  # noqa: E402
from .popup import Popup  # noqa: E402
from .widgets import HoverButton, spawn  # noqa: E402

log = logging.getLogger("hyprtk_bar.tasklist")

GENERIC_ICON = "application-x-executable"


def _class_matches(pinned_class: str, window_class: str) -> bool:
    """Case-insensitive match, also treating a prefix as a match.

    Apps often report a class that differs from the pinned entry
    (``Brave`` vs ``brave-browser``); matching keeps one icon per app.
    """
    a = (pinned_class or "").strip().lower()
    b = (window_class or "").strip().lower()
    if not a or not b:
        return False
    if a == b:
        return True
    return a.startswith(b) or b.startswith(a)


# A window class / app_id is attacker-influenced (any app on the session can
# set its own). Before it reaches ``Gio.DesktopAppInfo.new("<id>.desktop")`` —
# which treats a value containing ``/`` as a FILESYSTEM PATH — it must match a
# safe desktop-id shape.
_DESKTOP_ID_RE = re.compile(r"^[A-Za-z0-9_.+-]+$")


def _desktop_id(value: str) -> str:
    """Return ``value`` only when it is a safe desktop-id, else ""."""
    value = (value or "").strip()
    return value if _DESKTOP_ID_RE.fullmatch(value) else ""


def resolve_command(app_class: str) -> str:
    """Best-guess launch command for an app class (via its .desktop entry)."""
    app_id = _desktop_id(app_class)
    if not app_id:
        return app_class.lower()
    try:
        info = Gio.DesktopAppInfo.new(f"{app_id}.desktop")
        line = info.get_commandline() if info is not None else None
        if line:
            cmd = line.split()[0].rsplit("/", 1)[-1]
            if cmd:
                return cmd
    except (TypeError, GLib.Error):
        pass
    return app_class.lower()


def resolve_icon(app_class: str, explicit: str | None = None) -> str:
    """Best icon name for an app class: config override, desktop entry, class, generic.

    Prefers the symbolic variant (``<name>-symbolic``) when the icon theme
    ships one, so tasklist icons match the bar's monochrome modules; otherwise
    the original colour icon is kept.
    """
    theme = Gtk.IconTheme.get_default()
    if explicit and theme.has_icon(explicit):
        return _prefer_symbolic(theme, explicit)
    app_id = _desktop_id(app_class)
    if app_id:
        try:
            info = Gio.DesktopAppInfo.new(f"{app_id}.desktop")
        except (TypeError, GLib.Error):
            # constructor returns NULL (raised by pygobject) when no matching .desktop
            info = None
        if info is not None:
            icon = info.get_icon()
            if icon is not None:
                name = icon.to_string()
                if name and theme.has_icon(name):
                    return _prefer_symbolic(theme, name)
    if theme.has_icon(app_class):
        return _prefer_symbolic(theme, app_class)
    return _prefer_symbolic(theme, GENERIC_ICON)


def _prefer_symbolic(theme: Gtk.IconTheme, name: str) -> str:
    """Return ``name-symbolic`` when the icon theme provides it, else ``name``."""
    if name and theme.has_icon(f"{name}-symbolic"):
        return f"{name}-symbolic"
    return name


# Generic symbolic icons per app category, offered when pinning an app that
# has no symbolic variant of its own icon.
CATEGORY_SYMBOLIC = (
    ("FILEMANAGER", "system-file-manager-symbolic"),
    ("TERMINALEMULATOR", "utilities-terminal-symbolic"),
    ("TEXTEDITOR", "accessories-text-editor-symbolic"),
    ("WEBBROWSER", "web-browser-symbolic"),
)


def generic_symbolic_icon(app_class: str) -> str | None:
    """A generic symbolic icon for the app's category, or None."""
    app_id = _desktop_id(app_class)
    if not app_id:
        return None
    for candidate in (f"{app_id}.desktop", f"{app_id.lower()}.desktop"):
        try:
            info = Gio.DesktopAppInfo.new(candidate)
        except (TypeError, GLib.Error):
            # constructor returns NULL (raised by pygobject) when no match
            info = None
        if info is None:
            continue
        categories = (info.get_categories() or "").upper()
        for token, icon in CATEGORY_SYMBOLIC:
            if token in categories:
                return icon
    return None


def build_preview_content(
    box: Gtk.Box,
    app_class: str,
    windows: list,
    on_focus,
    on_close,
    on_launch,
) -> None:
    """Fill ``box`` (a popup's content) with the app's window list."""
    for child in box.get_children():
        box.remove(child)

    title = Gtk.Label(label=app_class, xalign=0)
    title.get_style_context().add_class("popup-title")
    title.set_margin_bottom(2)
    box.pack_start(title, False, False, 0)

    for win in windows:
        box.pack_start(_make_row(win, on_focus, on_close), False, False, 0)

    if on_launch:
        sep = Gtk.Separator()
        sep.set_margin_top(3)
        sep.set_margin_bottom(3)
        box.pack_start(sep, False, False, 0)
        new_row = HoverButton("popup-row", vertical=False, spacing=8)
        new_row.box.pack_start(
            Gtk.Image.new_from_icon_name("list-add-symbolic", Gtk.IconSize.MENU),
            False, False, 0,
        )
        new_row.box.pack_start(
            Gtk.Label(label="Open new window", xalign=0), True, True, 0
        )
        new_row.connect("button-press-event", lambda *_a: on_launch())
        box.pack_start(new_row, False, False, 0)

    box.show_all()


def _make_row(win: dict, on_focus, on_close):
    row = HoverButton("popup-row", vertical=False, spacing=8)
    icon_name = resolve_icon(win.get("class") or "unknown")
    icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.MENU)
    icon.set_pixel_size(16)
    row.box.pack_start(icon, False, False, 0)
    label = Gtk.Label(
        label=(win.get("title") or win.get("class") or "Untitled"),
        xalign=0,
    )
    label.set_ellipsize(Pango.EllipsizeMode.END)
    label.set_max_width_chars(28)
    row.box.pack_start(label, True, True, 0)
    close = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.MENU)
    close.set_relief(Gtk.ReliefStyle.NONE)
    close.connect("clicked", lambda *_a: on_close(win))
    row.box.pack_start(close, False, False, 0)
    row.connect("button-press-event", lambda *_a: on_focus(win))
    return row


class TaskButton(HoverButton):
    """One taskbar icon with a running indicator and a hover preview."""

    def __init__(self, app_class: str, pinned: dict, callbacks: dict, icon_size: int = 20):
        super().__init__("task-button", vertical=True, spacing=2)
        self.app_class = app_class
        self.pinned = pinned
        self._cb = callbacks
        self._icon_size = icon_size
        self._windows: list = []
        self._show_timer = None
        self._hide_timer = None

        self._icon = Gtk.Image.new_from_icon_name(
            resolve_icon(app_class, pinned.get("icon")), Gtk.IconSize.INVALID
        )
        self._icon.set_pixel_size(self._icon_size)
        self._icon.get_style_context().add_class("task-icon")
        self._icon.set_halign(Gtk.Align.CENTER)
        self._icon.set_valign(Gtk.Align.CENTER)

        # Running/active indicator: a small dot overlaid on the icon's
        # bottom-right corner.
        self._overlay = Gtk.Overlay()
        self._overlay.add(self._icon)
        self._dot = Gtk.Box()
        self._dot.get_style_context().add_class("task-dot")
        self._dot.set_no_show_all(True)
        self._dot.set_halign(Gtk.Align.END)
        self._dot.set_valign(Gtk.Align.END)
        self._dot.set_margin_end(2)
        self._dot.set_margin_bottom(2)
        self._dot.hide()
        self._overlay.add_overlay(self._dot)
        self.box.pack_start(self._overlay, True, True, 0)

        self.connect("enter-notify-event", self._on_enter_preview)
        self.connect("leave-notify-event", self._on_leave_preview)

    # ── state ─────────────────────────────────────────────────────

    def update(self, windows: list, active: bool) -> None:
        self._windows = windows
        ctx = self.box.get_style_context()
        if windows:
            self._dot.show()
            ctx.remove_class("dimmed")
        else:
            self._dot.hide()
            ctx.add_class("dimmed")
        if active:
            ctx.add_class("active")
        else:
            ctx.remove_class("active")

    # ── pointer ───────────────────────────────────────────────────

    def _on_button_press(self, _widget, event):
        if event.button == 1:
            self._cb["hide_preview"]()
            self._cb["left"]()
        elif event.button == 2:
            self._cb["hide_preview"]()
            self._cb["middle"]()
        elif event.button == 3:
            self._cb["hide_preview"]()
            self._show_context_menu(event)
        return True

    def _show_context_menu(self, event) -> None:
        menu = Gtk.Menu()
        if self.pinned:
            item = Gtk.MenuItem(label="Unpin from taskbar")
            item.connect("activate", lambda *_a: self._cb["unpin"]())
        else:
            item = Gtk.MenuItem(label="Pin to taskbar")
            item.connect("activate", lambda *_a: self._cb["pin"]())
        menu.append(item)
        if self._windows:
            close = Gtk.MenuItem(label="Close window")
            close.connect("activate", lambda *_a: self._cb["middle"]())
            menu.append(close)
        menu.show_all()
        menu.popup_at_pointer(event)

    # ── hover preview ─────────────────────────────────────────────

    def _on_enter_preview(self, *_args):
        self._cancel_hide()
        if self._show_timer is None and self._windows:
            self._show_timer = GLib.timeout_add(250, self._open_preview)
        return False

    def _on_leave_preview(self, *_args):
        if self._show_timer is not None:
            GLib.source_remove(self._show_timer)
            self._show_timer = None
        self._schedule_hide()
        return False

    def _open_preview(self) -> bool:
        self._show_timer = None
        self._show_preview(force=False)
        return GLib.SOURCE_REMOVE

    def _show_preview(self, force: bool) -> None:
        if not self._windows:
            return
        self._cb["show_preview"](self)

    def _schedule_hide(self) -> None:
        if self._hide_timer is not None:
            return
        self._hide_timer = GLib.timeout_add(200, self._hide_preview)

    def _cancel_hide(self) -> None:
        if self._hide_timer is not None:
            GLib.source_remove(self._hide_timer)
            self._hide_timer = None

    def _hide_preview(self) -> bool:
        self._cancel_hide()
        if self._show_timer is not None:
            GLib.source_remove(self._show_timer)
            self._show_timer = None
        self._cb["hide_preview"]()
        return GLib.SOURCE_REMOVE


class TaskList(Gtk.Box):
    """The centered group of app buttons, with a shared preview popup."""

    def __init__(self, cfg: dict, ipc, reload_cb=None, restart_cb=None):
        super().__init__(spacing=2)
        self._cfg = cfg
        self._ipc = ipc
        self._reload_cb = reload_cb
        self._restart_cb = restart_cb
        self._pinned = {p["class"]: p for p in (cfg.get("center") or {}).get("pinned", [])}
        self._buttons: dict[str, TaskButton] = {}
        self._grouped: dict[str, list] = {}
        self._focus_address = None
        self._active_workspace = 1
        self._last_clients: list = []

        self._preview = Popup(cfg, cfg.get("position", "bottom"))
        self._preview.set_on_leave(self._preview_leave)

    # ── public ────────────────────────────────────────────────────

    def _display_class(self, window_class: str) -> str:
        """Map a running window class to a pinned class when they match.

        Apps can report a class that differs from the pinned entry (e.g. pinned
        ``Brave`` vs the window's ``brave-browser``). Matching those keeps a
        single taskbar icon that turns active instead of duplicating.
        """
        for pinned_class in self._pinned:
            if _class_matches(pinned_class, window_class):
                return pinned_class
        return window_class

    def update(self, clients: list, focus_address: str | None, active_workspace: int) -> None:
        self._focus_address = focus_address
        self._active_workspace = active_workspace
        self._last_clients = clients

        grouped: dict[str, list] = {}
        for c in clients:
            if not c.get("mapped"):
                continue
            cls = self._display_class(c.get("class") or "unknown")
            grouped.setdefault(cls, []).append(c)
        self._grouped = grouped

        order = list(self._pinned)
        for cls in grouped:
            if cls not in order:
                order.append(cls)

        for cls in list(self._buttons):
            if cls not in order:
                self._buttons.pop(cls).destroy()

        for cls in order:
            if cls not in self._buttons:
                font_cfg = self._cfg.get("font") or {}
                self._buttons[cls] = TaskButton(
                    cls, self._pinned.get(cls, {}), self._callbacks(cls),
                    icon_size_for(font_cfg.get("size", 16), font_cfg.get("icon_size", 0)),
                )
                self.pack_start(self._buttons[cls], False, False, 0)

        for cls, btn in self._buttons.items():
            wins = grouped.get(cls, [])
            btn.update(wins, self._focus_address in {w.get("address") for w in wins})
        self.show_all()

    def shutdown(self) -> None:
        self._preview.hide_popup()
        self._preview.destroy()

    def apply_font(self, font_size, icon_size=0) -> None:
        size = icon_size_for(font_size, icon_size)
        for btn in self._buttons.values():
            btn._icon_size = size
            btn._icon.set_pixel_size(size)

    # ── preview popup ─────────────────────────────────────────────

    def show_preview(self, button: TaskButton) -> None:
        build_preview_content(
            self._preview.content,
            button.app_class,
            button._windows,
            on_focus=lambda win: self._preview_close(self._focus_win, win),
            on_close=lambda win: self._preview_close(self._close_win, win),
            on_launch=lambda: self._preview_close(self._launch, button.app_class)
            if button.pinned
            else None,
        )
        # Entering the preview cancels the button's pending hide, so moving from
        # the icon up into the popup doesn't dismiss it.
        self._preview.set_on_enter(button._cancel_hide)
        self._preview.set_on_leave(self._preview_leave)
        self._preview.show_above(button)

    def hide_preview(self) -> None:
        self._preview.hide_popup()

    def _preview_leave(self) -> None:
        btn = self._button_under_preview()
        if btn is not None:
            btn._schedule_hide()
        else:
            self.hide_preview()

    def _button_under_preview(self) -> TaskButton | None:
        return None  # pointer left into the bar; leave handling is on the button

    def _preview_close(self, action, *args) -> None:
        self.hide_preview()
        action(*args)

    # ── interactions ──────────────────────────────────────────────

    def _callbacks(self, cls: str) -> dict:
        return {
            "left": lambda: self._left_click(cls),
            "middle": lambda: self._middle_click(cls),
            "show_preview": lambda btn: self.show_preview(btn),
            "hide_preview": lambda: self.hide_preview(),
            "focus": lambda win: self._focus_win(win),
            "close": lambda win: self._close_win(win),
            "launch": lambda: self._launch(cls),
            "pin": lambda: self._pin(cls),
            "unpin": lambda: self._unpin(cls),
        }

    # ── pin / unpin (right-click) ─────────────────────────────────

    def _pin(self, cls: str) -> None:
        pinned = self._cfg.setdefault("center", {}).setdefault("pinned", [])
        if any(p.get("class") == cls for p in pinned):
            return
        pinned.append({
            "class": cls,
            "command": resolve_command(cls),
            "icon": self._choose_pin_icon(cls),
        })
        config_module.save(self._cfg)
        self._pinned = {p["class"]: p for p in pinned}
        self._refresh()
        self._reload_and_verify(cls, expected=True)

    def _choose_pin_icon(self, cls: str) -> str:
        """Ask whether to use the generic symbolic category icon or the actual
        application icon when pinning. Falls back to the app icon when the app
        has no category mapping or the icons are the same."""
        generic = generic_symbolic_icon(cls)
        actual = resolve_icon(cls, None)
        if generic is None or generic == actual:
            return actual

        dialog = Gtk.MessageDialog(
            transient_for=None,
            modal=True,
            destroy_with_parent=False,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.NONE,
            text=f"Pin “{cls}” to the taskbar",
        )
        dialog.format_secondary_text(
            "Choose which icon the pinned app should use."
        )
        dialog.set_keep_above(True)
        resp_generic = 1
        resp_actual = 2
        dialog.add_button(f"Generic symbolic icon ({generic})", resp_generic)
        dialog.add_button(f"Application icon ({actual})", resp_actual)
        dialog.set_default_response(resp_generic)
        response = dialog.run()
        dialog.destroy()
        return generic if response == resp_generic else actual

    def _unpin(self, cls: str) -> None:
        pinned = self._cfg.setdefault("center", {}).setdefault("pinned", [])
        self._cfg["center"]["pinned"] = [p for p in pinned if p.get("class") != cls]
        config_module.save(self._cfg)
        self._pinned = {p["class"]: p for p in self._cfg["center"]["pinned"]}
        self._refresh()
        self._reload_and_verify(cls, expected=False)

    def _reload_and_verify(self, cls: str, expected: bool) -> None:
        """Reload the bar config after a pin change; restart if it didn't stick."""
        try:
            if self._reload_cb is not None:
                self._reload_cb()
        except Exception as exc:
            log.warning("config reload after pin change failed: %s", exc)
        GLib.timeout_add(600, self._verify_pin_change, cls, expected)

    def _verify_pin_change(self, cls: str, expected: bool) -> bool:
        present = cls in self._pinned and cls in self._buttons
        if present != expected:
            log.warning(
                "pin change for %r not reflected (%s), restarting bar",
                cls,
                "expected present" if expected else "expected gone",
            )
            if self._restart_cb is not None:
                self._restart_cb()
        return GLib.SOURCE_REMOVE

    def _refresh(self) -> None:
        self.update(self._last_clients, self._focus_address, self._active_workspace)

    def _windows(self, cls: str) -> list:
        return self._grouped.get(cls, [])

    def _left_click(self, cls: str) -> None:
        wins = self._windows(cls)
        if not wins:
            self._launch(cls)
            return
        focused = [w for w in wins if w.get("address") == self._focus_address]
        if focused:
            self._minimize(focused[0])
            return
        target = max(wins, key=lambda w: w.get("focusHistoryID", 0))
        self._focus_win(target)

    def _middle_click(self, cls: str) -> None:
        wins = self._windows(cls)
        if wins:
            target = max(wins, key=lambda w: w.get("focusHistoryID", 0))
            self._close_win(target)

    def _launch(self, cls: str) -> None:
        command = (self._pinned.get(cls) or {}).get("command")
        if not command:
            return
        if not spawn(command):
            log.warning("Failed to launch %r", command)

    def _focus_win(self, win: dict) -> None:
        addr = win.get("address")
        if not addr:
            return
        if self._ws_id(win) < 0:  # minimized on a special workspace: restore first
            self._ipc.move_window(self._active_workspace, addr)
        self._ipc.focus_window(addr)

    def _minimize(self, win: dict) -> None:
        addr = win.get("address")
        if not addr:
            return
        self._ipc.move_window("special:minimized", addr)

    def _close_win(self, win: dict) -> None:
        addr = win.get("address")
        if not addr:
            return
        self._ipc.close_window(addr)

    @staticmethod
    def _ws_id(win: dict) -> int:
        ws = win.get("workspace")
        if isinstance(ws, dict):
            return ws.get("id", 0)
        return ws or 0