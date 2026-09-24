"""The bar: a horizontal taskbar with left/center/right module sections.

Layout (inside the transparent layer-shell surface):

    [ left spacer ][ pill (left | centered | right sections) ]

The pill carries the background/rounded corners and is composed of three
sections (left/center/right) populated from the config's ``layout``.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · bar
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import os

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib, Gtk  # noqa: E402

from . import config as config_module  # noqa: E402
from . import proc  # noqa: E402
from .clock import Clock  # noqa: E402
from .config import DEFAULT_LAYOUT, icon_size_for  # noqa: E402
from .kbstate import KbState  # noqa: E402
from .layout import SECTION_ORDER, SectionBox  # noqa: E402
from .notifications import NotificationCenterButton  # noqa: E402
from .popup import bind_hover_tooltip  # noqa: E402
from .quicksettings import QuickSettingsButton  # noqa: E402
from .quicklinks import QuickLinks  # noqa: E402
from .sysmon import SysMon  # noqa: E402
from .tasklist import TaskList  # noqa: E402
from .tray import Tray, TrayController  # noqa: E402
from .updates import Updates  # noqa: E402
from .widgets import Glyph, HoverButton, spawn  # noqa: E402
from .window import Window  # noqa: E402
from .workspaces import Workspaces  # noqa: E402

log = logging.getLogger("hyprtk_bar.bar")


class StartButton(HoverButton):
    def __init__(self, cfg: dict, ipc, bar):
        super().__init__("task-button start", vertical=True, spacing=2)
        center = cfg.get("center") or {}
        self._ipc = ipc
        self._bar = bar
        self._command = center.get("start_command", "~/.local/bin/hyprtk-bar-menu-toggle.sh")
        font_cfg = cfg.get("font") or {}
        glyph = Glyph(center.get("start_glyph", "\uf015"), "accent-icon")
        glyph.set_pixel_size(
            icon_size_for(font_cfg.get("size", 16), font_cfg.get("icon_size", 0))
        )
        self._icon = glyph
        self.box.pack_start(self._icon, True, True, 0)
        # Keep the start icon clear of the bar's left edge, with the same
        # breathing room as the spacing between the other modules.
        self.set_margin_start(6)
        bind_hover_tooltip(self, cfg, lambda: "Open menu")

    def apply_font(self, font_size, icon_size=0) -> None:
        self._icon.set_pixel_size(icon_size_for(font_size, icon_size))

    def _on_button_press(self, _widget, event):
        if event.button == 1:
            toggle = self._bar._menu_cb
            if toggle is not None:
                toggle()
            elif (self._bar._cfg.get("menu") or {}).get("enabled", True):
                # No in-process menu callback (e.g. standalone fallback) — spawn
                # the configured command instead.
                if not spawn(self._command):
                    log.warning("Failed to launch start menu %r", self._command)
        return True


class ClipBox(Gtk.EventBox):
    """Clip the pill's content to the pill's own box.

    A GTK box propagates its minimum size up to the window, so the bar's layer
    surface could never be narrower than the modules' total — on a small display
    it grew wider than the monitor and extended off the right edge. This reports
    a 0 minimum so the surface fits the monitor: the child keeps its minimum
    width and overflows when the configured width is genuinely smaller than the
    content.

    The overflow must not be visible outside the bar's border. This widget owns
    the ``.taskbar`` background (and its margins/rounded ends) and has its own
    GdkWindow, so GTK clips the child's drawing to the pill — content overflows
    only as far as the border, never into the surface's margin.
    """

    def __init__(self):
        super().__init__()
        self.set_visible_window(True)

    def do_get_preferred_width(self):
        child = self.get_child()
        natural = child.get_preferred_width()[1] if child is not None else 0
        return 0, natural


class Bar(Gtk.Box):
    def __init__(self, cfg: dict, ipc, is_primary: bool = True, notif_ctrl=None):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL)
        self._cfg = cfg
        self._ipc = ipc
        self._is_primary = is_primary
        self._notif_ctrl = notif_ctrl
        self._theme_cb = None
        self._height_cb = None
        self._position_cb = None
        self._arcmenu_cb = None
        self._menu_cb = None
        self._menu_reload_cb = None
        self._widgets_cb = None
        self._widgets: dict[str, Gtk.Widget] = {}
        self._sections: dict[str, SectionBox] = {}
        self._tray_ctrl: TrayController | None = None
        self._settings_win = None
        self._width = cfg.get("width", "100%")
        self._align = cfg.get("align", "center")
        self._max_total = 0
        self._pending_total: int | None = None
        self._width_idle: int | None = None
        # Fit-to-width content scale: 1.0 (no scaling) unless the configured
        # width is smaller than the modules' natural width, in which case the
        # glyphs/icons (and CSS font size) shrink so every module stays visible
        # instead of being clipped.
        self._content_scale = 1.0
        self._scale_min = 0.35
        self._pill_spacing = 8

        self.pill = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=self._pill_spacing)
        self.pill.set_hexpand(True)
        self.pill.set_halign(Gtk.Align.FILL)
        # ClipBox owns the .taskbar background (+ margins/rounded ends) and
        # clips the content to the pill: the bar's surface may be narrower than
        # the pill's content, and the overflow must not spill outside the border.
        self.pill_clip = ClipBox()
        self.pill_clip.get_style_context().add_class("taskbar")
        self.pill_clip.set_hexpand(True)
        self.pill_clip.set_halign(Gtk.Align.FILL)
        self.pill_clip.add(self.pill)
        self.pack_start(self.pill_clip, True, True, 0)

        for section_id in SECTION_ORDER:
            section = SectionBox(section_id, self)
            self._sections[section_id] = section
            # The left/right sections are given EQUAL widths (_balance_sections)
            # so the center's midpoint stays the pill's midpoint, but without the
            # wasted space of fully homogeneous cells (which size every cell to
            # the widest one). The center expands to take the rest.
            is_center = section_id == "center"
            section.set_hexpand(is_center)
            if is_center:
                section.box.set_halign(Gtk.Align.CENTER)
            elif section_id == "right":
                section.box.set_halign(Gtk.Align.END)
            else:
                section.box.set_halign(Gtk.Align.START)
            self.pill.pack_start(section, is_center, is_center, 0)

        self.connect("size-allocate", self._on_bar_size_allocate)
        self._apply_width()

        self._build_layout(cfg.get("layout") or DEFAULT_LAYOUT)

    # ── width & alignment ────────────────────────────────────────

    def _on_bar_size_allocate(self, _widget, allocation, *_args) -> None:
        # Defer geometry changes out of the size-allocate pass (applying them
        # inline is overridden by the pass that already computed sizes).
        self._pending_total = allocation.width
        if self._width_idle is None:
            self._width_idle = GLib.idle_add(self._apply_width_idle)

    def _apply_width_idle(self) -> bool:
        self._width_idle = None
        if self._pending_total is not None:
            self._apply_width(self._pending_total)
        return GLib.SOURCE_REMOVE

    def _width_px(self, total: int) -> int:
        width = self._width
        if isinstance(width, str):
            s = width.strip()
            if s.endswith("%"):
                try:
                    frac = float(s.rstrip("%")) / 100.0
                except ValueError:
                    return 0
                return int(total * max(0.0, min(1.0, frac)))
            if s.endswith("px"):
                s = s[:-2].strip()
            try:
                return int(float(s))
            except ValueError:
                return 0
        try:
            return int(width)
        except (TypeError, ValueError):
            return 0

    def _monitor_width(self) -> int:
        """The bar monitor's width — the stable base for percentage widths.

        The bar's own allocation shrinks when the surface is narrowed, so it
        must NOT be used as the percentage base (that would collapse: 50% of
        50% of …). The Gdk monitor geometry stays constant.
        """
        win = self.get_toplevel()
        monitor = getattr(win, "monitor", None)
        if monitor is not None:
            try:
                return monitor.get_geometry().width
            except Exception:
                pass
        return self.get_allocated_width()

    def _apply_width(self, total: int | None = None) -> None:
        """Constrain the bar to the configured width (px or %), aligned.

        The width is applied to the layer SURFACE (via left/right margins), not
        to the pill: the pill has a minimum width (~its content), so shrinking
        it fails on displays narrower than that minimum. The surface width is
        set by the compositor, so small widths work; the content is scaled
        down to fit (see _update_content_scale) and only clipped if even the
        minimum scale cannot fit it.

        The percentage base is the MONITOR width, not the (shrinking) surface
        allocation — using the allocation collapses it (50% of 50% of …) which
        showed up as the bar flickering narrower on hover.
        """
        observed = total if (total and total > 0) else self.get_allocated_width()
        if observed > self._max_total:
            self._max_total = observed
        monitor_w = self._monitor_width()
        if monitor_w <= 0:
            monitor_w = self._max_total
        if monitor_w <= 0:
            monitor_w = observed
        px = self._width_px(monitor_w)

        toplevel = self.get_toplevel()
        set_width = getattr(toplevel, "set_surface_width", None)
        if set_width is not None:
            set_width(px, monitor_w, self._align)

        # The pill always fills the surface; the surface carries the width.
        self.pill.set_hexpand(True)
        self.pill.set_halign(Gtk.Align.FILL)
        self.pill.set_size_request(-1, -1)

        self._update_content_scale(px)

    # ── fit-to-width content scale ──────────────────────────────

    def content_scale(self) -> float:
        """Current fit-to-width content scale (1.0 = no scaling)."""
        return self._content_scale

    def _update_content_scale(self, px: int) -> None:
        """Shrink the content so it fits *px*, keeping every module visible.

        The modules have a natural width at scale 1. When the configured width
        is smaller, scale the glyphs/icons and the CSS font size down so the
        whole cluster still fits inside the border (rather than being clipped).
        The natural width changes with the scale, so solve iteratively; the
        0.02 epsilon stops it once it has converged.
        """
        if px <= 0:
            return
        self._balance_sections()
        natural = self.pill.get_preferred_width()[1]
        if natural <= 0:
            return
        target = (px * self._content_scale) / natural
        target = max(self._scale_min, min(1.0, target))
        # Damp the step: the natural width has a fixed part (spacing/padding), so
        # the naive solve can overshoot; a half-step converges stably.
        new = self._content_scale + 0.5 * (target - self._content_scale)
        new = max(self._scale_min, min(1.0, new))
        if abs(new - self._content_scale) < 0.01:
            return
        self._content_scale = new
        self._apply_content_spacing()
        if self._theme_cb is not None:
            self._theme_cb()

    def _balance_sections(self) -> None:
        """Give the left/right sections equal width so the center stays centered.

        Fully homogeneous cells size every cell to the widest one, which wastes
        ~2x the space and forces the fit-to-width scale far lower than needed.
        Equal left/right widths keep the center's midpoint at the pill's
        midpoint while letting the center take the remaining space.
        """
        left = self._sections.get("left")
        right = self._sections.get("right")
        if left is None or right is None:
            return
        # Use the inner box's natural width: the SectionBox's own preferred
        # width is pinned by the size_request we set, which would otherwise
        # freeze the balance at its first value.
        w = max(
            left.box.get_preferred_width()[1],
            right.box.get_preferred_width()[1],
        )
        if getattr(self, "_balanced_w", None) == w:
            return
        self._balanced_w = w
        left.set_size_request(w, -1)
        right.set_size_request(w, -1)

    def _apply_content_spacing(self) -> None:
        """Scale the pill's inter-module gap with the content scale."""
        self.pill.set_spacing(max(2, int(round(self._pill_spacing * self._content_scale))))

    # ── layout ──────────────────────────────────────────────────

    def _build_layout(self, layout: dict) -> None:
        """Empty all sections and repack the module widgets per ``layout``."""
        for section_id in SECTION_ORDER:
            box = self._sections[section_id].box
            for child in list(box.get_children()):
                box.remove(child)
        for section_id in SECTION_ORDER:
            for mid in layout.get(section_id, []):
                widget = self._ensure_module(mid)
                if widget is not None:
                    widget.set_valign(Gtk.Align.CENTER)
                    self._sections[section_id].box.pack_start(widget, False, False, 0)

    def _ensure_module(self, mid: str) -> Gtk.Widget | None:
        if mid in self._widgets:
            return self._widgets[mid]
        widget = self._build_widget(mid)
        if widget is None:
            return None
        self._widgets[mid] = widget
        # A freshly-built widget is created hidden; the initial build relies on
        # the window's show_all(), but a mid-session rebuild (e.g. re-enabling a
        # module) packs it into an already-shown box, so it must be shown here
        # or it stays invisible until the next reload.
        widget.show_all()
        return widget

    def _build_widget(self, mid: str) -> Gtk.Widget | None:
        cfg, ipc = self._cfg, self._ipc
        if mid == "start_button":
            return StartButton(cfg, ipc, self)
        if mid == "quicklinks":
            return QuickLinks(cfg, ipc, restart_cb=self.restart, theme_cb=self.apply_theme)
        if mid == "workspaces":
            return Workspaces(cfg, ipc)
        if mid == "tasklist":
            return TaskList(
                cfg,
                ipc,
                reload_cb=self.reload_config,
                restart_cb=self.restart,
            )
        if mid == "window":
            return Window(cfg, ipc)
        if mid == "sysmon":
            return SysMon(cfg, ipc)
        if mid == "updates":
            return Updates(cfg, ipc)
        if mid == "kbstate":
            return KbState(cfg, ipc)
        if mid == "clock":
            return Clock(cfg, ipc)
        if mid == "notifications":
            if self._notif_ctrl is None:
                return None
            return NotificationCenterButton(cfg, self._notif_ctrl)
        if mid == "tray":
            if not self._is_primary:
                # Only the primary monitor hosts the SNI tray: a second watcher
                # would fight over the org.kde.StatusNotifierWatcher name.
                return None
            tray = Tray(cfg)
            if self._tray_ctrl is None:
                self._tray_ctrl = TrayController(cfg, tray)
            else:  # rebind a fresh widget and re-add any live items
                self._tray_ctrl._tray = tray
                for key, item in list(self._tray_ctrl._items.items()):
                    tray.set_item(key, item)
            return tray
        if mid == "quicksettings":
            return QuickSettingsButton(cfg)
        log.warning("unknown module id %r", mid)
        return None

    def rebuild_layout(self) -> None:
        self._build_layout(self._cfg.get("layout") or DEFAULT_LAYOUT)

    def reload_config(self) -> None:
        """Reload config from disk into the SHARED cfg dict in place.

        The window's _cfg is the same object, so a fresh dict assignment would
        be invisible to the theme/layer callbacks.
        """
        cfg = self._cfg
        fresh = config_module.load()
        cfg.clear()
        cfg.update(fresh)
        self._width = str(cfg.get("width", "100%"))
        self._align = cfg.get("align", "center")
        self.rebuild_layout()
        if self._theme_cb is not None:
            self._theme_cb()
        self._apply_width()
        if self._height_cb is not None:
            self._height_cb()
        if self._position_cb is not None:
            self._position_cb()

    def restart(self) -> None:
        """Spawn a fresh bar and exit this one.

        The single-instance flock means a new process can only start once this
        one has released it, so the replacement is launched after a short delay
        and then this instance quits.
        """
        launcher = os.path.expanduser("~/.local/bin/hyprtk-bar")
        # One explicit sh -c; the launcher path is passed as a positional
        # argument ($@), never string-interpolated into the script, so
        # spaces/quotes in $HOME are safe.
        if not proc.spawn_argv(["/bin/sh", "-c", 'sleep 1; exec "$@"', "sh", launcher]):
            return
        GLib.timeout_add(200, lambda: Gtk.main_quit() or False)

    def apply_palette_layout(self, palette: dict) -> None:
        """Apply theme-derived layout (module spacing) to the bar sections."""
        self._apply_content_spacing()
        spacing = palette.get("spacing")
        if spacing is None:
            return
        s = max(0, int(round(spacing * self._content_scale)))
        for section in self._sections.values():
            section.box.set_spacing(s)

    def apply_font(self, font_size, icon_size=0) -> None:
        """Scale module icons to the configured font/icon sizes."""
        if not font_size:
            return
        for widget in self._widgets.values():
            apply = getattr(widget, "apply_font", None)
            if apply is not None:
                try:
                    apply(font_size, icon_size)
                except Exception:
                    log.exception("apply_font failed on %r", widget)

    # ── bar menu ────────────────────────────────────────────────

    def show_bar_menu(self, event) -> None:
        from .bar_menu import build_bar_menu
        menu = build_bar_menu(self._cfg, self._menu_actions())
        menu.show_all()
        menu.popup_at_pointer(event)

    def open_settings(self, initial_page: str | None = None) -> None:
        from .bar_settings import BarSettings
        if self._settings_win is None or not self._settings_win.get_visible():
            self._settings_win = BarSettings(
                self._cfg, self._menu_actions(), initial_page=initial_page
            )
            toplevel = self.get_toplevel()
            if toplevel is not None and toplevel is not self:
                self._settings_win.set_transient_for(toplevel)
        elif initial_page:
            page = getattr(self._settings_win, "_page_buttons", {}).get(initial_page)
            if page is not None:
                self._settings_win._set_active_page(initial_page)
        self._settings_win.present()

    def _menu_actions(self) -> dict:
        cfg = self._cfg

        def _theme():
            if self._theme_cb is not None:
                self._theme_cb()

        def set_source(source: str) -> None:
            cfg.setdefault("theme", {})["source"] = source
            config_module.save(cfg)
            _theme()

        def set_theme_name(name: str) -> None:
            cfg.setdefault("theme", {})["theme_name"] = name
            config_module.save(cfg)
            _theme()

        def set_manual_colors(colors: dict) -> None:
            theme = cfg.setdefault("theme", {})
            for key in ("background", "foreground", "accent", "running", "hover", "border_color"):
                if key in colors:
                    theme[key] = colors[key]
            config_module.save(cfg)
            _theme()

        def reset_layout() -> None:
            cfg["layout"] = {
                "left": list(DEFAULT_LAYOUT["left"]),
                "center": list(DEFAULT_LAYOUT["center"]),
                "right": list(DEFAULT_LAYOUT["right"]),
            }
            config_module.save(cfg)
            self.rebuild_layout()

        def reload_config() -> None:
            # A full process restart: the bar runs the latest source and re-reads
            # config.json. An in-place config reload cannot pick up new modules
            # (their code is already loaded), so it would silently ignore config
            # that references them.
            self.restart()

        def set_width(value: str) -> None:
            self._width = str(value)
            cfg["width"] = self._width
            config_module.save(cfg)
            self._apply_width()

        def set_align(value: str) -> None:
            if value not in ("left", "center", "right"):
                return
            self._align = value
            cfg["align"] = value
            config_module.save(cfg)
            self._apply_width()

        def set_height(value) -> None:
            try:
                height = max(20, int(str(value).strip()))
            except (TypeError, ValueError):
                height = 42
            cfg["height"] = height
            config_module.save(cfg)
            _theme()  # re-theme: CSS min-height
            if self._height_cb is not None:
                self._height_cb()

        def set_gaps(value) -> None:
            try:
                gap_in = max(0, min(60, int(str(value.get("gap_in", 6)).strip())))
                gap_out = max(0, min(60, int(str(value.get("gap_out", 6)).strip())))
            except (TypeError, ValueError, AttributeError):
                return
            cfg["gap_in"] = gap_in
            cfg["gap_out"] = gap_out
            config_module.save(cfg)
            _theme()  # re-theme: CSS pill margins
            if self._height_cb is not None:
                self._height_cb()  # surface height = height + gap_in + gap_out

        def set_position(value) -> None:
            if value not in ("top", "bottom"):
                return
            cfg["position"] = value
            config_module.save(cfg)
            tray = self._widgets.get("tray")
            if tray is not None:
                tray.set_bar_edge(value)
            if self._position_cb is not None:
                self._position_cb()

        def set_opacity(value) -> None:
            try:
                opacity = max(0.0, min(1.0, float(str(value).strip())))
            except (TypeError, ValueError):
                opacity = 0.95
            cfg["opacity"] = opacity
            config_module.save(cfg)
            _theme()  # re-theme: CSS background alpha

        def set_font(family) -> None:
            cfg.setdefault("font", {})["family"] = str(family or "").strip()
            config_module.save(cfg)
            _theme()

        def set_font_size(size) -> None:
            try:
                size = max(8, int(str(size).strip()))
            except (TypeError, ValueError):
                size = 16
            cfg.setdefault("font", {})["size"] = size
            config_module.save(cfg)
            _theme()

        def set_icon_size(size) -> None:
            try:
                size = max(0, int(str(size).strip()))
            except (TypeError, ValueError):
                size = 0
            cfg.setdefault("font", {})["icon_size"] = size
            config_module.save(cfg)
            _theme()

        def set_quicklink_icon_size(size) -> None:
            try:
                size = max(0, int(str(size).strip()))
            except (TypeError, ValueError):
                size = 0
            cfg.setdefault("quicklinks", {})["icon_size"] = size
            config_module.save(cfg)
            _theme()

        def set_border_animation(enabled: bool, mode: str, speed: int | None = None) -> None:
            cfg.setdefault("theme", {})["border_animation"] = bool(enabled)
            anim = cfg.setdefault("animations", {})
            anim["mode"] = str(mode or "high").lower()
            if speed is not None:
                try:
                    anim["speed"] = max(1, int(speed))
                except (TypeError, ValueError):
                    pass
            config_module.save(cfg)
            _theme()

        def apply_layout(layout: dict) -> None:
            cfg["layout"] = {
                "left": list(layout.get("left", [])),
                "center": list(layout.get("center", [])),
                "right": list(layout.get("right", [])),
            }
            config_module.save(cfg)
            self.rebuild_layout()

        def set_arcmenu(block: dict) -> None:
            cfg["arcmenu"] = block
            config_module.save(cfg)
            if self._arcmenu_cb is not None:
                self._arcmenu_cb(block)

        def set_menu(block: dict) -> None:
            cfg["menu"] = block
            config_module.save(cfg)
            if self._menu_reload_cb is not None:
                self._menu_reload_cb(block)

        def set_widgets(block: dict) -> None:
            cfg["widgets"] = block
            config_module.save(cfg)
            if self._widgets_cb is not None:
                self._widgets_cb(block)

        def set_quicklinks(block: dict) -> None:
            cfg["quicklinks"] = block
            config_module.save(cfg)
            # Rebuild the module so the new links take effect (the cached widget
            # still holds the old buttons).
            old = self._widgets.pop("quicklinks", None)
            if old is not None:
                shutdown = getattr(old, "shutdown", None)
                if shutdown is not None:
                    shutdown()
            self.rebuild_layout()

        def open_settings() -> None:
            self.open_settings()

        def open_about() -> None:
            from .bar_menu import show_about
            show_about(self.get_toplevel())

        return {
            "set_source": set_source,
            "set_theme_name": set_theme_name,
            "set_manual_colors": set_manual_colors,
            "reset_layout": reset_layout,
            "reload_config": reload_config,
            "set_width": set_width,
            "set_align": set_align,
            "set_height": set_height,
            "set_gaps": set_gaps,
            "set_position": set_position,
            "set_opacity": set_opacity,
            "set_font": set_font,
            "set_font_size": set_font_size,
            "set_icon_size": set_icon_size,
            "set_quicklink_icon_size": set_quicklink_icon_size,
            "set_border_animation": set_border_animation,
            "apply_layout": apply_layout,
            "open_about": open_about,
            "set_arcmenu": set_arcmenu,
            "set_menu": set_menu,
            "set_quicklinks": set_quicklinks,
            "set_widgets": set_widgets,
            "open_settings": open_settings,
        }

    # ── theming callback (set by the app window) ────────────────

    def apply_theme(self, source: str, theme_name: str = "", colors: dict | None = None) -> None:
        """Apply a theme source / imported theme / manual colours live.

        Used by the Theme Manager (and matching bar settings behaviour): the
        shared config is updated, saved, and the bar re-themes in place. When
        ``colors`` is given (manual source) it is written into the theme block.
        """
        cfg = self._cfg
        theme = cfg.setdefault("theme", {})
        theme["source"] = source
        if theme_name:
            theme["theme_name"] = theme_name
        if colors:
            theme.update(colors)
        config_module.save(cfg)
        if self._theme_cb is not None:
            self._theme_cb()

    def set_theme_callback(self, callback) -> None:
        self._theme_cb = callback

    def set_arcmenu_callback(self, callback) -> None:
        self._arcmenu_cb = callback

    def set_menu_callback(self, callback) -> None:
        self._menu_cb = callback

    def set_menu_reload_callback(self, callback) -> None:
        self._menu_reload_cb = callback

    def set_widgets_callback(self, callback) -> None:
        self._widgets_cb = callback

    def set_height_callback(self, callback) -> None:
        self._height_cb = callback

    def set_position_callback(self, callback) -> None:
        self._position_cb = callback

    # ── data ────────────────────────────────────────────────────

    def start(self) -> None:
        if self._tray_ctrl is not None:
            self._tray_ctrl.start()

    def update(self, clients: list, workspaces: list, active_id: int, focus_address: str | None, active_title: str | None = None, active_class: str | None = None) -> None:
        tasklist = self._widgets.get("tasklist")
        if tasklist is not None:
            tasklist.update(clients, focus_address, active_id)
        workspaces_widget = self._widgets.get("workspaces")
        if workspaces_widget is not None:
            workspaces_widget.update(workspaces, active_id)
        window_widget = self._widgets.get("window")
        if window_widget is not None:
            window_widget.update(active_title, active_class)

    def shutdown(self) -> None:
        tasklist = self._widgets.get("tasklist")
        if tasklist is not None:
            tasklist.shutdown()
        clock = self._widgets.get("clock")
        if clock is not None:
            shutdown = getattr(clock, "shutdown", None)
            if shutdown is not None:
                shutdown()
        kb = self._widgets.get("kbstate")
        if kb is not None:
            shutdown = getattr(kb, "shutdown", None)
            if shutdown is not None:
                shutdown()
        upd = self._widgets.get("updates")
        if upd is not None:
            shutdown = getattr(upd, "shutdown", None)
            if shutdown is not None:
                shutdown()
        qs = self._widgets.get("quicksettings")
        if qs is not None:
            qs.shutdown()
        sysmon = self._widgets.get("sysmon")
        if sysmon is not None:
            shutdown = getattr(sysmon, "shutdown", None)
            if shutdown is not None:
                shutdown()
        quicklinks = self._widgets.get("quicklinks")
        if quicklinks is not None:
            shutdown = getattr(quicklinks, "shutdown", None)
            if shutdown is not None:
                shutdown()
        if self._tray_ctrl is not None:
            self._tray_ctrl.shutdown()