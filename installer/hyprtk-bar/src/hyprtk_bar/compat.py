"""Single GTK bootstrap + GTK3/GTK4 compatibility shim (port phase 0).

Part of the GTK3 -> GTK4 port for the hyprtk desktop. See
``hyprtk-bar/GTK4-MIGRATION.md`` for the full plan.

Every bar module imports its GTK symbols from here instead of talking to
``gi.repository`` directly::

    from .compat import Gdk, GLib, Gtk, GtkLayerShell
    #      ^ subpackages use ``from ..compat import ...``

This gives the port exactly one place that decides the toolkit version, and
one place to hang the polyfills for the API that GTK4 removed or reshaped
(``pack_start`` vs ``append``, ``StyleContext`` vs CSS classes,
``Gdk.Screen`` vs ``Gdk.Display``, ``.show_all()``, ``.destroy()``, ...).
The mechanical sweep in ``tools/gtk4_sweep.py`` rewrites the old per-module
bootstrap blocks into imports of this module.

Version selection
-----------------
``HYPRTK_GTK`` picks the stack:

* ``4`` (**default**, the target of this project) -> Gtk 4.0 + Gtk4LayerShell 1.0
* ``3`` -> Gtk 3.0 + GtkLayerShell 0.1 (escape hatch for A/B runs while the
  rest of the code is still being ported; the port is intentionally mid-flight
  in this tree)

``GtkLayerShell`` is always the name modules import — under GTK4 it is bound to
the ``Gtk4LayerShell`` namespace, whose C API and enums are identical, so the
seven layer-shell call sites do not need to change name.
"""

from __future__ import annotations

import logging
import os
from collections import namedtuple

import gi

log = logging.getLogger(__name__)

# ── Toolkit selection ────────────────────────────────────────────────────────
_TARGET = (os.environ.get("HYPRTK_GTK") or "4").strip() or "4"
IS_GTK4 = not _TARGET.startswith("3")
IS_GTK3 = not IS_GTK4

if IS_GTK4:
    GTK_VERSION = "4.0"
    GDK_VERSION = "4.0"
    LAYER_SHELL_NAMESPACE = "Gtk4LayerShell"
    LAYER_SHELL_VERSION = "1.0"
else:
    GTK_VERSION = "3.0"
    GDK_VERSION = "3.0"
    LAYER_SHELL_NAMESPACE = "GtkLayerShell"
    LAYER_SHELL_VERSION = "0.1"

