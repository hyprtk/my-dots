"""Active-window title module (waybar's `hyprland/window`).

Shows the focused window's title as text, hidden while no window is focused.
The module has a FIXED width so changing titles never shift the other modules;
the title is ellipsized within it.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · window
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")

from gi.repository import Gtk, Pango  # noqa: E402

from .popup import bind_hover_tooltip  # noqa: E402
from .widgets import HoverButton  # noqa: E402


class Window(HoverButton):
    def __init__(self, cfg: dict, ipc):
        super().__init__("window", vertical=False, spacing=0)
        self._cfg = cfg.get("window") or {}
        try:
            self._max_length = max(4, int(self._cfg.get("max_length", 40)))
        except (TypeError, ValueError):
            self._max_length = 40
        try:
            self._width = max(60, int(self._cfg.get("width", 220)))
        except (TypeError, ValueError):
            self._width = 220
        self._app_class = ""
        self._tip = ""

        self._label = Gtk.Label(label="")
        self._label.set_xalign(0)
        self._label.set_ellipsize(Pango.EllipsizeMode.END)
        self._label.set_max_width_chars(self._max_length)
        self._label.set_no_show_all(True)
        # Expand so the label fills the fixed box and ellipsizes within it.
        self.box.pack_start(self._label, True, True, 0)
        self.set_size_request(self._width, -1)
        bind_hover_tooltip(self, cfg, lambda: self._tip)

    def do_get_preferred_width(self):
        # A TRUE fixed width: size_request alone is only a minimum and a long
        # title would still widen the module (shifting its neighbors).
        return self._width, self._width

    def update(self, title: str | None, app_class: str | None = None) -> None:
        title = (title or "").strip()
        self._app_class = app_class or ""
        if not title:
            self._label.hide()
            self._tip = ""
            return
        if len(title) > self._max_length:
            title = title[: self._max_length].rstrip() + "…"
        self._label.set_text(title)
        self._label.show()
        self._tip = f"{self._app_class} — {title}" if self._app_class else title