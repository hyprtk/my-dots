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

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import Gtk  # noqa: E402

# order of the sections, left to right
SECTION_ORDER = ("left", "center", "right")


class SectionBox(Gtk.EventBox):
    """One left/center/right slot: hosts module widgets + right-click menu."""

    def __init__(self, section_id: str, bar):
        super().__init__()
        self.section_id = section_id
        self._bar = bar
        self.set_visible_window(False)
        self._box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        self.add(self._box)
        self.connect("button-press-event", self._on_button_press)

    @property
    def box(self) -> Gtk.Box:
        return self._box

    def _on_button_press(self, _widget, event):
        if event.button == 3:
            self._bar.show_bar_menu(event)
            return True
        return False