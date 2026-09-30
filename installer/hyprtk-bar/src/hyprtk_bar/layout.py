"""Section boxes for the bar layout.

Modules are positioned via the settings window (left/center/right + order), so
no drag & drop is needed. Each section is an ``SectionBox``: it hosts its module
widgets and — because empty bar space belongs to a section — right-clicking it
opens the bar menu (entry point to the settings window).
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · layout
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

from . import compat  # noqa: E402
from .compat import Gtk  # noqa: E402

# order of the sections, left to right
SECTION_ORDER = ("left", "center", "right")


class SectionBox(compat.EventSurface):
    """One left/center/right slot: hosts module widgets + right-click menu."""

    def __init__(self, section_id: str, bar):
        if compat.IS_GTK4:
            super().__init__(orientation=Gtk.Orientation.HORIZONTAL)
        else:
            super().__init__()
            self.set_visible_window(False)
        self.section_id = section_id
        self._bar = bar
        self._box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        compat.set_single_child(self, self._box)
        compat.on_press(self, self._on_button_press)

    @property
    def box(self) -> Gtk.Box:
        return self._box

    def _on_button_press(self, _widget, event):
        if event.button == 3:
            self._bar.show_bar_menu(self, at=(event.x, event.y))
            return True
        return False