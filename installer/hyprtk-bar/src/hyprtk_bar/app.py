"""Layer-shell window hosting the taskbar, plus Hyprland event wiring."""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · app
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import cairo
import logging
import subprocess
import threading
import time

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")

from gi.repository import Gdk, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from .bar import Bar  # noqa: E402
from .config import PYWAL_PATH, ROFI_SYNC_SH  # noqa: E402
from .hypr_animations import active_border_colors, border_animation, lerp_color  # noqa: E402
from .ipc import HyprIPC  # noqa: E402
from .notifications import NotificationController  # noqa: E402
from .theme import build_css, gap_value, resolve_palette  # noqa: E402
from .theme_import import find_themes_dir  # noqa: E402

log = logging.getLogger("hyprtk_bar.app")


def _prefers_reduced_motion() -> bool:
    """True when the system asks for reduced motion (GTK `enable-animations` off)."""
    try:
        settings = Gtk.Settings.get_default()
        return not settings.get_property("gtk-enable-animations")
    except Exception:
        return False

# Socket events that should trigger a taskbar refresh.
REFRESH_EVENTS = (
    "openwindow",
    "closewindow",
    "movewindow",
    "workspace",
    "workspacev2",
    "activewindow",
    "activewindowv2",
    "fullscreen",
    "changefloatingmode",
    "focusedmon",
    "moveworkspace",
    "windowtitlev2",
    "windowclassv2",
    "urgent",
    "monitoraddedv2",
    "monitorremovedv2",
    "openlayer",
    "closelayer",
)


def select_monitors(cfg: dict) -> list[Gdk.Monitor]:
    """Return the Gdk monitors the bar should be shown on.

    ``monitors`` selects the target set:
    - ``"primary"`` (default): only the primary monitor.
    - ``"all"``: every monitor.
    - a list of connector/model names (e.g. ``["DP-1", "HDMI-A-1"]``).
    """
    display = Gdk.Display.get_default()
    if display is None:
        return []
    monitors = [display.get_monitor(i) for i in range(display.get_n_monitors())]
    mode = cfg.get("monitors", "primary")
    if mode == "all":
        return list(monitors)
    if isinstance(mode, list) and mode:
        names = set(mode)
        # Gdk Wayland monitors expose no connector name; map Hyprland connector
        # names onto Gdk monitors by geometry so both names and models match.
        hypr_names = _hypr_monitors_by_geometry()
        matched = []
        for m in monitors:
            _connector, model, geo = _monitor_identifiers(m)
            name = hypr_names.get(geo) or ""
            if name in names or model in names:
                matched.append(m)
        return matched
    primary = [m for m in monitors if m.is_primary()]
    return primary or monitors[:1]


def _hypr_monitors_by_geometry() -> dict:
    """Map ``(x, y, w, h)`` -> Hyprland monitor connector name."""
    import json
    import subprocess

    try:
        out = subprocess.run(
            ["hyprctl", "-j", "monitors"], capture_output=True, text=True, timeout=5
        )
        data = json.loads(out.stdout)
    except (subprocess.SubprocessError, OSError, json.JSONDecodeError):
        return {}
    result = {}
    for mon in data:
        g = mon.get("geometry") or {}
        key = (
            g.get("x") if g.get("x") is not None else mon.get("x"),
            g.get("y") if g.get("y") is not None else mon.get("y"),
            g.get("width") if g.get("width") is not None else mon.get("width"),
            g.get("height") if g.get("height") is not None else mon.get("height"),
        )
        result[key] = mon.get("name")
    return result


def _monitor_identifiers(monitor: Gdk.Monitor) -> tuple[str, str, tuple]:
    """(connector, model, geometry) for a Gdk monitor.

    Under Wayland ``get_connector()`` is unavailable (X11-only), so the model
    name (e.g. "C49J89x") and the geometry are the reliable identifiers.
    """
    getter = getattr(monitor, "get_connector", None)
    connector = getter() if getter is not None else ""
    try:
        model = monitor.get_model() or ""
    except Exception:
        model = ""
    geo = monitor.get_geometry()
    return connector, model, (geo.x, geo.y, geo.width, geo.height)


