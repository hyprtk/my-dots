"""Quick links: a row of launcher buttons rendered as Nerd Font glyphs.

Each link is a small button that runs a command on left-click and — when
configured — an alternate command on right- and middle-click (e.g. wallpaper:
theme-gui on left, re-generate the palette on right; clipboard history:
pick/delete/wipe). The link list lives in the config's ``quicklinks.links``
block and is fully editable without touching the bar code.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · quicklinks
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import re

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import Gtk  # noqa: E402

from .clipboard import CliphistDialog  # noqa: E402
from .config import DEFAULT_LINKS, icon_size_for  # noqa: E402
from . import proc  # noqa: E402
from .popup import bind_hover_tooltip  # noqa: E402
from .sysapps import (  # noqa: E402
    default_browser_command,
    default_filemanager_command,
    default_terminal_command,
)
from .themer import ThemerDialog  # noqa: E402
from .widgets import Glyph, HoverButton  # noqa: E402

log = logging.getLogger("hyprtk_bar.quicklinks")

# Shell operators that make a command require an explicit sh -c wrapper.
_SHELL_OPS_RE = re.compile(r"(?:&&|\|\||;|\||`|\$\(|[<>])")

# App-launcher quick links whose empty command resolves to the session's
# preferred app at click time ("System default").
_RESOLVERS = {
    "terminal": default_terminal_command,
    "files": default_filemanager_command,
    "web": default_browser_command,
}


def _launch(command: str) -> bool:
    """Spawn a quick-link command, using an explicit sh -c only when needed."""
    command = command.strip()
    if not command:
        return False
    if _SHELL_OPS_RE.search(command):
        return proc.run_shell(command)
    return proc.spawn_command_line(command)


class QuickLinkButton(HoverButton):
    """One launcher button: a Nerd Font glyph, clickable per mouse button."""

    def __init__(self, cfg: dict, link: dict, icon_size: int):
        super().__init__("task-button", vertical=False, spacing=0)
        self._link = link
        ql = cfg.get("quicklinks") or {}
        self._glyph = Glyph(
            link.get("icon", ""),
            "quicklink-glyph",
            (ql.get("glyph_font") or "").strip(),
        )
        self.box.pack_start(self._glyph, False, False, 0)
        self._glyph.set_pixel_size(icon_size)
        label = link.get("label") or link.get("id") or ""
        bind_hover_tooltip(self, cfg, lambda: label)

    def apply_font(self, font_size, icon_size=0) -> None:
        if icon_size:
            self._glyph.set_pixel_size(max(10, int(icon_size)))
        else:
            self._glyph.set_pixel_size(icon_size_for(font_size, icon_size))

    def _on_button_press(self, _widget, event):
        command = self._link.get(
            {1: "command", 2: "command_middle", 3: "command_right"}.get(event.button, "command")
        ) or ""
        if not command:
            resolver = _RESOLVERS.get(self._link.get("id"))
            if resolver is not None:
                command = resolver() or ""
        if command:
            if not _launch(command):
                log.warning("failed to spawn quick link %r", command)
        return True


class ThemerLinkButton(QuickLinkButton):
    """The wallpaper quick link — opens the in-bar Theme Manager dialogue.

    Left-click toggles ThemerDialog (the theming dialogue from theme-gui);
    right-click re-runs the wallpaper palette regeneration. The glyph lives
    here, inside the quicklinks row.
    """

    def __init__(self, cfg: dict, link: dict, icon_size: int, restart_cb=None, theme_cb=None):
        # The glyph opens the Theme Manager, so its tooltip should say so rather
        # than the quick link's generic config label ("Wallpaper").
        link = dict(link)
        link.setdefault("id", "wallpaper")
        link["label"] = "Theme Manager"
        super().__init__(cfg, link, icon_size)
        self._cfg = cfg
        self._restart_cb = restart_cb
        self._theme_cb = theme_cb
        self._popup = None

    def _dialog(self) -> "ThemerDialog":
        # Built lazily on first open: constructing it eagerly (as the quicklinks
        # module is created at startup) decodes the current wallpaper and builds
        # all 8 pages before Gtk.main() — delaying first paint.
        if self._popup is None:
            self._popup = ThemerDialog(self._cfg, restart_cb=self._restart_cb, theme_cb=self._theme_cb)
        return self._popup

    def _on_button_press(self, _widget, event):
        if event.button == 1:
            popup = self._dialog()
            if popup.get_visible():
                popup.hide_popup()
            else:
                popup.show_above(self)
        elif event.button == 3:
            command = self._link.get("command_right") or ""
            if command and not _launch(command):
                log.warning("failed to spawn wallpaper regen %r", command)
        return True

    def shutdown(self) -> None:
        if self._popup is not None and self._popup.get_visible():
            self._popup.hide_popup()


class CliphistLinkButton(QuickLinkButton):
    """The clipboard quick link — opens the in-bar clipboard history dialogue.

    Left-click toggles CliphistDialog (replacing the old external
    cliphist.sh + rofi flow); there is no external command to spawn.
    """

    def __init__(self, cfg: dict, link: dict, icon_size: int):
        link = dict(link)
        link.setdefault("id", "cliphist")
        link["label"] = "Clipboard history"
        super().__init__(cfg, link, icon_size)
        self._cfg = cfg
        self._popup = None

    def _dialog(self) -> "CliphistDialog":
        if self._popup is None:
            self._popup = CliphistDialog(self._cfg)
        return self._popup

    def _on_button_press(self, _widget, event):
        if event.button == 1:
            popup = self._dialog()
            if popup.get_visible():
                popup.hide_popup()
            else:
                popup.show_above(self)
        return True

    def shutdown(self) -> None:
        if self._popup is not None and self._popup.get_visible():
            self._popup.hide_popup()


class QuickLinks(Gtk.Box):
    """The module: a horizontal row of QuickLinkButtons.

    The ``wallpaper`` link is a ``ThemerLinkButton`` — it opens the in-bar
    Theme Manager dialogue instead of spawning an external command.
    """

    def __init__(self, cfg: dict, ipc=None, restart_cb=None, theme_cb=None):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        self._cfg = cfg
        self._buttons: list[QuickLinkButton] = []
        links = (cfg.get("quicklinks") or {}).get("links") or DEFAULT_LINKS
        for link in links:
            if not isinstance(link, dict) or not link.get("icon"):
                continue
            if link.get("id") == "wallpaper":
                button = ThemerLinkButton(cfg, link, self._glyph_size(),
                                          restart_cb=restart_cb, theme_cb=theme_cb)
            elif link.get("id") == "cliphist":
                button = CliphistLinkButton(cfg, link, self._glyph_size())
            else:
                button = QuickLinkButton(cfg, link, self._glyph_size())
            self._buttons.append(button)
            self.pack_start(button, False, False, 0)

    def shutdown(self) -> None:
        for button in self._buttons:
            shutdown = getattr(button, "shutdown", None)
            if shutdown is not None:
                shutdown()

    def _glyph_size(self, font_size=None, icon_size=0) -> int:
        ql = self._cfg.get("quicklinks") or {}
        try:
            override = int(ql.get("icon_size", 0) or 0)
        except (TypeError, ValueError):
            override = 0
        if override > 0:
            return max(10, override)
        if icon_size:
            return max(10, int(icon_size))
        font_size = font_size if font_size else (self._cfg.get("font") or {}).get("size", 16)
        return icon_size_for(font_size, 0)

    def apply_font(self, font_size, icon_size=0) -> None:
        size = self._glyph_size(font_size, icon_size)
        for button in self._buttons:
            button.apply_font(font_size, size)