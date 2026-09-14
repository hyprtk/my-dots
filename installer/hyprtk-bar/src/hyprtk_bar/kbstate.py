"""Keyboard state widget: Caps Lock / Num Lock indicators.

Reads the keyboard LED brightness files under /sys/class/leds (the same source
the old waybar keyboard_state.sh polled) so it works on Wayland. Each lock is
a symbolic icon: lit up (accent) while the lock is on, dimmed while it is off.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · kbstate
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import glob
import logging

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib  # noqa: E402

from .config import icon_size_for  # noqa: E402
from .popup import bind_hover_tooltip  # noqa: E402
from .widgets import Glyph, HoverButton  # noqa: E402

log = logging.getLogger("hyprtk_bar.kbstate")

POLL_MS = 500

_LED_GLOBS = {
    "caps": "/sys/class/leds/*::capslock/brightness",
    "num": "/sys/class/leds/*::numlock/brightness",
}

# (state key, glyph) — caps uses a padlock, num uses a keyboard.
_ICONS = (
    ("caps", "\uf023"),  # fa-lock
    ("num", "\uf11c"),   # fa-keyboard
)

# The sysfs LED device paths are stable; resolve the globs once instead of
# re-globbing /sys/class/leds every 500ms poll.
_LED_PATHS: dict[str, list[str]] = {}


def _led_paths(led_class: str) -> list[str]:
    paths = _LED_PATHS.get(led_class)
    if paths is None:
        paths = glob.glob(_LED_GLOBS[led_class])
        _LED_PATHS[led_class] = paths
    return paths


def _led_on(led_class: str) -> bool:
    """True when any keyboard LED of the given class is lit."""
    for path in _led_paths(led_class):
        try:
            with open(path, encoding="ascii") as f:
                return f.read(1).strip() == "1"
        except OSError:
            continue
    return False


class KbState(HoverButton):
    def __init__(self, cfg: dict, ipc):
        super().__init__("kbstate", vertical=False, spacing=6)
        self._cfg = cfg
        kb_cfg = cfg.get("kbstate") or {}
        self._interval = max(100, int(kb_cfg.get("poll_ms", POLL_MS)))
        font_cfg = cfg.get("font") or {}
        icon_size = icon_size_for(
            font_cfg.get("size", 16), font_cfg.get("icon_size", 0)
        )
        self._icons: dict[str, Glyph] = {}
        for key, glyph in _ICONS:
            img = Glyph(glyph, "kbstate-icon")
            img.set_pixel_size(icon_size)
            img.get_style_context().add_class(key)
            self.box.pack_start(img, False, False, 0)
            self._icons[key] = img
        self._tip = ""
        self._last = None  # last (caps, num) state — skip no-op style churn
        self._update()
        self._tick_id = GLib.timeout_add(self._interval, self._tick)
        bind_hover_tooltip(self, cfg, lambda: self._tip)

    def apply_font(self, font_size, icon_size=0) -> None:
        size = icon_size_for(font_size, icon_size)
        for img in self._icons.values():
            img.set_pixel_size(size)

    def shutdown(self) -> None:
        """Stop the poll timer so a rebuilt module doesn't keep ticking."""
        if self._tick_id is not None:
            GLib.source_remove(self._tick_id)
            self._tick_id = None

    def _tick(self) -> bool:
        self._update()
        return GLib.SOURCE_CONTINUE

    def _update(self) -> None:
        states = {key: _led_on(key) for key, _name in _ICONS}
        # Skip the style-context add/remove-class churn when nothing changed —
        # keyboard LED state is idle 99.9% of the time.
        if states == self._last:
            return
        self._last = dict(states)
        for key, on in states.items():
            ctx = self._icons[key].get_style_context()
            if on:
                ctx.add_class("on")
                ctx.remove_class("off")
            else:
                ctx.add_class("off")
                ctx.remove_class("on")
        self._tip = (
            f"Caps Lock: {'on' if states['caps'] else 'off'}\n"
            f"Num Lock: {'on' if states['num'] else 'off'}"
        )