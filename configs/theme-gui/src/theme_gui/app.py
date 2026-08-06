import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, Gtk

from .colors import parse_wal_colors
from .config import load as load_config, save as save_config
from .modules.icons import IconsPage
from .modules.matuwall import MatuwallPage
from .modules.pywal import PywalPage
from .modules.rofi import RofiPage
from .modules.swaylock import SwaylockPage
from .modules.wallpaper import WallpaperPage
from .modules.waybar import WaybarPage


def _build_app_css() -> str:
    """Build CSS with pywal colors for buttons and UI elements."""
    colors = parse_wal_colors()
    # fallback colors if pywal not available
    bg = colors.get("background", "#1b0b0b")
    fg = colors.get("foreground", "#c6c2c2")
    color1 = colors.get("color1", "#69443B")
    color4 = colors.get("color4", "#A6522D")
    color5 = colors.get("color5", "#A05030")
    color6 = colors.get("color6", "#A16A52")

    return f"""
    @define-color accent_color {color5};
    @define-color accent_bg_color {color5};
    @define-color accent_fg_color {fg};
    @define-color window_bg_color {bg};
    @define-color window_fg_color {fg};
    @define-color headerbar_bg_color {bg};
    @define-color headerbar_fg_color {fg};
    @define-color card_bg_color alpha({bg}, 0.6);
    @define-color card_fg_color {fg};
    @define-color dialog_bg_color {bg};
    @define-color dialog_fg_color {fg};
    @define-color popover_bg_color {bg};
    @define-color popover_fg_color {fg};
    @define-color shade_color alpha(#000000, 0.36);
    @define-color sidebar_bg_color {bg};
    @define-color sidebar_fg_color {fg};
    @define-color sidebar_shade_color alpha(#000000, 0.36);
    @define-color view_bg_color {bg};
    @define-color view_fg_color {fg};
    @define-color success_color {color6};
    @define-color success_bg_color {color6};
    @define-color success_fg_color {fg};
    @define-color warning_color {color1};
    @define-color warning_bg_color {color1};
    @define-color warning_fg_color {fg};
    @define-color error_color #e01b24;
    @define-color error_bg_color #e01b24;
    @define-color error_fg_color #ffffff;
    @define-color destructive_color #e01b24;
    @define-color destructive_bg_color #e01b24;
    @define-color destructive_fg_color #ffffff;
    @define-color suggested_color {color4};
    @define-color suggested_bg_color {color4};
    @define-color suggested_fg_color {fg};
    @define-color window_bg {bg};
    @define-color window_fg {fg};
    @define-color view_bg {bg};
    @define-color view_fg {fg};

    /* Override Adw suggested-action buttons (pywal accent) */
    button.suggested-action, button.suggested-action:hover {{
        background: {color5};
        color: {fg};
        border-color: {color5};
    }}
    button.suggested-action:disabled {{
        background: alpha({color5}, 0.5);
    }}

    /* Override Adw flat buttons */
    button.flat {{
        color: {fg};
    }}
    button.flat:hover {{
        background: alpha({fg}, 0.08);
    }}

    /* Sidebar rows */
    .sidebar-row {{
        border-radius: 8px;
        margin: 2px 0;
        padding: 4px 8px;
    }}
    .sidebar-row:hover {{
        background: alpha({fg}, 0.08);
    }}

    /* Entry fields */
    entry {{
        background: alpha({fg}, 0.08);
        color: {fg};
        border-color: alpha({fg}, 0.15);
    }}
    entry:focus {{
        border-color: {color5};
    }}

    /* Switches */
    switch:checked {{
        background: {color5};
    }}
    """


class ThemeGuiApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="dev.hyprtk.theme_gui")
        self.connect("activate", self._on_activate)
        self.connect("startup", self._on_startup)
        self._cfg = load_config()
        self._pages: dict[str, Adw.NavigationPage] = {}

    def _on_startup(self, app):
        # detect system color scheme
        sm = Adw.StyleManager.get_default()
        if sm.get_dark():
            sm.set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        else:
            sm.set_color_scheme(Adw.ColorScheme.FORCE_LIGHT)

        # load pywal colors and apply
        provider = Gtk.CssProvider()
        provider.load_from_data(_build_app_css().encode())
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1,
        )

    def _on_activate(self, app):
        win = ThemeGuiWindow(application=app)
        win.set_config(self._cfg)
        win.present()


class ThemeGuiWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._cfg = {}
        self._pages: dict[str, Adw.NavigationPage] = {}

        self.set_title("Theme Manager")
        self.set_default_size(1100, 700)

        # ── navigation split view ─────────────────────────────
        nav = Adw.NavigationSplitView()
        nav.set_sidebar_width_fraction(0.3)

        # ── sidebar ───────────────────────────────────────────
        sidebar_page = Adw.NavigationPage(title="Themes", tag="sidebar")

        sidebar_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        sidebar_header = Adw.HeaderBar()
        sidebar_box.append(sidebar_header)

        # sidebar list
        sidebar_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        sidebar_list.set_margin_top(8)

        items = [
            ("wallpaper", "Wallpaper", "image-x-generic-symbolic"),
            ("pywal", "Pywal Colors", "colors-symbolic"),
            ("rofi", "Rofi Themes", "view-app-grid-symbolic"),
            ("waybar", "Waybar Themes", "view-dual-symbolic"),
            ("matuwall", "Matuwall", "folder-pictures-symbolic"),
            ("swaylock", "Swaylock", "system-lock-screen-symbolic"),
            ("icons", "Icons", "folder-symbolic"),
        ]

        self._nav = nav
        self._stack = Gtk.Stack()
        self._stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self._stack.set_transition_duration(200)

        first_btn = None
        for tag, title, icon in items:
            page = self._create_page(tag)
            self._stack.add_named(page, tag)

            btn = Gtk.Button()
            btn.add_css_class("flat")
            btn.add_css_class("sidebar-item")
            btn.set_halign(Gtk.Align.FILL)
            btn.set_child(self._make_sidebar_row(title, icon))
            btn._page_tag = tag
            btn.connect("clicked", self._on_sidebar_click)
            sidebar_list.append(btn)

            if first_btn is None:
                first_btn = btn

        sidebar_scroll = Gtk.ScrolledWindow()
        sidebar_scroll.set_child(sidebar_list)
        sidebar_scroll.set_vexpand(True)
        sidebar_box.append(sidebar_scroll)

        sidebar_page.set_child(sidebar_box)

        # ── content ───────────────────────────────────────────
        content_page = Adw.NavigationPage(title="Theme Manager", tag="content")
        content_page.set_child(self._stack)

        nav.set_sidebar(sidebar_page)
        nav.set_content(content_page)

        self.set_content(nav)

    def set_config(self, cfg: dict):
        self._cfg = cfg
        self.set_default_size(
            cfg.get("window_width", 1100),
            cfg.get("window_height", 700),
        )
        last_page = cfg.get("last_page", "wallpaper")
        self._select_page(last_page)

    def _make_sidebar_row(self, title: str, icon_name: str) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(12)
        box.set_margin_end(12)

        img = Gtk.Image.new_from_icon_name(icon_name)
        img.set_pixel_size(20)
        box.append(img)

        label = Gtk.Label(label=title)
        label.set_xalign(0)
        box.append(label)

        return box

    def _create_page(self, tag: str) -> Adw.NavigationPage:
        pages = {
            "wallpaper": WallpaperPage,
            "pywal": PywalPage,
            "rofi": RofiPage,
            "waybar": WaybarPage,
            "matuwall": MatuwallPage,
            "swaylock": SwaylockPage,
            "icons": IconsPage,
        }
        cls = pages.get(tag)
        if cls:
            page = cls()
            self._pages[tag] = page
            return page
        return Adw.NavigationPage(title=tag, tag=tag)

    def _on_sidebar_click(self, btn):
        tag = btn._page_tag
        self._select_page(tag)

    def _select_page(self, tag: str):
        self._stack.set_visible_child_name(tag)
        cfg = load_config()
        cfg["last_page"] = tag
        save_config(cfg)

    def do_close_request(self):
        cfg = load_config()
        w, h = self.get_default_size()
        cfg["window_width"] = w
        cfg["window_height"] = h
        save_config(cfg)
        return False
