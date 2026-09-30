"""Right-click bar menu.

All settings live in the bar settings window (right-click → "Bar settings…").
The context menu itself is just the entry point plus a config reload utility.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · bar_menu
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

from . import compat  # noqa: E402
from .compat import Gdk, Gtk  # noqa: E402

from .__init__ import __version__  # noqa: E402


def menu_items(cfg: dict, actions: dict) -> list:
    """The bar context menu as a ``menus.MenuPopup`` item model."""
    return [
        {"label": "Bar settings…", "activate": actions["open_settings"]},
        {"label": "Reload config", "activate": actions["reload_config"]},
        {"label": "About hyprtk-bar", "activate": actions["open_about"]},
    ]


def show_bar_menu(anchor, cfg: dict, actions: dict, at=None):
    """Show the bar context menu anchored to *anchor* (GTK4 popover).

    ``at`` (optional ``(x, y)`` in *anchor* coordinates) places the menu under
    the click point rather than the anchor's centre.
    """
    from .menus import MenuPopup

    popup = MenuPopup(menu_items(cfg, actions))
    popup.show_at(anchor, at=at)
    return popup


def build_bar_menu(cfg: dict, actions: dict) -> Gtk.Menu:
    """Legacy GTK3 ``Gtk.Menu`` build (escape hatch)."""
    menu = Gtk.Menu()

    settings = Gtk.MenuItem(label="Bar settings…")
    settings.connect("activate", lambda *_a: actions["open_settings"]())
    menu.append(settings)

    reload = Gtk.MenuItem(label="Reload config")
    reload.connect("activate", lambda *_a: actions["reload_config"]())
    menu.append(reload)

    about = Gtk.MenuItem(label="About hyprtk-bar")
    about.connect("activate", lambda *_a: actions["open_about"]())
    menu.append(about)

    return menu


def show_about(parent: Gtk.Widget | None = None) -> None:
    """Open the branded About window (frameless, themed like the settings).

    The bar's global CSS provider is already active, so the window inherits
    the pywal/imported theme (popup-box glass + animated border) without
    needing to rebuild CSS here.
    """
    from .config import load

    load()  # ensure config validation runs (harmless; theme provider is global)

    win = compat.new_window()
    win.set_title("hyprtk-bar about")
    win.set_decorated(False)
    compat.set_keep_above(win, True)
    win.set_resizable(False)
    compat.set_window_position(win)
    compat.add_class(win, "settings-window")
    compat.transparent_surface(win)
    # Transparent toplevel so the popup-box's themed bg + animated border show.
    compat.set_app_paintable(win, True)
    compat.apply_rgba_visual(win)
    if isinstance(parent, Gtk.Window):
        win.set_transient_for(parent)
    compat.on_key(win, lambda _w, e: win.close() if e.keyval == Gdk.KEY_Escape else False)

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
    compat.add_class(root, "popup-box")
    root.set_size_request(360, -1)
    compat.add(win, root)

    brand = Gtk.Label(label="HYPRTK", xalign=0.5)
    compat.add_class(brand, "mc-title")
    brand.set_markup('<span size="xx-large" weight="bold">HYPRTK</span>')
    compat.pack_start(root, brand, False, False, 0)

    name = Gtk.Label(label=f"hyprtk-bar  ·  v{__version__}", xalign=0.5)
    compat.add_class(name, "mc-page-title")
    compat.pack_start(root, name, False, False, 0)

    def _ver(ns) -> str:
        try:
            return "%d.%d.%d" % (
                ns.get_major_version(), ns.get_minor_version(), ns.get_micro_version()
            )
        except Exception:
            return "unknown"

    import platform

    versions = (
        f"GTK {_ver(Gtk)}  ·  layer-shell {_ver(compat.GtkLayerShell)}"
        f"  ·  Python {platform.python_version()}"
    )
    ver = Gtk.Label(label=versions, xalign=0.5)
    compat.add_class(ver, "settings-label")
    ver.set_opacity(0.6)
    compat.pack_start(root, ver, False, False, 0)

    desc = Gtk.Label(
        label="A modern, pywal-themed taskbar for the Hyprland desktop.\n"
              "Part of the Hyprtk desktop suite.",
        xalign=0.5, justify=Gtk.Justification.CENTER, wrap=True,
    )
    compat.add_class(desc, "settings-label")
    desc.set_opacity(0.85)
    compat.pack_start(root, desc, False, False, 0)

    repo = Gtk.Label(label="github.com/hyprtk/hyprtk-bar", xalign=0.5)
    compat.add_class(repo, "settings-label")
    repo.set_opacity(0.6)
    compat.pack_start(root, repo, False, False, 0)

    close = Gtk.Button(label="Close")
    compat.add_class(close, "settings-apply")
    close.connect("clicked", lambda *_a: win.close())
    compat.pack_start(root, close, False, False, 0)

    compat.show_all(win)