class BarWindow(Gtk.Window):
    """A transparent, full-width layer-shell surface pinned to an edge."""

    def __init__(
        self,
        cfg: dict,
        monitor: Gdk.Monitor | None = None,
        ipc: HyprIPC | None = None,
        is_primary: bool = True,
        start_ipc: bool = False,
        notif_ctrl: NotificationController | None = None,
    ):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self._cfg = cfg
        self.monitor = monitor
        self.is_primary = is_primary
        self._refresh_id: int | None = None
        self._wal_monitor: Gio.FileMonitor | None = None
        self._theme_dir_monitor: Gio.FileMonitor | None = None
        self._hypr_monitor: Gio.FileMonitor | None = None
        self._wal_debounce: int | None = None
        self._border_anim: dict | None = None
        self._border_anim_id: int | None = None
        self._border_hue = 0.0
        self._border_base = ""
        self._palette_cache: dict | None = None
        self._theme_extra_cbs: list = []
        self._ls_ready = False
        self._last_margins: tuple[int, int] | None = None
        self._surface_x = 0
        self._last_wal_colors: tuple | None = None

        self.set_title("hyprtk-bar")
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_app_paintable(True)
        self.set_accept_focus(False)

        visual = self.get_screen().get_rgba_visual()
        if visual:
            self.set_visual(visual)

        self._ipc = ipc if ipc is not None else HyprIPC()
        self._notif_ctrl = notif_ctrl
        if (
            self._notif_ctrl is None
            and is_primary
            and (cfg.get("notifications") or {}).get("enabled", True)
        ):
            self._notif_ctrl = NotificationController(cfg, monitor=monitor, bar_win=self)
            self._notif_ctrl.start()
        self._bar = Bar(cfg, self._ipc, is_primary=is_primary, notif_ctrl=self._notif_ctrl)
        self._bar.set_theme_callback(self._apply_theme)
        self._bar.set_height_callback(self._on_bar_height)
        self._bar.set_position_callback(self._on_bar_position)
        self.add(self._bar)
        self._bar.connect("size-allocate", self._on_size_allocate)

        self._provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_screen(
            self.get_screen(), self._provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
        )
        # Tiny provider that only overrides the pill's border-color each tick;
        # loaded after the base provider so it wins the cascade for that property.
        self._anim_provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_screen(
            self.get_screen(), self._anim_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
        )
        self._apply_theme()

        self._init_layer_shell()

        self._wire_ipc()
        if start_ipc:
            self._ipc.start()
        self._bar.start()

        self._setup_theme_monitors()
        self._setup_hypr_monitor()

    # ── theming ───────────────────────────────────────────────────

    def _apply_theme(self) -> None:
        try:
            scale = self._bar.content_scale()
        except Exception:
            scale = 1.0
        palette = resolve_palette(self._cfg)
        palette["content_scale"] = scale
        # Fit-to-width: shrink the bar font (and chip text) with the content
        # scale so a narrow bar keeps every module's glyph visible instead of
        # clipping it.
        if scale < 1.0:
            for key in ("font_size", "chip_font_size"):
                size = palette.get(key)
                if size:
                    palette[key] = max(7, int(round(float(size) * scale)))
        self._palette_cache = palette
        self._border_base = palette.get("border_color") or palette.get("accent") or ""
        css = build_css(palette, self._cfg)
        self._provider.load_from_data(css.encode())
        self._bar.apply_palette_layout(palette)
        icon_size = (self._cfg.get("font") or {}).get("icon_size", 0)
        try:
            icon_size = int(icon_size)
        except (TypeError, ValueError):
            icon_size = 0
        if icon_size > 0 and scale < 1.0:
            icon_size = max(8, int(round(icon_size * scale)))
        self._bar.apply_font(palette.get("font_size"), icon_size)
        # Force a redraw + re-layout so module text re-renders at the new font
        # size immediately (not only on the next pointer event).
        self._bar.queue_resize()
        self._bar.queue_draw()
        self._sync_rofi_variant()
        self._setup_border_animation()
        for callback in list(self._theme_extra_cbs):
            try:
                callback(palette)
            except Exception:
                log.exception("theme extra callback failed")

    def set_theme_extra_callback(self, callback) -> None:
        """Register a callback invoked with the palette after each re-theme.

        Used to keep overlays (the arc menu, desktop widgets) in lock-step with
        the bar's palette. Multiple callbacks are supported; registering the same
        callback twice is a no-op.
        """
        if callback not in self._theme_extra_cbs:
            self._theme_extra_cbs.append(callback)

    def add_theme_extra_callback(self, callback) -> None:
        """Alias of :meth:`set_theme_extra_callback` (multiple callbacks allowed)."""
        self.set_theme_extra_callback(callback)

    # ── animated border (mirrors Hyprland's border/borderangle) ─────

    def _setup_border_animation(self) -> None:
        """Start/stop a looping border-color animation for the bar border.

        The bar config's ``animations.mode`` selects the source:
        - ``low`` / ``high`` — the matching ``animations-<mode>.lua`` file (in
          the Hyprland config dir) sets the ``borderangle``/``border`` speed.
        - ``custom`` — ``animations.speed`` from the bar config, independent of
          Hyprland.

        The border interpolates between Hyprland's two ``active_border``
        colours (``color11`` + ``color4`` from ``window.lua``) on a ping-pong
        loop, at a period derived from that speed — mirroring the borderangle
        gradient, not a full hue wheel. Disabled when the theme draws no
        border, animations are off there, or ``theme.border_animation`` is
        false in config.
        """
        if self._border_anim_id is not None:
            GLib.source_remove(self._border_anim_id)
            self._border_anim_id = None
        # Only animate when the theme draws a pill border at all.
        palette = self._palette_cache or {}
        if not (
            self._border_base
            and palette.get("border_width")
            and (self._cfg.get("theme") or {}).get("border_animation", True)
        ):
            self._border_anim = None
            return
        # Respect the system reduced-motion preference (GTK animations setting).
        if _prefers_reduced_motion():
            self._border_anim = None
            return
        anim = border_animation(self._cfg)
        if not anim:
            self._border_anim = None
            return
        colors = active_border_colors()
        if not colors:
            self._border_anim = None
            return
        # Hyprland's ``speed`` is the animation duration in ds (1 ds = 100 ms),
        # so a full borderangle rotation takes speed * 100 ms. A ping-pong
        # A->B->A is one round trip, so use half the period per leg.
        speed = max(1, int(anim["speed"]))
        period_ms = max(200, int(speed * 100))
        self._border_anim = {
            "period_ms": period_ms,
            "leaf": anim.get("leaf"),
            "color_a": colors[0],
            "color_b": colors[1],
        }
        self._border_hue = 0.0
        self._border_anim_id = GLib.timeout_add(66, self._border_anim_tick)

    def _border_anim_tick(self) -> bool:
        """Advance the border blend and re-render with the animated color."""
        if self._border_anim is None or self._palette_cache is None:
            return GLib.SOURCE_REMOVE
        period = self._border_anim["period_ms"]
        # Ping-pong: 0 -> 1 -> 0 over the period (one leg = half the period).
        # Tick at ~15fps — a slow border blend needs no more; keeps the CSS
        # rebuild + redraw cheap.
        self._border_hue = (self._border_hue + 66.0 / (period / 2.0)) % 2.0
        t = self._border_hue if self._border_hue <= 1.0 else 2.0 - self._border_hue
        color = lerp_color(
            self._border_anim["color_a"], self._border_anim["color_b"], t
        )
        # The blend moves in tiny steps per frame (long periods); skip frames
        # whose color hasn't visibly changed to avoid rebuilding CSS + redrawing
        # ~30×/s needlessly. Updates still apply as soon as the color shifts.
        if color == getattr(self, "_border_last_color", None):
            return GLib.SOURCE_CONTINUE
        self._border_last_color = color
        try:
            # Animate the pill border plus every popup/dialogue that carries
            # the themed ``.popup-box`` border (notification center, quick
            # settings, toasts, tooltips, monitor dialog, settings dialogue).
            self._anim_provider.load_from_data(
                f".taskbar, .popup-box {{ border-color: {color}; }}".encode()
            )
        except GLib.Error:
            log.warning("failed to load animated-border CSS", exc_info=True)
            return GLib.SOURCE_REMOVE
        self._bar.queue_draw()
        return GLib.SOURCE_CONTINUE

    def _sync_rofi_variant(self) -> None:
        """Keep the rofi variant.rasi in lock-step with the bar's theme.

        sync-rofi-theme.sh derives the variant from ``theme.theme_name`` in
        this bar's config, so running it here makes rofi menus match whatever
        imported theme the bar is showing (and, on wallpaper changes, keeps the
        link in sync while the variant's ``@colorN`` refs track pywal live).

        Only re-run when the source/theme actually change — a wallpaper re-tint
        keeps the same variant symlink (its @colorN refs follow pywal live), so
        re-spawning the script every re-theme is wasted subprocess work.
        """
        if not ROFI_SYNC_SH.is_file():
            return
        theme = self._cfg.get("theme") or {}
        key = (theme.get("source", "pywal"), theme.get("theme_name", ""))
        if key == getattr(self, "_last_rofi_key", None):
            return
        self._last_rofi_key = key
        try:
            subprocess.Popen(["bash", str(ROFI_SYNC_SH)], start_new_session=True)
        except OSError:
            log.warning("could not spawn rofi theme sync", exc_info=True)

    def _setup_theme_monitors(self) -> None:
        """Watch the sources a live re-theme depends on.

        - pywal colors (``~/.cache/wal`` — colors.json + the generated
          ``colors-waybar*.css`` that waybar themes @import),
        - the hyprtk waybar theme switcher file (``~/.cache/.themestyle.sh``),
        - the hyprtk themes directory itself.
        """
        try:
            self._wal_monitor = Gio.File.new_for_path(
                str(PYWAL_PATH.parent)
            ).monitor_directory(Gio.FileMonitorFlags.NONE, None)
        except GLib.Error as exc:
            log.warning("Could not monitor pywal cache: %s", exc)
        else:
            self._wal_monitor.connect("changed", self._on_theme_source_changed)

        base = find_themes_dir()
        try:
            self._theme_dir_monitor = Gio.File.new_for_path(
                str(base)
            ).monitor_directory(Gio.FileMonitorFlags.NONE, None)
        except GLib.Error as exc:
            log.warning("Could not monitor themes dir: %s", exc)
        else:
            self._theme_dir_monitor.connect("changed", self._on_theme_source_changed)

    def _setup_hypr_monitor(self) -> None:
        """Watch the Hyprland config dir for animation-file changes.

        Toggling ``animations-high``/``animations-low`` in ``hyprland.lua``
        (or editing the speed in either file) re-runs the border animation at
        the new pace. The monitor fires on any file change in the dir, but the
        handler is cheap (re-reads the active file and adjusts the timer).
        """
        from .hypr_animations import HYPR_DIRS

        target = next((d for d in HYPR_DIRS if d.is_dir()), None)
        if target is None:
            return
        try:
            self._hypr_monitor = Gio.File.new_for_path(
                str(target)
            ).monitor_directory(Gio.FileMonitorFlags.NONE, None)
        except GLib.Error as exc:
            log.warning("Could not monitor hypr config dir: %s", exc)
        else:
            self._hypr_monitor.connect("changed", self._on_hypr_changed)

    def _on_hypr_changed(self, _monitor, *_args) -> None:
        self._setup_border_animation()

    def _on_theme_source_changed(self, _monitor, *_args) -> None:
        if self._wal_debounce is not None:
            GLib.source_remove(self._wal_debounce)
        self._wal_debounce = GLib.timeout_add(350, self._reload_theme)

    def _reload_theme(self) -> bool:
        self._wal_debounce = None
        self._apply_theme()
        self._sync_swaylock_if_changed()
        return GLib.SOURCE_REMOVE

    def _sync_swaylock_if_changed(self) -> None:
        """Keep the swaylock colors in sync with pywal on wallpaper change.

        The Theme Manager's swaylock page can do this manually, but the lock
        screen should also follow the wallpaper automatically. This fires on
        every pywal-cache change (debounced by ``_reload_theme``) and only
        rewrites the swaylock config when the palette actually changed, so a
        manual color edit is not clobbered by an unrelated theme change.
        """
        from .themer import _read_wal_hex, sync_swaylock_from_pywal

        try:
            key = tuple(_read_wal_hex())
        except Exception:
            log.warning("could not read pywal colors", exc_info=True)
            return
        if key == self._last_wal_colors:
            return
        self._last_wal_colors = key
        try:
            sync_swaylock_from_pywal()
        except Exception:
            log.warning("swaylock pywal sync failed", exc_info=True)

    def _on_bar_height(self) -> None:
        """Resize the layer surface when the bar height is changed in settings."""
        total_height = self._surface_height()
        GtkLayerShell.set_exclusive_zone(self, total_height)
        self.set_size_request(-1, total_height)

    def _surface_height(self) -> int:
        """Layer-surface height: pill height + gap_in (windows side) + gap_out (edge side)."""
        return (
            int(self._cfg.get("height", 42) or 42)
            + gap_value(self._cfg, "gap_in", 6)
            + gap_value(self._cfg, "gap_out", 6)
        )

    def set_surface_width(self, px: int, total: int, align: str) -> None:
        """Narrow the layer surface to *px* via left/right margins.

        Applied to the surface rather than the pill because the pill has a
        minimum width (~the modules' content) and cannot shrink below it — so
        percentages/px smaller than that minimum failed on smaller displays.
        The surface width is decided by the compositor, so any width works and
        content clips when the user asks for less than the modules need.
        """
        if not self._ls_ready:
            return
        if 0 < px < total:
            remaining = total - px
            left = {"left": 0, "right": remaining}.get(align, remaining // 2)
            right = remaining - left
        else:
            left = right = 0
        self._surface_x = left
        if (left, right) == self._last_margins:
            return
        self._last_margins = (left, right)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, left)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.RIGHT, right)

    def _on_bar_position(self) -> None:
        """Re-anchor the layer surface when the bar moves top/bottom in settings."""
        edge = (
            GtkLayerShell.Edge.TOP
            if self._cfg["position"] == "top"
            else GtkLayerShell.Edge.BOTTOM
        )
        other = (
            GtkLayerShell.Edge.BOTTOM
            if edge == GtkLayerShell.Edge.TOP
            else GtkLayerShell.Edge.TOP
        )
        GtkLayerShell.set_anchor(self, other, False)
        GtkLayerShell.set_anchor(self, edge, True)
        total_height = self._surface_height()
        GtkLayerShell.set_exclusive_zone(self, total_height)
        self.set_size_request(-1, total_height)
        # The pill's gap_in/gap_out margins flip with the position — rebuild CSS.
        self._apply_theme()
        # Move any open popups (calendar, previews, quick settings, notification
        # center) and the toast to the new bar edge.
        position = self._cfg["position"]
        for widget in self._bar._widgets.values():
            for attr in ("_popup", "_date_popup", "_preview"):
                popup = getattr(widget, attr, None)
                if popup is not None:
                    popup.set_bar_edge(position)
                    popup.reposition()
        if self._notif_ctrl is not None and self._notif_ctrl._toast is not None:
            self._notif_ctrl._toast.set_bar_edge(position)
            self._notif_ctrl._toast.reposition()

    # ── layer shell ───────────────────────────────────────────────

    def _init_layer_shell(self) -> None:
        total_height = self._surface_height()
        GtkLayerShell.init_for_window(self)
        if self.monitor is not None:
            GtkLayerShell.set_monitor(self, self.monitor)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_namespace(self, "hyprtk-bar")
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        if self._cfg["position"] == "top":
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        else:
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_exclusive_zone(self, total_height)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        self.set_size_request(-1, total_height)
        self._ls_ready = True
        # Apply the configured width now that the surface exists.
        self._bar._apply_width()

    # ── input shape: only the pill is clickable ─────────────────────

    def _on_size_allocate(self, *_args) -> None:
        self._apply_input_shape()

    def _apply_input_shape(self) -> None:
        wnd = self.get_window()
        if wnd is None:
            return
        region = cairo.Region()

        def add(widget, inset_left: int, inset_top: int, inset_right: int, inset_bottom: int) -> None:
            alloc = widget.get_allocation()
            rect = cairo.RectangleInt(
                alloc.x + inset_left,
                alloc.y + inset_top,
                max(alloc.width - inset_left - inset_right, 0),
                max(alloc.height - inset_top - inset_bottom, 0),
            )
            region.union(rect)

        for child in self._bar.get_children():
            if child is getattr(self._bar, "pill_clip", None):
                # The pill_clip owns the .taskbar background and its CSS margins,
                # so its allocation is already the pill's rect (GTK margins are
                # outside the allocation).
                add(child, 0, 0, 0, 0)
        wnd.input_shape_combine_region(region, 0, 0)

    # ── IPC ───────────────────────────────────────────────────────

    def _wire_ipc(self) -> None:
        self._ipc.on_connect(self._on_connected)
        for event in REFRESH_EVENTS:
            self._ipc.on(event, self._on_ipc_event)

    def _on_connected(self) -> None:
        GLib.idle_add(self._refresh)

    def _on_ipc_event(self, _data) -> None:
        GLib.idle_add(self._schedule_refresh)

    def _schedule_refresh(self) -> bool:
        if self._refresh_id is not None:
            GLib.source_remove(self._refresh_id)
        self._refresh_id = GLib.timeout_add(120, self._refresh)
        return GLib.SOURCE_REMOVE

    def _refresh(self) -> bool:
        self._refresh_id = None
        # The four hyprctl queries run on a worker thread so a focus/move burst
        # never stalls the GTK main loop (each spawn can block up to 5s). Results
        # are marshalled back to the main thread via idle_add.
        def _work() -> None:
            clients = self._ipc.query("clients")
            if clients is None:
                return
            workspaces = self._ipc.query("workspaces") or []
            focus = self._ipc.query("activewindow") or {}
            monitors = self._ipc.query("monitors") or []
            a_id = self._active_workspace_on_this_monitor(monitors)
            GLib.idle_add(
                self._bar.update,
                clients, workspaces, a_id,
                focus.get("address"), focus.get("title"), focus.get("class"),
            )

        threading.Thread(target=_work, daemon=True).start()
        return GLib.SOURCE_REMOVE

    def _active_workspace_on_this_monitor(self, monitors: list) -> int:
        """The active workspace on THIS bar's monitor (each monitor has its own).

        Gdk Wayland monitors expose no connector name, so the monitor is matched
        against the ``monitors`` result by model name or geometry. Falls back to
        the first monitor's active workspace (the global active one on a typical
        single-monitor setup) when this monitor can't be identified.

        ``monitors`` is passed in (already fetched by ``_refresh``) so a refresh
        does not re-spawn a separate ``hyprctl monitors`` per monitor.
        """
        fallback = 1
        for m in monitors:
            aw = m.get("activeWorkspace") or {}
            if isinstance(aw.get("id"), int):
                fallback = aw["id"]
                break
        if self.monitor is None:
            return fallback
        connector, model, geo = _monitor_identifiers(self.monitor)
        for m in monitors:
            if not self._monitor_matches(m, connector, model, geo):
                continue
            aw = m.get("activeWorkspace") or {}
            if isinstance(aw.get("id"), int):
                return aw["id"]
            break
        return fallback

    @staticmethod
    def _monitor_matches(m: dict, connector: str, model: str, geo: tuple) -> bool:
        if connector and m.get("name") == connector:
            return True
        if model and (m.get("model") or "") == model:
            return True
        g = m.get("geometry") or {}
        return (
            isinstance(g, dict)
            and g.get("x") == geo[0]
            and g.get("y") == geo[1]
            and g.get("width") == geo[2]
            and g.get("height") == geo[3]
        )

    # ── shutdown ──────────────────────────────────────────────────

    def shutdown(self) -> None:
        for monitor in (self._wal_monitor, self._theme_dir_monitor, self._hypr_monitor):
            if monitor is not None:
                monitor.cancel()
        if self._wal_debounce is not None:
            GLib.source_remove(self._wal_debounce)
        if self._border_anim_id is not None:
            GLib.source_remove(self._border_anim_id)
            self._border_anim_id = None
        if self._refresh_id is not None:
            GLib.source_remove(self._refresh_id)
        self._bar.shutdown()
        if self._notif_ctrl is not None:
            self._notif_ctrl.shutdown()
        self._ipc.stop()