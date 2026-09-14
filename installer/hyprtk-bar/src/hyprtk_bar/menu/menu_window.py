"""Layer-shell menu window for hyprtk-menu."""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · menu_window
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────


import json
import os
import shlex
import shutil
import subprocess
import pwd
import urllib.parse

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")

from gi.repository import Gdk, GLib, Gtk, GtkLayerShell, Pango

from . import apps, config as cfg, theme
from ..hypr_animations import active_border_colors, border_period_ms, lerp_color
from .theme import apply_border_color, apply_css, build_css
from ..widgets import Glyph
from ..popup import center_layer_dialog

# Win7-style places entries (label, icon_name, command_or_path)
WIN7_PLACES = [
    ("Documents", "folder-documents", None),
    ("Pictures", "folder-pictures", None),
    ("Music", "folder-music", None),
    ("Games", "applications-games", None),
    ("Computer", "computer", "thunar /"),
]

# hyprtk-bar config: auto position follows the bar's edge, width, align and height.
BAR_CONFIG_FILE = os.path.expanduser("~/.config/hyprtk-bar/config.json")


def _spawn_argv(argv):
    """Detach an argv list (never a shell string)."""
    try:
        subprocess.Popen(argv, start_new_session=True)
        return True
    except Exception:
        return False


def _gap_value(value, default):
    """Coerce a gap config value to ``int >= 0``; ``default`` for missing/None.

    Unlike ``value or default``, a stored ``0`` is kept (0 is a valid gap).
    """
    if value is None or value == "":
        return default
    try:
        return max(0, int(value))
    except (TypeError, ValueError):
        return default


def _bar_width_px(width, total):
    """Resolve hyprtk-bar's ``width`` ("NN%" or px) against a monitor width."""
    if isinstance(width, str) and width.strip().endswith("%"):
        try:
            frac = float(width.strip().rstrip("%")) / 100.0
        except ValueError:
            return 0
        return int(total * max(0.0, min(1.0, frac)))
    try:
        return int(width)
    except (TypeError, ValueError):
        return 0

# Nerd Font glyphs for the power actions (same icon language as the bar).
POWER_GLYPH = {
    "lock": "\uf023",
    "logout": "\uf08b",
    "reboot": "\uf021",
    "shutdown": "\uf011",
    "suspend": "\uf186",
    "hibernate": "\uf236",
}

POWER_ICON_SIZE = 16

# Actions that destroy the session — always confirm before running.
POWER_CONFIRM = ("logout", "reboot", "shutdown", "hibernate")

# Actions that get danger styling (red tint) in the power bar.
POWER_DANGER = ("reboot", "shutdown")

CONFIRM_LABELS = {
    "logout": "Log Out",
    "reboot": "Restart",
    "shutdown": "Power Off",
    "hibernate": "Hibernate",
}

ALIGN_ICONS = {
    "left": "\uf036",
    "center": "\uf037",
    "right": "\uf038",
}
ALIGN_ORDER = ["left", "center", "right"]

# Shown in the Recommended/Recently Used section until real recents exist.
DEFAULT_RECOMMENDED = [
    "Alacritty.desktop",
    "brave-browser.desktop",
    "thunar.desktop",
    "org.pulseaudio.pavucontrol.desktop",
]

# Shown in the Win11 Pinned grid until the user pins apps.
DEFAULT_PINNED = [
    "Alacritty.desktop",
    "brave-browser.desktop",
    "thunar.desktop",
    "chromium.desktop",
    "kitty.desktop",
    "org.pulseaudio.pavucontrol.desktop",
    "btop.desktop",
]

POSITION_ORDER = [
    "auto",
    "center",
    "top-left",
    "top-center",
    "top-right",
    "bottom-left",
    "bottom-center",
    "bottom-right",
]

LAYOUT_ICONS = theme.LAYOUT_ICONS
LAYOUT_ORDER = theme.LAYOUT_ORDER

TRASH_ROOT = os.path.expanduser("~/.local/share/Trash")
TRASH_URL = "trash:///"


def _parse_trash_path(value):
    """Parse a .trashinfo ``Path=`` value into an absolute local path.

    Only local ``file://`` URLs with an empty/localhost host are accepted;
    anything else (foreign host, ``file://host/...``) is refused.
    """
    value = urllib.parse.unquote(value.strip())
    if value.startswith("file://"):
        parsed = urllib.parse.urlparse(value)
        if parsed.netloc not in ("", "localhost"):
            return ""
        return parsed.path
    return value


def _safe_trash_restore_dest(orig):
    """Return a validated restore destination, or None to refuse.

    The original path comes from a .trashinfo file, which must not be able to
    redirect a restore (or its mkdirs) to an arbitrary location.
    """
    if not orig:
        return None
    dest = os.path.abspath(orig)
    home = os.path.expanduser("~")
    if dest != home and not dest.startswith(home + os.sep):
        return None
    return dest


def _read_trashinfo(path):
    """Return (original_path, deletion_date) from a .trashinfo file."""
    orig = ""
    date = ""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line.startswith("Path="):
                    orig = _parse_trash_path(line[len("Path="):])
                elif line.startswith("DeletionDate="):
                    date = line[len("DeletionDate="):]
    except OSError:
        pass
    return orig, date


def _trash_items():
    """List trash contents as dicts: name, file_path, info_path, orig, date."""
    files_dir = os.path.join(TRASH_ROOT, "files")
    info_dir = os.path.join(TRASH_ROOT, "info")
    items = []
    if not os.path.isdir(files_dir):
        return items
    for entry in os.scandir(files_dir):
        name = entry.name
        info_path = os.path.join(info_dir, name + ".trashinfo")
        orig, date = _read_trashinfo(info_path)
        items.append(
            {
                "name": name,
                "path": entry.path,
                "info": info_path,
                "orig": orig,
                "date": date,
            }
        )
    items.sort(key=lambda it: it["name"].lower())
    return items


