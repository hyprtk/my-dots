"""Clock widget: time label with a hover date popup and a floating calendar."""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · clock
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import datetime

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib, Gtk  # noqa: E402

from .popup import Popup  # noqa: E402
from .widgets import HoverButton  # noqa: E402

DATE_POPUP_GRACE = 180  # ms after leaving the clock before the date popup hides


class Clock(HoverButton):
    def __init__(self, cfg: dict, ipc):
        super().__init__("clock", vertical=True, spacing=0)
        self._cfg = cfg
        self._clock = cfg.get("clock") or {}
        self._ipc = ipc
        self._popup = None
        self._date_popup = None
        self._date_hide_timer = None

        self._time = Gtk.Label(label="--:--")
        self._time.get_style_context().add_class("clock-label")
        self._time.set_justify(Gtk.Justification.CENTER)
        self.box.pack_start(self._time, False, False, 0)

        if self._clock.get("date_format"):
            self._build_date_popup()
        if self._clock.get("calendar"):
            self._build_calendar_popup()

        self._update()
        self._tick_id = GLib.timeout_add_seconds(1, self._tick)

    def shutdown(self) -> None:
        """Stop the 1s tick and release popups so a rebuilt module doesn't leak."""
        if self._tick_id is not None:
            GLib.source_remove(self._tick_id)
            self._tick_id = None
        for popup in (self._date_popup, self._popup):
            if popup is not None:
                try:
                    popup.hide_popup()
                    popup.destroy()
                except Exception:
                    pass
        self._date_popup = None
        self._popup = None

    def _build_date_popup(self) -> None:
        """The date is a popup (above a bottom bar, below a top bar), never
        packed under the time where it would squeeze the clock's height."""
        self._date = Gtk.Label(label="")
        self._date.get_style_context().add_class("clock-date")
        self._date.set_justify(Gtk.Justification.CENTER)
        self._date_popup = Popup(self._cfg, self._cfg.get("position", "bottom"))
        self._date_popup.content.pack_start(self._date, False, False, 0)
        self._date_popup.content.show_all()
        self._date_popup.set_on_enter(self._cancel_date_hide)
        self._date_popup.set_on_leave(self._schedule_date_hide)

    def _build_calendar_popup(self) -> None:
        self._popup = Popup(self._cfg, self._cfg.get("position", "bottom"))
        cal = Gtk.Calendar()
        cal.set_display_options(
            Gtk.CalendarDisplayOptions.SHOW_HEADING
            | Gtk.CalendarDisplayOptions.SHOW_DAY_NAMES
        )
        self._popup.content.pack_start(cal, False, False, 0)
        self._popup.content.show_all()
        self._popup.set_on_leave(self._popup_hide)

    def _tick(self) -> bool:
        self._update()
        return GLib.SOURCE_CONTINUE

    def _update(self) -> None:
        now = datetime.datetime.now()
        fmt = self._clock.get("format", "%H:%M")
        self._time.set_text(now.strftime(fmt))
        if getattr(self, "_date", None) is not None and self._clock.get("date_format"):
            self._date.set_text(now.strftime(self._clock["date_format"]))

    # ── hover date popup ──────────────────────────────────────────

    def _on_enter(self, *_args):
        super()._on_enter(*_args)
        self._cancel_date_hide()
        calendar_open = self._popup is not None and self._popup.get_visible()
        if self._date_popup is not None and not calendar_open:
            self._date_popup.show_above(self)
        return False

    def _on_leave(self, *_args):
        super()._on_leave(*_args)
        self._schedule_date_hide()
        return False

    def _cancel_date_hide(self, *_args) -> None:
        if self._date_hide_timer is not None:
            GLib.source_remove(self._date_hide_timer)
            self._date_hide_timer = None

    def _schedule_date_hide(self, *_args) -> None:
        if self._date_hide_timer is None:
            self._date_hide_timer = GLib.timeout_add(DATE_POPUP_GRACE, self._hide_date_popup)

    def _hide_date_popup(self) -> bool:
        self._date_hide_timer = None
        if self._date_popup is not None:
            self._date_popup.hide_popup()
        return GLib.SOURCE_REMOVE

    def _popup_hide(self) -> None:
        if self._popup is not None:
            self._popup.hide_popup()

    def _on_button_press(self, _widget, event):
        if event.button == 1 and self._popup is not None:
            self._cancel_date_hide()
            self._hide_date_popup()
            if self._popup.get_visible():
                self._popup.hide_popup()
            else:
                self._popup.show_above(self)
        return True