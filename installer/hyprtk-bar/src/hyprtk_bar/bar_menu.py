"""Right-click bar menu.

All settings live in the bar settings window (right-click → "Bar settings…").
The context menu itself is just the entry point plus a config reload utility.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · bar_menu
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import Gdk, Gtk  # noqa: E402

from .__init__ import __version__  # noqa: E402


def build_bar_menu(cfg: dict, actions: dict) -> Gtk.Menu:
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

    win = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    win.set_title("hyprtk-bar about")
    win.set_decorated(False)
    win.set_keep_above(True)
    win.set_resizable(False)
    win.set_position(Gtk.WindowPosition.CENTER)
    win.get_style_context().add_class("settings-window")
    # Transparent toplevel so the popup-box's themed bg + animated border show.
    win.set_app_paintable(True)
    visual = win.get_screen().get_rgba_visual()
    if visual:
        win.set_visual(visual)
    if isinstance(parent, Gtk.Window):
        win.set_transient_for(parent)
    win.connect("key-press-event", lambda _w, e: win.close() if e.keyval == Gdk.KEY_Escape else False)

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
    root.get_style_context().add_class("popup-box")
    root.set_size_request(360, -1)
    win.add(root)

    brand = Gtk.Label(label="HYPRTK", xalign=0.5)
    brand.get_style_context().add_class("mc-title")
    brand.set_markup('<span size="xx-large" weight="bold">HYPRTK</span>')
    root.pack_start(brand, False, False, 0)

    name = Gtk.Label(label=f"hyprtk-bar  ·  v{__version__}", xalign=0.5)
    name.get_style_context().add_class("mc-page-title")
    root.pack_start(name, False, False, 0)

    desc = Gtk.Label(
        label="A modern, pywal-themed taskbar for the Hyprland desktop.\n"
              "Part of the Hyprtk desktop suite.",
        xalign=0.5, justify=Gtk.Justification.CENTER, wrap=True,
    )
    desc.get_style_context().add_class("settings-label")
    desc.set_opacity(0.85)
    root.pack_start(desc, False, False, 0)

    repo = Gtk.Label(label="github.com/hyprtk/hyprtk-bar", xalign=0.5)
    repo.get_style_context().add_class("settings-label")
    repo.set_opacity(0.6)
    root.pack_start(repo, False, False, 0)

    close = Gtk.Button(label="Close")
    close.get_style_context().add_class("settings-apply")
    close.connect("clicked", lambda *_a: win.close())
    root.pack_start(close, False, False, 0)

    win.show_all()