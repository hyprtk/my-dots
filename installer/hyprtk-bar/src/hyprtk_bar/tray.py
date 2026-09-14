"""StatusNotifier system tray (SNI).

Implements the `org.kde.StatusNotifierWatcher` service with dbus-next's GLib
integration (no extra event loop) and renders registered items as taskbar
icons. If another process already owns the watcher name (e.g. waybar), items
are *adopted* from that watcher instead, so the tray works alongside it and
keeps showing items after it stops and this process takes the name.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · tray
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import os
import re
import subprocess
import threading
import time
from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")

from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

from dbus_next.constants import MessageType, NameFlag, RequestNameReply  # noqa: E402
from dbus_next.glib import MessageBus  # noqa: E402
from dbus_next.service import (  # noqa: E402
    PropertyAccess,
    ServiceInterface,
    dbus_property,
    method,
    signal,
)
from dbus_next import Message  # noqa: E402

from .popup import bind_hover_tooltip  # noqa: E402
from .widgets import HoverButton, safe_icon_name  # noqa: E402

log = logging.getLogger("hyprtk_bar.tray")

# Cap on tracked SNI items (any session-bus app can register unlimited ones).
_MAX_SNI_ITEMS = 16

# Cap on SNI IconPixmap dimensions (remote-controlled; guards against absurd
# allocations). 512px is far beyond any tray icon need.
_MAX_PIXMAP_DIM = 512

# IconThemePath from a remote item is injected into GTK's GLOBAL icon search
# path; only accept sane, directory-resolvable absolute paths so a malicious
# client can't point the shared search at "/" or a net export.
_MAX_THEME_PATH_LEN = 512

WATCHER_NAME = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"
ITEM_IFACE = "org.kde.StatusNotifierItem"
ITEM_PATH = "/StatusNotifierItem"
GENERIC_ICON = "application-x-executable"


# ── themed tray tooltips (network / bluetooth) ────────────────────

def _tray_run(args, timeout=3) -> str:
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return out.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return ""


class _NetRate:
    """Two-point upload/download rate sampler over /proc/net/dev."""

    def __init__(self):
        self._prev: tuple[int, int] | None = None
        self._prev_t = 0.0

    def sample(self, iface: str) -> tuple[float | None, float | None]:
        try:
            with open("/proc/net/dev") as f:
                for line in f:
                    if line.lstrip().startswith(iface + ":"):
                        parts = line.split()
                        rx, tx = int(parts[1]), int(parts[9])
                        now = time.monotonic()
                        up = dn = None
                        if self._prev is not None and now > self._prev_t:
                            dt = now - self._prev_t
                            up = max(0.0, (tx - self._prev[1])) / dt / 1024.0
                            dn = max(0.0, (rx - self._prev[0])) / dt / 1024.0
                        self._prev = (rx, tx)
                        self._prev_t = now
                        return up, dn
        except (OSError, ValueError, IndexError):
            pass
        return None, None


def _active_network_device() -> str:
    """The connected NetworkManager device name ('' when none)."""
    for line in _tray_run(
        ["nmcli", "-t", "-f", "DEVICE,STATE", "device", "status"]
    ).splitlines():
        dev, _, state = line.partition(":")
        if state == "connected":
            return dev
    return ""


def _device_ip(dev: str) -> str:
    return _tray_run(["nmcli", "-g", "IP4.ADDRESS", "device", "show", dev])


def _fmt_rate(value: float | None) -> str:
    return "--" if value is None else f"{value:.1f} KiB/s"


def network_tooltip(net_rate: _NetRate) -> str:
    dev = _active_network_device()
    lines = ["Network"]
    if not dev:
        lines.append("Not connected")
        return "\n".join(lines)
    ip = _device_ip(dev)
    up, dn = net_rate.sample(dev)
    lines.append(f"Device: {dev}")
    if ip:
        lines.append(f"IP: {ip}")
    lines.append(f"Upload: {_fmt_rate(up)}")
    lines.append(f"Download: {_fmt_rate(dn)}")
    return "\n".join(lines)


def bluetooth_tooltip() -> str:
    show = _tray_run(["bluetoothctl", "show"])
    m = re.search(r"Powered:\s+(yes|no)", show)
    power = "on" if (m and m.group(1) == "yes") else "off"
    lines = ["Bluetooth", f"Power: {power}"]
    connected = _tray_run(["bluetoothctl", "devices", "Connected"])
    devices = [l.strip() for l in connected.splitlines() if l.strip()]
    if devices:
        lines.append("Connected:")
        for line in devices:
            parts = line.split()
            name = " ".join(parts[2:]) if len(parts) > 2 else line
            lines.append(f"  {name}")
    return "\n".join(lines)


def _is_nm_applet(item: "SniItem") -> bool:
    return "nm_applet" in (item.path or "")


def _is_blueman(item: "SniItem") -> bool:
    return "blueman" in (item.path or "")

# Introspection for the item client; defines the methods/properties/signals we
# use regardless of whether the applet exports full introspection data.
SNI_INTROSPECTION = """<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="u" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionMovieName" type="s" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <property name="IconThemePath" type="s" access="read"/>
    <method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
    <method name="Refresh"/>
    <signal name="NewTitle"/>
    <signal name="NewIcon"/>
    <signal name="NewAttentionIcon"/>
    <signal name="NewOverlayIcon"/>
    <signal name="NewToolTip"/>
    <signal name="NewStatus"/>
    <signal name="NewMenu"/>
  </interface>
