"""Bar settings window: bar width/height/align and per-module layout control.

A frameless floating window (dragged by its header; Hyprland floats+centers it
via a windowrule on the title "hyprtk-bar settings"). Edits the bar's
``layout`` — each module can be shown/hidden, assigned to the left/center/right
section, and reordered within its section — plus bar width, height, alignment
and theme. Apply writes the config and rebuilds/re-themes the bar live.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · bar_settings
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")

from gi.repository import Gdk, Gtk, Pango  # noqa: E402

from .config import DEFAULT_LAYOUT, DEFAULT_LINKS, MENU_LAYOUTS, MODULE_IDS, MODULE_LABELS  # noqa: E402
from .sysapps import (  # noqa: E402
    default_browser_command,
    default_filemanager_command,
    default_terminal_command,
)
from .theme_import import import_theme, list_themes  # noqa: E402
from .widgets import Glyph, HoverButton  # noqa: E402

SECTION_ORDER = ("left", "center", "right")
SECTION_LABELS = {"left": "Left", "center": "Center", "right": "Right"}
THEME_SOURCES = (
    ("pywal", "Pywal (dynamic)"),
    ("imported", "Imported theme"),
    ("manual", "Manual (config)"),
)


def _hex_to_rgba(hex_color: str) -> Gdk.RGBA:
    rgba = Gdk.RGBA()
    if not rgba.parse(hex_color or "#000000"):
        rgba.parse("#000000")
    return rgba


def _rgba_to_hex(rgba: Gdk.RGBA) -> str:
    return "#{:02X}{:02X}{:02X}".format(
        int(rgba.red * 255), int(rgba.green * 255), int(rgba.blue * 255)
    )


def _rgba_to_css(rgba: Gdk.RGBA) -> str:
    """``#RRGGBB`` when opaque, else ``rgba(r, g, b, a)`` (keeps the alpha)."""
    r, g, b = int(rgba.red * 255), int(rgba.green * 255), int(rgba.blue * 255)
    if rgba.alpha >= 0.999:
        return "#{:02X}{:02X}{:02X}".format(r, g, b)
    return "rgba({}, {}, {}, {:.2f})".format(r, g, b, rgba.alpha)


_APP_DIRS = [
    Path.home() / ".local/share/applications",
    Path("/usr/local/share/applications"),
    Path("/usr/share/applications"),
    Path("/var/lib/flatpak/exports/share/applications"),
]


def _parse_desktop(path: Path) -> dict | None:
    name = exec_ = icon = comment = None
    in_section = False
    for line in path.read_text(errors="ignore").splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("["):
            in_section = line == "[Desktop Entry]"
            continue
        if not in_section or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if key == "Name":
            name = value
        elif key == "Exec":
            exec_ = value
        elif key == "Icon":
            icon = value
        elif key == "Comment":
            comment = value
        elif key in ("NoDisplay", "Hidden") and value.lower() in ("true", "1"):
            return None
    if not name or not exec_:
        return None
    clean = " ".join(tok for tok in exec_.split() if not tok.startswith("%"))
    return {
        "name": name,
        "exec": clean,
        "icon": icon or "application-x-executable",
        "comment": comment or name,
    }


def _load_installed_apps() -> list[dict]:
    apps: dict[str, dict] = {}
    for directory in _APP_DIRS:
        if not directory.is_dir():
            continue
        for f in sorted(directory.glob("*.desktop")):
            app = _parse_desktop(f)
            if app and app["exec"] not in apps:
                apps[app["exec"]] = app
    return sorted(apps.values(), key=lambda a: a["name"].lower())


def _radio_group(labels: list[tuple[str, str]]) -> dict[str, Gtk.RadioButton]:
    """Build a Gtk.RadioButton group from ``(key, label)`` pairs.

    Gtk.RadioButton.new_with_label(group, ...) crashes in this build and the
    ``group=`` kwarg rejects a sequence, so buttons are created standalone
    (``group=None``) and joined with ``join_group``.
    """
    buttons: dict[str, Gtk.RadioButton] = {}
    first: Gtk.RadioButton | None = None
    for key, label in labels:
        btn = Gtk.RadioButton(group=None, label=label)
        if first is not None:
            btn.join_group(first)
        else:
            first = btn
        buttons[key] = btn
    return buttons


def _theme_dialog(win: Gtk.Window) -> None:
    """Theme a plain ``Gtk.Window`` with the bar's pywal/imported palette.

    The dialogs use a frameless+transparent ``Gtk.Window`` (like the About
    window) with a ``popup-box`` root — not ``Gtk.Dialog``, whose internal
    ``dialog-vbox`` picks up GTK-theme chrome that draws a second frame. Each
    dialog adds ``popup-box`` to its own root box.
    """
    win.get_style_context().add_class("settings-window")
    win.set_decorated(False)
    win.set_keep_above(True)
    win.set_app_paintable(True)
    visual = win.get_screen().get_rgba_visual()
    if visual:
        win.set_visual(visual)