class MenuWindow(Gtk.Window):
    """Layer-shell start menu owned by the bar process (hyprtk-menu merged in).

    ``bar_cfg`` is the bar's shared config dict; the menu reads/writes its own
    ``menu`` block inside it (see :mod:`.config`). ``on_settings`` lets the
    menu's settings button open the bar settings dialogue's "Menu" page instead
    of a separate floating window.
    """

    def __init__(self, bar_cfg: dict | None = None, on_settings=None):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self._bar_cfg = bar_cfg or {}
        self._on_settings = on_settings
        cfg.set_bar_cfg(self._bar_cfg)
        self.config = cfg.load_config()
        self.apps = apps.scan_apps()
        self.pinned = set(self.config.get("favorites", []))
        self.recents = list(self.config.get("recents", []))
        self.current_category = "All"
        self._app_rows = {}  # entry id -> ListBoxRow (rows cached so icons load once)

        self.set_title("hyprtk-menu")
        width = int(self.config.get("width", 920))
        height = int(self.config.get("height", 580))
        self.set_size_request(600, 400)
        self.set_default_size(width, height)
        self.set_resizable(True)
        self.set_decorated(False)
        self.set_keep_above(True)
        self.set_accept_focus(True)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)

        screen = Gdk.Screen.get_default()
        if screen.get_rgba_visual():
            self.set_visual(screen.get_rgba_visual())
        self.set_app_paintable(True)

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        GtkLayerShell.set_namespace(self, "hyprtk-menu")
        # Pure overlay — no exclusive zone, so windows are never pushed.
        GtkLayerShell.set_exclusive_zone(self, 0)
        self._apply_position()

        try:
            apply_css(build_css())
        except Exception as exc:
            # A malformed pywal cache / imported theme must not prevent launch.
            print("hyprtk-menu: initial css build failed: %s" % exc, flush=True)
        self.get_style_context().add_class("menu-root")
        self._apply_layout_class()

        self._wal_mtime = theme.wal_mtime()
        self._bar_cfg_prev = theme.bar_config_mtime()
        self._themes_dir_prev = theme.themes_dir_mtime()
        self._wal_timer = GLib.timeout_add_seconds(2, self._check_wal)

        # Border animation mirrors the bar's (low/high/custom from the bar
        # config). Started while the menu is visible.
        self._border_anim_period = None
        self._border_anim_id = None
        self._border_hue = 0.0
        self._border_colors: tuple | None = None

        self._build_ui()
        self._layout_name = self.config.get("layout", "whisker")

        self.connect("key-press-event", self._on_window_key)
        # Destroying the menu must NOT quit the bar's main loop — it is now a
        # window inside the bar process, not a standalone app.
        self.connect("destroy", self._on_menu_destroy)

    def _on_menu_destroy(self, *_args) -> None:
        if self._wal_timer is not None:
            GLib.source_remove(self._wal_timer)
            self._wal_timer = None
        self._stop_border_animation()

    # -- layer shell ------------------------------------------------------

    def _monitor_width(self):
        """Width in px of the monitor the menu surfaces on (primary)."""
        display = Gdk.Display.get_default()
        if display is None or display.get_n_monitors() < 1:
            return 0
        monitor = display.get_primary_monitor()
        if monitor is None or not hasattr(monitor, "get_geometry"):
            # This GTK build's Gdk.Screen.get_primary_monitor returns an int;
            # Gdk.Display.get_primary_monitor is reliable but guard anyway.
            monitor = display.get_monitor(0)
        if monitor is None:
            return 0
        return monitor.get_geometry().width

    def _bar_geometry(self):
        """Read hyprtk-bar's config and return its on-monitor geometry.

        Returns ``(edge, bar_left, bar_right)`` or ``None`` when
        the bar config/monitor can't be read. ``bar_left``/``bar_right`` are
        the bar pill's horizontal bounds on the monitor (computed from the
        bar's ``width`` + ``align`` + ``gap``); the vertical offset is handled
        by the bar's exclusive zone.
        """
        try:
            with open(BAR_CONFIG_FILE, encoding="utf-8") as f:
                bar = json.load(f)
        except (OSError, ValueError):
            return None
        edge = bar.get("position")
        if edge not in ("top", "bottom"):
            return None
        total = self._monitor_width()
        if total <= 0:
            return None
        # Horizontal breathing room; legacy ``margin`` was replaced by the
        # vertical gap_in/gap_out pair but still seeds both when present.
        margin = 6
        legacy = bar.get("margin")
        if isinstance(legacy, (int, float)):
            margin = int(legacy)
            gap_in = gap_out = margin
        else:
            gap_in = _gap_value(bar.get("gap_in"), 6)
            gap_out = _gap_value(bar.get("gap_out"), 6)
        px = _bar_width_px(bar.get("width", "100%"), total)
        if px <= 0 or px >= total:
            left, right = margin, total
        else:
            align = bar.get("align", "center")
            if align == "left":
                left, right = margin, margin + px
            elif align == "right":
                left, right = total - px, total
            else:
                left = (total - px) // 2
                right = left + px
        height = int(bar.get("height", 40) or 40) + gap_in + gap_out
        return edge, left, right

    def _apply_position(self):
        position = self.config.get("position", "auto")
        follow_bar = bool(self.config.get("follow_bar", True))
        top = GtkLayerShell.Edge.TOP
        bottom = GtkLayerShell.Edge.BOTTOM
        left = GtkLayerShell.Edge.LEFT
        right = GtkLayerShell.Edge.RIGHT

        if position == "center" and not follow_bar:
            # No anchors on any edge → the surface is centered on the output.
            for anchor in (top, bottom, left, right):
                GtkLayerShell.set_anchor(self, anchor, False)
            return

        edge = "top"
        horizontal = "left"
        gap_in = _gap_value(self.config.get("gap_in"), 4)
        gap_out = _gap_value(self.config.get("gap_out"), 5)
        v_margin = gap_out
        x = None  # explicit left edge (px) when following the bar

        # Follow hyprtk-bar: the menu sits at the bar's edge and aligns
        # horizontally to the bar pill (its width + align + gaps), not the
        # screen. ``position`` only picks the fallback when follow is off.
        geo = self._bar_geometry() if follow_bar else None
        if geo is not None:
            edge, bar_left, bar_right = geo
            align = self.config.get("align", "left")
            horizontal = align if align in ("left", "center", "right") else "left"
            menu_w = int(self.config.get("width", 920))
            if horizontal == "left":
                x = bar_left
            elif horizontal == "right":
                x = bar_right - menu_w
            else:
                x = (bar_left + bar_right - menu_w) // 2
            total = self._monitor_width()
            if total > 0:
                x = max(gap_out, min(x, total - menu_w - gap_out))
            # The bar's exclusive zone already offsets the menu clear of the
            # bar's full surface (height + gap_in + gap_out); only the
            # configured gap_in breathing gap is needed on top of that.
            v_margin = gap_in
        else:
            if position == "auto":
                edge = "top"
                align = self.config.get("align", "left")
                horizontal = align if align in ("left", "center", "right") else "left"
            else:
                parts = position.split("-")
                edge = parts[0] if parts[0] in ("top", "bottom") else "top"
                horizontal = parts[1] if len(parts) > 1 else "left"

        GtkLayerShell.set_anchor(self, top, edge == "top")
        GtkLayerShell.set_anchor(self, bottom, edge == "bottom")

        if x is not None:
            # Follow the bar: pin the left edge at the computed x.
            GtkLayerShell.set_anchor(self, left, True)
            GtkLayerShell.set_anchor(self, right, False)
            GtkLayerShell.set_margin(self, left, x)
            GtkLayerShell.set_margin(self, right, 0)
        else:
            # Screen-anchored: anchor only the chosen side; unanchored → centered.
            GtkLayerShell.set_anchor(self, left, horizontal == "left")
            GtkLayerShell.set_anchor(self, right, horizontal == "right")
            GtkLayerShell.set_margin(self, left, gap_out if horizontal == "left" else 0)
            GtkLayerShell.set_margin(self, right, gap_out if horizontal == "right" else 0)

        GtkLayerShell.set_margin(self, top, v_margin if edge == "top" else 0)
        GtkLayerShell.set_margin(self, bottom, v_margin if edge == "bottom" else 0)

    # -- UI construction --------------------------------------------------

    def _build_ui(self):
        self._layout_initialized = False
        self._resizing = False
        layout = self.config.get("layout", "whisker")
        if layout not in LAYOUT_ORDER:
            layout = "whisker"
        builder = getattr(self, "_build_%s" % layout, None)
        if builder is None:
            layout = "whisker"
            builder = self._build_whisker
        root = builder()
        self._root = root
        self.add(root)

    def _rebuild_ui(self):
        """Tear down and rebuild the widget tree for a new layout."""
        child = self.get_child()
        if child is not None:
            self.remove(child)
            child.destroy()  # release the old layout's whole widget tree
        self._build_ui()
        self._refresh_favorites()
        self._refresh_apps()
        self._refresh_recents()
        self.show_all()
        self.present()
        GLib.idle_add(self.search.grab_focus)

    def _apply_saved_layout(self):
        """Restore saved window size and pane positions (first show only)."""
        self.set_size_request(
            int(self.config.get("width", 920)), int(self.config.get("height", 580))
        )
        if hasattr(self, "pane_main"):
            GLib.idle_add(self._apply_pane_positions)
        return False

    def _apply_pane_positions(self):
        window_w = self.get_allocated_width() or int(self.config.get("width", 920))
        sidebar_w = int(self.config.get("sidebar_width", 180))
        recents_w = int(self.config.get("recents_width", 230))
        if self.config.get("layout") == "win7":
            # Right places panel stays a fixed default width; apps take the rest.
            self.pane_main.set_position(max(window_w - 220, 400))
        else:
            self.pane_main.set_position(sidebar_w)
        if hasattr(self, "pane_right"):
            self.pane_right.set_position(max(window_w - sidebar_w - recents_w, 120))

    def _save_layout(self):
        window_w = self.get_allocated_width()
        window_h = self.get_allocated_height()
        if window_w and window_h:
            self.config["width"] = window_w
            self.config["height"] = window_h
        if hasattr(self, "pane_main"):
            sidebar_w = self.pane_main.get_position()
            if sidebar_w > 0:
                self.config["sidebar_width"] = sidebar_w
        if hasattr(self, "pane_right"):
            right_pos = self.pane_right.get_position()
            if right_pos > 0 and window_w:
                self.config["recents_width"] = max(window_w - sidebar_w - right_pos, 120)
        cfg.save_config(self.config)

    def _on_paned_changed(self, _paned):
        self._save_layout()

    # -- shared widgets ---------------------------------------------------

    def _make_search(self):
        self.search = Gtk.SearchEntry()
        self.search.set_placeholder_text("Search applications...")
        self.search.get_style_context().add_class("search")
        self.search.connect("search-changed", self._on_search_changed)
        self.search.connect("key-press-event", self._on_search_key)
        return self.search

    def _build_sidebar(self, store=True):
        scroll = Gtk.ScrolledWindow()
        scroll.get_style_context().add_class("sidebar-scroll")
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)

        sidebar = Gtk.ListBox()
        sidebar.get_style_context().add_class("sidebar")
        sidebar.set_selection_mode(Gtk.SelectionMode.NONE)
        sidebar.set_activate_on_single_click(True)
        for category in apps.CATEGORY_ORDER:
            row = Gtk.ListBoxRow()
            row.get_style_context().add_class("cat-row")
            label = Gtk.Label(label=category, xalign=0)
            label.get_style_context().add_class("cat-label")
            row.add(label)
            row.category = category
            if category == "All":
                row.get_style_context().add_class("selected")
            sidebar.add(row)
        sidebar.connect("row-activated", self._on_category_activated)
        scroll.add(sidebar)
        if store:
            self.sidebar = sidebar
        return scroll

    def _make_app_list(self):
        scroll = Gtk.ScrolledWindow()
        scroll.get_style_context().add_class("app-list-scroll")
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.app_list = Gtk.ListBox()
        self.app_list.get_style_context().add_class("app-list")
        self.app_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.app_list.set_activate_on_single_click(True)
        self.app_list.connect("row-activated", self._on_app_activated)
        self.app_list.connect("button-press-event", self._on_app_button)
        # A fresh listbox means the old rows (and any cached rows) are gone —
        # the previous app_list was destroyed when its parent was rebuilt on a
        # layout/theme switch. Drop the cache so _refresh_apps builds new rows.
        self._app_rows = {}
        scroll.add(self.app_list)
        return scroll

    def _make_favorites(self, klass="favorites"):
        self.fav_row = Gtk.FlowBox()
        self.fav_row.get_style_context().add_class(klass)
        self.fav_row.set_selection_mode(Gtk.SelectionMode.NONE)
        self.fav_row.set_max_children_per_line(100)
        return self.fav_row

    def _make_center(self, with_favorites=True):
        center = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        center.get_style_context().add_class("center-pane")
        if with_favorites:
            center.pack_start(self._make_favorites(), False, False, 0)
        center.pack_start(self._make_app_list(), True, True, 0)
        return center

    def _build_recents(self, title="Recently Used", klass="recents-pane"):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.get_style_context().add_class(klass)
        box.set_size_request(int(self.config.get("recents_width", 230)), -1)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        label = Gtk.Label(label=title, xalign=0)
        label.get_style_context().add_class("pane-title")
        header.pack_start(label, True, True, 0)

        clear_btn = Gtk.Button(label="Clear")
        clear_btn.get_style_context().add_class("clear-btn")
        clear_btn.set_tooltip_text("Clear recently used apps")
        clear_btn.connect("clicked", self._on_clear_recents)
        header.pack_end(clear_btn, False, False, 0)

        box.pack_start(header, False, False, 0)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.recents_list = Gtk.ListBox()
        self.recents_list.get_style_context().add_class("recents-list")
        self.recents_list.set_selection_mode(Gtk.SelectionMode.NONE)
        self.recents_list.set_activate_on_single_click(True)
        self.recents_list.connect("row-activated", self._on_app_activated)
        scroll.add(self.recents_list)
        box.pack_start(scroll, True, True, 0)
        return box

    # -- layout builders --------------------------------------------------

    def _build_whisker(self):
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.get_style_context().add_class("menu")
        root.pack_start(self._make_search(), False, False, 0)

        self.pane_right = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        self.pane_right.get_style_context().add_class("pane")
        self.pane_right.pack1(self._make_center(), True, True)
        if self.config.get("show_recents", True):
            self.pane_right.pack2(self._build_recents(), False, False)

        self.pane_main = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        self.pane_main.get_style_context().add_class("pane")
        self.pane_main.pack1(self._build_sidebar(), False, False)
        self.pane_main.pack2(self.pane_right, True, True)

        self.pane_main.connect("accept-position", self._on_paned_changed)
        self.pane_right.connect("accept-position", self._on_paned_changed)

        root.pack_start(self.pane_main, True, True, 0)
        root.pack_end(self._build_footer(), False, False, 0)
        return root

    def _build_win7(self):
        """Windows 7 Start Menu — user+apps left, places+search right."""
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.get_style_context().add_class("menu")

        paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        paned.get_style_context().add_class("pane")

        # ── Left pane: favorites + app list ──
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        left.get_style_context().add_class("win7-left")

        # Favorites
        left.pack_start(self._make_favorites(), False, False, 0)

        # App list (fills remaining space)
        left.pack_start(self._make_app_list(), True, True, 0)

        # All Programs row at bottom of left pane
        allprog = Gtk.Button(label="All Programs  ▸", relief=Gtk.ReliefStyle.NONE, xalign=0)
        allprog.get_style_context().add_class("win7-allprograms")
        allprog.get_child().get_style_context().add_class("win7-allprograms-label")
        allprog.connect("clicked", self._on_win7_allprograms)
        left.pack_end(allprog, False, False, 0)

        paned.pack1(left, True, True)

        # ── Right pane: places + search ──
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        right.get_style_context().add_class("win7-right")
        right.set_size_request(220, -1)

        places_scroll = Gtk.ScrolledWindow()
        places_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        places_scroll.set_vexpand(True)
        places = Gtk.ListBox()
        places.get_style_context().add_class("win7-places")
        places.set_selection_mode(Gtk.SelectionMode.NONE)
        places.set_activate_on_single_click(True)
        for label_text, icon_name, cmd in WIN7_PLACES:
            row = Gtk.ListBoxRow()
            row.get_style_context().add_class("win7-place-row")
            hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.MENU)
            icon.get_style_context().add_class("win7-place-icon")
            hbox.pack_start(icon, False, False, 0)
            lbl = Gtk.Label(label=label_text, xalign=0)
            lbl.get_style_context().add_class("win7-place-label")
            hbox.pack_start(lbl, True, True, 0)
            row.add(hbox)
            row.place_cmd = cmd
            row.place_label = label_text
            places.add(row)
        places.connect("row-activated", self._on_place_activated)
        places_scroll.add(places)
        right.pack_start(places_scroll, True, True, 0)

        # Search bar at bottom-right
        self._make_search()
        self.search.get_style_context().add_class("win7-search")
        right.pack_end(self.search, False, False, 0)

        paned.pack2(right, False, False)
        self.pane_main = paned
        self.pane_main.connect("accept-position", self._on_paned_changed)
        root.pack_start(self.pane_main, True, True, 0)

        # Bottom bar: shared footer (user + settings + power + resize)
        bottom = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        bottom.get_style_context().add_class("win7-bottom")
        footer = self._build_footer()
        footer.get_style_context().add_class("win7-footer")
        bottom.pack_start(footer, True, True, 0)
        root.pack_end(bottom, False, False, 0)
        return root

    def _on_place_activated(self, _listbox, row):
        """Open a Win7-style place."""
        cmd = getattr(row, "place_cmd", None)
        label = getattr(row, "place_label", "")
        if cmd is not None:
            # Explicit command (static value, e.g. "thunar /") — run as argv.
            _spawn_argv(shlex.split(cmd))
        elif label:
            # Open in file manager
            path = os.path.expanduser("~/%s" % label)
            if os.path.isdir(path):
                try:
                    subprocess.Popen(["thunar", path], start_new_session=True)
                except Exception:
                    pass
        self.hide_menu()

    def _on_win7_allprograms(self, _row):
        """Switch Win7 to show all apps with category filter."""
        self.current_category = "All"
        if hasattr(self, "sidebar"):
            for child in self.sidebar.get_children():
                if getattr(child, "category", None) == "All":
                    child.get_style_context().add_class("selected")
                else:
                    child.get_style_context().remove_class("selected")
        self._refresh_apps()

    def _build_win11(self):
        """Windows 11 Start Menu — centered search, pinned grid, recommended, user footer."""
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.get_style_context().add_class("menu")
        root.set_size_request(
            int(self.config.get("width", 920)), int(self.config.get("height", 580))
        )

        # Search bar (pill-shaped, centered feel)
        self._make_search()
        self.search.get_style_context().add_class("win11-search")
        root.pack_start(self.search, False, False, 0)

        # Pinned section: header + "All apps >" + grid
        self._win11_pinned_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        self._win11_pinned_header.get_style_context().add_class("win11-section-header")
        ptitle = Gtk.Label(label="Pinned", xalign=0)
        ptitle.get_style_context().add_class("pane-title")
        self._win11_pinned_header.pack_start(ptitle, True, True, 0)
        allapps_btn = Gtk.Button(label="All apps  ▸")
        allapps_btn.get_style_context().add_class("win11-allapps-btn")
        allapps_btn.connect("clicked", self._on_win11_allapps)
        self._win11_pinned_header.pack_end(allapps_btn, False, False, 0)
        root.pack_start(self._win11_pinned_header, False, False, 0)

        # Pinned grid (6 columns, icon + label tiles)
        pinned_grid = Gtk.Grid()
        pinned_grid.get_style_context().add_class("win11-pinned")
        pinned_grid.set_column_spacing(4)
        pinned_grid.set_row_spacing(4)
        pinned_grid.set_column_homogeneous(True)
        self._win11_pinned_grid = pinned_grid
        self._win11_pinned_wrap = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self._win11_pinned_wrap.get_style_context().add_class("win11-pinned-wrap")
        self._win11_pinned_wrap.pack_start(pinned_grid, False, False, 0)
        root.pack_start(self._win11_pinned_wrap, False, False, 0)

        # Recommended section: header + "More >" + recents
        recents_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        recents_header.get_style_context().add_class("win11-section-header")
        rtitle = Gtk.Label(label="Recommended", xalign=0)
        rtitle.get_style_context().add_class("pane-title")
        recents_header.pack_start(rtitle, True, True, 0)
        more_btn = Gtk.Button(label="More  ▸")
        more_btn.get_style_context().add_class("win11-more-btn")
        recents_header.pack_end(more_btn, False, False, 0)
        root.pack_start(recents_header, False, False, 0)

        recents = self._build_recents(title="", klass="recents-pane win11-recommended")
        recents.set_size_request(-1, int(self.config.get("height", 580)) // 3)
        root.pack_start(recents, False, False, 0)

        # App list (shown by search / "All apps" in Win11)
        app_scroll = Gtk.ScrolledWindow()
        app_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        app_scroll.get_style_context().add_class("app-list-scroll")
        app_scroll.set_vexpand(True)
        self._make_app_list()
        self.app_list.get_style_context().add_class("win11-app-list")
        app_scroll.add(self.app_list)
        self._win11_app_scroll = app_scroll
        self._win11_home = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self._win11_home.get_style_context().add_class("win11-home")
        for child in list(root.get_children()):
            # Keep the search bar and the app list at root level so they stay
            # visible in both the home and apps views.
            if child is not app_scroll and child is not self.search:
                root.remove(child)
                self._win11_home.pack_start(child, False, False, 0)
        self._win11_home.set_vexpand(True)
        root.pack_start(self._win11_home, True, True, 0)
        root.pack_start(app_scroll, True, True, 0)
        self._show_win11_home()

        # Footer: user avatar (left) + powerbar (right)
        footer = self._build_footer()
        footer.get_style_context().add_class("win11-footer")
        root.pack_end(footer, False, False, 0)

        return root

    def _show_win11_home(self):
        self._win11_view = "home"
        if hasattr(self, "_win11_home"):
            self._win11_home.set_visible(True)
        if hasattr(self, "_win11_app_scroll"):
            self._win11_app_scroll.set_visible(False)

    def _show_win11_apps(self):
        self._win11_view = "apps"
        if hasattr(self, "_win11_home"):
            self._win11_home.set_visible(False)
        if hasattr(self, "_win11_app_scroll"):
            self._win11_app_scroll.set_visible(True)

    def _reapply_win11_view(self):
        if getattr(self, "_win11_view", "home") == "apps":
            self._show_win11_apps()
        else:
            self._show_win11_home()

    def _on_win11_allapps(self, _button):
        """Show all apps list (scrollable) in Win11."""
        self.current_category = "All"
        self._refresh_apps()
        self._show_win11_apps()

    def _refresh_win11_pinned(self):
        """Populate the Win11 pinned grid with favorite app tiles."""
        if not hasattr(self, "_win11_pinned_grid"):
            return
        grid = self._win11_pinned_grid
        for child in grid.get_children():
            grid.remove(child)
            child.destroy()
        pinned = self.pinned if self.pinned else DEFAULT_PINNED
        cols = 6
        col = 0
        row = 0
        for entry in self.apps:
            if entry.id not in pinned:
                continue
            tile = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            tile.get_style_context().add_class("win11-tile")
            image = self._make_icon_image(entry, 32)
            image.get_style_context().add_class("win11-tile-icon")
            tile.pack_start(image, False, False, 0)
            label = Gtk.Label(
                label=entry.name,
                ellipsize=Pango.EllipsizeMode.END,
                max_width_chars=8,
            )
            label.get_style_context().add_class("win11-tile-label")
            tile.pack_start(label, False, False, 0)
            btn = Gtk.Button()
            btn.get_style_context().add_class("win11-tile-btn")
            btn.add(tile)
            btn.set_tooltip_text(entry.name)
            btn.connect("clicked", self._on_fav_clicked, entry)
            grid.attach(btn, col, row, 1, 1)
            col += 1
            if col >= cols:
                col = 0
                row += 1
        grid.show_all()

    def _refresh_recents(self):
        if not hasattr(self, "recents_list"):
            return
        for child in self.recents_list.get_children():
            self.recents_list.remove(child)
            child.destroy()
        by_id = {entry.id: entry for entry in self.apps}
        shown = 0
        for item in self.recents:
            entry = by_id.get(item)
            if entry:
                self.recents_list.add(self._make_row(entry, 26))
                shown += 1
        if shown == 0:
            # No real recents yet — show a sensible default set so the
            # Recommended/Recently Used section isn't empty.
            for item in DEFAULT_RECOMMENDED:
                entry = by_id.get(item)
                if entry:
                    self.recents_list.add(self._make_row(entry, 26))
        self.recents_list.show_all()

    def _build_plasma(self):
        """KDE Plasma-style menu — icon tabs, favorites grid, places, power footer."""
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.get_style_context().add_class("menu")

        # Search bar
        self._make_search()
        root.pack_start(self.search, False, False, 0)

        # Tab row with icons
        tabs = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        tabs.get_style_context().add_class("plasma-tabs")
        self._plasma_stack = Gtk.Stack()
        self._plasma_stack.set_transition_type(Gtk.StackTransitionType.NONE)
        self._plasma_buttons = {}
        tab_defs = [
            ("Applications", "view-grid"),
            ("Computer", "drive-harddisk"),
            ("Recently Used", "document-open-recent"),
        ]
        for name, icon_name in tab_defs:
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
            icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.MENU)
            icon.get_style_context().add_class("plasma-tab-icon")
            box.pack_start(icon, False, False, 0)
            label = Gtk.Label(label=name)
            box.pack_start(label, False, False, 0)
            button = Gtk.Button()
            button.get_style_context().add_class("plasma-tab")
            button.add(box)
            button.connect("clicked", self._on_plasma_tab, name)
            tabs.pack_start(button, True, True, 0)
            self._plasma_buttons[name] = button
        root.pack_start(tabs, False, False, 0)

        # ── Applications page: category sidebar + app list ──
        app_page = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        app_page.pack1(self._build_sidebar(), False, False)
        app_page.pack2(self._make_center(with_favorites=False), True, True)
        self._plasma_stack.add_named(app_page, "Applications")

        # ── Computer page: in-menu file browser (places sidebar + content) ──
        comp_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        comp_page.get_style_context().add_class("plasma-page")

        # Navigation bar: back / up / current path (controls the content pane)
        nav = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        nav.get_style_context().add_class("plasma-nav")
        back_btn = Gtk.Button.new_from_icon_name("go-previous-symbolic", Gtk.IconSize.MENU)
        back_btn.get_style_context().add_class("plasma-nav-btn")
        back_btn.connect("clicked", self._on_plasma_back)
        back_btn.set_sensitive(False)
        nav.pack_start(back_btn, False, False, 0)
        up_btn = Gtk.Button.new_from_icon_name("go-up-symbolic", Gtk.IconSize.MENU)
        up_btn.get_style_context().add_class("plasma-nav-btn")
        up_btn.connect("clicked", self._on_plasma_up)
        up_btn.set_sensitive(False)
        nav.pack_start(up_btn, False, False, 0)
        path_label = Gtk.Label(label="Computer", xalign=0)
        path_label.get_style_context().add_class("plasma-nav-path")
        path_label.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        nav.pack_start(path_label, True, True, 0)

        # Trash actions — only shown while browsing the trash.
        restore_btn = Gtk.Button(label="Restore")
        restore_btn.get_style_context().add_class("plasma-nav-btn")
        restore_btn.get_style_context().add_class("plasma-trash-restore")
        restore_btn.connect("clicked", self._on_plasma_restore)
        nav.pack_end(restore_btn, False, False, 0)
        empty_btn = Gtk.Button(label="Empty Trash")
        empty_btn.get_style_context().add_class("plasma-nav-btn")
        empty_btn.get_style_context().add_class("plasma-trash-empty")
        empty_btn.connect("clicked", self._on_plasma_empty)
        nav.pack_end(empty_btn, False, False, 0)
        restore_btn.set_no_show_all(True)
        empty_btn.set_no_show_all(True)
        restore_btn.hide()
        empty_btn.hide()
        self._plasma_restore_btn = restore_btn
        self._plasma_empty_btn = empty_btn

        self._plasma_nav = nav
        self._plasma_back_btn = back_btn
        self._plasma_up_btn = up_btn
        self._plasma_path_label = path_label
        comp_page.pack_start(nav, False, False, 0)

        # Two panes: sticky places sidebar + content browser
        paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        paned.get_style_context().add_class("plasma-places-paned")

        # Left: places list (stays visible so other locations stay reachable)
        places_scroll = Gtk.ScrolledWindow()
        places_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        places_scroll.set_size_request(150, -1)
        places_list = Gtk.ListBox()
        places_list.get_style_context().add_class("plasma-places")
        places_list.set_selection_mode(Gtk.SelectionMode.NONE)
        places_list.set_activate_on_single_click(True)
        self._plasma_places = places_list
        self._plasma_root_places = [
            ("Home", "user-home", os.path.expanduser("~")),
            ("Desktop", "user-desktop", os.path.expanduser("~/Desktop")),
            ("Documents", "folder-documents", os.path.expanduser("~/Documents")),
            ("Downloads", "folder-download", os.path.expanduser("~/Downloads")),
            ("Music", "folder-music", os.path.expanduser("~/Music")),
            ("Pictures", "folder-pictures", os.path.expanduser("~/Pictures")),
            ("Videos", "folder-videos", os.path.expanduser("~/Videos")),
            ("Trash", "user-trash", "trash:///"),
            ("Network", "network-workgroup", "network:///"),
        ]
        for lbl, icon_name, path in self._plasma_root_places:
            places_list.add(self._make_plasma_row(lbl, icon_name, path))
        places_list.connect("row-activated", self._on_plasma_place_activated)
        places_scroll.add(places_list)
        paned.pack1(places_scroll, False, False)

        # Right: content browser (current directory contents)
        content_scroll = Gtk.ScrolledWindow()
        content_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        browse_list = Gtk.ListBox()
        browse_list.get_style_context().add_class("plasma-places")
        browse_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        browse_list.set_activate_on_single_click(True)
        browse_list.connect("selected-rows-changed", self._on_plasma_browse_selection)
        self._plasma_browse_list = browse_list
        browse_list.connect("row-activated", self._on_plasma_browse_activated)
        content_scroll.add(browse_list)
        paned.pack2(content_scroll, True, True)

        comp_page.pack_start(paned, True, True, 0)
        self._plasma_stack.add_named(comp_page, "Computer")
        self._plasma_browse_history: list[str] = []
        self._plasma_current_path: str | None = None
        self._plasma_trash_mode = False

        # ── Recently Used page ──
        rec_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        rec_page.get_style_context().add_class("plasma-page")
        rec_scroll = Gtk.ScrolledWindow()
        rec_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.recents_list = Gtk.ListBox()
        self.recents_list.get_style_context().add_class("recents-list")
        self.recents_list.set_selection_mode(Gtk.SelectionMode.NONE)
        self.recents_list.set_activate_on_single_click(True)
        self.recents_list.connect("row-activated", self._on_app_activated)
        rec_scroll.add(self.recents_list)
        rec_page.pack_start(rec_scroll, True, True, 0)
        self._plasma_stack.add_named(rec_page, "Recently Used")

        root.pack_start(self._plasma_stack, True, True, 0)

        # Footer: user avatar (left) + powerbar (settings/power/resize)
        footer = self._build_footer()
        footer.get_style_context().add_class("plasma-footer")
        root.pack_end(footer, False, False, 0)

        self._plasma_stack.set_visible_child_name("Applications")
        self._plasma_buttons["Applications"].get_style_context().add_class("active")
        return root

    def _on_plasma_place_activated(self, _listbox, row):
        """A places-sidebar entry was clicked — show it in the content pane."""
        path = getattr(row, "row_path", None)
        if not path:
            return
        if path == TRASH_URL:
            self._plasma_enter_trash()
            return
        if os.path.isdir(path):
            # Jump to the place, starting a fresh navigation history.
            self._plasma_browse_history = []
            self._plasma_enter_dir(path)
        else:
            self._plasma_open_external(path)

    def _on_plasma_browse_activated(self, _listbox, row):
        """A content-pane row was clicked — enter subfolder or open file."""
        if self._plasma_trash_mode:
            # In trash mode, single-click selects; double-activation restores.
            self._plasma_restore_selected()
            return
        path = getattr(row, "row_path", None)
        if not path:
            return
        if os.path.isdir(path):
            self._plasma_enter_dir(path)
        else:
            self._plasma_open_external(path)

    def _on_plasma_browse_selection(self, _listbox):
        """Refresh restore-button state based on trash selection."""
        if self._plasma_trash_mode and hasattr(self, "_plasma_restore_btn"):
            selected = self._plasma_browse_list.get_selected_rows()
            self._plasma_restore_btn.set_sensitive(bool(selected))

    def _make_plasma_row(self, label_text: str, icon_name: str, path: str) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row.get_style_context().add_class("plasma-place-row")
        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.MENU)
        icon.get_style_context().add_class("plasma-place-icon")
        hbox.pack_start(icon, False, False, 0)
        label = Gtk.Label(label=label_text, xalign=0)
        label.get_style_context().add_class("plasma-place-label")
        label.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        hbox.pack_start(label, True, True, 0)
        row.add(hbox)
        row.row_path = path
        return row

    def _plasma_enter_dir(self, path):
        path = os.path.abspath(path)
        if not os.path.isdir(path):
            return
        if self._plasma_trash_mode:
            self._plasma_leave_trash()
        if self._plasma_current_path is not None:
            self._plasma_browse_history.append(self._plasma_current_path)
        self._plasma_current_path = path
        self._plasma_populate_places(path)

    def _plasma_open_external(self, path):
        """Open a file or special location (trash:///, network:///) externally."""
        try:
            subprocess.Popen(["xdg-open", path], start_new_session=True)
        except Exception:
            try:
                subprocess.Popen(["thunar", path], start_new_session=True)
            except Exception:
                pass
        self.hide_menu()

    def _on_plasma_back(self, _btn=None):
        if self._plasma_trash_mode:
            self._plasma_leave_trash()
            self._plasma_show_places()
            return
        if not self._plasma_browse_history:
            self._plasma_show_places()
            return
        self._plasma_current_path = self._plasma_browse_history.pop()
        self._plasma_populate_places(self._plasma_current_path)

    def _on_plasma_up(self, _btn=None):
        if self._plasma_trash_mode:
            self._plasma_leave_trash()
            self._plasma_show_places()
            return
        if self._plasma_current_path is None:
            self._plasma_show_places()
            return
        parent = os.path.dirname(self._plasma_current_path)
        if parent == self._plasma_current_path:
            return
        self._plasma_browse_history.append(self._plasma_current_path)
        self._plasma_current_path = parent
        self._plasma_populate_places(parent)

    def _plasma_show_places(self):
        """Reset the browser to Home as the default content view."""
        if self._plasma_trash_mode:
            self._plasma_leave_trash()
        self._plasma_browse_history = []
        self._plasma_current_path = None
        self._plasma_enter_dir(os.path.expanduser("~"))

    def _plasma_leave_trash(self):
        """Exit trash mode and hide the trash action buttons."""
        if not self._plasma_trash_mode:
            return
        self._plasma_trash_mode = False
        self._plasma_restore_btn.hide()
        self._plasma_empty_btn.hide()
        self._plasma_browse_list.set_activate_on_single_click(True)

    def _plasma_populate_places(self, path):
        """List the contents of *path* in the content pane (dirs first, then files)."""
        browse = getattr(self, "_plasma_browse_list", None)
        if browse is None:
            return
        for child in browse.get_children():
            browse.remove(child)
            child.destroy()
        try:
            entries = list(os.scandir(path))
        except OSError:
            entries = []
        dirs = [e for e in entries if e.is_dir(follow_symlinks=True)]
        files = [e for e in entries if not e.is_dir(follow_symlinks=True)]
        dirs.sort(key=lambda e: e.name.lower())
        files.sort(key=lambda e: e.name.lower())
        for entry in dirs:
            row = self._make_plasma_row(entry.name, "folder", entry.path)
            row.get_style_context().add_class("plasma-place-dir")
            browse.add(row)
        for entry in files:
            row = self._make_plasma_row(entry.name, self._plasma_file_icon(entry.name), entry.path)
            row.get_style_context().add_class("plasma-place-file")
            browse.add(row)
        if not entries:
            empty = Gtk.Label(label="(empty folder)", xalign=0)
            empty.get_style_context().add_class("plasma-empty")
            empty_row = Gtk.ListBoxRow()
            empty_row.get_style_context().add_class("plasma-place-row")
            empty_row.set_sensitive(False)
            empty_row.add(empty)
            browse.add(empty_row)
        browse.show_all()
        self._plasma_update_nav()

    # -- trash view -------------------------------------------------------

    def _plasma_enter_trash(self):
        """Show the trash contents in the content pane with restore/empty actions."""
        self._plasma_trash_mode = True
        self._plasma_current_path = None
        self._plasma_browse_history = []
        # Single-click selects an item; restore happens via the Restore button
        # or a double-click. Activating on single click would restore instantly.
        self._plasma_browse_list.set_activate_on_single_click(False)
        self._plasma_restore_btn.show()
        self._plasma_empty_btn.show()
        self._plasma_restore_btn.set_sensitive(False)
        self._plasma_populate_trash()

    def _plasma_populate_trash(self):
        browse = self._plasma_browse_list
        if browse is None:
            return
        for child in browse.get_children():
            browse.remove(child)
            child.destroy()
        items = _trash_items()
        for item in items:
            row = self._make_plasma_row(
                item["name"], "user-trash", item["path"]
            )
            row.get_style_context().add_class("plasma-place-file")
            row.trash_item = item
            if item["orig"]:
                row.set_tooltip_text(item["orig"])
            browse.add(row)
        if not items:
            empty = Gtk.Label(label="(trash is empty)", xalign=0)
            empty.get_style_context().add_class("plasma-empty")
            empty_row = Gtk.ListBoxRow()
            empty_row.get_style_context().add_class("plasma-place-row")
            empty_row.set_sensitive(False)
            empty_row.add(empty)
            browse.add(empty_row)
        browse.show_all()
        self._plasma_update_nav()
        self._plasma_restore_btn.set_sensitive(False)

    def _plasma_restore_selected(self):
        """Restore the currently selected trash item(s) to their original path."""
        rows = self._plasma_browse_list.get_selected_rows()
        restored = 0
        for row in rows:
            item = getattr(row, "trash_item", None)
            if not item or not item.get("orig"):
                continue
            if self._restore_trash_item(item):
                restored += 1
        if restored:
            self._plasma_populate_trash()

    def _restore_trash_item(self, item):
        """Move a single trashed file back to its original location."""
        dest = _safe_trash_restore_dest(item.get("orig") or "")
        if not dest:
            return False
        try:
            parent = os.path.dirname(dest)
            if parent:
                os.makedirs(parent, exist_ok=True)
            if os.path.exists(dest):
                dest = self._unique_dest(dest)
            shutil.move(item["path"], dest)
            if os.path.exists(item["info"]):
                os.remove(item["info"])
            return True
        except OSError:
            return False

    def _unique_dest(self, path):
        base, ext = os.path.splitext(path)
        counter = 1
        candidate = "%s.%d%s" % (base, counter, ext)
        while os.path.exists(candidate):
            counter += 1
            candidate = "%s.%d%s" % (base, counter, ext)
        return candidate

    def _on_plasma_restore(self, _btn=None):
        self._plasma_restore_selected()

    def _on_plasma_empty(self, _btn=None):
        """Confirm and permanently delete all trash contents."""
        if not self._confirm_empty_trash():
            return
        files_dir = os.path.join(TRASH_ROOT, "files")
        info_dir = os.path.join(TRASH_ROOT, "info")
        try:
            for name in os.listdir(files_dir):
                p = os.path.join(files_dir, name)
                if os.path.isdir(p) and not os.path.islink(p):
                    shutil.rmtree(p, ignore_errors=True)
                else:
                    try:
                        os.remove(p)
                    except OSError:
                        pass
            for name in os.listdir(info_dir):
                try:
                    os.remove(os.path.join(info_dir, name))
                except OSError:
                    pass
        except OSError:
            pass
        self._plasma_populate_trash()

    def _confirm_empty_trash(self):
        dialog = Gtk.MessageDialog(
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.NONE,
            text="Empty Trash?",
        )
        dialog.format_secondary_text(
            "All items in the trash will be permanently deleted. This cannot be undone."
        )
        dialog.get_style_context().add_class("confirm-dialog")
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        confirm = dialog.add_button("Empty Trash", Gtk.ResponseType.ACCEPT)
        confirm.get_style_context().add_class("confirm-accept")
        dialog.set_default_response(Gtk.ResponseType.CANCEL)
        center_layer_dialog(dialog)
        response = dialog.run()
        dialog.destroy()
        return response == Gtk.ResponseType.ACCEPT

    def _plasma_file_icon(self, name: str) -> str:
        ext = os.path.splitext(name)[1].lstrip(".").lower()
        if ext in {"png", "jpg", "jpeg", "webp", "gif", "svg", "bmp"}:
            return "image-x-generic"
        if ext in {"mp3", "wav", "flac", "ogg", "m4a"}:
            return "audio-x-generic"
        if ext in {"mp4", "mkv", "webm", "mov", "avi"}:
            return "video-x-generic"
        if ext in {"zip", "tar", "gz", "bz2", "xz", "7z", "rar"}:
            return "package-x-generic"
        if ext == "py":
            return "text-x-python"
        if ext == "sh":
            return "text-x-script"
        if ext == "pdf":
            return "application-pdf"
        return "text-x-generic"

    def _plasma_update_nav(self):
        """Refresh the browser nav bar (path label + back/up sensitivity)."""
        if not hasattr(self, "_plasma_back_btn"):
            return
        if self._plasma_trash_mode:
            self._plasma_path_label.set_text("Trash")
            self._plasma_back_btn.set_sensitive(False)
            self._plasma_up_btn.set_sensitive(False)
            return
        path = self._plasma_current_path
        if path is None:
            self._plasma_path_label.set_text("Computer")
            self._plasma_back_btn.set_sensitive(False)
            self._plasma_up_btn.set_sensitive(False)
        else:
            self._plasma_path_label.set_text(path)
            self._plasma_back_btn.set_sensitive(bool(self._plasma_browse_history))
            self._plasma_up_btn.set_sensitive(os.path.dirname(path) != path)

    def _on_plasma_tab(self, button, name):
        self._plasma_stack.set_visible_child_name(name)
        # Plain buttons: drive the active state via a CSS class.
        for key, btn in self._plasma_buttons.items():
            if key == name:
                btn.get_style_context().add_class("active")
            else:
                btn.get_style_context().remove_class("active")

    def _build_powerbar(self):
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        bar.get_style_context().add_class("powerbar")

        left = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        left.get_style_context().add_class("power-left")

        title = Gtk.Label(label="hyprtk-menu", xalign=0)
        title.get_style_context().add_class("power-title")
        left.pack_start(title, False, False, 0)

        self.settings_button = Gtk.Button()
        self.settings_button.get_style_context().add_class("menu-settings-btn")
        self.settings_button.set_tooltip_text("Menu settings")
        cog = Glyph("\uf013", "menu-settings-icon")
        cog.set_pixel_size(POWER_ICON_SIZE)
        self.settings_button.add(cog)
        self.settings_button.connect("clicked", self._open_settings)
        left.pack_start(self.settings_button, False, False, 0)

        bar.pack_start(left, True, True, 0)

        # Power buttons: always-visible fixed set (lock, logout, restart, shutdown).
        group = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        group.get_style_context().add_class("power-group")
        group.get_style_context().add_class("power-group-box")
        power = self.config.get("power", {})
        for action in ("lock", "logout", "reboot", "shutdown"):
            command = power.get(action)
            if not command:
                continue
            button = Gtk.Button()
            button.get_style_context().add_class("power-btn")
            if action in POWER_DANGER:
                button.get_style_context().add_class("power-danger")
            button.set_tooltip_text(action.capitalize())
            image = self._make_power_icon(action)
            button.add(image)
            button.connect("clicked", self._on_power, action)
            group.pack_start(button, False, False, 0)
        bar.pack_end(group, False, False, 0)

        # Corner resize grip
        grip = Gtk.EventBox()
        grip.get_style_context().add_class("resize-grip")
        grip.add_events(
            Gdk.EventMask.BUTTON_PRESS_MASK
            | Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.POINTER_MOTION_MASK
        )
        grip.set_tooltip_text("Drag to resize")
        grip_icon = Gtk.Label(label="\u2b0c")
        grip_icon.get_style_context().add_class("resize-grip-icon")
        grip.add(grip_icon)
        grip.connect("button-press-event", self._on_grip_press)
        grip.connect("button-release-event", self._on_grip_release)
        grip.connect("motion-notify-event", self._on_grip_motion)
        bar.pack_end(grip, False, False, 0)
        self.grip = grip
        return bar

    def _build_footer(self):
        """Shared bottom bar: user avatar (left) + powerbar (settings/power/resize)."""
        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        footer.get_style_context().add_class("menu-footer")
        avatar_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        avatar_box.get_style_context().add_class("menu-user")
        avatar = Gtk.Image.new_from_icon_name("avatar-default", Gtk.IconSize.MENU)
        avatar.get_style_context().add_class("menu-avatar")
        avatar_box.pack_start(avatar, False, False, 0)
        username = Gtk.Label(label=pwd.getpwuid(os.getuid()).pw_name, xalign=0)
        username.get_style_context().add_class("menu-username")
        avatar_box.pack_start(username, False, False, 0)
        footer.pack_start(avatar_box, False, False, 0)
        footer.pack_end(self._build_powerbar(), False, False, 0)
        return footer

    def _on_grip_press(self, _widget, event):
        if event.button == 1:
            self._resizing = True
            self._resize_start_w = self.get_allocated_width()
            self._resize_start_h = self.get_allocated_height()
            self._resize_start_x = event.x_root
            self._resize_start_y = event.y_root
            seat = Gdk.Display.get_default().get_default_seat()
            if seat:
                seat.grab(
                    self.grip.get_window(),
                    Gdk.SeatCapabilities.POINTER,
                    False,
                    None,
                    None,
                    None,
                    None,
                )
            return True
        return False

    def _on_grip_motion(self, _widget, event):
        if not self._resizing:
            return False
        dx = event.x_root - self._resize_start_x
        dy = event.y_root - self._resize_start_y
        new_w = max(int(self._resize_start_w + dx), 600)
        new_h = max(int(self._resize_start_h + dy), 400)
        self.set_size_request(new_w, new_h)
        return True

    def _on_grip_release(self, _widget, event):
        if self._resizing:
            self._resizing = False
            seat = Gdk.Display.get_default().get_default_seat()
            if seat:
                seat.ungrab()
            self._save_layout()
            return True
        return False

    def _on_clear_recents(self, _button):
        self.recents = []
        self.config["recents"] = []
        cfg.save_config(self.config)
        self._refresh_recents()
        self._refresh_apps()

    def _open_settings(self, _button):
        """Open the bar settings dialogue on its "Menu" page.

        hyprtk-menu's settings now live in the bar settings dialogue (the menu
        is owned by the bar process). If no bar-settings callback was wired
        (standalone/diagnostic use), fall back to the old floating window.
        """
        if self._on_settings is not None:
            self._on_settings()
            return
        win = getattr(self, "_settings_window", None)
        if win is not None:
            win.present()
            return

        win = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
        win.set_title("hyprtk-menu settings")
        win.set_decorated(False)
        win.set_keep_above(True)
        win.set_default_size(360, -1)
        win.get_style_context().add_class("menu-root")
        win.get_style_context().add_class("menu")
        win.get_style_context().add_class("settings-dialog")
        win.set_position(Gtk.WindowPosition.CENTER)
        win.connect("destroy", self._on_settings_closed)
        win.connect("key-press-event", self._on_settings_key)
        self._settings_window = win

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        vbox.get_style_context().add_class("settings-window")

        # Draggable header
        header = Gtk.EventBox()
        header.get_style_context().add_class("settings-header")
        header.connect("button-press-event", self._on_settings_header_press)
        title = Gtk.Label(label="Menu Settings")
        title.get_style_context().add_class("settings-title")
        header.add(title)
        vbox.pack_start(header, False, False, 0)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.get_style_context().add_class("settings-content")
        vbox.pack_start(content, True, True, 0)

        def _section_label(text):
            label = Gtk.Label(label=text, xalign=0)
            label.get_style_context().add_class("settings-section")
            return label

        # ── Menu theme: radio list (one selectable per theme) ──
        content.pack_start(_section_label("Menu Theme"), False, False, 0)
        theme_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        theme_box.get_style_context().add_class("settings-theme-list")
        layout = self.config.get("layout", "whisker")
        theme_radios = {}
        theme_group = None
        for name in LAYOUT_ORDER:
            radio = Gtk.RadioButton.new_with_label_from_widget(theme_group, name.capitalize())
            radio.get_style_context().add_class("settings-radio")
            if name == layout:
                radio.set_active(True)
            theme_group = radio
            theme_radios[name] = radio
            theme_box.pack_start(radio, False, False, 0)
        content.pack_start(theme_box, False, False, 0)

        # ── Alignment + position: visual display grid ──
        content.pack_start(_section_label("Position"), False, False, 0)
        position = self.config.get("position", "auto")

        # Auto option (follow hyprtk-bar edge)
        auto_radio = Gtk.RadioButton.new_with_label(
            None, "Auto (follow hyprtk-bar)"
        )
        auto_radio.get_style_context().add_class("settings-radio")
        if position == "auto":
            auto_radio.set_active(True)
        content.pack_start(auto_radio, False, False, 0)

        # Monitor grid: a display with a check point + name at each corner and center.
        grid = Gtk.Grid()
        grid.get_style_context().add_class("settings-monitor")
        grid.set_row_homogeneous(True)
        grid.set_column_homogeneous(True)
        grid.set_row_spacing(6)
        grid.set_column_spacing(6)
        position_radios = {}
        # (row, col) -> (position name, display label)
        cells = {
            (0, 0): ("top-left", "Top Left"),
            (0, 1): ("top-center", "Top Center"),
            (0, 2): ("top-right", "Top Right"),
            (1, 1): ("center", "Center"),
            (2, 0): ("bottom-left", "Bottom Left"),
            (2, 1): ("bottom-center", "Bottom Center"),
            (2, 2): ("bottom-right", "Bottom Right"),
        }
        for (row, col), (name, label) in cells.items():
            cell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            cell.get_style_context().add_class("settings-pos-cell")
            radio = Gtk.RadioButton.new_with_label_from_widget(auto_radio, "")
            radio.get_style_context().add_class("settings-pos-radio")
            text = Gtk.Label(label=label, xalign=0.5)
            text.get_style_context().add_class("settings-pos-label")
            cell.pack_start(radio, False, False, 0)
            cell.pack_start(text, False, False, 0)
            if position == name:
                radio.set_active(True)
            position_radios[name] = radio
            grid.attach(cell, col, row, 1, 1)
        grid.set_size_request(220, 140)
        content.pack_start(grid, False, False, 0)

        # ── Spacing: menu-to-bar and menu-to-screen-edge gaps ──
        content.pack_start(_section_label("Spacing"), False, False, 0)
        spacing_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)

        gap_in_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        gap_in_label = Gtk.Label(label="Gap in:", xalign=1)
        gap_in_label.set_size_request(70, -1)
        gap_in_label.get_style_context().add_class("settings-radio")
        self._gap_in = Gtk.SpinButton.new_with_range(0, 60, 2)
        self._gap_in.set_value(_gap_value(self.config.get("gap_in"), 4))
        gap_in_hint = Gtk.Label(label="px — menu to bar", xalign=0)
        gap_in_hint.set_opacity(0.7)
        gap_in_row.pack_start(gap_in_label, False, False, 0)
        gap_in_row.pack_start(self._gap_in, True, True, 0)
        gap_in_row.pack_start(gap_in_hint, False, False, 0)

        gap_out_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        gap_out_label = Gtk.Label(label="Gap out:", xalign=1)
        gap_out_label.set_size_request(70, -1)
        gap_out_label.get_style_context().add_class("settings-radio")
        self._gap_out = Gtk.SpinButton.new_with_range(0, 60, 2)
        self._gap_out.set_value(_gap_value(self.config.get("gap_out"), 5))
        gap_out_hint = Gtk.Label(label="px — menu to screen edge", xalign=0)
        gap_out_hint.set_opacity(0.7)
        gap_out_row.pack_start(gap_out_label, False, False, 0)
        gap_out_row.pack_start(self._gap_out, True, True, 0)
        gap_out_row.pack_start(gap_out_hint, False, False, 0)

        spacing_box.pack_start(gap_in_row, False, False, 0)
        spacing_box.pack_start(gap_out_row, False, False, 0)
        content.pack_start(spacing_box, False, False, 0)

        # Buttons
        buttons = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        buttons.get_style_context().add_class("settings-buttons")
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.get_style_context().add_class("settings-cancel")
        cancel_btn.connect("clicked", lambda *_: win.destroy())
        apply_btn = Gtk.Button(label="Apply")
        apply_btn.get_style_context().add_class("settings-apply")
        apply_btn.connect(
            "clicked",
            lambda *_: self._apply_settings(
                win, theme_radios, auto_radio, position_radios
            ),
        )
        buttons.pack_end(apply_btn, False, False, 0)
        buttons.pack_end(cancel_btn, False, False, 0)
        vbox.pack_end(buttons, False, False, 0)

        win.add(vbox)
        win.show_all()
        apply_btn.set_can_default(True)
        apply_btn.grab_default()

    def _on_settings_header_press(self, _widget, event):
        """Allow dragging the frameless settings window by its header."""
        if event.button == 1 and event.type == Gdk.EventType.BUTTON_PRESS:
            self._settings_window.begin_move_drag(
                event.button, int(event.x_root), int(event.y_root), event.time
            )
            return True
        return False

    def _on_settings_key(self, _win, event):
        if event.keyval == Gdk.KEY_Escape:
            self._settings_window.destroy()
            return True
        return False

    def _on_settings_closed(self, *_):
        self._settings_window = None

    def _apply_settings(self, win, theme_radios, auto_radio, position_radios):
        new_layout = next(
            (name for name, radio in theme_radios.items() if radio.get_active()),
            "whisker",
        )
        if auto_radio.get_active():
            new_position = "auto"
        else:
            new_position = next(
                (name for name, radio in position_radios.items() if radio.get_active()),
                "top-left",
            )

        # Derive horizontal alignment from the chosen corner, for auto mode.
        if new_position == "auto":
            new_align = self.config.get("align", "left")
        elif new_position == "center":
            new_align = "center"
        elif new_position.endswith("-left"):
            new_align = "left"
        elif new_position.endswith("-right"):
            new_align = "right"
        else:
            new_align = "center"

        old_layout = self.config.get("layout", "whisker")
        self.config["layout"] = new_layout
        self.config["align"] = new_align
        self.config["position"] = new_position
        if hasattr(self, "_gap_in"):
            self.config["gap_in"] = max(0, int(self._gap_in.get_value()))
        if hasattr(self, "_gap_out"):
            self.config["gap_out"] = max(0, int(self._gap_out.get_value()))
        cfg.save_config(self.config)

        if new_layout != old_layout:
            self._apply_layout_class()
            try:
                apply_css(build_css())
            except Exception as exc:
                print("hyprtk-menu: layout css update failed: %s" % exc, flush=True)
            was_visible = self.get_visible()
            if was_visible:
                GLib.idle_add(self._rebuild_ui)
            else:
                self._rebuild_ui()
        else:
            self.reposition()

    def _apply_layout_class(self):
        layout = self.config.get("layout", "whisker")
        if layout not in LAYOUT_ORDER:
            layout = "whisker"
        for name in LAYOUT_ORDER:
            self.get_style_context().remove_class("layout-%s" % name)
        self.get_style_context().add_class("layout-%s" % layout)

    def _apply_layout_tweaks(self):
        """CSS-impossible per-layout tweaks. Called on open and layout change."""
        layout = self.config.get("layout", "whisker")
        if layout == "win11":
            self.search.set_placeholder_text("Search for apps, settings, and documents...")
        else:
            self.search.set_placeholder_text("Search applications...")

    # -- helpers ----------------------------------------------------------

    def _make_power_icon(self, action, pixel_size=POWER_ICON_SIZE):
        """Nerd Font glyph for a power action (matches the bar's icon style)."""
        glyph = Glyph(POWER_GLYPH.get(action, "\uf011"), "power-icon")
        glyph.set_pixel_size(pixel_size)
        return glyph

    def _make_icon_image(self, entry, pixel_size):
        icon = entry.icon
        if icon is None:
            return Gtk.Image.new_from_icon_name(
                "application-x-executable", Gtk.IconSize.DND
            )
        image = Gtk.Image.new_from_gicon(icon, Gtk.IconSize.DND)
        image.set_pixel_size(pixel_size)
        return image

    def _make_row(self, entry, icon_size=32):
        row = Gtk.ListBoxRow()
        row.get_style_context().add_class("app-row")
        row.entry = entry

        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        image = self._make_icon_image(entry, icon_size)
        image.get_style_context().add_class("app-icon")
        hbox.pack_start(image, False, False, 0)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        name = Gtk.Label(
            label=entry.name,
            xalign=0,
            ellipsize=Pango.EllipsizeMode.END,
        )
        name.get_style_context().add_class("app-name")
        vbox.pack_start(name, False, False, 0)
        if entry.comment:
            desc = Gtk.Label(
                label=entry.comment,
                xalign=0,
                ellipsize=Pango.EllipsizeMode.END,
            )
            desc.get_style_context().add_class("app-desc")
            vbox.pack_start(desc, False, False, 0)
        hbox.pack_start(vbox, True, True, 0)
        row.add(hbox)
        return row

    def _visible_apps(self):
        query = self.search.get_text().strip()
        if query:
            return [entry for entry in self.apps if entry.matches(query)]

        category = self.current_category
        if category == "Favorites":
            return [entry for entry in self.apps if entry.id in self.pinned]
        if category == "Recently Used":
            by_id = {entry.id: entry for entry in self.apps}
            return [by_id[item] for item in self.recents if item in by_id]

        if category == "All":
            return list(self.apps)
        return [entry for entry in self.apps if category in entry.categories]

    # -- refresh ----------------------------------------------------------

    def _refresh_favorites(self):
        # Win11 pinned grid populates regardless of fav_row
        if hasattr(self, "_win11_pinned_grid"):
            self._refresh_win11_pinned()
        if not hasattr(self, "fav_row"):
            return
        for child in self.fav_row.get_children():
            self.fav_row.remove(child)
            child.destroy()
        for entry in self.apps:
            if entry.id not in self.pinned:
                continue
            button = Gtk.Button()
            button.get_style_context().add_class("fav-btn")
            image = self._make_icon_image(entry, 26)
            button.add(image)
            button.set_tooltip_text(entry.name)
            button.connect("clicked", self._on_fav_clicked, entry)
            self.fav_row.add(button)
        self.fav_row.set_visible(bool(self.pinned))
        self.fav_row.show_all()

    def _refresh_apps(self):
        if not hasattr(self, "app_list"):
            return
        # Cache rows per entry so icons load once instead of once per keystroke.
        # Rows are reparented (remove + add), never destroyed, so search just
        # reshuffles existing widgets rather than reloading every app icon.
        for child in list(self.app_list.get_children()):
            self.app_list.remove(child)
        for entry in self._visible_apps():
            row = self._app_rows.get(entry.id)
            if row is None:
                row = self._make_row(entry)
                self._app_rows[entry.id] = row
            self.app_list.add(row)
        self.app_list.show_all()
        if self.app_list.get_children():
            self.app_list.select_row(self.app_list.get_row_at_index(0))

    # -- actions ----------------------------------------------------------

    def _launch(self, entry):
        if apps.launch_app(entry):
            self.recents = [entry.id] + [
                item for item in self.recents if item != entry.id
            ]
            self.recents = self.recents[: int(self.config.get("max_recents", 10))]
            self.config["recents"] = self.recents
            cfg.save_config(self.config)
        self.hide_menu()

    def _toggle_pin(self, entry):
        if entry.id in self.pinned:
            self.pinned.discard(entry.id)
        else:
            self.pinned.add(entry.id)
        self.config["favorites"] = sorted(self.pinned)
        cfg.save_config(self.config)
        self._refresh_favorites()
        self._refresh_apps()

    # -- signals ----------------------------------------------------------

    def _on_search_changed(self, _widget):
        self._refresh_apps()
        if hasattr(self, "_win11_app_scroll"):
            if self.search.get_text().strip():
                self._show_win11_apps()
            else:
                self._show_win11_home()

    def _on_search_key(self, _widget, event):
        if event.keyval in (Gdk.KEY_Up, Gdk.KEY_Down):
            rows = self.app_list.get_children()
            if not rows:
                return True
            selected = self.app_list.get_selected_row()
            index = rows.index(selected) if selected in rows else 0
            if event.keyval == Gdk.KEY_Down:
                index = (index + 1) % len(rows)
            else:
                index = (index - 1) % len(rows)
            self.app_list.select_row(rows[index])
            self.app_list.scroll_to_row(rows[index])
            return True
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            row = self.app_list.get_selected_row()
            if row:
                entry = getattr(row, "entry", None)
                if entry:
                    self._launch(entry)
            return True
        return False

    def _on_window_key(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.hide_menu()
            return True
        if event.keyval == Gdk.KEY_F and event.state & Gdk.ModifierType.CONTROL_MASK:
            self.search.grab_focus()
            self.search.select_region(0, -1)
            return True
        return False

    def _on_category_activated(self, _sidebar, row):
        category = getattr(row, "category", None)
        if not category:
            return
        self.current_category = category
        if hasattr(self, "sidebar"):
            for child in self.sidebar.get_children():
                if child is row:
                    child.get_style_context().add_class("selected")
                else:
                    child.get_style_context().remove_class("selected")
        self._refresh_apps()

    def _on_app_activated(self, _listbox, row):
        entry = getattr(row, "entry", None)
        if entry:
            self._launch(entry)

    def _on_app_button(self, _widget, event):
        if event.button == 3:  # right-click: pin/unpin
            row = self.app_list.get_row_at_y(int(event.y))
            if row:
                entry = getattr(row, "entry", None)
                if entry:
                    self._toggle_pin(entry)
            return True
        return False

    def _on_fav_clicked(self, _button, entry):
        self._launch(entry)

    def _on_power(self, _button, action):
        command = self.config.get("power", {}).get(action)
        if not command:
            return
        if action in POWER_CONFIRM and not self._confirm_power(action):
            return
        # Power commands are the USER'S OWN config strings and legitimately use
        # shell operators (default lock is `pidof swaylock hyprlock ||
        # swaylock || hyprlock`), so run them through one explicit `sh -c`.
        # This is trusted input (the user's config), NOT an untrusted surface.
        _spawn_argv(["/bin/sh", "-c", command])
        self.hide_menu()

    def _confirm_power(self, action):
        """Ask before running a destructive power action. Returns bool."""
        title = CONFIRM_LABELS.get(action, action.capitalize())
        dialog = Gtk.MessageDialog(
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.NONE,
            text="%s?" % title,
        )
        dialog.format_secondary_text(
            "Are you sure you want to %s? Any unsaved work will be lost."
            % title.lower()
        )
        dialog.get_style_context().add_class("confirm-dialog")
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        confirm = dialog.add_button(title, Gtk.ResponseType.ACCEPT)
        confirm.get_style_context().add_class("confirm-accept")
        dialog.set_default_response(Gtk.ResponseType.CANCEL)
        center_layer_dialog(dialog)
        response = dialog.run()
        dialog.destroy()
        return response == Gtk.ResponseType.ACCEPT

    # -- show / hide ------------------------------------------------------

    def _check_wal(self):
        """Live-update the menu palette (pywal + bar theme) while open."""
        changed = False
        wal_mtime = theme.wal_mtime()
        if wal_mtime and wal_mtime != self._wal_mtime:
            self._wal_mtime = wal_mtime
            changed = True
        bar_mtime = theme.bar_config_mtime()
        if bar_mtime != self._bar_cfg_prev:
            self._bar_cfg_prev = bar_mtime
            changed = True
        themes_mtime = theme.themes_dir_mtime()
        if themes_mtime != self._themes_dir_prev:
            self._themes_dir_prev = themes_mtime
            changed = True
        if not changed:
            return True

        was_visible = self.get_visible()
        if was_visible:
            # Hide first so re-anchoring happens on an unmapped surface.
            self.hide()
        try:
            apply_css(build_css())
        except Exception as exc:
            print("hyprtk-menu: theme css update failed: %s" % exc, flush=True)
        else:
            print("hyprtk-menu: theme updated", flush=True)
        # The bar edge/width/align/height may have changed too — re-anchor.
        self._apply_position()
        if was_visible:
            GLib.idle_add(self._remap_after_update)
        return True

    def _remap_after_update(self):
        self.hide()
        self.show_all()
        if hasattr(self, "_reapply_win11_view"):
            self._reapply_win11_view()
        self.present()
        GLib.idle_add(self.search.grab_focus)
        return False

    # -- border animation --------------------------------------------------

    def _start_border_animation(self):
        """Start the panel-border animation if the bar has one enabled.

        Interpolates between Hyprland's two ``active_border`` colours
        (``color11`` + ``color4``) on a ping-pong loop — mirroring the
        borderangle gradient, not a full hue wheel.
        """
        if self._border_anim_id is not None:
            return
        self._border_anim_period = border_period_ms()
        if self._border_anim_period is None:
            return
        colors = active_border_colors()
        if not colors:
            return
        self._border_colors = colors
        self._border_hue = 0.0
        self._border_anim_id = GLib.timeout_add(66, self._border_anim_tick)

    def _stop_border_animation(self):
        if self._border_anim_id is not None:
            GLib.source_remove(self._border_anim_id)
            self._border_anim_id = None

    def _border_anim_tick(self):
        """Advance the border blend and re-render with the animated color."""
        if self._border_anim_period is None:
            return False
        # ~15fps tick: a slow border blend needs no more (cheaper CSS update).
        self._border_hue = (self._border_hue + 66.0 / (self._border_anim_period / 2.0)) % 2.0
        t = self._border_hue if self._border_hue <= 1.0 else 2.0 - self._border_hue
        color = lerp_color(self._border_colors[0], self._border_colors[1], t)
        if color == getattr(self, "_border_last_color", None):
            return True
        self._border_last_color = color
        try:
            apply_border_color(color)
        except Exception as exc:
            print("hyprtk-menu: border animation update failed: %s" % exc, flush=True)
            return False
        return True

    def show_menu(self):
        if not self._enabled():
            return
        self._apply_position()
        self._apply_layout_tweaks()
        self._refresh_favorites()
        self._refresh_apps()
        self._refresh_recents()
        if hasattr(self, "_plasma_places"):
            self._plasma_show_places()
        self.show_all()
        if hasattr(self, "_reapply_win11_view"):
            self._reapply_win11_view()
        self.present()
        if not self._layout_initialized:
            self._layout_initialized = True
            GLib.idle_add(self._apply_saved_layout)
        GLib.idle_add(self.search.grab_focus)
        self._start_border_animation()

    def hide_menu(self):
        self._stop_border_animation()
        self.hide()
        self.search.set_text("")
        self.current_category = "All"
        if getattr(self, "_settings_window", None) is not None:
            self._settings_window.destroy()
        if hasattr(self, "sidebar"):
            for child in self.sidebar.get_children():
                if getattr(child, "category", None) == "All":
                    child.get_style_context().add_class("selected")
                else:
                    child.get_style_context().remove_class("selected")

    def toggle(self):
        if not self._enabled():
            return
        if self.get_visible():
            self.hide_menu()
        else:
            self.show_menu()

    def _enabled(self) -> bool:
        """Whether the menu module is enabled (menu.enabled in the bar config)."""
        return bool((self._bar_cfg.get("menu") or {}).get("enabled", True))

    def reposition(self):
        """Re-apply anchoring after the user changes alignment."""
        self.config = cfg.load_config()
        was_visible = self.get_visible()
        self._apply_position()
        if was_visible:
            GLib.idle_add(self._remap_after_update)

    def reload_from_cfg(self):
        """Rebuild/re-theme after the bar settings edited the ``menu`` block.

        The bar settings dialogue mutates the shared bar config and calls this
        (via the bar's ``set_menu`` action) so layout/position/alignment/gaps
        apply live — mirroring how the arc menu reloads after its settings.
        When ``menu.enabled`` was switched off the menu hides and stays hidden
        (toggle no-ops) until re-enabled.
        """
        self.config = cfg.load_config()
        if not self._enabled():
            self.hide_menu()
            return
        new_layout = self.config.get("layout", "whisker")
        old_layout = getattr(self, "_layout_name", None)
        self._layout_name = new_layout
        self._apply_layout_class()
        try:
            apply_css(build_css())
        except Exception as exc:
            print("hyprtk-menu: layout css update failed: %s" % exc, flush=True)
        was_visible = self.get_visible()
        if new_layout != old_layout and old_layout is not None:
            self._rebuild_ui()
            if not was_visible:
                self.hide_menu()
        else:
            self._apply_position()
            if was_visible:
                self._remap_after_update()