</node>"""

WATCHER_INTROSPECTION = """<node>
  <interface name="org.kde.StatusNotifierWatcher">
    <method name="RegisterStatusNotifierItem"><arg type="s" direction="in"/></method>
    <method name="RegisterStatusNotifierHost"><arg type="s" direction="in"/></method>
    <property name="RegisteredStatusNotifierItems" type="as" access="read"/>
    <property name="IsStatusNotifierHostRegistered" type="b" access="read"/>
    <property name="ProtocolVersion" type="i" access="read"/>
    <signal name="StatusNotifierItemRegistered"><arg type="s"/></signal>
    <signal name="StatusNotifierItemUnregistered"><arg type="s"/></signal>
    <signal name="StatusNotifierHostRegistered"><arg type="s"/></signal>
  </interface>
</node>"""

DBUS_INTROSPECTION = """<node>
  <interface name="org.freedesktop.DBus">
    <method name="GetNameOwner"><arg type="s" direction="in"/><arg type="s" direction="out"/></method>
    <signal name="NameOwnerChanged"><arg type="s"/><arg type="s"/><arg type="s"/></signal>
  </interface>
</node>"""


def _to_snake(name: str) -> str:
    out = []
    for i, ch in enumerate(name):
        if ch.isupper() and i:
            out.append("_")
        out.append(ch.lower())
    return "".join(out)


def _pixbuf_from_pixmap(width: int, height: int, argb: bytes):
    try:
        if width <= 0 or height <= 0:
            return None
        # A remote app controls IconPixmap dimensions; refuse absurd sizes so a
        # malicious StatusNotifier client can't force multi-megabyte allocations
        # per refresh (memory DoS / GTK crash).
        if width > _MAX_PIXMAP_DIM or height > _MAX_PIXMAP_DIM:
            return None
        if len(argb) < width * height * 4:
            return None
        return GdkPixbuf.Pixbuf.new_from_bytes(
            GLib.Bytes(argb),
            GdkPixbuf.Colorspace.RGB,
            True,  # has_alpha
            8,     # bits per sample
            width, height,
            width * 4,
        )
    except Exception:
        return None


def _safe_icon_theme_path(value) -> str:
    """Return *value* if it is a safe icon-theme search path, else "".

    SNI IconThemePath is remote-controlled and lands in GTK's shared icon search
    path; restrict it to an existing, absolute, non-traversal directory under a
    normal icon location (home or a system icon dir), with a sane length.
    """
    if not isinstance(value, str):
        return ""
    path = value.strip()
    if not path or len(path) > _MAX_THEME_PATH_LEN or not os.path.isabs(path):
        return ""
    try:
        real = os.path.realpath(path)
    except OSError:
        return ""
    allowed = (str(Path.home()), "/usr/share/icons", "/usr/local/share/icons", "/usr/share/pixmaps")
    if not real.startswith(allowed):
        return ""
    if not os.path.isdir(real):
        return ""
    return real


class Watcher(ServiceInterface):
    """The org.kde.StatusNotifierWatcher service we export when we own the name."""

    def __init__(self, controller: "TrayController"):
        super().__init__("org.kde.StatusNotifierWatcher")
        self._ctrl = controller

    @dbus_property(access=PropertyAccess.READ)
    def RegisteredStatusNotifierItems(self) -> "as":
        return list(self._ctrl.services())

    @dbus_property(access=PropertyAccess.READ)
    def IsStatusNotifierHostRegistered(self) -> "b":
        return self._ctrl.host_registered

    @dbus_property(access=PropertyAccess.READ)
    def ProtocolVersion(self) -> "i":
        return 0

    @method()
    def RegisterStatusNotifierHost(self, service: "s"):
        self._ctrl.set_host_registered(service)

    @signal()
    def StatusNotifierItemRegistered(self, service: "s") -> "s":
        return service

    @signal()
    def StatusNotifierItemUnregistered(self, service: "s") -> "s":
        return service

    @signal()
    def StatusNotifierHostRegistered(self, service: "s") -> "s":
        return service


class SniItem:
    """A client-side handle to one registered StatusNotifierItem."""

    def __init__(self, controller: "TrayController", service: str, path: str):
        self._ctrl = controller
        self.service = service
        self.path = path
        self.key = service if path == ITEM_PATH else f"{service}{path}"
        self.id = ""
        self.title = ""
        self.icon_name = ""
        self.tooltip = ""
        self.status = "Active"
        self.menu_path = ""
        self.item_is_menu = False
        self._pixmaps: list[tuple[int, int, bytes]] = []
        self._iface = None
        self._props_iface = None
        self._theme_paths_added = False

    @property
    def bus(self):
        return self._ctrl.bus

    def connect(self) -> None:
        proxy = self.bus.get_proxy_object(self.service, self.path, SNI_INTROSPECTION)
        self._iface = proxy.get_interface(ITEM_IFACE)
        try:
            self._props_iface = proxy.get_interface("org.freedesktop.DBus.Properties")
        except Exception:
            self._props_iface = None
        self._subscribe()
        # Render with defaults immediately, then update as properties arrive.
        self._load_props()
        self._ctrl.refresh_item(self.key)

    # ── properties ────────────────────────────────────────────────
    # All reads are callback-based. Items that never reply to a property just
    # keep their default; the bar never blocks (sync getters would nest a
    # GLib.MainLoop and deadlock against dbus-next's dispatch).

    def _get_async(self, prop: str) -> None:
        iface = self._iface
        if iface is None:
            return
        getter = getattr(iface, f"get_{_to_snake(prop)}", None)
        if getter is None:
            return
        try:
            getter(self._on_prop(prop))
        except Exception:
            pass

    def _on_prop(self, prop: str):
        def cb(value, err):
            if err is not None:
                return
            if prop == "ToolTip":
                if isinstance(value, list) and len(value) >= 4:
                    self.tooltip = value[2] or value[3] or ""
            elif prop == "IconPixmap":
                self._pixmaps = list(value or [])
            elif prop == "Menu":
                self.menu_path = str(value or "")
            elif prop == "ItemIsMenu":
                self.item_is_menu = bool(value)
            elif prop == "IconThemePath":
                safe = _safe_icon_theme_path(value)
                if safe and not self._theme_paths_added:
                    try:
                        Gtk.IconTheme.get_default().add_search_path(safe)
                    except Exception:
                        pass
                    self._theme_paths_added = True
            elif prop == "IconName":
                # Icon names are remote-controlled; a name containing "/" makes
                # GTK's icon loader open it as a filesystem path. Sanitize.
                self.icon_name = safe_icon_name(value)
            else:
                setattr(self, _to_snake(prop), value or "")
            self._ctrl.refresh_item(self.key)

        return cb

    def _load_props(self) -> None:
        for prop in (
            "Id", "Title", "IconName", "Status", "IconPixmap", "ToolTip",
            "IconThemePath", "Menu", "ItemIsMenu",
        ):
            self._get_async(prop)

    def _subscribe(self) -> None:
        if self._iface is None:
            return
        for sig in ("new_icon", "new_title", "new_tool_tip", "new_status", "new_menu"):
            on = getattr(self._iface, f"on_{sig}", None)
            if on:
                try:
                    on(self._on_change)  # these SNI signals carry no args
                except TypeError:
                    log.debug("no signal %r on %s", sig, self.service)
        if self._props_iface is not None:
            self._props_iface.on_properties_changed(self._on_props_changed)

    def detach(self) -> None:
        """Remove every D-Bus signal subscription so the bus stops pinning this
        item (and its widgets/pixmaps) after unregister. Without this, each
        register/unregister cycle leaves a zombie item in the bus's handler
        registry — a slow but real leak on nm-applet resets and name flaps."""
        if self._iface is not None:
            for sig in ("new_icon", "new_title", "new_tool_tip", "new_status", "new_menu"):
                off = getattr(self._iface, f"off_{sig}", None)
                if off:
                    try:
                        off(self._on_change)
                    except Exception:
                        pass
        if self._props_iface is not None:
            off = getattr(self._props_iface, "off_properties_changed", None)
            if off:
                try:
                    off(self._on_props_changed)
                except Exception:
                    pass
        self._iface = None
        self._props_iface = None

    def _on_props_changed(self, iface_name, changed, invalidated) -> None:
        self._on_change()

    def _on_change(self) -> None:
        self._load_props()
        self._ctrl.refresh_item(self.key)

    # ── actions ───────────────────────────────────────────────────

    def activate(self, x: int = 0, y: int = 0) -> None:
        self._call("Activate", x, y)

    def secondary_activate(self, x: int = 0, y: int = 0) -> None:
        self._call("SecondaryActivate", x, y)

    def context_menu(self, x: int = 0, y: int = 0) -> None:
        self._call("ContextMenu", x, y)

    def _call(self, method_name: str, *args) -> None:
        iface = self._iface
        if iface is None:
            return
        fn = getattr(iface, f"call_{_to_snake(method_name)}", None)
        if fn is None:
            return
        try:
            fn(*args, lambda *_a: None)
        except Exception as exc:
            log.warning("tray %s failed: %s", method_name, exc)

    # ── rendering ─────────────────────────────────────────────────

    def best_pixbuf(self):
        if not self._pixmaps:
            return None
        for w, h, argb in sorted(self._pixmaps, key=lambda p: -(p[0] * p[1])):
            pixbuf = _pixbuf_from_pixmap(w, h, bytes(argb))
            if pixbuf is not None:
                return pixbuf
        return None

    def label(self) -> str:
        return self.tooltip or self.title or self.id or self.service


class TrayButton(HoverButton):
    def __init__(self, item: SniItem, icon_size: int, bar_edge: str = "bottom", cfg: dict | None = None):
        super().__init__("tray-button", vertical=True, spacing=0)
        self._item = item
        self._icon_size = icon_size
        self._bar_edge = bar_edge
        self._cfg = cfg or {}
        self._dbusmenu = None
        self._image = Gtk.Image()
        self._image.set_pixel_size(icon_size)
        self.box.pack_start(self._image, True, True, 0)

        # Network (nm-applet) and bluetooth (blueman) icons get themed popup
        # tooltips like every other module; nm-applet's left click opens the
        # connection editor.
        self._is_nm = _is_nm_applet(item)
        self._is_blueman = _is_blueman(item)
        self._net_rate = _NetRate() if self._is_nm else None
        if cfg:
            if self._is_nm:
                bind_hover_tooltip(self, cfg, lambda: network_tooltip(self._net_rate))
            elif self._is_blueman:
                bind_hover_tooltip(self, cfg, bluetooth_tooltip)

    def _monitor_geometry(self):
        """(x, y, w, h) of the bar's monitor, or the whole screen fallback."""
        bar_win = self.get_toplevel()
        monitor = getattr(bar_win, "monitor", None)
        if monitor is not None:
            geo = monitor.get_geometry()
            return geo.x, geo.y, geo.width, geo.height
        bar_alloc = bar_win.get_allocation()
        screen = Gdk.Screen.get_default()
        return bar_alloc.x, bar_alloc.y, screen.get_width(), screen.get_height()

    def _screen_xy(self) -> tuple[int, int]:
        """Approximate global pointer target for Activate/ContextMenu.

        The bar spans its monitor width at an edge, so the button's screen
        position is computable from allocations. Applets (e.g. nm-applet) use
        these to anchor their popup menu next to the icon.
        """
        bar_win = self.get_toplevel()
        base_x, base_y, _w, screen_h = self._monitor_geometry()
        alloc = self.get_allocation()
        x = base_x + alloc.x + alloc.width // 2
        bar_alloc = bar_win.get_allocation()
        if self._bar_edge == "top":
            y = base_y + alloc.y + alloc.height // 2
        else:
            y = base_y + screen_h - bar_alloc.height + alloc.y + alloc.height // 2
        return x, y

    def refresh(self) -> None:
        item = self._item
        pixbuf = item.best_pixbuf()
        if pixbuf is not None:
            # This GTK3 build ignores `pixel_size` for pixbuf-backed images
            # (the natural size wins), so scale the applet's pixmap to the
            # tray icon size explicitly — some items (e.g. Whatsie) hand over
            # very large pixmaps that would otherwise blow up the bar.
            pixbuf = pixbuf.scale_simple(
                self._icon_size, self._icon_size, GdkPixbuf.InterpType.BILINEAR
            )
            self._image.set_from_pixbuf(pixbuf)
        else:
            self._image.set_from_icon_name(item.icon_name or GENERIC_ICON, Gtk.IconSize.INVALID)
            self._image.set_pixel_size(self._icon_size)
        if not (self._is_nm or self._is_blueman):
            self.set_tooltip_text(item.label())
        ctx = self.box.get_style_context()
        if item.status == "Passive":
            ctx.add_class("dimmed")
        else:
            ctx.remove_class("dimmed")

    def _on_button_press(self, _widget, event):
        item = self._item
        if event.button == 1 and self._is_nm and self._cfg:
            self._launch_nm_editor()
            return True
        x, y = self._screen_xy()
        if event.button == 1:
            if item.item_is_menu and item.menu_path:
                self._show_dbus_menu(event)
            else:
                item.activate(x, y)
        elif event.button == 2:
            item.secondary_activate(x, y)
        elif event.button == 3:
            if item.menu_path:
                self._show_dbus_menu(event)
            else:
                item.context_menu(x, y)
        return True

    def _launch_nm_editor(self) -> None:
        try:
            GLib.spawn_command_line_async("nm-connection-editor")
        except GLib.Error as exc:
            log.warning("could not open nm-connection-editor: %s", exc)

    def _show_dbus_menu(self, event) -> None:
        """Render the item's com.canonical.dbusmenu (if it exports one) as a Gtk.Menu."""
        item = self._item
        bus = item._ctrl.bus if item._ctrl is not None else None
        if not (item.menu_path and bus):
            return
        if self._dbusmenu is None or self._dbusmenu.path != item.menu_path:
            from .dbusmenu import DbusMenu
            self._dbusmenu = DbusMenu(bus, item.service, item.menu_path)
        try:
            self._dbusmenu.build(lambda menu: self._popup_dbus_menu(menu, event))
        except Exception as exc:
            log.warning("failed to build tray menu: %s", exc)

    def _popup_dbus_menu(self, menu, event) -> None:
        if menu is None:
            return
        menu.show_all()
        # Anchor the menu to the tray button rather than ``popup_at_pointer``:
        # the menu is popped up from the async dbus GetLayout callback, by which
        # time the press event's GdkWindow can be freed (segfault in
        # gdk_window_get_screen, seen with Whatsie). ``popup_at_widget`` uses
        # the button's own live window, and a bare ``popup()`` lands the menu
        # center-screen on this Wayland build. The bar-edge gravity opens the
        # menu above a bottom bar and below a top bar.
        if self._bar_edge == "top":
            widget_anchor, menu_anchor = Gdk.Gravity.NORTH_WEST, Gdk.Gravity.SOUTH_WEST
        else:
            widget_anchor, menu_anchor = Gdk.Gravity.SOUTH_WEST, Gdk.Gravity.NORTH_WEST
        menu.popup_at_widget(self, widget_anchor, menu_anchor, None)
        # A Gtk.Menu is a popup window that lingers after dismissal unless
        # destroyed; each open builds a fresh one, so release it on close to
        # avoid accumulating hidden menu surfaces.
        menu.connect("deactivate", lambda m: m.destroy())