class BarSettings(Gtk.Window):
    def __init__(self, cfg: dict, actions: dict, initial_page: str | None = None):
        super().__init__(title="hyprtk-bar settings")
        self._cfg = cfg
        self._actions = actions
        self._initial_page = initial_page or "bar"
        self._hidden: set[str] = set()
        self._rows: dict[str, dict] = {}
        self._theme_buttons: dict[str, Gtk.CheckButton] = {}
        self._themes: list[str] = []
        self._layout = cfg.get("layout") or {}

        visible = {
            mid
            for section in SECTION_ORDER
            for mid in (self._layout.get(section) or [])
        }
        self._order: dict[str, list[str]] = {
            s: list(self._layout.get(s, []) or []) for s in SECTION_ORDER
        }
        for mid in MODULE_IDS:
            if mid not in visible:
                self._hidden.add(mid)
                for s in SECTION_ORDER:
                    if mid in DEFAULT_LAYOUT[s]:
                        self._order[s].append(mid)
                        break

        self.set_decorated(False)
        self.set_keep_above(True)
        self.set_default_size(620, 580)
        self.set_position(Gtk.WindowPosition.CENTER)
        # Strip any GTK window frame/outline so the only border is the
        # popup-box's 2px animated one (the popup-box now fills the window).
        self.get_style_context().add_class("settings-window")
        # Transparent toplevel so the theme's opacity (via .popup-box alpha)
        # shows through to the desktop, like the bar's popups.
        self.set_app_paintable(True)
        visual = self.get_screen().get_rgba_visual()
        if visual:
            self.set_visual(visual)
        self.connect("key-press-event", self._on_key)
        self._build()
        self.show_all()
        # _build already called _set_active_page, but a Gtk.Stack with a
        # crossfade transition drops a visible-child change made before the
        # window is realized and falls back to its first page. Re-apply after
        # show_all so opening settings on the Menu/Arc Menu page actually shows
        # that page (not Bar).
        if self._initial_page in self._page_buttons:
            self._set_active_page(self._initial_page)

    # ── ui ───────────────────────────────────────────────────────

    def _style_header(self, header: Gtk.EventBox) -> None:
        """Scope a little CSS so the drag header reads as a title bar."""
        provider = Gtk.CssProvider()
        provider.load_from_data(
            b"""
.settings-title { font-weight: bold; font-size: 14px; }
.settings-header { background-color: transparent;
                   border-bottom: 1px solid alpha(currentColor, 0.12);
                   border-radius: 8px 8px 0 0;
                   padding: 8px 10px; }
"""
        )
        style = header.get_style_context()
        style.add_class("settings-header")
        style.add_provider(provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def _on_header_press(self, _widget, event) -> bool:
        """Drag the frameless window by its header."""
        if event.button == 1 and event.type == Gdk.EventType.BUTTON_PRESS:
            self.begin_move_drag(
                event.button, int(event.x_root), int(event.y_root), event.time
            )
            return True
        return False

    def _on_key(self, _window, event) -> bool:
        if event.keyval == Gdk.KEY_Escape:
            self.close()
            return True
        return False

    def _build(self) -> None:
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        root.get_style_context().add_class("popup-box")
        self.add(root)

        # Draggable header (frameless window) — matches the monitor's header.
        header = Gtk.EventBox()
        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        title = Gtk.Label(label="Bar Settings", xalign=0)
        title.get_style_context().add_class("mc-title")
        header_box.pack_start(title, True, True, 0)
        close = Gtk.Button(label="\u00d7")
        close.get_style_context().add_class("mc-close")
        close.set_relief(Gtk.ReliefStyle.NONE)
        close.connect("clicked", lambda *_a: self.close())
        header_box.pack_start(close, False, False, 0)
        header.add(header_box)
        header.connect("button-press-event", self._on_header_press)
        self._style_header(header)
        root.pack_start(header, False, False, 0)

        # Body: sidebar navigation + stack (same pattern as the system monitor).
        body = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        sidebar.get_style_context().add_class("mc-sidebar")
        sidebar.set_size_request(132, -1)
        self._sidebar = sidebar

        self._stack = Gtk.Stack()
        self._stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self._stack.set_transition_duration(120)

        self._page_buttons: dict[str, HoverButton] = {}
        for key, glyph, label in (
            ("bar", "\uf2db", "Bar"),
            ("fonts", "\uf031", "Fonts"),
            ("themes", "\uf1fc", "Themes"),
            ("animations", "\uf1fe", "Animations"),
            ("arcmenu", "\uf0e7", "Arc Menu"),
            ("menu", "\uf0ca", "Menu"),
            ("quicklinks", "\uf0c1", "Quicklinks"),
            ("modules", "\uf009", "Modules"),
        ):
            sidebar.pack_start(self._build_page_button(key, glyph, label),
                               False, False, 0)
            page = self._build_page(key)
            self._stack.add_named(page, key)
            self._page_buttons[key].page = page

        body.pack_start(sidebar, False, False, 0)
        body.pack_start(self._stack, True, True, 0)
        root.pack_start(body, True, True, 0)

        # Populate the imported-theme list (the Themes page needs the buttons to
        # exist before the user can select one).
        self._refresh_themes(select=(self._cfg.get("theme") or {}).get("theme_name") or None)
        self._update_source_state()

        # Footer buttons — accent "Apply" like the monitor's accent chrome.
        buttons = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        buttons.set_halign(Gtk.Align.END)
        reset_btn = Gtk.Button(label="Reset layout")
        reset_btn.connect("clicked", self._on_reset)
        close_btn = Gtk.Button(label="Close")
        close_btn.connect("clicked", lambda *_a: self.close())
        apply_btn = Gtk.Button(label="Apply")
        apply_btn.get_style_context().add_class("settings-apply")
        apply_btn.connect("clicked", self._on_apply)
        buttons.pack_start(reset_btn, False, False, 0)
        buttons.pack_start(close_btn, False, False, 0)
        buttons.pack_start(apply_btn, False, False, 0)
        root.pack_start(buttons, False, False, 0)

        # Apply the theme's fg/bg colours to standard widgets so the dialogue
        # stays readable on light imported themes.
        self._apply_theme_fg_class(root)
        self._set_active_page(self._initial_page if self._initial_page in self._page_buttons else "bar")

    def _build_page_button(self, key: str, glyph: str, label: str) -> HoverButton:
        btn = HoverButton("mc-sidebar-button", vertical=False, spacing=8)
        btn.set_size_request(-1, 30)
        icon = Glyph(glyph, "mc-icon")
        icon.set_pixel_size(14)
        btn.box.pack_start(icon, False, False, 0)
        lbl = Gtk.Label(label=label, xalign=0)
        lbl.get_style_context().add_class("mc-sidebar-label")
        btn.box.pack_start(lbl, True, True, 0)
        btn.connect("button-press-event",
                    lambda _w, _e, k=key: self._set_active_page(k) or False)
        self._page_buttons[key] = btn
        return btn

    def _set_active_page(self, key: str) -> None:
        self._active_page = key
        for k, btn in self._page_buttons.items():
            box = btn.box
            if k == key:
                box.get_style_context().add_class("active")
            else:
                box.get_style_context().remove_class("active")
        self._stack.set_visible_child_name(key)

    def _build_page(self, key: str) -> Gtk.Box:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        page.set_hexpand(True)
        title = Gtk.Label(label=self._page_title(key), xalign=0)
        title.get_style_context().add_class("mc-page-title")
        page.pack_start(title, False, False, 0)
        if key == "bar":
            self._build_bar_tab(page)
        elif key == "fonts":
            self._build_font_tab(page)
        elif key == "themes":
            self._build_themes_tab(page)
        elif key == "animations":
            self._build_animations_tab(page)
        elif key == "arcmenu":
            self._build_arcmenu_tab(page)
        elif key == "menu":
            self._build_menu_tab(page)
        elif key == "quicklinks":
            self._build_quicklinks_tab(page)
        elif key == "modules":
            self._build_modules_tab(page)
        return page

    @staticmethod
    def _page_title(key: str) -> str:
        return {
            "bar": "Bar", "fonts": "Fonts", "themes": "Themes",
            "animations": "Animations", "arcmenu": "Arc Menu", "menu": "Menu",
            "quicklinks": "Quicklinks", "modules": "Modules",
        }[key]

    def _tab_margins(self) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_margin_top(8)
        box.set_margin_bottom(4)
        box.set_margin_start(4)
        box.set_margin_end(4)
        return box

    def _apply_theme_fg_class(self, widget) -> None:
        """Apply the theme to the dialogue's widgets.

        Mirrors the system monitor's approach: chrome widgets (buttons, labels,
        check/radio) get semantic CSS classes from ``build_css`` with
        transparent / translucent backgrounds and theme colours — no opaque
        blocks. GTK's default theme hard-colours spinbuttons and entries, so
        those alone use the ``override_*`` API for text + a translucent fill.
        """
        from .theme import resolve_palette
        import re

        palette = resolve_palette(self._cfg)
        fg = palette.get("foreground", "#14141e")

        def _hex(color: str) -> str:
            m = re.search(r"rgba?\((\d+),\s*(\d+),\s*(\d+)", color)
            if m:
                return "#%02x%02x%02x" % (
                    int(m.group(1)), int(m.group(2)), int(m.group(3))
                )
            return color

        def _rgba(hex_color: str):
            h = hex_color.lstrip("#")
            if len(h) == 3:
                h = "".join(c * 2 for c in h)
            r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
            return Gdk.RGBA(r / 255, g / 255, b / 255, 1.0)

        fg_rgba = _rgba(_hex(fg))

        states = (
            Gtk.StateFlags.NORMAL,
            Gtk.StateFlags.ACTIVE,
            Gtk.StateFlags.SELECTED,
            Gtk.StateFlags.INSENSITIVE,
            Gtk.StateFlags.FOCUSED,
            Gtk.StateFlags.BACKDROP,
            Gtk.StateFlags.SELECTED | Gtk.StateFlags.FOCUSED,
        )

        def _apply(w):
            ctx = w.get_style_context()
            # Arc Menu widgets — notebook tab strip, colour buttons and lists get
            # theme classes so they follow the palette like the rest of the
            # dialogue (ColorButton must precede Button — it subclasses it).
            if isinstance(w, Gtk.Notebook):
                ctx.add_class("settings-notebook")
            elif isinstance(w, Gtk.ColorButton):
                ctx.add_class("settings-color")
            elif isinstance(w, Gtk.ListBox):
                ctx.add_class("settings-list")
            elif isinstance(w, Gtk.Button):
                if w.get_relief() != Gtk.ReliefStyle.NONE:
                    w.set_relief(Gtk.ReliefStyle.NONE)
                # The accent Apply button keeps its .settings-apply styling.
                if not w.get_style_context().has_class("settings-apply"):
                    ctx.add_class("settings-btn")
            elif isinstance(w, Gtk.Label):
                ctx.add_class("settings-label")
            elif isinstance(w, Gtk.CheckButton):
                ctx.add_class("settings-check")
            elif isinstance(w, Gtk.RadioButton):
                ctx.add_class("settings-radio")
            elif isinstance(w, Gtk.Switch):
                ctx.add_class("settings-switch")
            elif isinstance(w, (Gtk.SpinButton, Gtk.Entry, Gtk.FontButton)):
                # GTK hard-colours these; override only the TEXT so the themed
                # `.settings-input` CSS class (translucent fill + accent border)
                # supplies the background. Overriding the background on every
                # state would paint an opaque block over the translucent fill.
                ctx.add_class("settings-input")
                for state in states:
                    try:
                        w.override_color(state, fg_rgba)
                    except Exception:
                        pass
            if isinstance(w, Gtk.Container):
                for child in w.get_children():
                    _apply(child)

        _apply(widget)

    def _theme_fg(self) -> str:
        """The resolved theme foreground (for tinting symbolic icons)."""
        from .theme import resolve_palette

        return resolve_palette(self._cfg).get("foreground", "#14141e")

    def _build_bar_tab(self, page: Gtk.Box) -> None:
        tab = page

        height_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        height_label = Gtk.Label(label="Height:", xalign=1)
        height_label.set_size_request(70, -1)
        self._height = Gtk.SpinButton.new_with_range(20, 120, 2)
        self._height.set_value(int(self._cfg.get("height", 42)))
        self._height.set_hexpand(True)
        height_row.pack_start(height_label, False, False, 0)
        height_row.pack_start(self._height, True, True, 0)

        # Width is a percentage only.
        width_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        width_label = Gtk.Label(label="Width:", xalign=1)
        width_label.set_size_request(70, -1)
        self._width = Gtk.SpinButton.new_with_range(10, 100, 5)
        self._width.set_value(self._width_percent())
        self._width.set_hexpand(True)
        width_hint = Gtk.Label(label="% of the monitor", xalign=0)
        width_hint.set_opacity(0.7)
        width_row.pack_start(width_label, False, False, 0)
        width_row.pack_start(self._width, True, True, 0)
        width_row.pack_start(width_hint, False, False, 0)

        align_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        align_label = Gtk.Label(label="Align:", xalign=1)
        align_label.set_size_request(70, -1)
        self._align_buttons = _radio_group(
            [(s, SECTION_LABELS[s]) for s in SECTION_ORDER]
        )
        align_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        for btn in self._align_buttons.values():
            align_box.pack_start(btn, False, False, 0)
        self._align_buttons[self._cfg.get("align", "center")].set_active(True)
        align_box.set_hexpand(True)
        align_row.pack_start(align_label, False, False, 0)
        align_row.pack_start(align_box, True, True, 0)

        position_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        position_label = Gtk.Label(label="Position:", xalign=1)
        position_label.set_size_request(70, -1)
        self._position_buttons = _radio_group(
            [("bottom", "Bottom"), ("top", "Top")]
        )
        position_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        for btn in self._position_buttons.values():
            position_box.pack_start(btn, False, False, 0)
        self._position_buttons[self._cfg.get("position", "bottom")].set_active(True)
        position_box.set_hexpand(True)
        position_row.pack_start(position_label, False, False, 0)
        position_row.pack_start(position_box, True, True, 0)

        gap_in_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        gap_in_label = Gtk.Label(label="Gap in:", xalign=1)
        gap_in_label.set_size_request(70, -1)
        self._gap_in = Gtk.SpinButton.new_with_range(0, 60, 2)
        self._gap_in.set_value(int(self._cfg.get("gap_in", 6)))
        self._gap_in.set_hexpand(True)
        gap_in_hint = Gtk.Label(label="px — bar to windows", xalign=0)
        gap_in_hint.set_opacity(0.7)
        gap_in_row.pack_start(gap_in_label, False, False, 0)
        gap_in_row.pack_start(self._gap_in, True, True, 0)
        gap_in_row.pack_start(gap_in_hint, False, False, 0)

        gap_out_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        gap_out_label = Gtk.Label(label="Gap out:", xalign=1)
        gap_out_label.set_size_request(70, -1)
        self._gap_out = Gtk.SpinButton.new_with_range(0, 60, 2)
        self._gap_out.set_value(int(self._cfg.get("gap_out", 6)))
        self._gap_out.set_hexpand(True)
        gap_out_hint = Gtk.Label(label="px — bar to screen edge", xalign=0)
        gap_out_hint.set_opacity(0.7)
        gap_out_row.pack_start(gap_out_label, False, False, 0)
        gap_out_row.pack_start(self._gap_out, True, True, 0)
        gap_out_row.pack_start(gap_out_hint, False, False, 0)

        opacity_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        opacity_label = Gtk.Label(label="Opacity:", xalign=1)
        opacity_label.set_size_request(70, -1)
        self._opacity = Gtk.SpinButton.new_with_range(10, 100, 5)
        self._opacity.set_value(int(round(self._cfg.get("opacity", 0.95) * 100)))
        self._opacity.set_hexpand(True)
        opacity_hint = Gtk.Label(label="%", xalign=0)
        opacity_hint.set_opacity(0.7)
        opacity_row.pack_start(opacity_label, False, False, 0)
        opacity_row.pack_start(self._opacity, True, True, 0)
        opacity_row.pack_start(opacity_hint, False, False, 0)

        tab.pack_start(height_row, False, False, 0)
        tab.pack_start(width_row, False, False, 0)
        tab.pack_start(align_row, False, False, 0)
        tab.pack_start(position_row, False, False, 0)
        tab.pack_start(gap_in_row, False, False, 0)
        tab.pack_start(gap_out_row, False, False, 0)
        tab.pack_start(opacity_row, False, False, 0)

    def _build_font_tab(self, page: Gtk.Box) -> None:
        tab = page
        font_cfg = self._cfg.get("font") or {}
        self._font_family = str(font_cfg.get("family", "") or "")
        font_size = int(font_cfg.get("size", 16))
        icon_size = int(font_cfg.get("icon_size", 0))
        self._font_ready = False  # ignore the FontButton's init-time font-set

        family_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        family_label = Gtk.Label(label="Family:", xalign=1)
        family_label.set_size_request(70, -1)
        self._font_button = Gtk.FontButton()
        self._font_button.set_use_font(True)
        base = self._font_family if self._font_family else "Sans"
        self._font_button.set_font_name(f"{base} {font_size}")
        self._font_button.connect("font-set", self._on_font_set)
        self._font_button.set_hexpand(True)
        family_hint = Gtk.Label(label="blank = system font", xalign=0)
        family_hint.set_opacity(0.7)
        family_row.pack_start(family_label, False, False, 0)
        family_row.pack_start(self._font_button, True, True, 0)
        family_row.pack_start(family_hint, False, False, 0)

        size_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        size_label = Gtk.Label(label="Size:", xalign=1)
        size_label.set_size_request(70, -1)
        self._font_size = Gtk.SpinButton.new_with_range(8, 40, 1)
        self._font_size.set_value(font_size)
        self._font_size.connect("value-changed", self._on_size_changed)
        size_hint = Gtk.Label(label="px", xalign=0)
        size_hint.set_opacity(0.7)
        size_row.pack_start(size_label, False, False, 0)
        size_row.pack_start(self._font_size, True, True, 0)
        size_row.pack_start(size_hint, False, False, 0)

        icon_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        icon_label = Gtk.Label(label="Icon size:", xalign=1)
        icon_label.set_size_request(70, -1)
        self._icon_size = Gtk.SpinButton.new_with_range(0, 48, 1)
        self._icon_size.set_value(icon_size)
        icon_hint = Gtk.Label(label="px (0 = auto; module icons + start)", xalign=0)
        icon_hint.set_opacity(0.7)
        icon_row.pack_start(icon_label, False, False, 0)
        icon_row.pack_start(self._icon_size, True, True, 0)
        icon_row.pack_start(icon_hint, False, False, 0)

        ql_icon_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        ql_icon_label = Gtk.Label(label="Quicklink icons:", xalign=1)
        ql_icon_label.set_size_request(70, -1)
        self._ql_icon_size = Gtk.SpinButton.new_with_range(0, 48, 1)
        self._ql_icon_size.set_value(int((self._cfg.get("quicklinks") or {}).get("icon_size", 0) or 0))
        ql_icon_hint = Gtk.Label(label="px (0 = follow icon size)", xalign=0)
        ql_icon_hint.set_opacity(0.7)
        ql_icon_row.pack_start(ql_icon_label, False, False, 0)
        ql_icon_row.pack_start(self._ql_icon_size, True, True, 0)
        ql_icon_row.pack_start(ql_icon_hint, False, False, 0)

        tab.pack_start(family_row, False, False, 0)
        tab.pack_start(size_row, False, False, 0)
        tab.pack_start(icon_row, False, False, 0)
        tab.pack_start(ql_icon_row, False, False, 0)
        self._font_ready = True

    def _on_font_set(self, *_args) -> None:
        """Sync the picked font's family + size into the settings state."""
        if not getattr(self, "_font_ready", False):
            return
        try:
            fd = Pango.FontDescription.from_string(self._font_button.get_font())
        except Exception:
            return
        family = fd.get_family()
        size = fd.get_size()
        if family:
            self._font_family = family
        if size and size > 0:
            self._font_size.set_value(round(size / Pango.SCALE))

    def _on_size_changed(self, *_args) -> None:
        """Keep the font picker's preview in step with the size spin."""
        try:
            fd = Pango.FontDescription.from_string(self._font_button.get_font())
            family = fd.get_family() or "Sans"
        except Exception:
            return
        self._font_button.set_font_name(f"{family} {int(self._font_size.get_value())}")

    def _active_font_family(self) -> str:
        return self._font_family

    def _build_themes_tab(self, page: Gtk.Box) -> None:
        tab = page
        theme = self._cfg.get("theme") or {}

        source_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        source_label = Gtk.Label(label="Source:", xalign=1)
        source_label.set_size_request(70, -1)
        self._source_buttons = _radio_group(list(THEME_SOURCES))
        source_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        for btn in self._source_buttons.values():
            btn.connect("toggled", self._on_source_toggled)
            source_box.pack_start(btn, False, False, 0)
        source_key = theme.get("source", "pywal")
        self._source_buttons[source_key if source_key in self._source_buttons else "pywal"].set_active(True)
        source_box.set_hexpand(True)
        source_row.pack_start(source_label, False, False, 0)
        source_row.pack_start(source_box, True, True, 0)

        theme_row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        theme_label = Gtk.Label(label="Imported theme:", xalign=0)
        theme_label.set_size_request(-1, -1)
        self._themes_box = Gtk.FlowBox()
        self._themes_box.set_selection_mode(Gtk.SelectionMode.NONE)
        self._themes_box.set_column_spacing(8)
        self._themes_box.set_row_spacing(2)
        self._themes_box.set_max_children_per_line(3)
        self._themes_box.set_min_children_per_line(3)
        self._themes_box.set_homogeneous(True)
        themes_scroller = Gtk.ScrolledWindow()
        themes_scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        themes_scroller.set_min_content_height(120)
        themes_scroller.set_max_content_height(180)
        themes_scroller.add(self._themes_box)
        import_btn = Gtk.Button(label="Import theme…")
        import_btn.set_size_request(120, 26)
        import_btn.connect("clicked", self._on_import)
        theme_row.pack_start(theme_label, False, False, 0)
        theme_row.pack_start(themes_scroller, False, False, 0)
        themes_scroller.set_hexpand(True)
        theme_row.pack_start(import_btn, False, False, 0)

        # Manual colours — shown/editable only when source == "manual".
        manual_label = Gtk.Label(label="Manual colours:", xalign=0)
        self._manual_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._manual_colors: dict[str, Gtk.ColorButton] = {}
        for key, label in (
            ("background", "Background:"),
            ("foreground", "Foreground:"),
            ("accent", "Accent:"),
            ("running", "Running:"),
            ("hover", "Hover:"),
            ("border_color", "Border:"),
        ):
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            lbl = Gtk.Label(label=label, xalign=1)
            lbl.set_size_request(80, -1)
            btn = Gtk.ColorButton()
            btn.set_hexpand(True)
            if key == "hover":
                btn.set_use_alpha(True)
            row.pack_start(lbl, False, False, 0)
            row.pack_start(btn, True, True, 0)
            self._manual_box.pack_start(row, False, False, 0)
            self._manual_colors[key] = btn
        self._sync_manual_colors()

        tab.pack_start(source_row, False, False, 0)
        tab.pack_start(theme_row, False, False, 0)
        tab.pack_start(manual_label, False, False, 0)
        tab.pack_start(self._manual_box, False, False, 0)

    def _sync_manual_colors(self) -> None:
        """Load the config's manual theme colours into the colour buttons."""
        theme = self._cfg.get("theme") or {}
        accent = theme.get("accent", "#7aa2f7")
        values = {
            "background": theme.get("background", "#1a1b26"),
            "foreground": theme.get("foreground", "#c0caf5"),
            "accent": accent,
            "running": theme.get("running") or accent,
            "hover": theme.get("hover", "rgba(255, 255, 255, 0.08)"),
            "border_color": theme.get("border_color") or accent,
        }
        for key, btn in self._manual_colors.items():
            btn.set_rgba(_hex_to_rgba(values[key]))

    def _manual_colors_dict(self) -> dict:
        """The manual theme colours read back from the colour buttons."""
        out = {}
        for key, btn in self._manual_colors.items():
            if key == "hover":
                out[key] = _rgba_to_css(btn.get_rgba())
            else:
                out[key] = _rgba_to_hex(btn.get_rgba())
        return out

    def _build_animations_tab(self, page: Gtk.Box) -> None:
        tab = page
        anim_cfg = self._cfg.get("animations") or {}
        theme = self._cfg.get("theme") or {}

        hint = Gtk.Label(
            label="Animate the bar's border color. Low/High follow Hyprland's "
            "animations files; Custom is independent of Hyprland.",
            xalign=0,
            wrap=True,
        )
        hint.set_opacity(0.8)
        tab.pack_start(hint, False, False, 0)

        enable_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        enable_label = Gtk.Label(label="Animated border:", xalign=1)
        enable_label.set_size_request(70, -1)
        self._border_anim_enabled = Gtk.CheckButton()
        self._border_anim_enabled.set_active(bool(theme.get("border_animation", True)))
        self._border_anim_enabled.set_hexpand(True)
        enable_row.pack_start(enable_label, False, False, 0)
        enable_row.pack_start(self._border_anim_enabled, True, True, 0)
        tab.pack_start(enable_row, False, False, 0)

        mode_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        mode_label = Gtk.Label(label="Mode:", xalign=1)
        mode_label.set_size_request(70, -1)
        self._anim_mode_buttons = _radio_group(
            [("low", "Low"), ("high", "High"), ("custom", "Custom")]
        )
        mode_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        for key, btn in self._anim_mode_buttons.items():
            btn.connect("toggled", self._on_anim_mode_toggled, key)
            mode_box.pack_start(btn, False, False, 0)
        mode = str(anim_cfg.get("mode") or "high").lower()
        self._anim_mode_buttons[mode if mode in self._anim_mode_buttons else "high"].set_active(True)
        mode_box.set_hexpand(True)
        mode_row.pack_start(mode_label, False, False, 0)
        mode_row.pack_start(mode_box, True, True, 0)
        tab.pack_start(mode_row, False, False, 0)

        speed_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        speed_label = Gtk.Label(label="Custom speed:", xalign=1)
        speed_label.set_size_request(70, -1)
        self._anim_speed = Gtk.SpinButton.new_with_range(1, 200, 1)
        self._anim_speed.set_value(int(anim_cfg.get("speed", 15) or 15))
        self._anim_speed.set_hexpand(True)
        speed_hint = Gtk.Label(label="Hyprland-style speed (mode=custom)", xalign=0)
        speed_hint.set_opacity(0.7)
        speed_row.pack_start(speed_label, False, False, 0)
        speed_row.pack_start(self._anim_speed, True, True, 0)
        speed_row.pack_start(speed_hint, False, False, 0)
        tab.pack_start(speed_row, False, False, 0)

        self._update_anim_speed_state()

    def _on_anim_mode_toggled(self, btn: Gtk.RadioButton, key: str) -> None:
        if btn.get_active():
            self._update_anim_speed_state()

    def _update_anim_speed_state(self) -> None:
        """Only enable the custom speed field when the Custom mode is active."""
        if not getattr(self, "_anim_speed", None):
            return
        custom = self._anim_mode_buttons.get("custom")
        self._anim_speed.set_sensitive(
            bool(custom and custom.get_active())
        )

    def _active_anim_mode(self) -> str:
        for key, btn in self._anim_mode_buttons.items():
            if btn.get_active():
                return key
        return "high"

    # ── arc menu tab ─────────────────────────────────────────────

    _ARC_POSITIONS = [
        ("top-left", "Top Left"),
        ("top-center", "Top Center"),
        ("top-right", "Top Right"),
        ("bottom-left", "Bottom Left"),
        ("bottom-center", "Bottom Center"),
        ("bottom-right", "Bottom Right"),
    ]

    def _build_arcmenu_tab(self, page: Gtk.Box) -> None:
        arc = self._cfg.get("arcmenu") or {}
        self._arc_items: list[dict] = [dict(i) for i in arc.get("items", [])]

        notebook = Gtk.Notebook()
        notebook.set_vexpand(True)
        page.pack_start(notebook, True, True, 0)

        general = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self._build_arc_general(general, arc)
        notebook.append_page(self._scroll_tab(general), Gtk.Label(label="General"))

        source = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self._build_arc_source(source, arc)
        notebook.append_page(self._scroll_tab(source), Gtk.Label(label="Source"))

        colors = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self._build_arc_colors(colors, arc)
        notebook.append_page(self._scroll_tab(colors), Gtk.Label(label="Colors"))

        items = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self._build_arc_items_tab(items)
        notebook.append_page(items, Gtk.Label(label="Menu Items"))

    @staticmethod
    def _scroll_tab(box: Gtk.Box) -> Gtk.ScrolledWindow:
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.add(box)
        return scroller

    def _build_arc_general(self, tab: Gtk.Box, arc: dict) -> None:
        hint = Gtk.Label(
            label="The arc menu is an overlay owned by the bar, toggled by the "
            "FAB or Super+Ctrl+M. It follows the bar theme and pywal.",
            xalign=0, wrap=True,
        )
        hint.set_opacity(0.8)
        tab.pack_start(hint, False, False, 0)

        self._arc_enabled = self._radio_bool_row(tab, "Enabled", bool(arc.get("enabled", True)))

        pos_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        pos_label = Gtk.Label(label="Position:", xalign=1)
        pos_label.set_size_request(70, -1)
        self._arc_position = _radio_group(
            [(key, key.replace("-", " ").title()) for key, _lbl in self._ARC_POSITIONS]
        )
        grid = Gtk.Grid(row_spacing=2, column_spacing=4)
        for i, (key, _lbl) in enumerate(self._ARC_POSITIONS):
            grid.attach(self._arc_position[key], i % 2, i // 2, 1, 1)
        current = arc.get("position", "bottom-right")
        if current not in self._arc_position:
            current = "bottom-right"
        self._arc_position[current].set_active(True)
        grid.set_hexpand(True)
        pos_row.pack_start(pos_label, False, False, 0)
        pos_row.pack_start(grid, True, True, 0)
        tab.pack_start(pos_row, False, False, 0)

        shape_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        shape_label = Gtk.Label(label="Shape:", xalign=1)
        shape_label.set_size_request(70, -1)
        self._arc_shape = _radio_group([("circle", "Circle"), ("square", "Square")])
        shape_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        for btn in self._arc_shape.values():
            shape_box.pack_start(btn, False, False, 0)
        self._arc_shape[arc.get("shape", "circle")].set_active(True)
        shape_box.set_hexpand(True)
        shape_row.pack_start(shape_label, False, False, 0)
        shape_row.pack_start(shape_box, True, True, 0)
        tab.pack_start(shape_row, False, False, 0)

        self._arc_radius = self._spin_row(tab, "Radius (px)", arc.get("radius", 140), 40, 600, 10)
        self._arc_margin = self._spin_row(tab, "Edge padding", arc.get("margin", 24), 0, 200, 2)
        self._arc_fab = self._spin_row(tab, "Menu button size", arc.get("fab_size", 56), 24, 120, 4)
        self._arc_item = self._spin_row(tab, "Item size", arc.get("item_size", 48), 24, 120, 4)
        self._arc_anim = self._spin_row(tab, "Animation (ms)", arc.get("animation_time", 300), 50, 2000, 25)
        self._arc_glyph = self._spin_row(tab, "Glyph size (px)", arc.get("glyph_size", 0), 0, 64, 1)

        icon_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        icon_label = Gtk.Label(label="Menu glyph:", xalign=1)
        icon_label.set_size_request(70, -1)
        self._arc_fab_glyph = Gtk.Entry()
        self._arc_fab_glyph.set_text(str(arc.get("fab_glyph", "\uf00a")))
        self._arc_fab_glyph.set_hexpand(True)
        icon_hint = Gtk.Label(label="Nerd Font codepoint (blank = icon)", xalign=0)
        icon_hint.set_opacity(0.7)
        icon_row.pack_start(icon_label, False, False, 0)
        icon_row.pack_start(self._arc_fab_glyph, True, True, 0)
        icon_row.pack_start(icon_hint, False, False, 0)
        tab.pack_start(icon_row, False, False, 0)

        self._arc_unfocus = self._radio_bool_row(tab, "Close on unfocus", bool(arc.get("close_on_unfocus", False)))
        self._arc_click = self._radio_bool_row(tab, "Close on item click", bool(arc.get("close_on_click", True)))

    def _build_arc_source(self, tab: Gtk.Box, arc: dict) -> None:
        hint = Gtk.Label(
            label="Where the arc menu's look comes from. Follow bar theme mirrors "
            "the bar's palette glass + text; pywal keeps color5/color6 accents.",
            xalign=0, wrap=True,
        )
        hint.set_opacity(0.8)
        tab.pack_start(hint, False, False, 0)
        self._arc_pywal = self._radio_bool_row(tab, "Use pywal colors", bool(arc.get("use_pywal", True)))
        self._arc_follow = self._radio_bool_row(tab, "Follow bar theme", bool(arc.get("follow_bar", True)))
        self._arc_transparent = self._radio_bool_row(tab, "Transparent (icons only)", bool(arc.get("transparent", False)))

    def _build_arc_colors(self, tab: Gtk.Box, arc: dict) -> None:
        hint = Gtk.Label(
            label="Used when pywal / follow-bar theming is off (or as a fallback).",
            xalign=0, wrap=True,
        )
        hint.set_opacity(0.8)
        tab.pack_start(hint, False, False, 0)
        self._arc_fab_color = Gtk.ColorButton()
        self._arc_fab_color.set_rgba(_hex_to_rgba(arc.get("fab_color", "#c084fc")))
        self._arc_item_color = Gtk.ColorButton()
        self._arc_item_color.set_rgba(_hex_to_rgba(arc.get("item_color", "#22d3ee")))
        fab_color_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        fab_color_label = Gtk.Label(label="Menu color:", xalign=1)
        fab_color_label.set_size_request(70, -1)
        self._arc_fab_color.set_hexpand(True)
        fab_color_row.pack_start(fab_color_label, False, False, 0)
        fab_color_row.pack_start(self._arc_fab_color, True, True, 0)
        tab.pack_start(fab_color_row, False, False, 0)
        item_color_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        item_color_label = Gtk.Label(label="Item color:", xalign=1)
        item_color_label.set_size_request(70, -1)
        self._arc_item_color.set_hexpand(True)
        item_color_row.pack_start(item_color_label, False, False, 0)
        item_color_row.pack_start(self._arc_item_color, True, True, 0)
        tab.pack_start(item_color_row, False, False, 0)

    def _build_arc_items_tab(self, tab: Gtk.Box) -> None:
        hint = Gtk.Label(
            label="Items fan out from the menu button. Action 'settings' opens "
            "the bar settings instead of a command.",
            xalign=0, wrap=True,
        )
        hint.set_opacity(0.8)
        tab.pack_start(hint, False, False, 0)
        self._arc_list = Gtk.ListBox()
        self._arc_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._populate_arc_items()
        items_scroll = Gtk.ScrolledWindow()
        items_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        items_scroll.set_min_content_height(160)
        items_scroll.set_vexpand(True)
        items_scroll.add(self._arc_list)
        tab.pack_start(items_scroll, True, True, 0)
        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        up_btn = Gtk.Button.new_from_icon_name("go-up-symbolic", Gtk.IconSize.BUTTON)
        down_btn = Gtk.Button.new_from_icon_name("go-down-symbolic", Gtk.IconSize.BUTTON)
        add_btn = Gtk.Button(label="Add")
        edit_btn = Gtk.Button(label="Edit")
        remove_btn = Gtk.Button(label="Remove")
        up_btn.set_tooltip_text("Move item up")
        down_btn.set_tooltip_text("Move item down")
        up_btn.connect("clicked", self._on_arc_move, -1)
        down_btn.connect("clicked", self._on_arc_move, 1)
        add_btn.connect("clicked", self._on_arc_add)
        edit_btn.connect("clicked", self._on_arc_edit)
        remove_btn.connect("clicked", self._on_arc_remove)
        for b in (up_btn, down_btn, add_btn, edit_btn, remove_btn):
            btn_row.pack_start(b, False, False, 0)
        tab.pack_start(btn_row, False, False, 0)

    def _radio_bool_row(self, tab: Gtk.Box, label: str, active: bool) -> Gtk.RadioButton:
        """A label + an Enable/Disable radio-button pair.

        Returns the "Enable" button — ``get_active()`` is True when enabled, so
        the existing ``_active_arc_block`` readers work unchanged.
        """
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        lbl = Gtk.Label(label=label, xalign=1)
        lbl.set_size_request(150, -1)
        buttons = _radio_group([("enable", "Enable"), ("disable", "Disable")])
        buttons["enable" if active else "disable"].set_active(True)
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        for btn in buttons.values():
            box.pack_start(btn, False, False, 0)
        box.set_hexpand(True)
        row.pack_start(lbl, False, False, 0)
        row.pack_start(box, True, True, 0)
        tab.pack_start(row, False, False, 0)
        return buttons["enable"]

    def _spin_row(self, tab: Gtk.Box, label: str, value: int, lo: int, hi: int, step: int) -> Gtk.SpinButton:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        lbl = Gtk.Label(label=label, xalign=1)
        lbl.set_size_request(150, -1)
        spin = Gtk.SpinButton.new_with_range(lo, hi, step)
        spin.set_value(int(value))
        spin.set_hexpand(True)
        row.pack_start(lbl, False, False, 0)
        row.pack_start(spin, True, True, 0)
        tab.pack_start(row, False, False, 0)
        return spin

    # ── arc menu items ───────────────────────────────────────────

    def _populate_arc_items(self) -> None:
        from .arcmenu import _face_widget

        for child in self._arc_list.get_children():
            self._arc_list.remove(child)
        for item in self._arc_items:
            row = Gtk.ListBoxRow()
            hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            hbox.set_margin_top(4)
            hbox.set_margin_bottom(4)
            hbox.set_margin_start(6)
            hbox.set_margin_end(6)
            icon = _face_widget(
                24, item.get("glyph", ""), item.get("icon", "application-x-executable"), self._theme_fg()
            )
            hbox.pack_start(icon, False, False, 0)
            labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            title = Gtk.Label(
                label=item.get("tooltip") or item.get("command") or item.get("action", ""),
                xalign=0,
            )
            sub = Gtk.Label(
                label=(item.get("command") or item.get("action", "no command")),
                xalign=0, width_chars=46, ellipsize=True,
            )
            sub.set_opacity(0.7)
            labels.pack_start(title, False, False, 0)
            labels.pack_start(sub, False, False, 0)
            hbox.pack_start(labels, True, True, 0)
            row.add(hbox)
            self._arc_list.add(row)
        self._arc_list.show_all()

    def _arc_selected_index(self) -> int | None:
        row = self._arc_list.get_selected_row()
        if row is None:
            return None
        return row.get_index()

    def _on_arc_move(self, _btn, delta: int) -> None:
        idx = self._arc_selected_index()
        if idx is None:
            return
        new = idx + delta
        if new < 0 or new >= len(self._arc_items):
            return
        self._arc_items[idx], self._arc_items[new] = self._arc_items[new], self._arc_items[idx]
        self._populate_arc_items()
        row = self._arc_list.get_row_at_index(new)
        if row is not None:
            self._arc_list.select_row(row)

    def _on_arc_add(self, _btn) -> None:
        item = _ArcItemDialog(self).run_dialog()
        if item is not None:
            self._arc_items.append(item)
            self._populate_arc_items()

    def _on_arc_edit(self, _btn) -> None:
        idx = self._arc_selected_index()
        if idx is None:
            return
        item = _ArcItemDialog(self, self._arc_items[idx]).run_dialog()
        if item is not None:
            self._arc_items[idx] = item
            self._populate_arc_items()

    def _on_arc_remove(self, _btn) -> None:
        idx = self._arc_selected_index()
        if idx is None:
            return
        del self._arc_items[idx]
        self._populate_arc_items()

    def _active_arc_position(self) -> str:
        for key, btn in self._arc_position.items():
            if btn.get_active():
                return key
        return "bottom-right"

    def _active_arc_shape(self) -> str:
        for key, btn in self._arc_shape.items():
            if btn.get_active():
                return key
        return "circle"

    def _active_arc_block(self) -> dict:
        return {
            "enabled": self._arc_enabled.get_active(),
            "position": self._active_arc_position(),
            "shape": self._active_arc_shape(),
            "radius": int(self._arc_radius.get_value()),
            "margin": int(self._arc_margin.get_value()),
            "fab_size": int(self._arc_fab.get_value()),
            "item_size": int(self._arc_item.get_value()),
            "animation_time": int(self._arc_anim.get_value()),
            "glyph_size": int(self._arc_glyph.get_value()),
            "fab_icon": "view-grid-symbolic",
            "fab_glyph": self._arc_fab_glyph.get_text().strip(),
            "fab_color": _rgba_to_hex(self._arc_fab_color.get_rgba()),
            "item_color": _rgba_to_hex(self._arc_item_color.get_rgba()),
            "use_pywal": self._arc_pywal.get_active(),
            "follow_bar": self._arc_follow.get_active(),
            "transparent": self._arc_transparent.get_active(),
            "close_on_unfocus": self._arc_unfocus.get_active(),
            "close_on_click": self._arc_click.get_active(),
            "items": self._arc_items,
        }

    _MENU_POSITIONS = [
        ("top-left", "Top Left"),
        ("top-center", "Top Center"),
        ("top-right", "Top Right"),
        ("center", "Center"),
        ("bottom-left", "Bottom Left"),
        ("bottom-center", "Bottom Center"),
        ("bottom-right", "Bottom Right"),
    ]

    def _build_menu_tab(self, page: Gtk.Box) -> None:
        menu = self._cfg.get("menu") or {}
        hint = Gtk.Label(
            label="The start menu is owned by the bar, toggled by the start "
            "button or the menu keybind. Follow hyprtk-bar anchors the menu to "
            "the bar's edge and pill width (align follows the bar's width); "
            "off positions it at the chosen screen corner. It follows the bar "
            "theme and pywal.",
            xalign=0, wrap=True,
        )
        hint.set_opacity(0.8)
        page.pack_start(hint, False, False, 0)

        self._menu_enabled = self._radio_bool_row(
            page, "Enabled", bool(menu.get("enabled", True))
        )

        self._menu_follow = self._radio_bool_row(
            page, "Follow hyprtk-bar", bool(menu.get("follow_bar", True))
        )

        layout_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        layout_label = Gtk.Label(label="Layout:", xalign=1)
        layout_label.set_size_request(70, -1)
        self._menu_layout = _radio_group(
            [(name, name.capitalize()) for name in MENU_LAYOUTS]
        )
        layout_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        for btn in self._menu_layout.values():
            layout_box.pack_start(btn, False, False, 0)
        current = menu.get("layout", "whisker")
        if current not in self._menu_layout:
            current = "whisker"
        self._menu_layout[current].set_active(True)
        layout_box.set_hexpand(True)
        layout_row.pack_start(layout_label, False, False, 0)
        layout_row.pack_start(layout_box, True, True, 0)
        page.pack_start(layout_row, False, False, 0)

        pos_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        pos_label = Gtk.Label(label="Position:", xalign=1)
        pos_label.set_size_request(70, -1)
        pos_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        pos_box.set_hexpand(True)
        self._menu_position = _radio_group(
            [("auto", "Auto (bar)")] +
            [(key, label.replace(" ", "\n")) for key, label in self._MENU_POSITIONS]
        )
        auto_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        auto_box.pack_start(self._menu_position["auto"], False, False, 0)
        pos_box.pack_start(auto_box, False, False, 0)
        grid = Gtk.Grid(row_spacing=2, column_spacing=4)
        for i, (key, _label) in enumerate(self._MENU_POSITIONS):
            grid.attach(self._menu_position[key], i % 3, i // 3, 1, 1)
        pos_box.pack_start(grid, False, False, 0)
        current = menu.get("position", "auto")
        if current not in self._menu_position:
            current = "auto"
        self._menu_position[current].set_active(True)
        pos_row.pack_start(pos_label, False, False, 0)
        pos_row.pack_start(pos_box, True, True, 0)
        page.pack_start(pos_row, False, False, 0)

        align_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        align_label = Gtk.Label(label="Align:", xalign=1)
        align_label.set_size_request(70, -1)
        self._menu_align = _radio_group(
            [("left", "Left"), ("center", "Center"), ("right", "Right")]
        )
        align_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        for btn in self._menu_align.values():
            align_box.pack_start(btn, False, False, 0)
        align = menu.get("align", "left")
        if align not in self._menu_align:
            align = "left"
        self._menu_align[align].set_active(True)
        align_box.set_hexpand(True)
        align_row.pack_start(align_label, False, False, 0)
        align_row.pack_start(align_box, True, True, 0)
        page.pack_start(align_row, False, False, 0)

        self._menu_gap_in = self._spin_row(page, "Gap in (px)", menu.get("gap_in", 4), 0, 60, 2)
        self._menu_gap_out = self._spin_row(page, "Gap out (px)", menu.get("gap_out", 5), 0, 60, 2)

    def _active_menu_block(self) -> dict:
        pos = "auto"
        for key, btn in self._menu_position.items():
            if btn.get_active():
                pos = key
                break
        layout = "whisker"
        for key, btn in self._menu_layout.items():
            if btn.get_active():
                layout = key
                break
        align = "left"
        for key, btn in self._menu_align.items():
            if btn.get_active():
                align = key
                break
        menu = dict(self._cfg.get("menu") or {})
        menu.update(
            {
                "enabled": self._menu_enabled.get_active(),
                "follow_bar": self._menu_follow.get_active(),
                "layout": layout,
                "position": pos,
                "align": align,
                "gap_in": int(self._menu_gap_in.get_value()),
                "gap_out": int(self._menu_gap_out.get_value()),
            }
        )
        return menu

    # ── quicklinks ───────────────────────────────────────────────

    _QUICKLINK_APPS = (
        ("terminal", "Terminal", default_terminal_command),
        ("files", "File manager", default_filemanager_command),
        ("web", "Web browser", default_browser_command),
    )

    def _build_quicklinks_tab(self, page: Gtk.Box) -> None:
        ql = self._cfg.get("quicklinks") or {}
        # Working copy of the links; edits accumulate until Apply.
        links = ql.get("links") or DEFAULT_LINKS
        self._quicklinks: list[dict] = [dict(l) for l in links if isinstance(l, dict)]
        # Ensure the three app links exist so they can always be chosen.
        for link_id, _label, _resolver in self._QUICKLINK_APPS:
            self._ensure_quicklink(link_id)

        hint = Gtk.Label(
            label="Quick links launch your preferred apps. Choose an app, or "
            "leave one on \"System default\" to follow the session's preferred "
            "terminal, file manager and web browser.",
            xalign=0, wrap=True,
        )
        hint.set_opacity(0.8)
        page.pack_start(hint, False, False, 0)

        self._quicklink_value_labels: dict[str, Gtk.Label] = {}
        for link_id, label, _resolver in self._QUICKLINK_APPS:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            lbl = Gtk.Label(label=label + ":", xalign=0)
            lbl.set_size_request(120, -1)
            value = Gtk.Label(xalign=0)
            value.set_ellipsize(Pango.EllipsizeMode.END)
            value.set_hexpand(True)
            edit = Gtk.Button(label="Choose\u2026")
            edit.connect("clicked", self._on_quicklink_edit, link_id)
            row.pack_start(lbl, False, False, 0)
            row.pack_start(value, True, True, 0)
            row.pack_start(edit, False, False, 0)
            page.pack_start(row, False, False, 0)
            self._quicklink_value_labels[link_id] = value
        self._refresh_quicklink_values()

    def _ensure_quicklink(self, link_id: str) -> dict:
        for link in self._quicklinks:
            if link.get("id") == link_id:
                return link
        default = next((l for l in DEFAULT_LINKS if l.get("id") == link_id), {})
        link = dict(default)
        self._quicklinks.append(link)
        return link

    def _quicklink_link(self, link_id: str) -> dict | None:
        for link in self._quicklinks:
            if link.get("id") == link_id:
                return link
        return None

    def _quicklink_resolver(self, link_id: str):
        for id_, _label, resolver in self._QUICKLINK_APPS:
            if id_ == link_id:
                return resolver
        return None

    def _refresh_quicklink_values(self) -> None:
        for link_id, label in self._quicklink_value_labels.items():
            command = (self._quicklink_link(link_id) or {}).get("command", "")
            if command:
                label.set_text(command)
                label.set_opacity(1.0)
            else:
                resolver = self._quicklink_resolver(link_id)
                resolved = (resolver() or "") if resolver is not None else ""
                label.set_text("System default" + (f" ({resolved})" if resolved else ""))
                label.set_opacity(0.8)

    def _on_quicklink_edit(self, _btn, link_id: str) -> None:
        link = self._quicklink_link(link_id) or {}
        title = next(lbl for id_, lbl, _ in self._QUICKLINK_APPS if id_ == link_id)
        dialog = _QuicklinkPickerDialog(self, title, link.get("command", ""))
        result = dialog.run_dialog()
        if result is None:
            return
        command, name = result
        link["command"] = command
        if name:
            link["label"] = name
        else:
            link.pop("label", None)
        self._refresh_quicklink_values()

    def _active_quicklinks_block(self) -> dict:
        ql = dict(self._cfg.get("quicklinks") or {})
        ql["links"] = self._quicklinks
        return ql

    def _build_modules_tab(self, page: Gtk.Box) -> None:
        tab = page
        hint = Gtk.Label(
            label="Position (left/center/right) and order within the bar.",
            xalign=0,
            wrap=True,
        )
        hint.set_opacity(0.8)
        tab.pack_start(hint, False, False, 0)

        list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        for mid in MODULE_IDS:
            list_box.pack_start(self._make_row(mid), False, False, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.add(list_box)
        tab.pack_start(scroller, True, True, 0)

    def _width_percent(self) -> int:
        width = str(self._cfg.get("width", "100%"))
        if width.endswith("%"):
            try:
                return max(10, min(100, int(width[:-1].strip())))
            except ValueError:
                pass
        return 100

    def _make_row(self, mid: str) -> Gtk.Box:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        check = Gtk.CheckButton(label=MODULE_LABELS.get(mid, mid))
        check.set_active(mid not in self._hidden)
        check.connect("toggled", self._on_show, mid)
        check.set_hexpand(True)
        row.pack_start(check, True, True, 0)

        position = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        buttons = _radio_group([(s, SECTION_LABELS[s]) for s in SECTION_ORDER])
        for s, btn in buttons.items():
            btn.connect("toggled", self._on_position, mid, s)
            position.pack_start(btn, False, False, 0)
        row.pack_start(position, False, False, 0)

        up = Gtk.Button.new_from_icon_name("go-up-symbolic", Gtk.IconSize.BUTTON)
        down = Gtk.Button.new_from_icon_name("go-down-symbolic", Gtk.IconSize.BUTTON)
        up.connect("clicked", self._on_move, mid, -1)
        down.connect("clicked", self._on_move, mid, 1)
        row.pack_start(up, False, False, 0)
        row.pack_start(down, False, False, 0)

        self._rows[mid] = {
            "check": check,
            "position": buttons,
            "up": up,
            "down": down,
        }
        self._update_row_state(mid)
        return row

    def _update_row_state(self, mid: str) -> None:
        state = self._rows[mid]
        shown = mid not in self._hidden
        section = self._section_of(mid)
        for sec, btn in state["position"].items():
            btn.handler_block_by_func(self._on_position)
            btn.set_active(sec == section)
            btn.handler_unblock_by_func(self._on_position)
            btn.set_sensitive(shown)
        state["check"].set_active(shown)
        order = self._order.get(section, [])
        index = order.index(mid) if mid in order else -1
        state["up"].set_sensitive(shown and index > 0)
        state["down"].set_sensitive(shown and 0 <= index < len(order) - 1)

    # ── handlers ─────────────────────────────────────────────────

    def _section_of(self, mid: str) -> str:
        for s in SECTION_ORDER:
            if mid in self._order.get(s, []):
                return s
        return "center"

    def _on_show(self, check: Gtk.CheckButton, mid: str) -> None:
        if check.get_active():
            self._hidden.discard(mid)
        else:
            self._hidden.add(mid)
        self._update_row_state(mid)

    def _on_position(self, btn: Gtk.ToggleButton, mid: str, section: str) -> None:
        if not btn.get_active():
            return
        for s in SECTION_ORDER:
            if mid in self._order.get(s, []):
                self._order[s].remove(mid)
        self._order.setdefault(section, []).append(mid)
        self._update_row_state(mid)

    def _on_move(self, _button, mid: str, delta: int) -> None:
        section = self._section_of(mid)
        order = self._order.get(section, [])
        if mid not in order:
            return
        index = order.index(mid)
        target = index + delta
        if 0 <= target < len(order):
            order[index], order[target] = order[target], order[index]
        self._update_row_state(mid)

    def _on_apply(self, *_args) -> None:
        # theme
        source = self._active_source()
        self._actions["set_source"](source)
        if source == "imported":
            self._actions["set_theme_name"](self._get_imported_theme())
        elif source == "manual":
            self._actions["set_manual_colors"](self._manual_colors_dict())

        # layout
        layout = {
            s: [mid for mid in self._order.get(s, []) if mid not in self._hidden]
            for s in SECTION_ORDER
        }
        self._actions["apply_layout"](layout)

        # width / align / height / position / opacity
        self._actions["set_width"](self._active_width())
        self._actions["set_align"](self._active_align())
        height = str(int(self._height.get_value()))
        self._actions["set_height"](height)
        self._actions["set_gaps"](
            {
                "gap_in": str(int(self._gap_in.get_value())),
                "gap_out": str(int(self._gap_out.get_value())),
            }
        )
        self._actions["set_position"](self._active_position())
        self._actions["set_opacity"](str(self._active_opacity()))
        self._actions["set_font"](self._active_font_family())
        self._actions["set_font_size"](str(int(self._font_size.get_value())))
        self._actions["set_icon_size"](str(int(self._icon_size.get_value())))
        self._actions["set_quicklink_icon_size"](str(int(self._ql_icon_size.get_value())))

        # animations
        self._actions["set_border_animation"](
            self._border_anim_enabled.get_active(),
            self._active_anim_mode(),
            int(self._anim_speed.get_value()),
        )

        # arc menu
        self._actions["set_arcmenu"](self._active_arc_block())

        # start menu
        self._actions["set_menu"](self._active_menu_block())

        # quicklinks
        self._actions["set_quicklinks"](self._active_quicklinks_block())

        # The theme actions above mutate the shared cfg and re-theme the bar,
        # but this window's widgets keep their build-time override colours.
        # Re-apply them so the dialogue itself follows the newly selected theme
        # (e.g. the light imported themes: light frame must come with light
        # contents, not stale dark widget colours).
        self._apply_theme_fg_class(self.get_child())

    def _on_reset(self, *_args) -> None:
        self._actions["reset_layout"]()
        self._order = {
            s: list(DEFAULT_LAYOUT[s]) for s in SECTION_ORDER
        }
        self._hidden = {
            mid for mid in MODULE_IDS
            if mid not in {m for s in self._order.values() for m in s}
        }
        for mid in MODULE_IDS:
            if mid in self._rows:
                self._update_row_state(mid)

    # ── read current widget state ───────────────────────────────

    def _active_source(self) -> str:
        for key, btn in self._source_buttons.items():
            if btn.get_active():
                return key
        return "pywal"

    def _active_align(self) -> str:
        for s, btn in self._align_buttons.items():
            if btn.get_active():
                return s
        return "center"

    def _active_position(self) -> str:
        for key, btn in self._position_buttons.items():
            if btn.get_active():
                return key
        return "bottom"

    def _active_width(self) -> str:
        return f"{int(self._width.get_value())}%"

    def _active_opacity(self) -> float:
        return max(0.0, min(1.0, self._opacity.get_value() / 100.0))

    def _get_imported_theme(self) -> str:
        for name, btn in self._theme_buttons.items():
            if btn.get_active():
                return name
        return ""

    def _update_source_state(self) -> None:
        source = self._active_source()
        for btn in self._theme_buttons.values():
            btn.set_sensitive(source == "imported")
        manual = getattr(self, "_manual_box", None)
        if manual is not None:
            manual.set_sensitive(source == "manual")

    def _on_source_toggled(self, btn, *_args) -> None:
        if btn.get_active():
            self._update_source_state()

    def _on_theme_toggled(self, btn: Gtk.CheckButton, name: str) -> None:
        if not btn.get_active():
            return
        for other in self._theme_buttons.values():
            if other is not btn:
                other.handler_block_by_func(self._on_theme_toggled)
                other.set_active(False)
                other.handler_unblock_by_func(self._on_theme_toggled)

    def _refresh_themes(self, select: str | None = None) -> None:
        for child in self._themes_box.get_children():
            self._themes_box.remove(child)
        self._theme_buttons = {}
        self._themes = list_themes()
        if not self._themes:
            label = Gtk.Label(label="No themes imported yet — use Import…", xalign=0)
            label.set_opacity(0.7)
            self._themes_box.add(label)
        else:
            for name in self._themes:
                btn = Gtk.CheckButton(label=name)
                btn.set_active(name == select)
                btn.set_hexpand(True)
                btn.set_halign(Gtk.Align.FILL)
                btn.connect("toggled", self._on_theme_toggled, name)
                self._theme_buttons[name] = btn
                self._themes_box.add(btn)
        self._themes_box.show_all()
        self._update_source_state()

    def _on_import(self, *_args) -> None:
        chooser = Gtk.FileChooserNative.new(
            "Import theme folder",
            self,
            Gtk.FileChooserAction.SELECT_FOLDER,
            "Import",
            "Cancel",
        )
        chooser.set_current_folder(str(Path.home()))

        def on_response(dialog: Gtk.FileChooserNative, response) -> None:
            if response == Gtk.ResponseType.ACCEPT:
                folder = dialog.get_file()
                if folder is not None:
                    name = import_theme(folder.get_path())
                    if name:
                        self._refresh_themes(select=name)
                        for key, btn in self._source_buttons.items():
                            btn.set_active(key == "imported")
                        self._update_source_state()
                        self._actions["set_source"]("imported")
                        self._actions["set_theme_name"](name)
            dialog.destroy()

        chooser.connect("response", on_response)
        chooser.show()

class _ArcItemDialog(Gtk.Window):
    """Add/edit a single arc menu item (icon, command, tooltip), with an
    embedded application search panel."""

    def __init__(self, parent, item: dict | None = None):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.set_title("Arc Menu Item")
        self.set_transient_for(parent)
        self.set_modal(True)
        self._parent = parent
        self._result: dict | None = None
        self._finished = False
        _theme_dialog(self)
        self._apps = _load_installed_apps()

        self.connect("key-press-event", self._on_key_press)

        item = item or {"icon": "", "command": "", "tooltip": ""}
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.get_style_context().add_class("popup-box")
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        self.add(box)

        title_label = Gtk.Label(label="Arc Menu Item", xalign=0)
        title_label.get_style_context().add_class("mc-page-title")
        box.pack_start(title_label, False, False, 0)

        def field(label: str, value: str) -> Gtk.Entry:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            lbl = Gtk.Label(label=label, xalign=0)
            lbl.set_size_request(90, -1)
            entry = Gtk.Entry()
            entry.set_text(value or "")
            row.pack_start(lbl, False, False, 0)
            row.pack_start(entry, True, True, 0)
            box.pack_start(row, False, False, 0)
            return entry

        self._glyph_entry = field("Glyph", item.get("glyph", ""))
        self._icon_entry = field("Icon", item.get("icon", ""))
        self._tooltip_entry = field("Tooltip", item.get("tooltip", ""))
        self._command_entry = field("Command", item.get("command", ""))
        self._action_entry = field("Action", item.get("action", ""))

        search_btn = Gtk.Button(label="Search Applications...")
        search_btn.connect("clicked", lambda _b: self._show_app_search())
        box.pack_start(search_btn, False, False, 0)

        self._search = Gtk.SearchEntry()
        self._search.set_placeholder_text("Type to search applications...")
        self._search.connect("search-changed", lambda _e: self._populate_apps())
        self._search.connect("activate", lambda _e: self._select_app())

        self._apps_list = Gtk.ListBox()
        self._apps_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._apps_list.connect("row-activated", lambda _l, _r: self._select_app())

        self._apps_scroll = Gtk.ScrolledWindow()
        self._apps_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._apps_scroll.set_size_request(-1, 280)
        self._apps_scroll.add(self._apps_list)

        hide_btn = Gtk.Button(label="Hide Search")
        hide_btn.connect("clicked", lambda _b: self._hide_app_search())

        search_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        search_row.pack_start(self._search, True, True, 0)
        search_row.pack_start(hide_btn, False, False, 0)

        for widget in (self._search, search_row, self._apps_scroll):
            widget.set_no_show_all(True)

        box.pack_start(search_row, False, False, 0)
        box.pack_start(self._apps_scroll, True, True, 0)

        hint = Gtk.Label(
            label="Glyph: Nerd Font codepoint (e.g. \\uf120).\n"
            "Icon: theme icon name (used when Glyph is blank).\n"
            "Action: 'settings' opens the bar settings instead of a command.",
            xalign=0, wrap=True,
        )
        hint.set_margin_top(4)
        box.pack_start(hint, False, False, 0)

        # Buttons live in the content area (single popup-box), not an action
        # area, so there is one bordered box — not two stacked ones.
        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_row.set_halign(Gtk.Align.END)
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _b: self._finish(None))
        save_btn = Gtk.Button(label="Save")
        save_btn.get_style_context().add_class("settings-apply")
        save_btn.set_can_default(True)
        save_btn.connect("clicked", lambda _b: self._finish(self.get_item()))
        btn_row.pack_start(cancel_btn, False, False, 0)
        btn_row.pack_start(save_btn, False, False, 0)
        save_btn.grab_default()
        box.pack_start(btn_row, False, False, 0)

        # Theme the dialog's widgets (content + buttons) so it matches
        # the bar settings dialogue's pywal/imported-theme look.
        if hasattr(parent, "_apply_theme_fg_class"):
            parent._apply_theme_fg_class(self)
        self.show_all()

    def run_dialog(self) -> dict | None:
        # Block like Gtk.Dialog.run(): a nested main loop that quits on _finish.
        Gtk.main()
        result = self._result
        self.destroy()
        return result

    def _finish(self, result: dict | None) -> None:
        if self._finished:
            return
        self._finished = True
        self._result = result
        Gtk.main_quit()

    def _show_app_search(self) -> None:
        self._search.set_visible(True)
        self._apps_scroll.set_visible(True)
        self._populate_apps()
        self._search.grab_focus()

    def _hide_app_search(self) -> None:
        self._search.set_visible(False)
        self._apps_scroll.set_visible(False)
        self._search.set_text("")

    def _populate_apps(self) -> None:
        from .arcmenu import load_icon_image

        for child in self._apps_list.get_children():
            self._apps_list.remove(child)
        query = self._search.get_text().strip().lower()
        fg = self._parent._theme_fg()
        for app in self._apps:
            if query and query not in app["name"].lower() and query not in (app["comment"] or "").lower():
                continue
            row = Gtk.ListBoxRow()
            hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            hbox.set_margin_top(4)
            hbox.set_margin_bottom(4)
            hbox.set_margin_start(6)
            hbox.set_margin_end(6)
            icon = load_icon_image(app["icon"], 24, fg)
            hbox.pack_start(icon, False, False, 0)
            labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            title = Gtk.Label(label=app["name"], xalign=0)
            sub = Gtk.Label(label=app.get("comment") or app["exec"], xalign=0, width_chars=45, ellipsize=True)
            sub.set_opacity(0.7)
            labels.pack_start(title, False, False, 0)
            labels.pack_start(sub, False, False, 0)
            hbox.pack_start(labels, True, True, 0)
            row.add(hbox)
            row._app = app
            self._apps_list.add(row)
        self._apps_list.show_all()

    def _select_app(self) -> None:
        from .arcmenu import glyph_for_app

        row = self._apps_list.get_selected_row() or self._apps_list.get_row_at_index(0)
        app = getattr(row, "_app", None)
        if app:
            self._icon_entry.set_text(app["icon"])
            self._tooltip_entry.set_text(app["name"])
            self._command_entry.set_text(app["exec"])
            self._action_entry.set_text("")
            # Prefer a Nerd Font glyph when one is known for the app; otherwise
            # leave the glyph blank so the button falls back to the theme icon.
            self._glyph_entry.set_text(glyph_for_app(app))
            self._hide_app_search()

    def _on_key_press(self, _widget, event) -> bool:
        if event.keyval == Gdk.KEY_Escape:
            self._finish(None)
            return True
        return False

    def get_item(self) -> dict:
        item = {
            "icon": self._icon_entry.get_text().strip(),
            "tooltip": self._tooltip_entry.get_text().strip(),
        }
        glyph = self._glyph_entry.get_text().strip()
        if glyph:
            item["glyph"] = glyph
        action = self._action_entry.get_text().strip()
        command = self._command_entry.get_text().strip()
        if action:
            item["action"] = action
        if command:
            item["command"] = command
        return item


class _QuicklinkPickerDialog(Gtk.Window):
    """Pick the app for a quick link, or reset it to the system default.

    ``run_dialog()`` returns ``None`` on cancel, else a ``(command, name)``
    tuple — ``command`` is the bare binary name (empty = system default) and
    ``name`` the app's display name.
    """

    def __init__(self, parent, title: str, current: str):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.set_title(f"Choose {title}")
        self.set_transient_for(parent)
        self.set_modal(True)
        self._parent = parent
        self._result = None
        self._finished = False
        _theme_dialog(self)
        self._apps = _load_installed_apps()

        self.connect("key-press-event", self._on_key_press)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.get_style_context().add_class("popup-box")
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        self.add(box)

        title_label = Gtk.Label(label=f"Choose {title}", xalign=0)
        title_label.get_style_context().add_class("mc-page-title")
        box.pack_start(title_label, False, False, 0)

        hint = Gtk.Label(label=f"Current: {current or 'System default'}", xalign=0, wrap=True)
        hint.set_opacity(0.8)
        box.pack_start(hint, False, False, 0)

        self._search = Gtk.SearchEntry()
        self._search.set_placeholder_text("Type to search applications...")
        self._search.connect("search-changed", lambda _e: self._populate())
        self._search.connect("activate", lambda _e: self._select())
        box.pack_start(self._search, False, False, 0)

        self._list = Gtk.ListBox()
        self._list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._list.connect("row-activated", lambda _l, _r: self._select())
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_size_request(420, 300)
        scroll.add(self._list)
        box.pack_start(scroll, True, True, 0)

        # Buttons live in the content area (single popup-box), not an action
        # area, so there is one bordered box — not two stacked ones.
        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_row.set_halign(Gtk.Align.END)
        system_btn = Gtk.Button(label="System default")
        system_btn.connect("clicked", lambda _b: self._finish(("", "")))
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _b: self._finish(None))
        btn_row.pack_start(system_btn, False, False, 0)
        btn_row.pack_start(cancel_btn, False, False, 0)
        box.pack_start(btn_row, False, False, 0)

        self._populate()
        if hasattr(parent, "_apply_theme_fg_class"):
            parent._apply_theme_fg_class(self)
        self.show_all()

    def run_dialog(self):
        # Block like Gtk.Dialog.run(): a nested main loop that quits on _finish.
        Gtk.main()
        result = self._result
        self.destroy()
        return result

    def _finish(self, result) -> None:
        if self._finished:
            return
        self._finished = True
        self._result = result
        Gtk.main_quit()

    def _on_key_press(self, _widget, event) -> bool:
        if event.keyval == Gdk.KEY_Escape:
            self._finish(None)
            return True
        return False

    def _populate(self) -> None:
        from .arcmenu import load_icon_image

        for child in self._list.get_children():
            self._list.remove(child)
        query = self._search.get_text().strip().lower()
        fg = self._parent._theme_fg()
        for app in self._apps:
            if query and query not in app["name"].lower() and query not in (app["comment"] or "").lower():
                continue
            row = Gtk.ListBoxRow()
            hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            hbox.set_margin_top(4)
            hbox.set_margin_bottom(4)
            hbox.set_margin_start(6)
            hbox.set_margin_end(6)
            icon = load_icon_image(app["icon"], 24, fg)
            hbox.pack_start(icon, False, False, 0)
            labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            title = Gtk.Label(label=app["name"], xalign=0)
            sub = Gtk.Label(label=app.get("comment") or app["exec"], xalign=0, width_chars=42, ellipsize=True)
            sub.set_opacity(0.7)
            labels.pack_start(title, False, False, 0)
            labels.pack_start(sub, False, False, 0)
            hbox.pack_start(labels, True, True, 0)
            row.add(hbox)
            row._app = app
            self._list.add(row)
        self._list.show_all()

    def _select(self) -> None:
        row = self._list.get_selected_row() or self._list.get_row_at_index(0)
        app = getattr(row, "_app", None)
        if app is None:
            return
        command = app["exec"].split()[0].rsplit("/", 1)[-1]
        self._finish((command, app["name"]))
