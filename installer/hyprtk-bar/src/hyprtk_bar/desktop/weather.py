"""Weather desktop widget.

Location is set by city name. The city is geocoded (Open-Meteo geocoding) and
the current conditions + daily forecast are fetched from Open-Meteo — both
keyless. Fetches run on a worker thread and the last good result is cached under
``~/.cache/hyprtk-bar/weather.json`` so the widget still renders offline (and
immediately on the next start) instead of going blank.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.weather
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import json
import logging
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib, Gtk  # noqa: E402

from ..config import icon_size_for  # noqa: E402
from ..widgets import Glyph  # noqa: E402
from .base import DesktopWidgetWindow  # noqa: E402

log = logging.getLogger("hyprtk_bar.desktop.weather")

CACHE_PATH = Path.home() / ".cache" / "hyprtk-bar" / "weather.json"
GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
HTTP_TIMEOUT = 8

# WMO weather code -> (label, day glyph, night glyph). Glyphs are Nerd Font
# weather codepoints; the night variant is only used for the clear/partly codes.
_WMO = {
    0: ("Clear", "\uf00d", "\uf02e"),
    1: ("Mainly clear", "\uf00d", "\uf02e"),
    2: ("Partly cloudy", "\uf002", "\uf086"),
    3: ("Overcast", "\uf013", "\uf013"),
    45: ("Fog", "\uf014", "\uf014"),
    48: ("Rime fog", "\uf014", "\uf014"),
    51: ("Light drizzle", "\uf01c", "\uf01c"),
    53: ("Drizzle", "\uf01c", "\uf01c"),
    55: ("Dense drizzle", "\uf01c", "\uf01c"),
    56: ("Freezing drizzle", "\uf017", "\uf017"),
    57: ("Freezing drizzle", "\uf017", "\uf017"),
    61: ("Light rain", "\uf01a", "\uf01a"),
    63: ("Rain", "\uf019", "\uf019"),
    65: ("Heavy rain", "\uf019", "\uf019"),
    66: ("Freezing rain", "\uf017", "\uf017"),
    67: ("Freezing rain", "\uf017", "\uf017"),
    71: ("Light snow", "\uf01b", "\uf01b"),
    73: ("Snow", "\uf01b", "\uf01b"),
    75: ("Heavy snow", "\uf01b", "\uf01b"),
    77: ("Snow grains", "\uf01b", "\uf01b"),
    80: ("Light showers", "\uf01a", "\uf01a"),
    81: ("Showers", "\uf01a", "\uf01a"),
    82: ("Violent showers", "\uf019", "\uf019"),
    85: ("Snow showers", "\uf01b", "\uf01b"),
    86: ("Snow showers", "\uf01b", "\uf01b"),
    95: ("Thunderstorm", "\uf01e", "\uf01e"),
    96: ("Thunderstorm, hail", "\uf01e", "\uf01e"),
    99: ("Thunderstorm, hail", "\uf01e", "\uf01e"),
}


def describe(code) -> tuple[str, str, str]:
    try:
        return _WMO.get(int(code), ("Unknown", "\uf07b", "\uf07b"))
    except (TypeError, ValueError):
        return "Unknown", "\uf07b", "\uf07b"


def _http_json(url: str) -> dict | None:
    try:
        with urllib.request.urlopen(url, timeout=HTTP_TIMEOUT) as response:
            return json.loads(response.read().decode("utf-8", "replace"))
    except (urllib.error.URLError, OSError, ValueError) as exc:
        log.warning("weather request failed: %s", exc)
        return None


def geocode(city: str) -> dict | None:
    """Resolve a city name to ``{name, country, latitude, longitude}``."""
    query = urllib.parse.urlencode(
        {"name": city, "count": 1, "language": "en", "format": "json"}
    )
    data = _http_json(f"{GEOCODE_URL}?{query}")
    results = (data or {}).get("results") or []
    if not results:
        return None
    hit = results[0]
    return {
        "name": hit.get("name") or city,
        "country": hit.get("country_code") or hit.get("country") or "",
        "latitude": hit.get("latitude"),
        "longitude": hit.get("longitude"),
    }


def fetch_weather(city: str, units: str = "metric", days: int = 3) -> dict | None:
    """Geocode *city* and fetch current + daily weather, or None on failure."""
    place = geocode(city)
    if place is None or place.get("latitude") is None:
        return None
    metric = units != "imperial"
    params = {
        "latitude": place["latitude"],
        "longitude": place["longitude"],
        "current": "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min",
        "timezone": "auto",
        "forecast_days": max(1, min(7, int(days) or 3)),
        "temperature_unit": "celsius" if metric else "fahrenheit",
        "wind_speed_unit": "kmh" if metric else "mph",
    }
    data = _http_json(f"{FORECAST_URL}?{urllib.parse.urlencode(params)}")
    if not data:
        return None
    current = data.get("current") or {}
    daily = data.get("daily") or {}
    dates = daily.get("time") or []
    codes = daily.get("weather_code") or []
    highs = daily.get("temperature_2m_max") or []
    lows = daily.get("temperature_2m_min") or []
    forecast = [
        {
            "date": dates[i] if i < len(dates) else "",
            "code": codes[i] if i < len(codes) else 0,
            "hi": highs[i] if i < len(highs) else None,
            "lo": lows[i] if i < len(lows) else None,
        }
        for i in range(min(len(dates), len(codes), len(highs), len(lows)))
    ]
    return {
        "city": place["name"],
        "country": place["country"],
        "temp": current.get("temperature_2m"),
        "feels": current.get("apparent_temperature"),
        "humidity": current.get("relative_humidity_2m"),
        "wind": current.get("wind_speed_10m"),
        "code": current.get("weather_code", 0),
        "is_day": current.get("is_day", 1),
        "daily": forecast,
        "unit": "°F" if not metric else "°C",
        "wind_unit": "mph" if not metric else "km/h",
        "fetched": time.time(),
    }


def _load_cache() -> dict | None:
    try:
        data = json.loads(CACHE_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def _save_cache(data: dict) -> None:
    try:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        CACHE_PATH.write_text(json.dumps(data))
    except OSError:
        log.warning("could not cache weather data", exc_info=True)


class WeatherWidget(DesktopWidgetWindow):
    WIDGET_ID = "weather"

    def __init__(self, cfg: dict, block: dict):
        self._timer_id: int | None = None
        self._alive = True
        self._fetching = False
        self._data: dict | None = None
        self._icon: Glyph | None = None
        self._temp: Gtk.Label | None = None
        self._city: Gtk.Label | None = None
        self._condition: Gtk.Label | None = None
        self._details: Gtk.Label | None = None
        self._forecast_box: Gtk.Box | None = None
        self._forecast_cells: list[tuple[Glyph, Gtk.Label, Gtk.Label]] = []
        super().__init__(cfg, block)

    # ── build ────────────────────────────────────────────────────

    def build(self) -> None:
        block = self._block
        font = (self._cfg.get("font") or {})
        icon_size = icon_size_for(font.get("size", 16), font.get("icon_size", 0))

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        if block.get("show_icon", True):
            self._icon = Glyph("\uf07b", "weather-icon")
            self._icon.set_pixel_size(int(round(icon_size * 2.4)))
            header.pack_start(self._icon, False, False, 0)
        text_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        if block.get("show_temp", True):
            self._temp = Gtk.Label(label="--")
            self._temp.get_style_context().add_class("weather-temp")
            self._temp.set_halign(Gtk.Align.START)
            text_col.pack_start(self._temp, False, False, 0)
        self._city = Gtk.Label(label=str(block.get("city") or ""))
        self._city.get_style_context().add_class("weather-city")
        self._city.set_halign(Gtk.Align.START)
        text_col.pack_start(self._city, False, False, 0)
        header.pack_start(text_col, True, True, 0)
        self.root.pack_start(header, False, False, 0)

        if block.get("show_condition", True):
            self._condition = Gtk.Label(label="Loading…")
            self._condition.get_style_context().add_class("weather-condition")
            self._condition.set_halign(Gtk.Align.START)
            self.root.pack_start(self._condition, False, False, 0)

        if block.get("show_feels_like", True) or block.get("show_humidity", True) or block.get("show_wind", True):
            self._details = Gtk.Label(label="")
            self._details.get_style_context().add_class("weather-detail")
            self._details.set_halign(Gtk.Align.START)
            self.root.pack_start(self._details, False, False, 0)

        if block.get("show_forecast", True) and int(block.get("forecast_days", 3) or 0) > 0:
            self._forecast_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            self._forecast_box.set_halign(Gtk.Align.START)
            self.root.pack_start(self._forecast_box, False, False, 0)
            self._build_forecast_cells(int(block.get("forecast_days", 3) or 3))

        self._adopt_cache()
        self._schedule_fetch(initial=True)
        interval = max(300, int(block.get("refresh_minutes", 15) or 15) * 60)
        self._timer_id = GLib.timeout_add_seconds(interval, self._on_timer)

    def _build_forecast_cells(self, days: int) -> None:
        icon_size = icon_size_for(
            (self._cfg.get("font") or {}).get("size", 16),
            (self._cfg.get("font") or {}).get("icon_size", 0),
        )
        for _ in range(days):
            cell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
            cell.set_halign(Gtk.Align.CENTER)
            day = Gtk.Label(label="")
            day.get_style_context().add_class("weather-forecast-day")
            icon = Glyph("\uf07b", "weather-icon")
            icon.set_pixel_size(max(10, int(round(icon_size * 1.2))))
            temps = Gtk.Label(label="")
            temps.get_style_context().add_class("weather-forecast-hi")
            cell.pack_start(day, False, False, 0)
            cell.pack_start(icon, False, False, 0)
            cell.pack_start(temps, False, False, 0)
            self._forecast_box.pack_start(cell, False, False, 0)
            self._forecast_cells.append((icon, day, temps))

    # ── data ─────────────────────────────────────────────────────

    def _adopt_cache(self) -> None:
        cached = _load_cache()
        if not cached:
            return
        if cached.get("city") and self._block.get("city"):
            # Only show a cache hit for the same city/units request.
            if cached.get("city").lower() != str(self._block["city"]).lower():
                return
        self._data = cached
        self._render()

    def _schedule_fetch(self, initial: bool = False) -> None:
        if self._fetching:
            return
        cached = self._data
        stale = (
            cached is None
            or cached.get("fetched", 0) < time.time() - max(300, int(self._block.get("refresh_minutes", 15) or 15) * 60)
        )
        if not (initial or stale):
            return
        self._fetching = True
        city = str(self._block.get("city") or "")
        units = str(self._block.get("units") or "metric")
        days = int(self._block.get("forecast_days", 3) or 3)

        def _work() -> None:
            data = fetch_weather(city, units, days)
            GLib.idle_add(self._on_fetched, data)

        threading.Thread(target=_work, daemon=True).start()

    def _on_fetched(self, data: dict | None) -> bool:
        if not self._alive:
            return GLib.SOURCE_REMOVE
        self._fetching = False
        if data:
            self._data = data
            _save_cache(data)
            self._render()
        elif self._data is None and self._condition is not None:
            self._condition.set_text("Weather unavailable")
        return GLib.SOURCE_REMOVE

    def _on_timer(self) -> bool:
        self._schedule_fetch()
        return GLib.SOURCE_CONTINUE

    def _render(self) -> None:
        data = self._data
        if not data:
            return
        label, day_glyph, night_glyph = describe(data.get("code"))
        glyph = day_glyph if data.get("is_day", 1) else night_glyph
        if self._icon is not None:
            self._icon.set_text(glyph)
        if self._temp is not None:
            temp = data.get("temp")
            self._temp.set_text("--" if temp is None else f"{round(temp)}°")
        if self._city is not None:
            country = data.get("country") or ""
            name = data.get("city") or self._block.get("city") or ""
            self._city.set_text(f"{name}, {country}" if country else name)
        if self._condition is not None:
            self._condition.set_text(label)
        if self._details is not None:
            self._details.set_text(self._details_text(data))
        self._render_forecast(data)

    def _details_text(self, data: dict) -> str:
        block = self._block
        unit = data.get("unit", "°C")
        wind_unit = data.get("wind_unit", "km/h")
        parts = []
        if block.get("show_feels_like", True) and data.get("feels") is not None:
            parts.append(f"Feels {round(data['feels'])}{unit}")
        if block.get("show_humidity", True) and data.get("humidity") is not None:
            parts.append(f"Humidity {round(data['humidity'])}%")
        if block.get("show_wind", True) and data.get("wind") is not None:
            parts.append(f"Wind {round(data['wind'])} {wind_unit}")
        return "   ".join(parts)

    def _render_forecast(self, data: dict) -> None:
        if not self._forecast_cells:
            return
        import datetime as _dt

        daily = data.get("daily") or []
        for index, (icon, day, temps) in enumerate(self._forecast_cells):
            if index >= len(daily):
                day.set_text("")
                temps.set_text("")
                continue
            entry = daily[index]
            label, day_glyph, _night = describe(entry.get("code"))
            icon.set_text(day_glyph)
            try:
                parsed = _dt.datetime.strptime(entry.get("date", ""), "%Y-%m-%d")
                day.set_text(parsed.strftime("%a"))
            except (ValueError, TypeError):
                day.set_text("")
            hi = entry.get("hi")
            lo = entry.get("lo")
            hi_s = "--" if hi is None else str(round(hi))
            lo_s = "--" if lo is None else str(round(lo))
            temps.set_text(f"{hi_s}° / {lo_s}°")

    # ── teardown ─────────────────────────────────────────────────

    def shutdown(self) -> None:
        self._alive = False
        if self._timer_id is not None:
            GLib.source_remove(self._timer_id)
            self._timer_id = None