class Tray(Gtk.Box):
    """Taskbar row of StatusNotifier icons."""

    def __init__(self, cfg: dict):
        super().__init__(spacing=2)
        self._cfg = cfg
        self._icon_size = (cfg.get("tray") or {}).get("icon_size", 20)
        self._bar_edge = cfg.get("position", "bottom")
        self._buttons: dict[str, TrayButton] = {}

    def set_item(self, key: str, item: SniItem) -> None:
        btn = self._buttons.get(key)
        if btn is None:
            btn = TrayButton(item, self._icon_size, self._bar_edge, self._cfg)
            self._buttons[key] = btn
            self.pack_start(btn, False, False, 0)
        btn.refresh()
        self.show_all()

    def remove_item(self, key: str) -> None:
        btn = self._buttons.pop(key, None)
        if btn is not None:
            btn.destroy()

    def clear(self) -> None:
        for btn in self._buttons.values():
            btn.destroy()
        self._buttons.clear()

    def set_bar_edge(self, edge: str) -> None:
        """Re-target the tray's screen coordinates after a top/bottom toggle."""
        self._bar_edge = edge
        for btn in self._buttons.values():
            btn._bar_edge = edge


class TrayController:
    """Owns the watcher name (when possible), adopts items otherwise."""

    def __init__(self, cfg: dict, tray: Tray):
        self._cfg = cfg
        self._tray = tray
        self.bus: MessageBus | None = None
        self._watcher: Watcher | None = None
        self._items: dict[str, SniItem] = {}
        self._am_watcher = False
        self._host_registered = False
        self._dbus_iface = None

    # ── lifecycle ─────────────────────────────────────────────────

    def start(self) -> None:
        try:
            self.bus = MessageBus()
            self.bus.connect_sync()
        except Exception as exc:
            log.warning("could not connect to session bus: %s", exc)
            self.bus = None
            return
        self._watcher = Watcher(self)
        self.bus.export(WATCHER_PATH, self._watcher)
        # Intercept item registrations at the message level so we can see the
        # caller's unique name (required for path-only args, e.g. blueman).
        self.bus.add_message_handler(self._on_message)
        self.bus.request_name(
            WATCHER_NAME, NameFlag.DO_NOT_QUEUE, self._on_name_reply
        )
        self._watch_dbus()
        self._watch_watcher_signals()
        self._adopt_existing()

    def _on_message(self, msg):
        if (
            msg.message_type == MessageType.METHOD_CALL
            and msg.member == "RegisterStatusNotifierItem"
            and msg.interface == "org.kde.StatusNotifierWatcher"
            and msg.path == WATCHER_PATH
        ):
            arg = msg.body[0] if msg.body else ""
            self.register(arg, sender=msg.sender)
            return Message.new_method_return(msg, "", [])
        return False

    def shutdown(self) -> None:
        for key in list(self._items):
            self.unregister(key)
        if self.bus is not None:
            try:
                self.bus.disconnect()
            except Exception:
                pass
            self.bus = None

    # ── name ownership ────────────────────────────────────────────

    @property
    def host_registered(self) -> bool:
        return self._host_registered

    def set_host_registered(self, service: str) -> None:
        """Mark a StatusNotifierHost as present (the protocol requires it).

        Many applets (e.g. nm-applet) only register their item once a host has
        announced itself, so this is announced to the watcher and reflected in
        the IsStatusNotifierHostRegistered property + signal.
        """
        self._host_registered = True
        if self._am_watcher and self._watcher is not None:
            self._watcher.StatusNotifierHostRegistered(service)
            self._watcher.emit_properties_changed(
                {"IsStatusNotifierHostRegistered": True}
            )

    def _on_name_reply(self, reply, err) -> None:
        if err is not None:
            log.warning("could not request %s: %s", WATCHER_NAME, err)
        elif reply == RequestNameReply.PRIMARY_OWNER:
            self._am_watcher = True
            log.info("owns %s", WATCHER_NAME)
        else:
            self._am_watcher = False
            self._adopt_existing()
        # Announce a host on whichever process owns the name (us or a foreign
        # watcher) so applets waiting for a host go ahead and register.
        if self.bus is not None:
            self.bus.call(
                Message(
                    destination=WATCHER_NAME,
                    path=WATCHER_PATH,
                    interface="org.kde.StatusNotifierWatcher",
                    member="RegisterStatusNotifierHost",
                    signature="s",
                    body=["hyprtk-bar"],
                ),
                lambda reply, err: None,
            )
        self._reset_nm_applet()

    def _watch_dbus(self) -> None:
        try:
            proxy = self.bus.get_proxy_object(
                "org.freedesktop.DBus", "/org/freedesktop/DBus", DBUS_INTROSPECTION
            )
            self._dbus_iface = proxy.get_interface("org.freedesktop.DBus")
            self._dbus_iface.on_name_owner_changed(self._on_name_owner_changed)
        except Exception as exc:
            log.warning("could not watch name ownership: %s", exc)

    def _watch_watcher_signals(self) -> None:
        """Adopt items registered with whoever owns the watcher name.

        The proxy resolves to the current owner (this process included), so new
        registrations and removals are picked up even while a foreign watcher
        (e.g. waybar) holds the name.
        """
        try:
            proxy = self.bus.get_proxy_object(
                WATCHER_NAME, WATCHER_PATH, WATCHER_INTROSPECTION
            )
            iface = proxy.get_interface("org.kde.StatusNotifierWatcher")
            iface.on_status_notifier_item_registered(self._on_watcher_registered)
            iface.on_status_notifier_item_unregistered(self._on_watcher_unregistered)
            self._watcher_proxy_iface = iface
        except Exception as exc:
            log.warning("could not watch watcher signals: %s", exc)

    def _on_watcher_registered(self, service: str) -> None:
        if service and not self._am_watcher:
            self.register(service)

    def _on_watcher_unregistered(self, service: str) -> None:
        if not service:
            return
        for key, item in list(self._items.items()):
            if item.service == service:
                self.unregister(key)

    def _on_name_owner_changed(self, name, old, new) -> None:
        if name == WATCHER_NAME:
            if new and new != (self.bus.unique_name if self.bus else ""):
                # another process took the name; adopt its items
                self._am_watcher = False
                self._adopt_existing()
            return
        for key, item in list(self._items.items()):
            if item.service == name and not new:
                self.unregister(key)

    # ── item management ───────────────────────────────────────────

    def services(self) -> list[str]:
        return list(self._items)

    def _reset_nm_applet(self) -> None:
        """Kill and relaunch nm-applet so it re-registers with our watcher.

        nm-applet only registers once at launch, so after a watcher handoff it
        stays orphaned. Restarting it makes it call RegisterStatusNotifierItem
        on whichever process owns the name now (usually us).
        """
        if not (self._cfg.get("tray") or {}).get("reset_nm_applet"):
            return

        def _do():
            try:
                subprocess.run(
                    ["pkill", "-x", "nm-applet"], capture_output=True, timeout=5
                )
            except (subprocess.SubprocessError, OSError):
                pass
            time.sleep(0.4)
            try:
                subprocess.Popen(
                    ["nm-applet", "--indicator"],
                    start_new_session=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                log.info("relaunched nm-applet")
            except OSError as exc:
                log.warning("could not relaunch nm-applet: %s", exc)

        threading.Thread(target=_do, daemon=True, name="nm-applet-reset").start()

    def register(self, arg: str, sender: str | None = None) -> None:
        service, path = self._split_arg(arg, sender)
        if not service:
            log.warning("could not resolve tray item %r", arg)
            return
        key = service if path == ITEM_PATH else f"{service}{path}"
        if key in self._items:
            return
        # Any session-bus app can flood RegisterStatusNotifierItem; cap the
        # number of tracked items so a flood can't grow the bar unboundedly.
        if len(self._items) >= _MAX_SNI_ITEMS:
            log.warning("tray item limit reached (%d); ignoring %r", _MAX_SNI_ITEMS, arg)
            return
        item = SniItem(self, service, path)
        try:
            item.connect()
        except Exception as exc:
            log.warning("could not connect tray item %r: %s", arg, exc)
            return
        self._items[key] = item
        self._tray.set_item(key, item)
        self._emit_registered(service)

    def unregister(self, key: str) -> None:
        item = self._items.pop(key, None)
        if item is None:
            return
        item.detach()
        self._tray.remove_item(key)
        self._emit_unregistered(item.service)

    def refresh_item(self, key: str) -> None:
        GLib.idle_add(self._do_refresh, key)

    def _do_refresh(self, key: str) -> bool:
        item = self._items.get(key)
        if item is not None:
            self._tray.set_item(key, item)
        return GLib.SOURCE_REMOVE

    def _emit_registered(self, service: str) -> None:
        if self._am_watcher and self._watcher is not None:
            self._watcher.StatusNotifierItemRegistered(service)
            self._watcher.emit_properties_changed(
                {"RegisteredStatusNotifierItems": list(self._items)}
            )

    def _emit_unregistered(self, service: str) -> None:
        if self._am_watcher and self._watcher is not None:
            self._watcher.StatusNotifierItemUnregistered(service)
            self._watcher.emit_properties_changed(
                {"RegisteredStatusNotifierItems": list(self._items)}
            )

    def _split_arg(self, arg: str, sender: str | None = None) -> tuple[str, str]:
        arg = arg.strip()
        if not arg:
            return "", ITEM_PATH
        if arg.startswith("/"):
            # Path-only: the item lives on the caller's own bus name.
            return sender or "", arg
        if "/" in arg:
            service, _, path = arg.rpartition("/")
            return service, f"/{path}"
        return arg, ITEM_PATH

    # ── adoption (when another process owns the name) ─────────────

    def _adopt_existing(self) -> None:
        if self.bus is None or self._watcher is None:
            return
        try:
            proxy = self.bus.get_proxy_object(
                WATCHER_NAME, WATCHER_PATH, WATCHER_INTROSPECTION
            )
            iface = proxy.get_interface("org.kde.StatusNotifierWatcher")
        except Exception as exc:
            log.debug("nothing to adopt: %s", exc)
            return

        def _got(items, err):
            if err is not None:
                return
            for service in items or []:
                self.register(service)

        # Callback form, NOT `_sync`: this runs inside dbus-next's own dispatch
        # (called from _on_name_reply / _on_name_owner_changed), and a sync
        # getter nests a GLib.MainLoop there and deadlocks.
        try:
            iface.get_registered_status_notifier_items(_got)
        except Exception as exc:
            log.debug("nothing to adopt: %s", exc)