# Version pins must be declared before the namespaces are imported. Required
# once, here, for the whole app.
gi.require_version("Gtk", GTK_VERSION)
gi.require_version("Gdk", GDK_VERSION)
gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
gi.require_version("Pango", "1.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version(LAYER_SHELL_NAMESPACE, LAYER_SHELL_VERSION)

from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango  # noqa: E402

if IS_GTK4:
    from gi.repository import Gtk4LayerShell as GtkLayerShell  # noqa: E402
else:
    from gi.repository import GtkLayerShell  # noqa: E402

# GLibUnix carries the Unix signal helpers __main__ uses. Its typelib is split
# out on some distros, so tolerate it being absent (the bar's signal helper
# already degrades gracefully).
try:
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import GLibUnix  # noqa: E402
except (ValueError, ImportError):  # pragma: no cover - distro dependent
    GLibUnix = None

# A widget class that can host a child and receive pointer events: GTK4 has no
# Gtk.EventBox, so the shell widgets derive from a plain Gtk.Box there and use
# controllers for input, while GTK3 keeps the EventBox (whose window makes
# enter/leave/press events work on the box).
if IS_GTK4:
    EventSurface = Gtk.Box
else:
    EventSurface = Gtk.EventBox

__all__ = [
    "IS_GTK3",
    "IS_GTK4",
    "GTK_VERSION",
    "GDK_VERSION",
    "LAYER_SHELL_VERSION",
    "Gdk",
    "GdkPixbuf",
    "Gio",
    "GLib",
    "GLibUnix",
    "Gtk",
    "GtkLayerShell",
    "Pango",
    "EventSurface",
    # lifecycle
    "run_main",
    "quit_main",
    # CSS classes
    "add_class",
    "remove_class",
    "has_class",
    # visibility / teardown
    "show",
    "show_all",
    "hide",
    "destroy",
    # containers
    "set_child",
    "set_single_child",
    "single_child",
    "box_append",
    "box_prepend",
    "pack_start",
    "pack_end",
    "children",
    "is_container",
    "toplevel",
    # input / gestures
    "on_press",
    "on_hover",
    "on_motion",
    "on_key",
    "on_drag",
    "on_focus_out",
    "popover_release",
    "transparent_surface",
    "popover_anchor",
    "KeyEvent",
    "PressEvent",
    "BUTTON_PRESS_TYPE",
    "DOUBLE_BUTTON_PRESS_TYPE",
    # geometry
    "compute_bounds",
    "allocation",
    "Alloc",
    "screen_size",
    "monitor_is_primary",
    # misc
    "set_wrap",
    "hide_from_show_all",
    "set_no_show_all",
    "set_draw_func",
    "new_window",
    "set_window_position",
    "apply_rgba_visual",
    "reset_widgets",
    "is_radio",
    "font_button_set_font_name",
    "paned_pack2",
    "paned_pack1",
    "icon_theme",
    "image_set_from_icon_name",
    "new_image_from_gicon",
    "new_button_from_icon_name",
    "new_image_from_icon_name",
    "join_radio_group",
    "radio_with_label_from_widget",
    "new_radio",
    "set_button_image",
    "set_skip_taskbar_hint",
    "set_skip_pager_hint",
    "set_app_paintable",
    "set_accept_focus",
    "set_keep_above",
    "set_relief",
    "is_flat",
    "add",
    "style_context",
    "toplevel",
    "event_surface",
    "set_visible_window",
    "style_context",
    "toplevel",
    "event_surface",
    "set_visible_window",
    # display / monitors
    "get_display",
    "monitors",
    "primary_monitor",
    "monitor_geometry",
    # providers
    "add_provider_for_display",
    "remove_provider_for_display",
    # surfaces / input
    "widget_surface",
    "set_input_region",
    # measurement
    "preferred_size",
    "preferred_width",
    "preferred_height",
    "allocated_size",
    "allocated_width",
    "allocated_height",
]


# ── Main loop ────────────────────────────────────────────────────────────────
# GTK4 removed Gtk.main()/Gtk.main_quit(). Drive an explicit GLib.MainLoop
# instead (the bar already manages its own lifetime and single-instance flock,
# so it does not need Gtk.Application). A stack keeps nested loops — the modal
# settings dialogs block on one — quitting the right loop.
_main_loops: list = []


def run_main() -> None:
    """Run the toolkit main loop (replaces ``Gtk.main()``)."""
    if IS_GTK4:
        loop = GLib.MainLoop()
        _main_loops.append(loop)
        try:
            loop.run()
        finally:
            _main_loops.pop()
    else:
        Gtk.main()


def quit_main() -> None:
    """Quit the innermost running main loop (replaces ``Gtk.main_quit()``)."""
    if IS_GTK4:
        if _main_loops:
            _main_loops[-1].quit()
    else:
        Gtk.main_quit()


def set_secondary_text(dialog, text: str) -> None:
    """Set a message dialog's secondary text.

    GTK4 removed ``Gtk.MessageDialog.format_secondary_text()`` and exposes no
    setter method either, so set the ``secondary-text`` property directly.
    """
    if IS_GTK4:
        dialog.set_property("secondary-text", text)
    else:
        dialog.format_secondary_text(text)


def dialog_run(dialog) -> int:
    """Run *dialog* modally, blocking like GTK3's removed ``Gtk.Dialog.run()``.

    GTK4 removed ``Gtk.Dialog.run()``/``Gtk.Dialog.response()``. Block on a
    nested main loop that quits when the dialog emits ``response``, then return
    that response. The caller keeps ownership and still destroys the dialog.
    """
    if not IS_GTK4:
        return dialog.run()

    result = {"response": Gtk.ResponseType.NONE}

    def _on_response(_dialog, response):
        result["response"] = response
        quit_main()

    handler = dialog.connect("response", _on_response)
    show_all(dialog)
    run_main()
    try:
        dialog.disconnect(handler)
    except Exception:
        pass
    return result["response"]


# ── CSS classes (Gtk.StyleContext removed in GTK4) ───────────────────────────
def add_class(widget, name: str) -> None:
    if IS_GTK4:
        widget.add_css_class(name)
    else:
        widget.get_style_context().add_class(name)


def remove_class(widget, name: str) -> None:
    if IS_GTK4:
        widget.remove_css_class(name)
    else:
        widget.get_style_context().remove_class(name)


def has_class(widget, name: str) -> bool:
    if IS_GTK4:
        return widget.has_css_class(name)
    return widget.get_style_context().has_class(name)


class _StyleContext:
    """Stand-in for the removed ``Gtk.StyleContext`` (CSS classes only).

    GTK4 removed per-widget style contexts, but code shaped as
    ``ctx = w.get_style_context(); ctx.add_class(...)`` can keep that shape via
    :func:`style_context`. ``add_provider`` registers on the display (the only
    scope GTK4 supports).
    """

    __slots__ = ("_widget",)

    def __init__(self, widget):
        self._widget = widget

    def add_class(self, name: str) -> None:
        add_class(self._widget, name)

    def remove_class(self, name: str) -> None:
        remove_class(self._widget, name)

    def has_class(self, name: str) -> bool:
        return has_class(self._widget, name)

    def add_provider(self, provider, priority=None) -> None:
        add_provider_for_display(provider, priority)


def style_context(widget) -> _StyleContext:
    """A CSS-class shim for ``widget.get_style_context()``."""
    return _StyleContext(widget)


# ── Visibility / teardown ────────────────────────────────────────────────────
def show(widget) -> None:
    """Replaces ``widget.show()``."""
    if IS_GTK4:
        widget.set_visible(True)
        if isinstance(widget, Gtk.Window):
            widget.present()
    else:
        widget.show()


def show_all(widget) -> None:
    """Replaces ``widget.show_all()``.

    GTK4 has no ``show_all`` and widgets are visible by default, so this only
    reveals the widget itself (leaving deliberately-hidden children hidden) and
    presents it when it is a window. Recursing would undo explicit ``hide()``
    calls such as the window-title module's empty label.
    """
    if IS_GTK4:
        widget.set_visible(True)
        if isinstance(widget, Gtk.Window):
            widget.present()
    else:
        widget.show_all()


def hide(widget) -> None:
    """Replaces ``widget.hide()``."""
    if IS_GTK4:
        widget.set_visible(False)
    else:
        widget.hide()


def destroy(widget) -> None:
    """Replaces ``widget.destroy()``.

    GTK4 widgets are torn down by unparenting; only windows keep ``destroy``.
    """
    if IS_GTK4:
        if isinstance(widget, Gtk.Window):
            widget.destroy()
        else:
            widget.unparent()
    else:
        widget.destroy()


def chooser_path(dialog):
    """Selected path from a ``Gtk.FileChooserDialog``.

    GTK4 removed ``Gtk.FileChooser.get_filename``; use ``get_file()``.
    """
    if IS_GTK4:
        gfile = dialog.get_file()
        return gfile.get_path() if gfile is not None else None
    return dialog.get_filename()


# ── Containers ───────────────────────────────────────────────────────────────
def set_child(container, child) -> None:
    """Attach the single child of a window (GTK4) or ``add`` it (GTK3)."""
    if IS_GTK4:
        container.set_child(child)
    else:
        container.add(child)


def set_single_child(container, child) -> None:
    """Give a single-child container its child.

    GTK4 containers use ``set_child`` (Window, ScrolledWindow, Overlay, Button)
    or ``append`` (Box, ListBox, FlowBox); GTK3 containers all use ``add``.
    """
    if IS_GTK4:
        if hasattr(container, "set_child"):
            container.set_child(child)
        elif hasattr(container, "append"):
            container.append(child)
        else:
            raise TypeError(f"cannot add a child to {type(container).__name__}")
    else:
        container.add(child)


# Alias used by the mechanical sweep for ``X.add(child)``.
add = set_single_child


def clear_child(container, child=None) -> None:
    """Detach *child* from *container*.

    GTK4 removed ``Gtk.Container.remove``; a ``Gtk.Window`` (and other
    single-child containers) drop their child with ``set_child(None)``, while
    ``Box``/``Grid``/``ListBox`` still expose ``remove``. GTK3 uses ``remove``
    everywhere. Passing *child* is optional on GTK4 but required on GTK3.
    """
    if IS_GTK4:
        if hasattr(container, "set_child"):
            container.set_child(None)
            return
        container.remove(child)
        return
    container.remove(child)


class _CenterBoxGTK3(Gtk.Overlay):
    """A minimal ``Gtk.CenterBox`` stand-in for GTK3 (which has none).

    The centre child is overlaid with ``halign=CENTER`` so it sits on the true
    midpoint regardless of the side widths — the same behaviour the GTK4
    ``Gtk.CenterBox`` gives the bar pill. (Caveat: a GTK3 ``Overlay`` is
    non-windowed, so a press handler attached to it needs the caller's own
    input surface.)
    """

    def __init__(self) -> None:
        super().__init__()
        self._start = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self._center = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self._end = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        for box, align in (
            (self._start, Gtk.Align.START),
            (self._center, Gtk.Align.CENTER),
            (self._end, Gtk.Align.END),
        ):
            box.set_halign(align)
            box.set_valign(Gtk.Align.FILL)
        self.add(self._center)
        self.add_overlay(self._start)
        self.add_overlay(self._end)

    @staticmethod
    def _fill(target, widget) -> None:
        for child in list(target.get_children()):
            target.remove(child)
        if widget is not None:
            target.add(widget)

    def set_start_widget(self, widget) -> None:
        self._fill(self._start, widget)

    def set_center_widget(self, widget) -> None:
        self._fill(self._center, widget)

    def set_end_widget(self, widget) -> None:
        self._fill(self._end, widget)


def center_box():
    """A centre-box widget: ``Gtk.CenterBox`` (GTK4) or an Overlay emulation."""
    return Gtk.CenterBox() if IS_GTK4 else _CenterBoxGTK3()


def make_window_draggable(window, header) -> None:
    """Let a frameless *window* be moved by dragging its *header* widget.

    GTK4 removed ``Gtk.Window.begin_move_drag``; the equivalent is a
    ``Gtk.WindowDragGesture`` attached to the header, which starts a
    compositor-side move (works on Wayland). GTK3 keeps the classic
    button-press handler.
    """
    if IS_GTK4:
        gesture_cls = getattr(Gtk, "WindowDragGesture", None)
        if gesture_cls is not None:
            header.add_controller(gesture_cls())
        return

    def _press(widget, event):
        if event.button == 1 and event.type == Gdk.EventType.BUTTON_PRESS:
            window.begin_move_drag(
                event.button, int(event.x_root), int(event.y_root), event.time
            )
            return True
        return False

    header.connect("button-press-event", _press)


def single_child(container):
    """The single child of a container, or ``None``."""
    if IS_GTK4:
        return container.get_first_child()
    getter = getattr(container, "get_child", None)
    if getter is not None:
        return getter()
    kids = container.get_children() if hasattr(container, "get_children") else []
    return kids[0] if kids else None


def _apply_pack_flags(box, child, expand: bool, padding: int) -> None:
    """Map a GTK3 ``pack`` expand/padding onto a GTK4 box child.

    ``hexpand``/``vexpand`` alone are *not* equivalent to GTK3's per-child
    ``expand``: in GTK4 :meth:`Gtk.Widget.compute_expand` propagates a
    descendant's expand upward, so a child packed with ``expand=False`` whose
    grandchildren expand would itself be treated as expandable (this is what
    made the Theme Manager sidebar claim half the dialogue). Calling
    ``set_*_expand_set(True)`` alongside pins the explicit flag and stops the
    propagation, matching GTK3 semantics.
    """
    horizontal = box.get_orientation() == Gtk.Orientation.HORIZONTAL
    if horizontal:
        child.set_hexpand(expand)
        child.set_hexpand_set(True)
        if padding:
            child.set_margin_start(padding)
            child.set_margin_end(padding)
    else:
        child.set_vexpand(expand)
        child.set_vexpand_set(True)
        if padding:
            child.set_margin_top(padding)
            child.set_margin_bottom(padding)


def box_append(box, child) -> None:
    """Append a child at the trailing side (GTK4 ``append`` / GTK3 ``pack_end``)."""
    if IS_GTK4:
        box.append(child)
        _apply_pack_flags(box, child, expand=False, padding=0)
    else:
        box.pack_end(child, False, False, 0)


def box_prepend(box, child) -> None:
    """Prepend a child at the leading side (GTK4 ``prepend`` / GTK3 ``pack_start``)."""
    if IS_GTK4:
        box.prepend(child)
        _apply_pack_flags(box, child, expand=False, padding=0)
    else:
        box.pack_start(child, False, False, 0)


def pack_start(box, child, expand: bool = False, fill: bool = True,
               padding: int = 0) -> None:
    """Best-effort ``pack_start`` for GTK4.

    GTK4's ``append`` cannot express expand/fill/padding, so they are mapped to
    widget properties (``hexpand``/``vexpand`` along the box orientation, plus
    margins for padding). This is close but not always pixel-identical; use it
    only where the layout is simple, and port layout-critical call sites by
    hand (see ``bar.py`` / ``layout.py`` / ``desktop/base.py``).
    """
    if not IS_GTK4:
        box.pack_start(child, expand, fill, padding)
        return
    box.append(child)
    _apply_pack_flags(box, child, expand, padding)


def pack_end(box, child, expand: bool = False, fill: bool = True,
             padding: int = 0) -> None:
    """Best-effort ``pack_end`` for GTK4.

    GTK4 has no positional packing, so this appends (trailing side) and maps
    expand/padding onto widget properties, like ``pack_start``. Note that a box
    which *mixes* ``pack_start`` and ``pack_end`` cannot be reproduced this way
    and must be ported by hand.
    """
    if not IS_GTK4:
        box.pack_end(child, expand, fill, padding)
        return
    box.append(child)
    _apply_pack_flags(box, child, expand, padding)


def children(widget) -> list:
    """Return a widget's children as a list (GTK4 has no ``get_children``)."""
    if IS_GTK4:
        out = []
        child = widget.get_first_child()
        while child is not None:
            out.append(child)
            child = child.get_next_sibling()
        return out
    if isinstance(widget, Gtk.Container):
        return widget.get_children()
    return []


def is_container(widget) -> bool:
    """True when ``widget`` can hold children (GTK4 removed ``Gtk.Container``)."""
    if IS_GTK4:
        return hasattr(widget, "get_first_child")
    return isinstance(widget, Gtk.Container)


def toplevel(widget):
    """The widget's toplevel window (``Gtk.Widget.get_toplevel`` is gone in
    GTK4, where the equivalent is ``get_root``)."""
    if IS_GTK4:
        return widget.get_root()
    return widget.get_toplevel()


def event_surface():
    """A widget that can hold a child and receive pointer events.

    ``Gtk.EventBox()`` on GTK3; a plain ``Gtk.Box`` on GTK4 (input is attached
    with controllers, and ``set_visible_window`` becomes a no-op).
    """
    if IS_GTK4:
        return Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
    return Gtk.EventBox()


def set_visible_window(surface, visible: bool) -> None:
    """Toggle an EventBox's own window (no-op on GTK4, which has no EventBox)."""
    if IS_GTK3:
        surface.set_visible_window(visible)


# ── Display / monitors (Gdk.Screen removed in GTK4) ──────────────────────────
def get_display():
    """The ``Gdk.Display`` (GTK4) — ``None`` under GTK3, which uses screens."""
    if IS_GTK4:
        return Gdk.Display.get_default()
    return None


def _list_monitors(display) -> list:
    mons = display.get_monitors()
    try:
        return list(mons)
    except TypeError:
        return [mons.get_item(i) for i in range(mons.get_n_items())]


def monitors() -> list:
    """All monitors, version-agnostically."""
    display = Gdk.Display.get_default()
    if display is None:
        return []
    if IS_GTK4:
        return _list_monitors(display)
    return [display.get_monitor(i) for i in range(display.get_n_monitors())]


def primary_monitor():
    """The primary monitor.

    GTK4 has no primary-monitor concept, so this falls back to the first
    monitor; call sites that must disambiguate should use
    ``Gdk.Display.get_monitor_at_surface``. On GTK3 the ``is_primary()`` flag is
    used rather than ``get_primary_monitor`` (which returns an index, not a
    monitor, on some builds).
    """
    mons = monitors()
    if not mons:
        return None
    if IS_GTK4:
        return mons[0]
    for m in mons:
        try:
            if m.is_primary():
                return m
        except Exception:
            pass
    return mons[0]


def monitor_geometry(monitor):
    """The monitor's ``Gdk.Rectangle`` geometry."""
    return monitor.get_geometry()


# ── CSS providers (per-widget providers removed in GTK4) ─────────────────────
def add_provider_for_display(provider, priority=None) -> None:
    """Register a ``Gtk.CssProvider`` app-wide.

    GTK4 only supports display-scoped providers (per-widget providers are
    gone), so this is the single supported path on both toolkits.
    """
    if priority is None:
        priority = Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    if IS_GTK4:
        display = Gdk.Display.get_default()
        if display is not None:
            Gtk.StyleContext.add_provider_for_display(display, provider, priority)
    else:
        screen = Gdk.Screen.get_default()
        if screen is not None:
            Gtk.StyleContext.add_provider_for_screen(screen, provider, priority)


def remove_provider_for_display(provider) -> None:
    if IS_GTK4:
        display = Gdk.Display.get_default()
        if display is not None:
            Gtk.StyleContext.remove_provider_for_display(display, provider)
    else:
        screen = Gdk.Screen.get_default()
        if screen is not None:
            Gtk.StyleContext.remove_provider_for_screen(screen, provider)


# ── Surfaces / input region ──────────────────────────────────────────────────
def widget_surface(widget):
    """The widget's ``Gdk.Surface`` (GTK4) or ``Gdk.Window`` (GTK3)."""
    if IS_GTK4:
        native = widget.get_native()
        return native.get_surface() if native is not None else None
    return widget.get_window()


def set_input_region(widget, region) -> None:
    """Shape a widget's input region.

    GTK4 moved this from ``Gdk.Window.input_shape_combine_region`` onto
    ``Gdk.Surface.set_input_region``; the call sites are the bar's click-through
    popups/arc menu.
    """
    if IS_GTK4:
        surface = widget_surface(widget)
        if surface is not None:
            surface.set_input_region(region)
    else:
        window = widget.get_window()
        if window is not None:
            window.input_shape_combine_region(region, 0, 0)


# ── Input / gestures (GdkEvent signals removed in GTK4) ──────────────────────
# GdkEventType values kept locally: GTK4 has no GdkEvent and lacks
# DOUBLE_BUTTON_PRESS, but press handlers compare event.type against these.
BUTTON_PRESS_TYPE = 4
DOUBLE_BUTTON_PRESS_TYPE = 5


class PressEvent:
    """Minimal stand-in for the GTK3 ``Gdk.EventButton`` a press handler expects.

    GTK4 has no ``GdkEvent``; :func:`on_press` builds this so existing
    ``event.button`` / ``event.type`` handlers keep working unchanged.
    Coordinates are widget-local on GTK4 (``x_root``/``y_root`` mirror them);
    call sites that need true root coordinates must use a drag controller.
    """

    __slots__ = ("button", "n_press", "x", "y", "x_root", "y_root", "time", "type")

    def __init__(self, button: int = 0, x: float = 0.0, y: float = 0.0,
                 n_press: int = 1, time: int = 0):
        self.button = button
        self.n_press = n_press
        self.x = x
        self.y = y
        self.x_root = x
        self.y_root = y
        self.time = time
        self.type = (
            DOUBLE_BUTTON_PRESS_TYPE if n_press == 2 else BUTTON_PRESS_TYPE
        )


def on_press(widget, handler, *user_data) -> None:
    """Connect a pointer-press handler.

    ``handler(widget, event, *user_data)`` returns True when the press is
    handled (it then claims the sequence so it does not propagate). On GTK4
    ``event`` is a :class:`PressEvent`; on GTK3 it is the real
    ``Gdk.EventButton``. Any ``user_data`` is forwarded to the handler, matching
    the GTK3 ``connect("button-press-event", handler, user_data)`` form. All
    buttons match.
    """
    if IS_GTK4:
        gesture = Gtk.GestureClick()
        gesture.set_button(0)  # 0 = any button
        def _pressed(gest, n_press, x, y):
            event = PressEvent(gest.get_current_button(), x, y, n_press)
            if handler(widget, event, *user_data):
                gest.set_state(Gtk.EventSequenceState.CLAIMED)
        gesture.connect("pressed", _pressed)
        widget.add_controller(gesture)
    else:
        def _pressed(_widget, event, *ud):
            return bool(handler(widget, event, *ud))
        widget.connect("button-press-event", _pressed, *user_data)


def on_hover(widget, on_enter, on_leave) -> None:
    """Connect pointer enter/leave handlers (no arguments passed to them)."""
    if IS_GTK4:
        motion = Gtk.EventControllerMotion()
        motion.connect("enter", lambda *_a: on_enter())
        motion.connect("leave", lambda *_a: on_leave())
        widget.add_controller(motion)
    else:
        widget.connect("enter-notify-event", lambda *_a: on_enter())
        widget.connect("leave-notify-event", lambda *_a: on_leave())


def on_motion(widget, handler) -> None:
    """Connect a pointer-motion handler (no arguments passed to it)."""
    if IS_GTK4:
        motion = Gtk.EventControllerMotion()
        motion.connect("motion", lambda *_a: handler())
        widget.add_controller(motion)
    else:
        widget.connect("motion-notify-event", lambda *_a: handler())


class KeyEvent:
    """Minimal key event with a ``keyval`` (GdkEventKey replacement)."""

    __slots__ = ("keyval",)

    def __init__(self, keyval: int):
        self.keyval = keyval


def on_key(widget, handler) -> None:
    """Connect a key-press handler (``handler(widget, event.keyval)``)."""
    if IS_GTK4:
        controller = Gtk.EventControllerKey()

        def _pressed(_c, keyval, _keycode, _state):
            return bool(handler(widget, KeyEvent(keyval)))

        controller.connect("key-pressed", _pressed)
        widget.add_controller(controller)
    else:
        def _pressed(_widget, event):
            return bool(handler(widget, event))
        widget.connect("key-press-event", _pressed)


def on_drag(widget, on_begin=None, on_update=None, on_end=None) -> None:
    """Connect a drag gesture.

    ``on_begin()`` starts, ``on_update(offset_x, offset_y)`` reports the offset
    from the drag origin, ``on_end()`` finishes. Uses ``Gtk.GestureDrag`` on both
    toolkits — GTK4 adds it as a controller, GTK3 creates it attached to the
    widget (``Gtk.GestureDrag.new(widget)``; there is no ``attach``).
    """
    gesture = Gtk.GestureDrag() if IS_GTK4 else Gtk.GestureDrag.new(widget)
    if on_begin is not None:
        gesture.connect("drag-begin", lambda *_a: on_begin())
    if on_update is not None:
        gesture.connect("drag-update", lambda _g, ox, oy: on_update(ox, oy))
    if on_end is not None:
        gesture.connect("drag-end", lambda *_a: on_end())
    if IS_GTK4:
        widget.add_controller(gesture)
    # GTK3: the gesture is already attached via ``Gtk.GestureDrag.new(widget)``.


def on_focus_out(widget, handler) -> None:
    """Connect a focus-leave handler (``focus-out-event`` removed in GTK4)."""
    if IS_GTK4:
        controller = Gtk.EventControllerFocus()
        controller.connect("leave", lambda *_a: handler())
        widget.add_controller(controller)
    else:
        widget.connect("focus-out-event", lambda *_a: handler())


def popover_anchor(popover, widget) -> None:
    """Anchor a popover to a widget (GTK4 ``set_parent`` / GTK3 ``set_relative_to``)."""
    if IS_GTK4:
        popover.set_parent(widget)
    else:
        popover.set_relative_to(widget)


def popover_release(popover) -> None:
    """Drop a GTK4 popover's parent (no-op on GTK3)."""
    if IS_GTK4:
        try:
            popover.unparent()
        except Exception:
            pass


def transparent_surface(widget) -> None:
    """Mark a toplevel surface transparent.

    GTK3 made windows transparent with ``set_app_paintable`` + an RGBA visual.
    GTK4 windows/popovers paint an opaque theme background by default, which
    shows through the gaps around the themed pill / popup-box; the
    ``.hyprtk-window`` class removes it (see ``theme.build_css``).
    """
    add_class(widget, "hyprtk-window")


# ── Geometry ─────────────────────────────────────────────────────────────────
def compute_bounds(widget, target):
    """``(x, y, width, height)`` of *widget* in *target*'s space, or ``None``.

    GTK4 computes this with ``Gtk.Widget.compute_bounds``; GTK3 returns the
    (parent-relative) allocation.
    """
    if IS_GTK4:
        ok, rect = widget.compute_bounds(target)
        if not ok:
            return None
        return (
            int(rect.origin.x),
            int(rect.origin.y),
            int(rect.size.width),
            int(rect.size.height),
        )
    alloc = widget.get_allocation()
    return (alloc.x, alloc.y, alloc.width, alloc.height)


def monitor_is_primary(monitor) -> bool:
    """Whether *monitor* is the primary one.

    GTK4 has no primary-monitor concept, so this picks the monitor containing
    the origin (falling back to the first in the display's order).
    """
    if IS_GTK4:
        mons = monitors()
        if not mons:
            return False
        geo = monitor.get_geometry()
        for m in mons:
            g = m.get_geometry()
            if g.x <= 0 < g.x + g.width and g.y <= 0 < g.y + g.height:
                return m == monitor
        return monitor == mons[0]
    try:
        return bool(monitor.is_primary())
    except AttributeError:
        return False


# ── Measurement (Gtk.Widget.measure replaced get_preferred_*/get_allocated_*) ─
def preferred_size(widget) -> tuple[int, int]:
    """Natural (preferred) ``(width, height)`` of a widget."""
    if IS_GTK4:
        width = widget.measure(Gtk.Orientation.HORIZONTAL, -1)[1]
        height = widget.measure(Gtk.Orientation.VERTICAL, -1)[1]
        return width, height
    return (
        widget.get_preferred_width()[1],
        widget.get_preferred_height()[1],
    )


def preferred_width(widget, for_height: int = -1) -> int:
    if IS_GTK4:
        return widget.measure(Gtk.Orientation.HORIZONTAL, for_height)[1]
    return widget.get_preferred_width()[1]


def preferred_height(widget, for_width: int = -1) -> int:
    if IS_GTK4:
        return widget.measure(Gtk.Orientation.VERTICAL, for_width)[1]
    return widget.get_preferred_height()[1]


def allocated_size(widget) -> tuple[int, int]:
    """Currently allocated ``(width, height)``."""
    if IS_GTK4:
        return widget.get_width(), widget.get_height()
    return widget.get_allocated_width(), widget.get_allocated_height()


def allocated_width(widget) -> int:
    if IS_GTK4:
        return widget.get_width()
    return widget.get_allocated_width()


def allocated_height(widget) -> int:
    if IS_GTK4:
        return widget.get_height()
    return widget.get_allocated_height()


# ── Misc widget shims ────────────────────────────────────────────────────────
def set_wrap(widget, wrap: bool = True) -> None:
    """Label line-wrapping (``set_line_wrap`` on GTK3, ``set_wrap`` on GTK4)."""
    if IS_GTK4:
        widget.set_wrap(wrap)
    else:
        widget.set_line_wrap(wrap)


def set_no_show_all(widget, flag: bool = True) -> None:
    """Compatibility for ``Gtk.Widget.set_no_show_all`` (gone in GTK4)."""
    if IS_GTK4:
        if flag:
            widget.set_visible(False)
    else:
        widget.set_no_show_all(flag)


def hide_from_show_all(widget) -> None:
    """Exclude a widget from ``show_all``.

    GTK4 has no ``no-show-all`` flag and widgets start visible, so this simply
    hides it; GTK3 gets the real flag.
    """
    set_no_show_all(widget, True)


def set_draw_func(area, handler) -> None:
    """Connect a ``Gtk.DrawingArea`` draw callback.

    GTK4 removed the ``::draw`` signal; ``set_draw_func`` passes
    ``(area, cr, width, height)``. Existing handlers take ``(widget, cr)`` and
    return a bool.
    """
    if IS_GTK4:
        def _draw(_area, cr, _width, _height):
            return handler(_area, cr)
        area.set_draw_func(_draw)
    else:
        area.connect("draw", handler)


def new_window():
    """A plain toplevel ``Gtk.Window`` (GTK4 dropped ``Gtk.WindowType``)."""
    if IS_GTK4:
        return Gtk.Window()
    return Gtk.Window(type=Gtk.WindowType.TOPLEVEL)


# ── GTK3 window hints removed in GTK4 (no-ops there) ─────────────────────────
def set_skip_taskbar_hint(window, value: bool = True) -> None:
    if IS_GTK3:
        window.set_skip_taskbar_hint(value)


def set_skip_pager_hint(window, value: bool = True) -> None:
    if IS_GTK3:
        window.set_skip_pager_hint(value)


def set_app_paintable(window, value: bool = True) -> None:
    if IS_GTK3:
        window.set_app_paintable(value)


def set_accept_focus(window, value: bool = True) -> None:
    if IS_GTK3:
        window.set_accept_focus(value)


def set_keep_above(window, value: bool = True) -> None:
    if IS_GTK3:
        window.set_keep_above(value)


def set_relief(widget, relief=None) -> None:
    """GTK3 ``set_relief``; GTK4 removed relief (buttons are flat by default)."""
    if IS_GTK3:
        widget.set_relief(relief if relief is not None else Gtk.ReliefStyle.NONE)


def is_flat(widget) -> bool:
    """Whether a button has no relief (GTK4 buttons are always flat)."""
    if IS_GTK4:
        return True
    try:
        return widget.get_relief() == Gtk.ReliefStyle.NONE
    except Exception:
        return False


def set_window_position(window, position=None) -> None:
    """GTK3 ``Gtk.Window.set_position`` (removed in GTK4 — a no-op there).

    Defaults to ``Gtk.WindowPosition.CENTER``, matching the swept
    ``set_position(Gtk.WindowPosition.CENTER)`` call.
    """
    if IS_GTK3:
        window.set_position(
            Gtk.WindowPosition.CENTER if position is None else position
        )


def apply_rgba_visual(window) -> None:
    """Make a toplevel transparent-capable.

    GTK3 needs an explicit RGBA visual on the window; GTK4 surfaces are RGBA by
    default, so this is a no-op there.
    """
    if not IS_GTK4:
        visual = window.get_screen().get_rgba_visual()
        if visual:
            window.set_visual(visual)


def reset_widgets() -> None:
    """Force a full style refresh (GTK3 ``StyleContext.reset_widgets``).

    GTK4 has no equivalent; reloading the CssProvider already restyles.
    """
    if IS_GTK3:
        screen = Gdk.Screen.get_default()
        if screen is not None:
            Gtk.StyleContext.reset_widgets(screen)


# ── Buttons / radio groups (Gtk.RadioButton removed in GTK4) ─────────────────
def set_button_image(button, widget) -> None:
    """Give a button an image child (``set_image`` on GTK3)."""
    if IS_GTK4:
        button.set_child(widget)
    else:
        button.set_image(widget)


def new_radio(label: str = "", group=None):
    """A radio button (GTK4 uses a grouped ``Gtk.CheckButton``)."""
    if IS_GTK4:
        button = Gtk.CheckButton(label=label)
        if group is not None:
            button.set_group(group)
        return button
    return Gtk.RadioButton(group=group, label=label)


def radio_with_label_from_widget(group_widget, label: str = ""):
    """A radio button joined to *group_widget*'s group."""
    if IS_GTK4:
        button = Gtk.CheckButton(label=label)
        if group_widget is not None:
            button.set_group(group_widget)
        return button
    return Gtk.RadioButton.new_with_label_from_widget(group_widget, label)


def join_radio_group(button, leader) -> None:
    """Join *button* to the radio group led by *leader*."""
    if IS_GTK4:
        button.set_group(leader)
    else:
        button.join_group(leader)


def is_radio(widget) -> bool:
    """Whether a widget is a radio button."""
    if IS_GTK4:
        try:
            return isinstance(widget, Gtk.CheckButton) and widget.get_group() is not None
        except Exception:
            return False
    return isinstance(widget, Gtk.RadioButton)


# ── Icon theme / paned / font button ─────────────────────────────────────────
def icon_theme():
    """The icon theme (``Gtk.IconTheme.get_default`` on GTK3)."""
    if IS_GTK4:
        display = Gdk.Display.get_default()
        return Gtk.IconTheme.get_for_display(display) if display is not None else None
    return Gtk.IconTheme.get_default()


def new_image_from_icon_name(name):
    """``Gtk.Image.new_from_icon_name`` (GTK4 dropped the size argument)."""
    if IS_GTK4:
        return Gtk.Image.new_from_icon_name(name)
    return Gtk.Image.new_from_icon_name(name, Gtk.IconSize.BUTTON)


def new_button_from_icon_name(name):
    """``Gtk.Button.new_from_icon_name`` (GTK4 dropped the size argument)."""
    if IS_GTK4:
        return Gtk.Button.new_from_icon_name(name)
    return Gtk.Button.new_from_icon_name(name, Gtk.IconSize.BUTTON)


def new_image_from_gicon(gicon):
    """``Gtk.Image.new_from_gicon`` (GTK4 dropped the size argument)."""
    if IS_GTK4:
        return Gtk.Image.new_from_gicon(gicon)
    return Gtk.Image.new_from_gicon(gicon, Gtk.IconSize.DND)


def image_set_from_icon_name(widget, name) -> None:
    """``Gtk.Image.set_from_icon_name`` (GTK4 dropped the size argument)."""
    if IS_GTK4:
        widget.set_from_icon_name(name)
    else:
        widget.set_from_icon_name(name, Gtk.IconSize.BUTTON)


# ── Raster images ────────────────────────────────────────────────────────────
# GTK4's ``Gtk.Image`` measures a raster paintable at the *icon* size (~16px),
# not its intrinsic size, so a wallpaper preview or app icon collapses to a
# tiny glyph inside a larger button (GTK4 deprecated ``set_from_pixbuf`` /
# ``set_from_file`` for this reason). ``Gtk.Picture`` scales a paintable to the
# space it is given, so non-symbolic rasters use these helpers; symbolic icons
# (``new_image_from_icon_name``) still use ``Gtk.Image``.
def new_raster(cover: bool = False):
    """A widget that scales a raster paintable to the space it is given.

    ``cover=True`` crops to fill (photos/thumbnails); ``False`` letterboxes
    (contain). On GTK3 the ``Gtk.Image`` equivalent is returned.
    """
    if IS_GTK4:
        pic = Gtk.Picture()
        pic.set_can_shrink(True)
        pic.set_content_fit(
            Gtk.ContentFit.COVER if cover else Gtk.ContentFit.CONTAIN
        )
        return pic
    return Gtk.Image()


def raster_set_pixbuf(widget, pixbuf) -> None:
    """Show *pixbuf* on a widget from :func:`new_raster` (``None`` clears it)."""
    if IS_GTK4:
        widget.set_paintable(
            Gdk.Texture.new_for_pixbuf(pixbuf) if pixbuf is not None else None
        )
    else:
        widget.set_from_pixbuf(pixbuf)


def raster_set_file(widget, path) -> None:
    """Show the image file at *path* on a widget from :func:`new_raster`."""
    if IS_GTK4:
        if path is None:
            widget.set_paintable(None)
        else:
            widget.set_filename(str(path))
    elif path is None:
        widget.set_from_pixbuf(None)
    else:
        widget.set_from_file(str(path))


def new_raster_from_pixbuf(pixbuf, cover: bool = False):
    """A :func:`new_raster` widget already showing *pixbuf*."""
    widget = new_raster(cover=cover)
    raster_set_pixbuf(widget, pixbuf)
    return widget


def new_raster_from_paintable(paintable, size=None, cover: bool = False):
    """A :func:`new_raster` widget showing *paintable* (a ``Gdk.Paintable``).

    ``size`` (px) pins a square request when the icon must be a fixed size.
    """
    widget = new_raster(cover=cover)
    if paintable is not None:
        widget.set_paintable(paintable)
    if size is not None and IS_GTK4:
        widget.set_size_request(int(size), int(size))
    return widget


def paned_pack1(paned, child, resize: bool = True, shrink: bool = True) -> None:
    """GTK3 ``Gtk.Paned.pack1`` (GTK4 ``set_start_child``)."""
    if IS_GTK4:
        paned.set_start_child(child)
        paned.set_resize_start_child(resize)
    else:
        paned.pack1(child, resize, shrink)


def paned_pack2(paned, child, resize: bool = True, shrink: bool = True) -> None:
    """GTK3 ``Gtk.Paned.pack2`` (GTK4 ``set_end_child``)."""
    if IS_GTK4:
        paned.set_end_child(child)
        paned.set_resize_end_child(resize)
    else:
        paned.pack2(child, resize, shrink)


def font_button_set_font_name(button, name: str) -> None:
    """Set a ``Gtk.FontButton``'s font (GTK4 takes a font-name string)."""
    button.set_font(name)


def screen_size() -> tuple[int, int]:
    """Primary-monitor ``(width, height)`` (replaces ``Gdk.Screen.get_width()``)."""
    monitor = primary_monitor()
    if monitor is None:
        return 0, 0
    geo = monitor.get_geometry()
    return geo.width, geo.height


Alloc = namedtuple("Alloc", "x y width height")


def allocation(widget):
    """A parent-relative allocation with ``x/y/width/height`` attributes.

    GTK4 replaced ``Gtk.Widget.get_allocation`` with bounds computed against
    the parent; GTK3 returns the ``Gdk.Rectangle`` directly.
    """
    if IS_GTK4:
        parent = widget.get_parent()
        if parent is not None:
            bounds = compute_bounds(widget, parent)
            if bounds is not None:
                return Alloc(*bounds)
        return Alloc(0, 0, widget.get_width(), widget.get_height())
    return widget.get_allocation()
