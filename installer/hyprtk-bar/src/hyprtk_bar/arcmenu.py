"""Arc menu overlay for hyprtk-bar (merged from the standalone hyprtk-arc-menu).

A layer-shell surface pinned to a screen corner holding a round FAB with
sub-items fanned out along an arc — the MaterialArcMenu concept rendered as a
GTK3 widget. It is now owned by the bar process (no separate app):

- toggled by the FAB click or ``Super+Ctrl+M`` (a script signals the running
  bar with SIGUSR2),
- themed from the bar's resolved palette + live pywal (``arc_palette``),
- configured from the bar settings dialogue's "Arc Menu" tab (stored in the
  bar config under ``arcmenu``).
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · arcmenu
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import math
import time

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")

from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

from .colors import contrast_fg as _contrast_fg  # noqa: E402
from .config import load_pywal_colors  # noqa: E402
from .hypr_animations import active_border_colors, border_animation, lerp_color  # noqa: E402
from .widgets import Glyph, spawn  # noqa: E402

log = logging.getLogger("hyprtk_bar.arcmenu")

# Menu positions: arc direction signs, arc spread (90° corners, 180° centers)
# and the layer-shell anchors used to pin the surface.
POSITIONS = {
    "top-left": {"dx": 1, "dy": 1, "fan": 90, "edges": (GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.TOP)},
    "top-center": {"dx": 1, "dy": 1, "fan": 180, "edges": (GtkLayerShell.Edge.TOP,)},
    "top-right": {"dx": -1, "dy": 1, "fan": 90, "edges": (GtkLayerShell.Edge.RIGHT, GtkLayerShell.Edge.TOP)},
    "bottom-left": {"dx": 1, "dy": -1, "fan": 90, "edges": (GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.BOTTOM)},
    "bottom-center": {"dx": 1, "dy": -1, "fan": 180, "edges": (GtkLayerShell.Edge.BOTTOM,)},
    "bottom-right": {"dx": -1, "dy": -1, "fan": 90, "edges": (GtkLayerShell.Edge.RIGHT, GtkLayerShell.Edge.BOTTOM)},
}

DEFAULT_ITEMS = [
    {"icon": "firefox", "command": "firefox", "tooltip": "Firefox"},
    {"icon": "utilities-terminal", "command": "alacritty", "tooltip": "Terminal"},
    {"icon": "system-file-manager", "command": "thunar", "tooltip": "Files"},
    {"icon": "accessories-calculator", "command": "qalculate-gtk", "tooltip": "Calculator"},
    {"icon": "preferences-system", "action": "settings", "tooltip": "Settings"},
]

# Curated app -> Nerd Font glyph lookup for the arc-menu item editor. Each entry
# is ``(glyph, keyword, ...)``; a keyword is matched (substring, lowercased)
# against an app's icon name, exec command and display name. The first hit wins;
# no hit returns "" so the editor falls back to the theme icon.
ARC_APP_GLYPHS = [
    ("\uf120", "terminal", "alacritty", "kitty", "wezterm", "foot", "urxvt",
     "rxvt", "xterm", "console", "konsole", "termite", "tilix", "terminator"),
    ("\uf07c", "thunar", "nautilus", "nemo", "dolphin", "pcmanfm",
     "file-manager", "filemanager", "folder"),
    ("\uf0ac", "browser", "firefox", "chrome", "chromium", "brave", "epiphany",
     "falkon", "qutebrowser", "librewolf", "waterfox"),
    ("\uf0ce", "libreoffice-calc", "scalc", "gnumeric", "spreadsheet", "excel"),
    ("\uf1ec", "calculator", "qalculate", "galculator"),
    ("\uf1c3", "libreoffice-impress", "powerpoint", "presentation", "impress"),
    ("\uf013", "settings", "preferences", "control-center", "systemsettings",
     "configuration"),
    ("\uf001", "spotify", "rhythmbox", "audacious", "clementine", "strawberry",
     "amarok", "music", "mpd"),
    ("\uf008", "vlc", "celluloid", "totem", "mpv", "video", "film",
     "media-player", "player"),
    ("\uf03e", "gimp", "inkscape", "krita", "darktable", "rawtherapee", "eog",
     "gwenview", "viewnior", "image", "picture", "photo", "screenshot"),
    ("\uf0e0", "thunderbird", "geary", "evolution", "claws", "mail", "email"),
    ("\uf075", "discord", "telegram", "signal", "slack", "whatsapp", "element",
     "hexchat", "irssi", "chat", "messaging"),
    ("\uf11b", "steam", "lutris", "retroarch", "heroic", "game"),
    ("\uf15c", "gedit", "mousepad", "kate", "notepad", "leafpad", "pluma",
     "text-editor", "editor"),
    ("\uf121", "vscode", "visual-studio-code", "code-oss", "sublime", "emacs",
     "vim", "neovim", "pycharm", "intellij", "android-studio", "geany", "code"),
    ("\uf1c0", "database", "sql", "mysql", "mariadb", "postgres", "sqlite",
     "dbeaver"),
    ("\uf1c1", "evince", "okular", "zathura", "mupdf", "pdf", "document",
     "reader", "book", "ebook"),
    ("\uf108", "monitor", "htop", "btop", "task-manager", "system-monitor",
     "process", "mission-center"),
    ("\uf083", "camera", "webcam", "cheese", "obs-studio", "obsproject"),
    ("\uf1eb", "wifi", "network", "wpa", "connman"),
    ("\uf293", "bluetooth", "blueberry", "blueman"),
    ("\uf02f", "print", "printer"),
    ("\uf1c6", "archive", "file-roller", "ark", "engrampa", "peazip",
     "compress"),
    ("\uf019", "download", "transmission", "deluge", "qbittorrent", "torrent"),
    ("\uf1fc", "paint", "draw", "mypaint", "pinta", "azpainter"),
    ("\uf0ad", "wrench", "gparted", "partition", "baobab", "disk-usage",
     "disk"),
    ("\uf0a3", "certificate", "password", "keyring", "keepass", "seahorse",
     "kleopatra"),
    ("\uf007", "user", "account", "users"),
    ("\uf011", "logout", "session", "poweroff", "shutdown", "reboot",
     "suspend", "hibernate"),
]


def glyph_for_app(app: dict) -> str:
    """Best-effort Nerd Font glyph for an installed app, or "" to use the icon.

    Matches :data:`ARC_APP_GLYPHS` against the app's icon name, exec command and
    display name (all lowercased). Returns the first hit's glyph; no hit returns
    "" so the arc-menu item editor reverts to the theme icon.
    """
    haystack = " ".join(str(app.get(k, "")) for k in ("icon", "exec", "name")).lower()
    for glyph, *keywords in ARC_APP_GLYPHS:
        for kw in keywords:
            if kw in haystack:
                return glyph
    return ""

# ── colour helpers ───────────────────────────────────────────────


def _css_rgb(css_color: str) -> tuple[int, int, int] | None:
    import re

    if not css_color:
        return None
    if css_color.startswith("#"):
        h = css_color.lstrip("#")
        if len(h) >= 6:
            try:
                return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
            except ValueError:
                return None
    m = re.search(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)", css_color, re.I)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3))
    return None


def _contrast_ok(fg_css: str, bg_css: str) -> bool:
    """True if fg and bg are sufficiently different in luminance."""
    frgb = _css_rgb(fg_css)
    brgb = _css_rgb(bg_css)
    if frgb is None or brgb is None:
        return False
    lum = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]  # noqa: E731
    return abs(lum(frgb) - lum(brgb)) > 100


def arc_palette(cfg: dict, bar_palette: dict) -> dict:
    """Resolve FAB/item colours for the arc menu.

    Mirrors the old arc-menu logic against the bar's resolved palette:
    - ``follow_bar`` + ``use_pywal``: pywal accents (color5/color6) for the
      buttons, bar theme decides icon lightness (so pywal colours never get lost
      on theme switches).
    - ``follow_bar`` only: the bar's glass background + text colour.
    - otherwise: pywal color5/color6, or the explicit config colours.
    """
    arc = cfg.get("arcmenu") or {}
    use_pywal = bool(arc.get("use_pywal", True))
    follow_bar = bool(arc.get("follow_bar", True))
    pywal = load_pywal_colors()
    pywal_on = use_pywal and bool(pywal)
    bar_on = follow_bar and bool(bar_palette)

    palette = {
        "fab_color": arc.get("fab_color", "#c084fc"),
        "fab_icon_color": arc.get("fab_icon_color", "#000000"),
        "item_color": arc.get("item_color", "#22d3ee"),
        "item_icon_color": arc.get("item_icon_color", "#000000"),
    }
    if bar_on and pywal_on:
        fab = pywal.get("color5") or palette["fab_color"]
        item = pywal.get("color6") or palette["item_color"]
        palette["fab_color"] = fab
        palette["item_color"] = item
        theme_fg = bar_palette.get("foreground", "#c0caf5")
        palette["fab_icon_color"] = theme_fg if _contrast_ok(theme_fg, fab) else _contrast_fg(fab)
        palette["item_icon_color"] = theme_fg if _contrast_ok(theme_fg, item) else _contrast_fg(item)
    elif bar_on:
        bg = bar_palette.get("background", "#1a1b26")
        fg = bar_palette.get("foreground", "#c0caf5")
        palette["fab_color"] = bg
        palette["item_color"] = bg
        palette["fab_icon_color"] = fg
        palette["item_icon_color"] = fg
    elif pywal_on:
        fab = pywal.get("color5") or palette["fab_color"]
        item = pywal.get("color6") or palette["item_color"]
        palette["fab_color"] = fab
        palette["item_color"] = item
        palette["fab_icon_color"] = _contrast_fg(fab)
        palette["item_icon_color"] = _contrast_fg(item)
    return palette


def _rgba_from_hex(hex_color: str) -> Gdk.RGBA:
    rgba = Gdk.RGBA()
    rgba.parse(hex_color if hex_color else "#000000")
    return rgba


def load_icon_image(icon_name: str, pixel: int, fg_hex: str) -> Gtk.Image:
    """Load an icon-theme image at an exact pixel size.

    Colored icons are loaded as-is; symbolic icons are tinted with ``fg_hex``
    so they stay readable against any (pywal) background.
    """
    theme = Gtk.IconTheme.get_default()
    info = theme.lookup_icon(icon_name, pixel, 0)
    if info is None:
        info = theme.lookup_icon("application-x-executable", pixel, 0)
    try:
        if info is not None and info.is_symbolic():
            fg = _rgba_from_hex(fg_hex)
            pixbuf = info.load_symbolic(fg, fg, fg, fg)[0]
        elif info is not None:
            pixbuf = info.load_icon()
        else:
            pixbuf = None
    except GLib.Error:
        pixbuf = None
    if pixbuf is None:
        return Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.BUTTON)
    return Gtk.Image.new_from_pixbuf(pixbuf)


def _face_widget(size: int, glyph: str, icon_name: str, fg_color: str, glyph_px: int = 0) -> Gtk.Widget:
    """The button face: a Nerd Font glyph when ``glyph`` is set, else an icon.

    ``glyph_px`` (0 = auto) overrides the default glyph size of half the button.
    """
    if glyph:
        px = glyph_px if glyph_px > 0 else int(size * 0.5)
        g = Glyph(glyph, "arc-glyph")
        g.set_pixel_size(max(10, px))
        return g
    return load_icon_image(icon_name, max(8, int(size * 0.5)), fg_color)


def _make_round_button(size: int, icon_name: str, css_class: str, fg_color: str = "#000000", glyph: str = "", glyph_px: int = 0) -> Gtk.Button:
    btn = Gtk.Button()
    btn.set_size_request(size, size)
    btn.get_style_context().add_class(css_class)
    btn.set_image(_face_widget(size, glyph, icon_name, fg_color, glyph_px))
    btn.set_can_focus(False)
    return btn


def ease_out_cubic(t: float) -> float:
    return 1 - (1 - t) ** 3


# ── the arc menu widget ──────────────────────────────────────────


class ArcMenu(Gtk.Fixed):
    """FAB + arc items laid out on a Gtk.Fixed, with open/close animation."""

    def __init__(self, cfg: dict, on_close=None, on_run=None, on_toggle=None, palette: dict | None = None):
        super().__init__()
        self.cfg = cfg
        self.on_close = on_close
        self.on_run = on_run
        self.on_toggle = on_toggle

        self._palette = palette or arc_palette(cfg, {})
        self._css_provider = None

        self._border_period = None
        self._border_timer = None
        self._border_hue = 0.0
        self._border_colors = None
        self._animated_border = None

        self._open = False
        self._opening = False
        self._anim_start = 0.0
        self._anim_timer = None
        self._items = []

        self._fab = self._build_fab()
        self.put(self._fab, 0, 0)

        for entry in (cfg.get("arcmenu") or {}).get("items", []):
            self._add_item(entry)

        self._apply_css()
        # Border animation is started on open() and stopped on close() — a
        # closed FAB doesn't need a permanently re-rendering border.

    # ── geometry ─────────────────────────────────────────────────

    def _arc(self) -> dict:
        return POSITIONS.get((self.cfg.get("arcmenu") or {}).get("position", "bottom-right"), POSITIONS["bottom-right"])

    def _is_square(self) -> bool:
        return (self.cfg.get("arcmenu") or {}).get("shape") == "square"

    @property
    def fab_size(self) -> int:
        return int((self.cfg.get("arcmenu") or {}).get("fab_size", 56))

    @property
    def item_size(self) -> int:
        return int((self.cfg.get("arcmenu") or {}).get("item_size", 48))

    @property
    def margin(self) -> int:
        return int((self.cfg.get("arcmenu") or {}).get("margin", 24))

    @property
    def radius(self) -> int:
        return int((self.cfg.get("arcmenu") or {}).get("radius", 140))

    @property
    def animation_time(self) -> int:
        return int((self.cfg.get("arcmenu") or {}).get("animation_time", 300))

    @property
    def glyph_size(self) -> int:
        """Glyph pixel size (0 = auto: half the button size)."""
        try:
            return max(0, int((self.cfg.get("arcmenu") or {}).get("glyph_size", 0) or 0))
        except (TypeError, ValueError):
            return 0

    def effective_radius(self) -> int:
        """Ring radius that keeps items from overlapping on the arc fan."""
        n = len(self._items)
        if n <= 1:
            return self.radius
        if self._is_square():
            return max(self.radius, int(math.ceil(self._square_radius())))
        _, _, fan = self._arc()["dx"], self._arc()["dy"], self._arc()["fan"]
        delta = math.radians(fan / (n - 1))
        min_radius = (self.item_size + 4) / (2 * math.sin(delta / 2))
        return max(self.radius, int(math.ceil(min_radius)))

    def _square_radius(self) -> float:
        n = len(self._items)
        fan = self._arc()["fan"]
        pts = []
        for i in range(n):
            ang = math.radians(fan * i / (n - 1)) if n > 1 else math.radians(fan / 2)
            u, v = math.cos(ang), math.sin(ang)
            m = max(abs(u), abs(v)) or 1.0
            pts.append((u / m, v / m))
        min_dist = min(
            math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
            for i in range(n - 1)
        )
        return (self.item_size + 4) / min_dist

    def open_size(self) -> tuple[int, int]:
        m = self.margin
        f = self.fab_size
        r = self.effective_radius()
        i = self.item_size
        position = (self.cfg.get("arcmenu") or {}).get("position", "bottom-right")
        if "center" in position:
            return 2 * r + i, m + f // 2 + r + i // 2
        return m + f // 2 + r + i // 2, m + f // 2 + r + i // 2

    # ── construction ─────────────────────────────────────────────

    def _build_fab(self) -> Gtk.Button:
        arc = self.cfg.get("arcmenu") or {}
        fab = _make_round_button(
            self.fab_size,
            arc.get("fab_icon", "view-grid-symbolic"),
            "arc-fab",
            self._palette["fab_icon_color"],
            arc.get("fab_glyph", ""),
            self.glyph_size,
        )
        fab.set_tooltip_text("Menu")
        fab.connect("clicked", lambda _b: self.on_toggle() if self.on_toggle else None)
        return fab

    def _add_item(self, entry: dict) -> None:
        icon = entry.get("icon", "application-x-executable")
        btn = _make_round_button(
            self.item_size, icon, "arc-item", self._palette["item_icon_color"],
            entry.get("glyph", ""), self.glyph_size,
        )
        tooltip = entry.get("tooltip") or entry.get("command") or ""
        if tooltip:
            btn.set_tooltip_text(tooltip)
        btn.connect("clicked", self._on_item_clicked, entry)
        btn.set_opacity(0.0)
        btn.set_no_show_all(True)
        self.put(btn, 0, 0)
        self._items.append({"btn": btn, "entry": entry})

    # ── styling ──────────────────────────────────────────────────

    def apply_palette(self, palette: dict) -> None:
        self._palette = palette
        self._apply_css()
        self.refresh_icons()
        # Refresh the animated border colours too — pywal's color11/color4
        # change on wallpaper change, and they were captured at construction.
        self._refresh_border_colors()

    def _refresh_border_colors(self) -> None:
        """Re-read the active-border colours so the animation tracks pywal."""
        if self._border_timer is None:
            return
        colors = active_border_colors()
        if colors:
            self._border_colors = colors

    def refresh_icons(self) -> None:
        arc = self.cfg.get("arcmenu") or {}
        self._fab.set_image(
            _face_widget(
                self.fab_size,
                arc.get("fab_glyph", ""),
                arc.get("fab_icon", "view-grid-symbolic"),
                self._palette["fab_icon_color"],
                self.glyph_size,
            )
        )
        for item in self._items:
            e = item["entry"]
            item["btn"].set_image(
                _face_widget(
                    self.item_size,
                    e.get("glyph", ""),
                    e.get("icon", "application-x-executable"),
                    self._palette["item_icon_color"],
                    self.glyph_size,
                )
            )

    def _apply_css(self) -> None:
        p = self._palette
        radius = "50%" if not self._is_square() else "24%"
        if (self.cfg.get("arcmenu") or {}).get("transparent"):
            fab_bg = "transparent"
            item_bg = "transparent"
            hover = "rgba(255,255,255,0.12)"
            fab_shadow = "none"
            item_shadow = "none"
        else:
            fab_bg = p["fab_color"]
            item_bg = p["item_color"]
            hover = None
            fab_shadow = "0 2px 8px rgba(0,0,0,0.35)"
            item_shadow = "0 2px 6px rgba(0,0,0,0.3)"
        fab_border = self._animated_border or p.get("fab_border") or "none"
        item_border = self._animated_border or p.get("item_border") or "none"
        fab_border_rule = f"border: 2px solid {fab_border};" if fab_border != "none" else "border: none;"
        item_border_rule = f"border: 2px solid {item_border};" if item_border != "none" else "border: none;"
        css = f"""
        .arc-fab {{
            background-image: none;
            background-color: {fab_bg};
            color: {p["fab_icon_color"]};
            border-radius: {radius};
            {fab_border_rule}
            box-shadow: {fab_shadow};
        }}
        .arc-fab:hover {{
            background-color: {hover or "shade(" + p["fab_color"] + ", 1.1)"};
        }}
        .arc-item {{
            background-image: none;
            background-color: {item_bg};
            color: {p["item_icon_color"]};
            border-radius: {radius};
            {item_border_rule}
            box-shadow: {item_shadow};
        }}
        .arc-item:hover {{
            background-color: {hover or "shade(" + p["item_color"] + ", 1.1)"};
        }}
        .arc-fab .arc-glyph {{ color: {p["fab_icon_color"]}; }}
        .arc-item .arc-glyph {{ color: {p["item_icon_color"]}; }}
        """
        provider = self._css_provider
        screen = Gdk.Screen.get_default()
        if provider is None:
            # Reuse a single provider and reload CSS in place — the border tick
            # calls this every ~15fps while open, and remove/add churn over a
            # screen-wide provider invalidates every surface each frame.
            provider = Gtk.CssProvider()
            Gtk.StyleContext.add_provider_for_screen(
                screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )
            self._css_provider = provider
        provider.load_from_data(css.encode())

    # ── layout ───────────────────────────────────────────────────

    def fab_center(self, win_w: int, win_h: int) -> tuple[int, int]:
        position = (self.cfg.get("arcmenu") or {}).get("position", "bottom-right")
        m, f = self.margin, self.fab_size
        if "center" in position:
            cx = win_w // 2
        elif "right" in position:
            cx = win_w - m - f // 2
        else:
            cx = m + f // 2
        if "bottom" in position:
            cy = win_h - m - f // 2
        else:
            cy = m + f // 2
        return cx, cy

    def layout_fab(self, win_w: int, win_h: int) -> None:
        cx, cy = self.fab_center(win_w, win_h)
        self.move(self._fab, int(cx - self.fab_size / 2), int(cy - self.fab_size / 2))

    def layout_items(self, win_w: int, win_h: int, radius: float, opacity: float) -> None:
        cx, cy = self.fab_center(win_w, win_h)
        dx, dy, fan = self._arc()["dx"], self._arc()["dy"], self._arc()["fan"]
        square = self._is_square()
        n = len(self._items)
        half = self.item_size / 2
        for idx, item in enumerate(self._items):
            if n == 1:
                angle = math.radians(fan / 2)
            else:
                angle = math.radians(fan * idx / (n - 1))
            u = math.cos(angle)
            v = math.sin(angle)
            if square:
                m = max(abs(u), abs(v)) or 1.0
                u /= m
                v /= m
            ox = dx * radius * u
            oy = dy * radius * v
            x = cx + ox - half
            y = cy + oy - half
            self.move(item["btn"], int(x), int(y))
            item["btn"].set_opacity(opacity)

    def set_items_visible(self, visible: bool) -> None:
        for item in self._items:
            item["btn"].set_visible(visible)
            if not visible:
                item["btn"].set_opacity(0.0)

    # ── state / animation ─────────────────────────────────────────

    def is_open(self) -> bool:
        return self._open

    def cancel_animation(self) -> None:
        if self._anim_timer is not None:
            GLib.source_remove(self._anim_timer)
            self._anim_timer = None

    def open(self, win_w: int, win_h: int) -> None:
        if self._open:
            return
        self._open = True
        self._opening = True
        self.set_items_visible(True)
        self.layout_fab(win_w, win_h)
        self._anim_start = time.monotonic()
        self._schedule_tick(win_w, win_h)
        # Only run the 30fps border animation while the menu is open; a closed
        # FAB doesn't need a permanently re-rendering border.
        self._start_border_animation()

    def close(self, win_w: int, win_h: int) -> None:
        if not self._open:
            return
        self._open = False
        self._opening = False
        self._anim_start = time.monotonic()
        self._schedule_tick(win_w, win_h)
        self._stop_border_animation()

    # ── border animation (mirrors the bar) ───────────────────────

    def _start_border_animation(self) -> None:
        if self._border_timer is not None:
            return
        # Respect the system reduced-motion preference.
        try:
            if not Gtk.Settings.get_default().get_property("gtk-enable-animations"):
                return
        except Exception:
            pass
        anim = border_animation(self.cfg)
        if not anim:
            return
        colors = active_border_colors()
        if not colors:
            return
        speed = max(1, int(anim["speed"]))
        self._border_period = max(200, int(speed * 100))
        self._border_colors = colors
        self._border_hue = 0.0
        self._border_timer = GLib.timeout_add(66, self._border_tick)

    def _stop_border_animation(self) -> None:
        if self._border_timer is not None:
            GLib.source_remove(self._border_timer)
            self._border_timer = None
        self._animated_border = None
        self._apply_css()

    def _border_tick(self) -> bool:
        if self._border_period is None:
            return False
        # ~15fps tick: a slow border blend needs no more (cheaper CSS rebuild).
        self._border_hue = (self._border_hue + 66.0 / (self._border_period / 2.0)) % 2.0
        t = self._border_hue if self._border_hue <= 1.0 else 2.0 - self._border_hue
        color = lerp_color(self._border_colors[0], self._border_colors[1], t)
        self._animated_border = color
        if color == getattr(self, "_border_last_color", None):
            return True
        self._border_last_color = color
        try:
            self._apply_css()
        except Exception:
            return False
        return True

    def _schedule_tick(self, win_w: int, win_h: int) -> None:
        if self._anim_timer is not None:
            GLib.source_remove(self._anim_timer)
        self._anim_timer = GLib.timeout_add(16, self._tick, win_w, win_h)

    def _tick(self, win_w: int, win_h: int) -> bool:
        elapsed_ms = (time.monotonic() - self._anim_start) * 1000
        duration = max(1, self.animation_time)
        t = min(1.0, elapsed_ms / duration)
        eased = ease_out_cubic(t)

        if self._opening:
            radius = eased * self.effective_radius()
            opacity = eased
        else:
            radius = self.effective_radius()
            opacity = 1 - eased

        self.layout_items(win_w, win_h, radius, opacity)

        if t >= 1.0:
            self._anim_timer = None
            if self._opening:
                self.set_items_visible(True)
                for item in self._items:
                    item["btn"].set_opacity(1.0)
            else:
                self.set_items_visible(False)
                if self.on_close:
                    self.on_close()
            return False
        return True

    # ── actions ───────────────────────────────────────────────────

    def _on_item_clicked(self, _btn, entry: dict) -> None:
        if self.on_run:
            self.on_run(entry)


# ── the layer-shell overlay window ───────────────────────────────


class ArcMenuWindow(Gtk.Window):
    """A borderless, transparent layer-shell surface pinned to a screen corner.

    Keeps a constant surface size (the open/arc size) so collapsing never
    resizes it; when closed an input shape limits clicks to the FAB and the
    rest of the surface passes through.
    """

    def __init__(self, cfg: dict, palette: dict | None = None, on_settings=None):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self._cfg = cfg
        self._on_settings = on_settings

        self.set_title("hyprtk-bar-arc")
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_app_paintable(True)
        self.set_accept_focus(False)

        visual = self.get_screen().get_rgba_visual()
        if visual:
            self.set_visual(visual)

        self._menu = ArcMenu(
            cfg,
            on_close=self._on_menu_closed,
            on_run=self._on_run,
            on_toggle=self.toggle,
            palette=palette or arc_palette(cfg, {}),
        )
        self.add(self._menu)

        self._init_layer_shell()
        w, h = self._menu.open_size()
        self._set_surface_size(w, h)
        self._menu.layout_fab(w, h)
        self._apply_closed()

        self.connect("key-press-event", self._on_key_press)
        self.connect("focus-out-event", self._on_focus_out)
        # Middle-click anywhere on the menu surface closes it.
        self.connect("button-press-event", self._on_pointer_press)

    # ── theming ───────────────────────────────────────────────────

    def apply_bar_palette(self, bar_palette: dict) -> None:
        """Re-theme the FAB/items from the bar's resolved palette."""
        self._menu.apply_palette(arc_palette(self._cfg, bar_palette))

    def reload_from_cfg(self) -> None:
        """Rebuild the menu in place after the arcmenu config block changed.

        The shared cfg dict is mutated by the settings dialogue before this is
        called, so the new position/shape/sizes/items are already visible via
        ``self._cfg`` — only the widget tree + layer-shell anchors need
        rebuilding. When ``enabled`` was switched off the overlay is hidden
        (the surface unmaps) and nothing is rebuilt.
        """
        if not self._enabled():
            self._menu.cancel_animation()
            self._menu._stop_border_animation()
            self._apply_closed()
            self.hide()
            return

        self._menu.cancel_animation()
        self.remove(self._menu)
        self._menu.destroy()
        self._menu = ArcMenu(
            self._cfg,
            on_close=self._on_menu_closed,
            on_run=self._on_run,
            on_toggle=self.toggle,
            palette=arc_palette(self._cfg, {}),
        )
        self.add(self._menu)

        for edge in (
            GtkLayerShell.Edge.LEFT,
            GtkLayerShell.Edge.RIGHT,
            GtkLayerShell.Edge.TOP,
            GtkLayerShell.Edge.BOTTOM,
        ):
            GtkLayerShell.set_anchor(self, edge, False)
        position = POSITIONS[(self._cfg.get("arcmenu") or {}).get("position", "bottom-right")]
        for edge in position["edges"]:
            GtkLayerShell.set_anchor(self, edge, True)

        w, h = self._menu.open_size()
        self._set_surface_size(w, h)
        self._menu.layout_fab(w, h)
        self._apply_closed()
        self._set_keyboard_mode(False)
        self.show_all()
        self.queue_resize()

    # ── layer shell ───────────────────────────────────────────────

    def _init_layer_shell(self) -> None:
        position = POSITIONS[(self._cfg.get("arcmenu") or {}).get("position", "bottom-right")]
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_namespace(self, "hyprtk-bar-arc")
        for edge in position["edges"]:
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_exclusive_zone(self, -1)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)

    def _set_keyboard_mode(self, on: bool) -> None:
        mode = (
            GtkLayerShell.KeyboardMode.ON_DEMAND
            if on
            else GtkLayerShell.KeyboardMode.NONE
        )
        GtkLayerShell.set_keyboard_mode(self, mode)
        self.set_accept_focus(on)
        if on:
            self.grab_focus()

    # ── sizing / input shape ──────────────────────────────────────

    def _fab_rect(self) -> Gdk.Rectangle:
        m = self._menu.margin
        f = self._menu.fab_size
        w, h = self._menu.open_size()
        position = (self._cfg.get("arcmenu") or {}).get("position", "bottom-right")
        if "center" in position:
            x = w // 2 - f // 2
        elif "left" in position:
            x = m
        else:
            x = w - m - f
        y = m if "top" in position else h - m - f
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = x, y, f, f
        return rect

    def _set_input_region(self, rect: Gdk.Rectangle | None) -> None:
        wnd = self.get_window()
        if wnd is None:
            return
        import cairo

        if rect is None:
            w, h = self._menu.open_size()
            rect = Gdk.Rectangle()
            rect.x, rect.y, rect.width, rect.height = 0, 0, w, h
        region = cairo.Region(cairo.RectangleInt(rect.x, rect.y, rect.width, rect.height))
        wnd.input_shape_combine_region(region, 0, 0)

    def _set_surface_size(self, w: int, h: int) -> None:
        self._menu.set_size_request(w, h)
        self.set_size_request(w, h)

    def _apply_closed(self) -> None:
        self._menu.set_items_visible(False)
        self._set_input_region(self._fab_rect())

    def _apply_open(self) -> None:
        self._set_input_region(None)

    # ── state control ─────────────────────────────────────────────

    def _enabled(self) -> bool:
        return bool((self._cfg.get("arcmenu") or {}).get("enabled", True))

    def toggle(self) -> None:
        if not self._enabled():
            return
        if self._menu.is_open():
            self.close_menu()
        else:
            self.open_menu()

    def open_menu(self) -> None:
        w, h = self._menu.open_size()
        self._menu.layout_fab(w, h)
        self._apply_open()
        self._set_keyboard_mode(True)
        self._menu.open(w, h)

    def close_menu(self) -> None:
        if not self._menu.is_open():
            return
        w, h = self._menu.open_size()
        self._menu.close(w, h)

    def _on_menu_closed(self) -> None:
        self._apply_closed()
        self._set_keyboard_mode(False)

    def _on_run(self, entry: dict) -> None:
        if entry.get("action") == "settings":
            self.close_menu()
            if self._on_settings:
                self._on_settings()
            return
        command = entry.get("command")
        if command:
            if not spawn(command):
                log.warning("Failed to launch %r", command)
        if (self._cfg.get("arcmenu") or {}).get("close_on_click", True):
            self.close_menu()

    # ── events ────────────────────────────────────────────────────

    def _on_key_press(self, _widget, event) -> bool:
        if event.keyval == Gdk.KEY_Escape and self._menu.is_open():
            self.close_menu()
            return True
        return False

    def _on_pointer_press(self, _widget, event) -> bool:
        # Middle-click anywhere on the menu surface disables the arc menu:
        # close it and persist arcmenu.enabled=false so the settings dialogue
        # shows it off and the overlay stays hidden until re-enabled there.
        if event.button == Gdk.BUTTON_MIDDLE:
            from . import config as config_module

            arc = self._cfg.setdefault("arcmenu", {})
            arc["enabled"] = False
            try:
                config_module.save(self._cfg)
            except OSError:
                log.warning("could not persist arc menu disable", exc_info=True)
            self.reload_from_cfg()
            return True
        return False

    def _on_focus_out(self, *_args) -> bool:
        if (self._cfg.get("arcmenu") or {}).get("close_on_unfocus") and self._menu.is_open():
            self.close_menu()
        return False