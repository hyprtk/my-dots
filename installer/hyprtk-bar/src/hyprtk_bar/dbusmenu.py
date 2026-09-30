"""com.canonical.dbusmenu client: renders SNI tray items' menus.

Many StatusNotifier items export their context menu as a `com.canonical.dbusmenu`
object (the `Menu` property). Instead of asking the applet to open its own menu
(`ContextMenu`, which some applets position wrong under Wayland), we fetch the
menu layout with `GetLayout` and turn it into the version-agnostic item model
consumed by ``menus.MenuPopup`` (GTK4) / ``menus.build_gtk3_menu`` (GTK3),
firing `Event` back for activation.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · dbusmenu
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging

from .compat import GdkPixbuf, GLib, Gtk  # noqa: E402

from dbus_next import Message, Variant  # noqa: E402

from .widgets import safe_icon_name  # noqa: E402

log = logging.getLogger("hyprtk_bar.dbusmenu")

IFACE = "com.canonical.dbusmenu"

# A malicious (or buggy) item can return a huge/deep layout; cap both so the
# menu build can't blow up memory or hit RecursionError on the GLib main loop.
_MAX_DEPTH = 10
_MAX_ITEMS = 200


def _unpack(value):
    """Recursively unwrap dbus-next Variant objects."""
    if isinstance(value, Variant):
        return _unpack(value.value)
    if isinstance(value, list):
        return [_unpack(v) for v in value]
    if isinstance(value, tuple):
        return tuple(_unpack(v) for v in value)
    if isinstance(value, dict):
        return {k: _unpack(v) for k, v in value.items()}
    return value


def _pixbuf_from_argb(width: int, height: int, data: bytes):
    try:
        if width <= 0 or height <= 0 or len(data) < width * height * 4:
            return None
        # Icon data is remote-controlled; cap dimensions so a large icon-data
        # can't force a big allocation on every menu open (mirrors the tray's
        # SNI IconPixmap cap).
        if width > 512 or height > 512:
            return None
        return GdkPixbuf.Pixbuf.new_from_bytes(
            GLib.Bytes(bytes(data)),
            GdkPixbuf.Colorspace.RGB,
            True,  # has_alpha
            8,     # bits per sample
            width, height,
            width * 4,
        )
    except Exception:
        return None


class DbusMenu:
    """Client for one com.canonical.dbusmenu object on the session bus."""

    def __init__(self, bus, service: str, path: str):
        self.bus = bus
        self.service = service
        self.path = path

    # ── public ───────────────────────────────────────────────────

    def build(self, on_ready):
        """Fetch the menu layout and call ``on_ready(items | None)``.

        The fetch is async; ``on_ready`` runs on the GLib main loop (the glib
        MessageBus dispatches there), so the returned item model can be popped
        up immediately.
        """
        try:
            self.bus.call(
                Message(
                    destination=self.service,
                    path=self.path,
                    interface=IFACE,
                    member="GetLayout",
                    signature="iias",
                    body=[0, -1, []],
                ),
                lambda reply, err: self._on_layout(reply, err, on_ready),
            )
        except Exception as exc:
            log.warning("dbusmenu GetLayout failed: %s", exc)
            on_ready(None)

    # ── layout parsing ────────────────────────────────────────────

    def _on_layout(self, reply, err, on_ready) -> None:
        if err is not None or reply is None:
            log.warning("dbusmenu GetLayout failed: %s", err)
            on_ready(None)
            return
        try:
            _, tree = reply.body  # (revision, (id, props, children))
            _, props, children = tree
            props = _unpack(props or {})
            children = _unpack(children or [])
        except Exception as exc:
            log.warning("could not parse dbusmenu layout: %s", exc)
            on_ready(None)
            return
        self._items_remaining = _MAX_ITEMS
        try:
            items = self._build_items(children, depth=0)
        except Exception as exc:
            # Never let a malformed item crash the GLib callback chain.
            log.warning("dbusmenu build failed: %s", exc)
            items = []
        on_ready(items)

    def _build_items(self, children, depth: int = 0) -> list:
        items: list = []
        if depth > _MAX_DEPTH:
            return items
        for node in children:
            if self._items_remaining <= 0:
                break
            item = self._build_item(node, depth)
            if item is not None:
                items.append(item)
                self._items_remaining -= 1
        return items

    def _build_item(self, node, depth: int):
        try:
            item_id, props, children = node
            props = _unpack(props or {}) or {}
            children = _unpack(children or []) or []
        except Exception as exc:
            log.warning("bad dbusmenu item: %s", exc)
            return None

        if not props.get("visible", True):
            return None
        if props.get("type") == "separator":
            return {"type": "separator"}

        label = props.get("label", "") or ""
        display = props.get("children-display", "")
        toggle_type = props.get("toggle-type", "")
        toggle_state = props.get("toggle-state", 0)
        enabled = props.get("enabled", True)
        image = self._icon_image(props)

        item: dict = {
            "label": label,
            "enabled": bool(enabled),
            "activate": (lambda iid=item_id: self._event(iid)),
        }
        if image is not None:
            item["icon"] = image
        if display == "submenu":
            item["children"] = self._build_items(children, depth + 1)
        elif toggle_type == "radio":
            item["toggle"] = "radio"
            item["active"] = toggle_state == 1
        elif toggle_type == "checkmark":
            item["toggle"] = "check"
            item["active"] = toggle_state == 1
        return item

    def _icon_image(self, props):
        # icon-name is remote-controlled; sanitize so a path-like name can't
        # reach GTK's icon loader (which opens it as a file).
        name = safe_icon_name(props.get("icon-name"))
        if name:
            return compat.new_image_from_icon_name(name)
        data = props.get("icon-data")
        if data:
            try:
                width, height, _rowstride, _alpha, _bpp, _channels, pixels = data
                pixbuf = _pixbuf_from_argb(int(width), int(height), pixels)
                if pixbuf is not None:
                    return compat.new_raster_from_pixbuf(pixbuf)
            except Exception:
                pass
        return None

    def _event(self, item_id: int, event: str = "clicked", data: str = "", ts: int = 0) -> None:
        try:
            self.bus.call(
                Message(
                    destination=self.service,
                    path=self.path,
                    interface=IFACE,
                    member="Event",
                    signature="isvu",
                    body=[item_id, event, Variant("s", data), ts],
                ),
                lambda reply, err: None,
            )
        except Exception as exc:
            log.warning("dbusmenu Event failed: %s", exc)