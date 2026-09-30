"""GTK4 popover menus (replacement for the removed ``Gtk.Menu``).

``Gtk.Menu``/``Gtk.MenuItem`` were removed in GTK4. The bar's menus — the
right-click bar menu, the task button context menu and the SNI tray's
``com.canonical.dbusmenu`` — are all rendered here as a themed
``Gtk.Popover`` containing flat rows, with recursive submenus.

Everything is described by a small item model, so the static bar menu, the
tasklist menu and the dynamic dbusmenu share one renderer::

    [{"type": "separator"},
     {"label": "Bar settings…", "activate": fn},
     {"label": "Theme", "children": [...], "icon": widget},
     {"label": "Auto", "toggle": "radio", "active": True, "activate": fn}]

On GTK3 the caller keeps using the legacy ``Gtk.Menu`` path (see the
``compat.IS_GTK4`` branches in the consumers), so the escape hatch is intact.
"""

from __future__ import annotations

from . import compat  # noqa: E402
from .compat import Gdk, Gtk  # noqa: E402

# Row height / paddings come from CSS (``.bar-menu-item``), matching the bar's
# glass theme; only structural styles are set here.
_CHECK = "\u2713"   # ✓
_ARROW = "\u25b8"   # ▸


class MenuPopup:
    """A themed popover menu built from an item model."""

    def __init__(self, items: list, on_close=None):
        self._on_close = on_close
        self._sub: MenuPopup | None = None
        self._anchor = None

        self.pop = Gtk.Popover()
        self.pop.set_has_arrow(False)
        compat.add_class(self.pop, "bar-menu")
        self.pop.connect("closed", self._on_closed)
        compat.transparent_surface(self.pop)

        self._box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        compat.add_class(self._box, "popup-box")
        compat.add_class(self._box, "bar-menu-box")
        compat.set_single_child(self.pop, self._box)

        self._build(items)

    # ── construction ─────────────────────────────────────────────

    def _build(self, items: list) -> None:
        for item in items or []:
            if item.get("type") == "separator":
                sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
                compat.add_class(sep, "bar-menu-sep")
                compat.pack_start(self._box, sep, False, False, 0)
                continue
            compat.pack_start(self._box, self._row(item), False, False, 0)

    def _row(self, item: dict):
        children = item.get("children")
        button = Gtk.Button()
        compat.add_class(button, "bar-menu-item")
        button.set_sensitive(bool(item.get("enabled", True)))

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        compat.add_class(row, "bar-menu-row")

        # Leading check/radio marker keeps labels aligned across rows.
        toggle = item.get("toggle")
        marker = Gtk.Label(label=_CHECK if (toggle and item.get("active")) else "")
        compat.add_class(marker, "bar-menu-check")
        marker.set_size_request(16, -1)
        compat.pack_start(row, marker, False, False, 0)

        icon = item.get("icon")
        if icon is not None:
            compat.pack_start(row, icon, False, False, 0)

        label = Gtk.Label(label=item.get("label", "") or "", xalign=0)
        compat.add_class(label, "bar-menu-label")
        label.set_ellipsize(3)  # Pango.EllipsizeMode.END
        compat.pack_start(row, label, True, True, 0)

        if children:
            arrow = Gtk.Label(label=_ARROW)
            compat.add_class(arrow, "bar-menu-arrow")
            compat.pack_start(row, arrow, False, False, 0)

        compat.set_single_child(button, row)

        if children:
            button.connect("clicked", lambda _b, c=children, b=button: self._open_sub(b, c))
        else:
            button.connect("clicked", lambda _b, it=item: self._activate(it))
        return button

    # ── interaction ──────────────────────────────────────────────

    def _activate(self, item: dict) -> None:
        cb = item.get("activate")
        self.close()
        if cb is not None:
            cb()

    def _open_sub(self, anchor, items: list) -> None:
        if self._sub is not None:
            self._sub.close()
            self._sub = None
        sub = MenuPopup(items)
        sub.show_at(anchor, position=Gtk.PositionType.RIGHT)
        self._sub = sub

    def show_at(self, widget, position=None, at=None) -> None:
        """Show the menu anchored to *widget* (below by default).

        ``at`` is an optional ``(x, y)`` in *widget* coordinates: when given,
        the popover is placed against that point (so a context menu opens under
        the pointer) instead of against the widget's centre.
        """
        self._anchor = widget
        compat.popover_anchor(self.pop, widget)
        if position is not None:
            self.pop.set_position(position)
        if at is not None:
            rect = Gdk.Rectangle()
            rect.x, rect.y, rect.width, rect.height = int(at[0]), int(at[1]), 1, 1
            self.pop.set_pointing_to(rect)
        compat.show_all(self.pop)
        self.pop.popup()

    def close(self) -> None:
        self.pop.popdown()

    def _on_closed(self, *_args) -> None:
        if self._sub is not None:
            self._sub.close()
            self._sub = None
        compat.popover_release(self.pop)
        if self._on_close is not None:
            self._on_close()


def build_gtk3_menu(items: list):
    """Build a legacy ``Gtk.Menu`` from the item model (GTK3 escape hatch)."""
    menu = Gtk.Menu()
    radios: list = []
    for item in items or []:
        if item.get("type") == "separator":
            menu.append(Gtk.SeparatorMenuItem())
            continue
        children = item.get("children")
        toggle = item.get("toggle")
        if children:
            entry = Gtk.MenuItem(label=item.get("label", ""))
            entry.set_submenu(build_gtk3_menu(children))
        elif toggle == "radio":
            entry = Gtk.RadioMenuItem(label=item.get("label", ""))
            radios.append(entry)
            entry.set_active(bool(item.get("active")))
        elif toggle == "check":
            entry = Gtk.CheckMenuItem(label=item.get("label", ""))
            entry.set_active(bool(item.get("active")))
        else:
            entry = Gtk.MenuItem(label=item.get("label", ""))
        entry.set_sensitive(bool(item.get("enabled", True)))
        icon = item.get("icon")
        if icon is not None and hasattr(entry, "set_image"):
            entry.set_image(icon)
        cb = item.get("activate")
        if cb is not None:
            entry.connect("activate", lambda *_a, cb=cb: cb())
        menu.append(entry)
    for radio in radios[1:]:
        radio.join_group(radios[0])
    return menu
