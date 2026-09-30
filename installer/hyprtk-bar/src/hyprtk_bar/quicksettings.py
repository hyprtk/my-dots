"""Quick Settings flyout (Win11-style): wifi/bluetooth toggles, volume/brightness.

Backed by the system session tools: `nmcli`, `bluetoothctl`, `wpctl`
(WirePlumber) and `brightnessctl`. Screen brightness prefers a kernel backlight
(brightnessctl); on desktops with an external monitor it falls back to
hyprsunset gamma over hyprctl. State is refreshed when the flyout opens and
polled every few seconds while it is visible.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · quicksettings
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import re
import subprocess
import threading

from . import compat  # noqa: E402
from .compat import GLib, Gtk  # noqa: E402

from .config import icon_size_for  # noqa: E402
from .popup import Popup, bind_hover_tooltip  # noqa: E402
from .widgets import Glyph, HoverButton  # noqa: E402

log = logging.getLogger("hyprtk_bar.quicksettings")

SINK = "@DEFAULT_AUDIO_SINK@"
SOURCE = "@DEFAULT_AUDIO_SOURCE@"


def _run(args, timeout=3) -> str:
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return out.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return ""


def find_backlight() -> tuple[str, int, int] | None:
    """Return (device, current, max) for the first backlight/kbd class, or None."""
    for line in _run(["brightnessctl", "-m"]).splitlines():
        fields = line.split(",")
        if len(fields) < 5 or fields[1] not in ("backlight", "kbd_backlight"):
            continue
        device = fields[0]
        try:
            current, maxval = int(fields[2]), int(fields[4])
        except ValueError:
            continue
        if maxval > 0:
            return device, current, maxval
    return None


# ── brightness (screen gamma via hyprsunset) ───────────────────────
# Desktops with an external monitor have no /sys backlight, so screen
# brightness is done through hyprsunset's gamma (perceived brightness) over
# hyprctl. A minimum of 30% is enforced — gamma 0 is a fully black screen.

_GAMMA_MIN = 30
_gamma_cache = {"value": 100}


def hyprsunset_available() -> bool:
    """True when the hyprsunset daemon answers `hyprctl hyprsunset profile`."""
    try:
        proc = subprocess.run(
            ["hyprctl", "hyprsunset", "profile"],
            capture_output=True, timeout=2,
        )
    except (subprocess.SubprocessError, OSError):
        return False
    return proc.returncode == 0 and bool(proc.stdout.strip())


def get_gamma() -> int:
    """Current gamma percent (0-100), read from hyprsunset when possible."""
    try:
        proc = subprocess.run(
            ["hyprctl", "hyprsunset", "profile"],
            capture_output=True, text=True, timeout=2,
        )
        out = proc.stdout or ""
    except (subprocess.SubprocessError, OSError):
        out = ""
    m = re.search(r"gamma[:\s=]+([0-9]+)\s*%?", out, re.I)
    if m:
        try:
            _gamma_cache["value"] = max(_GAMMA_MIN, min(int(m.group(1)), 100))
        except ValueError:
            pass
    return _gamma_cache["value"]


def set_gamma(pct: int) -> None:
    """Set gamma percent, clamped to a safe minimum (never fully black)."""
    value = max(_GAMMA_MIN, min(int(pct), 100))
    _run(["hyprctl", "hyprsunset", "gamma", str(value)])
    _gamma_cache["value"] = value


# ── volume ───────────────────────────────────────────────────────

def get_volume() -> tuple[float, bool] | None:
    out = _run(["wpctl", "get-volume", SINK])
    m = re.search(r"Volume:\s+([\d.]+)", out)
    if not m:
        return None
    return float(m.group(1)), "[MUTED]" in out


def get_volume_state() -> tuple[int, bool] | None:
    """(percent, muted) for the sink in one wpctl read (used by the slider)."""
    vol = get_volume()
    if vol is None:
        return None
    pct, muted = vol
    return int(round(pct * 100)), muted


def set_volume_pct(pct: int) -> None:
    _run(["wpctl", "set-volume", SINK, f"{max(0, min(pct, 100)) / 100:.2f}"])
    # Moving the slider re-enables a muted sink.
    _run(["wpctl", "set-mute", SINK, "0"])


def toggle_mute() -> None:
    _run(["wpctl", "set-mute", SINK, "toggle"])


# ── microphone (source) volume ────────────────────────────────────

def get_mic_volume() -> tuple[float, bool] | None:
    out = _run(["wpctl", "get-volume", SOURCE])
    m = re.search(r"Volume:\s+([\d.]+)", out)
    if not m:
        return None
    return float(m.group(1)), "[MUTED]" in out


def get_mic_state() -> tuple[int, bool] | None:
    """(percent, muted) for the mic source in one wpctl read."""
    vol = get_mic_volume()
    if vol is None:
        return None
    pct, muted = vol
    return int(round(pct * 100)), muted


def set_mic_volume_pct(pct: int) -> None:
    _run(["wpctl", "set-volume", SOURCE, f"{max(0, min(pct, 100)) / 100:.2f}"])
    # Moving the slider re-enables a muted source.
    _run(["wpctl", "set-mute", SOURCE, "0"])


def toggle_mic_mute() -> None:
    _run(["wpctl", "set-mute", SOURCE, "toggle"])


# ── wifi ─────────────────────────────────────────────────────────

def get_wifi() -> bool:
    return _run(["nmcli", "radio", "wifi"]).strip() == "enabled"


def set_wifi(on: bool) -> None:
    _run(["nmcli", "radio", "wifi", "on" if on else "off"])


# ── bluetooth ────────────────────────────────────────────────────

def get_bt() -> bool:
    m = re.search(r"Powered:\s+(yes|no)", _run(["bluetoothctl", "show"]))
    return bool(m and m.group(1) == "yes")


def set_bt(on: bool) -> None:
    _run(["bluetoothctl", "power", "on" if on else "off"])


# ── widgets ──────────────────────────────────────────────────────

class ToggleRow(HoverButton):
    """A row with icon, label and a switch; clicking the row also toggles."""

    def __init__(self, icon_name: str, label: str, on_apply):
        super().__init__("qs-row", vertical=False, spacing=10)
        self._on_apply = on_apply

        icon = compat.new_image_from_icon_name(icon_name)
        icon.set_pixel_size(18)
        compat.pack_start(self.box, icon, False, False, 0)

        lbl = Gtk.Label(label=label, xalign=0)
        compat.pack_start(self.box, lbl, True, True, 0)

        self._switch = Gtk.Switch()
        compat.add_class(self._switch, "qs-switch")
        self._switch.set_valign(Gtk.Align.CENTER)
        compat.pack_start(self.box, self._switch, False, False, 0)
        self._switch.connect("state-set", self._on_state_set)

    def set_state(self, on: bool) -> None:
        self._switch.set_active(bool(on))

    def _on_state_set(self, _switch, state) -> bool:
        try:
            self._on_apply(state)
        except Exception as exc:
            log.warning("toggle failed: %s", exc)
        return False  # let the switch update its visual state

    def _on_button_press(self, _widget, event):
        if event.button == 1 and not self._switch.get_state():
            self._switch.set_active(True)
        return True


class SliderRow(Gtk.Box):
    """A row with an icon (clickable when mute supported), a scale and a % label."""

    def __init__(
        self,
        icon_name: str,
        icon_on_name: str | None,
        label: str,
        get_pct,
        set_pct,
        muted_get=None,
        mute_toggle=None,
        get_state=None,
        range_min: int = 0,
    ):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self._get_pct = get_pct
        self._set_pct = set_pct
        self._muted_get = muted_get
        self._get_state = get_state
        self._mute_toggle = mute_toggle
        self._icon_name = icon_name          # the "on" (unmuted) icon
        self._icon_on = icon_on_name         # the "off" (muted) icon
        self._pending = None

        self._icon = compat.new_image_from_icon_name(icon_name)
        self._icon.set_pixel_size(18)
        if mute_toggle is not None:
            holder = compat.event_surface()
            compat.set_visible_window(holder, False)
            compat.add(holder, self._icon)
            compat.on_press(holder, self._on_icon_press)
            holder.set_tooltip_text("Toggle mute")
            compat.pack_start(self, holder, False, False, 0)
        else:
            compat.pack_start(self, self._icon, False, False, 0)

        lbl = Gtk.Label(label=label, xalign=0)
        lbl.set_size_request(52, -1)
        compat.pack_start(self, lbl, False, False, 0)

        self._scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, range_min, 100, 1)
        self._scale.set_size_request(160, -1)
        self._scale.set_hexpand(True)
        self._scale.set_draw_value(False)
        compat.add_class(self._scale, "qs-scale")
        compat.pack_start(self, self._scale, True, True, 0)
        self._scale.connect("value-changed", self._on_value_changed)

        self._pct = Gtk.Label(label="100%", xalign=1)
        self._pct.set_width_chars(4)
        compat.pack_start(self, self._pct, False, False, 0)

    def refresh(self) -> None:
        muted = False
        if self._get_state is not None:
            # A single getter returns (pct, muted) in one subprocess read, so a
            # refresh doesn't call wpctl several times (get_pct + muted_get).
            state = self._get_state()
            pct, muted = state if state else (None, False)
        else:
            if self._muted_get is not None:
                muted = bool(self._muted_get())
            pct = self._get_pct()
        self.apply_state(pct, muted)

    def apply_state(self, pct, muted: bool) -> None:
        """Apply an already-fetched (percent, muted) state (no subprocess)."""
        # A muted source shows 0 so the slider reads "off"; moving it unmutes.
        display = 0 if muted else (pct if pct is not None else 0)
        self._scale.handler_block_by_func(self._on_value_changed)
        self._scale.set_value(display)
        self._scale.handler_unblock_by_func(self._on_value_changed)
        self._pct.set_text(f"{int(round(display))}%")
        if self._get_state is not None or self._muted_get is not None:
            self._update_icon(muted)

    def _update_icon(self, muted: bool) -> None:
        if self._icon_on:
            name = self._icon_on if muted else self._icon_name
            compat.image_set_from_icon_name(self._icon, name)
            self._icon.set_pixel_size(18)

    def _on_icon_press(self, *_args) -> bool:
        if self._mute_toggle:
            try:
                self._mute_toggle()
            except Exception as exc:
                log.warning("mute toggle failed: %s", exc)
            GLib.timeout_add(200, self._apply_mute_refresh)
        return True

    def _apply_mute_refresh(self) -> bool:
        self.refresh()
        return GLib.SOURCE_REMOVE

    def _on_value_changed(self, scale) -> None:
        value = int(round(scale.get_value()))
        self._pct.set_text(f"{value}%")
        if self._pending is not None:
            GLib.source_remove(self._pending)
        self._pending = GLib.timeout_add(200, self._apply, value)

    def _apply(self, value: int) -> bool:
        self._pending = None
        try:
            self._set_pct(value)
        except Exception as exc:
            log.warning("set %r failed: %s", self._set_pct, exc)
        return GLib.SOURCE_REMOVE


class QuickSettingsButton(HoverButton):
    """Taskbar button that toggles the Quick Settings flyout."""

    def __init__(self, cfg: dict):
        super().__init__("qs-button", vertical=True, spacing=0)
        font_cfg = cfg.get("font") or {}
        self._icon = Glyph("\uf013", "accent-icon")
        self._icon.set_pixel_size(
            icon_size_for(font_cfg.get("size", 16), font_cfg.get("icon_size", 0))
        )
        compat.pack_start(self.box, self._icon, True, True, 0)
        self._popup = QuickSettings(cfg)
        self._popup.set_on_leave(self._hide)
        bind_hover_tooltip(self, cfg, lambda: "Quick settings")

    def apply_font(self, font_size, icon_size=0) -> None:
        self._icon.set_pixel_size(icon_size_for(font_size, icon_size))

    def _toggle(self) -> None:
        if self._popup.get_visible():
            self._popup.hide_popup()
        else:
            self._popup.show_above(self)

    def _hide(self) -> None:
        self._popup.hide_popup()

    def shutdown(self) -> None:
        self._popup.hide_popup()

    def _on_button_press(self, _widget, event):
        if event.button == 1:
            self._toggle()
        return True


class QuickSettings(Popup):
    """The flyout panel."""

    def __init__(self, cfg: dict):
        super().__init__(cfg, cfg.get("position", "bottom"))
        self._cfg = cfg
        self._timer = None
        self._brightness_row = None
        self._refresh_busy = False

        title = Gtk.Label(label="Quick Settings", xalign=0)
        compat.add_class(title, "qs-title")
        compat.pack_start(self.content, title, False, False, 0)

        self._wifi = ToggleRow("network-wireless-symbolic", "Wi-Fi", set_wifi)
        compat.pack_start(self.content, self._wifi, False, False, 0)

        self._bt = ToggleRow("bluetooth-symbolic", "Bluetooth", set_bt)
        compat.pack_start(self.content, self._bt, False, False, 0)

        self._volume = SliderRow(
            "audio-volume-high-symbolic",
            "audio-volume-muted-symbolic",
            "Volume",
            get_pct=lambda: 100,
            set_pct=set_volume_pct,
            mute_toggle=toggle_mute,
            get_state=get_volume_state,
        )
        compat.pack_start(self.content, self._volume, False, False, 0)

        self._mic = SliderRow(
            "audio-input-microphone-symbolic",
            "audio-input-microphone-muted-symbolic",
            "Mic",
            get_pct=lambda: 100,
            set_pct=set_mic_volume_pct,
            mute_toggle=toggle_mic_mute,
            get_state=get_mic_state,
        )
        compat.pack_start(self.content, self._mic, False, False, 0)

        compat.show_all(self.content)

    # ── lifecycle ─────────────────────────────────────────────────

    def show_above(self, widget) -> None:
        self.refresh()
        self._start_poll()
        super().show_above(widget)

    def hide_popup(self) -> None:
        self._stop_poll()
        super().hide_popup()

    def refresh(self) -> None:
        # One fetch at a time: the 5s poll and every open both call this, and
        # bluetoothctl/nmcli can be slow enough to stack overlapping worker
        # fleets (whose out-of-order snapshots make the flyout flicker).
        if self._refresh_busy:
            return
        self._refresh_busy = True
        self._ensure_brightness()
        # Collect state off the GTK thread — nmcli/bluetoothctl/wpctl/
        # brightnessctl are subprocesses that would stall the flyout on open.
        def _work() -> None:
            try:
                data = {
                    "wifi": get_wifi(),
                    "bt": get_bt(),
                    "volume": get_volume_state(),
                    "mic": get_mic_state(),
                    "brightness": None,
                }
                br = self._brightness_row
                if br is not None:
                    try:
                        data["brightness"] = br._get_pct()
                    except Exception:
                        data["brightness"] = None
            except Exception:
                log.exception("quick-settings refresh failed")
                data = {}
            GLib.idle_add(self._apply_refresh, data)

        threading.Thread(target=_work, daemon=True).start()

    def _apply_refresh(self, data: dict) -> bool:
        self._refresh_busy = False
        if not data:
            return GLib.SOURCE_REMOVE
        self._wifi.set_state(data["wifi"])
        self._bt.set_state(data["bt"])
        vol = data["volume"]
        self._volume.apply_state(*vol) if vol else self._volume.apply_state(None, False)
        mic = data["mic"]
        self._mic.apply_state(*mic) if mic else self._mic.apply_state(None, False)
        if self._brightness_row is not None and data["brightness"] is not None:
            self._brightness_row.apply_state(data["brightness"], False)
        return GLib.SOURCE_REMOVE

    def _ensure_brightness(self) -> None:
        """Build the brightness row lazily, the first time a backend is found.

        The backend (kernel backlight, or hyprsunset for external monitors) may
        not be available when the bar starts — hyprsunset can be launched after
        it. Checking on each open means the slider appears as soon as a backend
        is reachable, without a bar restart.
        """
        if self._brightness_row is not None:
            return
        backlight = find_backlight()
        if backlight is not None:
            device, _cur, _mx = backlight

            def get_brightness():
                cur = _run(["brightnessctl", "-d", device, "get"])
                mx = _run(["brightnessctl", "-d", device, "max"])
                try:
                    return int(round(int(cur) / max(int(mx), 1) * 100))
                except ValueError:
                    return 0

            def set_brightness(pct: int) -> None:
                _run(["brightnessctl", "-d", device, "set", f"{pct}%"])

            self._brightness_row = SliderRow(
                "display-brightness-symbolic", None, "Brightness",
                get_brightness, set_brightness,
            )
        elif hyprsunset_available():
            self._brightness_row = SliderRow(
                "display-brightness-symbolic", None, "Brightness",
                get_gamma, set_gamma, range_min=_GAMMA_MIN,
            )
        else:
            return
        compat.pack_start(self.content, self._brightness_row, False, False, 0)
        compat.show_all(self.content)

    def _start_poll(self) -> None:
        if self._timer is None:
            self._timer = GLib.timeout_add_seconds(5, self._on_poll)

    def _stop_poll(self) -> None:
        if self._timer is not None:
            GLib.source_remove(self._timer)
            self._timer = None

    def _on_poll(self) -> bool:
        self.refresh()
        return GLib.SOURCE_CONTINUE