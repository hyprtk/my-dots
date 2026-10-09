"""Weather for the weather desktop widget (Open-Meteo, keyless).

Ported from the GTK bar's ``desktop/weather.py`` (toolkit-free): geocode a city
name, fetch current + daily forecast, cache the last good result to
``~/.cache/hyprtk-bar-qt/weather.json`` so the widget renders offline/instantly.

Usage::

    python3 weather.py --city London [--units metric] [--days 3] [--max-age 900]

Prints one JSON object: ``{"ok": bool, "data": {...}|null}``.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    from .paths import QT_CACHE
except ImportError:  # run as a script (python3 weather.py)
    from paths import QT_CACHE

CACHE_PATH = QT_CACHE / "weather.json"
GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
HTTP_TIMEOUT = 8
MAX_HTTP_BYTES = 2 * 1024 * 1024

# WMO code -> (label, day glyph, night glyph); glyphs are Nerd Font Weather Icons.
WMO = {
    0: ("Clear", "\ue30d", "\ue32b"),
    1: ("Mainly clear", "\ue30d", "\ue32b"),
    2: ("Partly cloudy", "\ue302", "\ue37e"),
    3: ("Overcast", "\ue312", "\ue312"),
    45: ("Fog", "\ue313", "\ue313"),
    48: ("Rime fog", "\ue313", "\ue313"),
    51: ("Light drizzle", "\ue31b", "\ue336"),
    53: ("Drizzle", "\ue31b", "\ue336"),
    55: ("Dense drizzle", "\ue31b", "\ue336"),
    56: ("Freezing drizzle", "\ue316", "\ue331"),
    57: ("Freezing drizzle", "\ue316", "\ue331"),
    61: ("Light rain", "\ue308", "\ue325"),
    63: ("Rain", "\ue318", "\ue333"),
    65: ("Heavy rain", "\ue317", "\ue332"),
    66: ("Freezing rain", "\ue3ad", "\ue3ad"),
    67: ("Freezing rain", "\ue3ad", "\ue3ad"),
    71: ("Light snow", "\ue31a", "\ue335"),
    73: ("Snow", "\ue31a", "\ue335"),
    75: ("Heavy snow", "\ue35e", "\ue35e"),
    77: ("Snow grains", "\ue31a", "\ue335"),
    80: ("Light showers", "\ue309", "\ue326"),
    81: ("Showers", "\ue319", "\ue334"),
    82: ("Violent showers", "\ue31c", "\ue329"),
    85: ("Snow showers", "\ue30a", "\ue327"),
    86: ("Snow showers", "\ue30a", "\ue327"),
    95: ("Thunderstorm", "\ue31d", "\ue32a"),
    96: ("Thunderstorm, hail", "\ue31d", "\ue32a"),
    99: ("Thunderstorm, hail", "\ue31d", "\ue32a"),
}


def describe(code) -> tuple[str, str, str]:
    try:
        return WMO.get(int(code), ("Unknown", "\ue33d", "\ue33d"))
    except (TypeError, ValueError):
        return "Unknown", "\ue33d", "\ue33d"


def _http_json(url: str) -> dict | None:
    try:
        with urllib.request.urlopen(url, timeout=HTTP_TIMEOUT) as response:
            raw = response.read(MAX_HTTP_BYTES + 1)
            if len(raw) > MAX_HTTP_BYTES:
                return None
            return json.loads(raw.decode("utf-8", "replace"))
    except (urllib.error.URLError, OSError, ValueError):
        return None


def geocode(city: str) -> dict | None:
    query = urllib.parse.urlencode({"name": city, "count": 1, "language": "en", "format": "json"})
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
        "unit": "\u00b0F" if not metric else "\u00b0C",
        "wind_unit": "mph" if not metric else "km/h",
        "fetched": time.time(),
    }


def load_cache() -> dict | None:
    try:
        data = json.loads(CACHE_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def save_cache(data: dict) -> None:
    try:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        CACHE_PATH.write_text(json.dumps(data))
    except OSError:
        pass


def get_weather(city: str, units: str = "metric", days: int = 3, max_age: float = 0) -> dict | None:
    """Cached-if-fresh weather for *city*, fetching when stale/absent/failed."""
    cached = load_cache()
    if cached and cached.get("city", "").lower() == (city or "").lower():
        if max_age > 0 and (time.time() - float(cached.get("fetched") or 0)) < max_age:
            return cached
    fresh = fetch_weather(city, units=units, days=days)
    if fresh is None:
        return cached  # offline: last good result, if any
    save_cache(fresh)
    return fresh


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Open-Meteo weather for the widget")
    ap.add_argument("--city", default="London")
    ap.add_argument("--units", default="metric")
    ap.add_argument("--days", type=int, default=3)
    ap.add_argument("--max-age", type=float, default=0, help="cache freshness (seconds)")
    args = ap.parse_args(argv)

    data = get_weather(args.city, units=args.units, days=args.days, max_age=args.max_age)
    print(json.dumps({"ok": data is not None, "data": data}))
    return 0 if data else 1


if __name__ == "__main__":
    raise SystemExit(main())
