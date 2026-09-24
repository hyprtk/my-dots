# Desktop Widgets

Desktop widgets are **free-floating layer-shell surfaces** owned by the bar
process, separate from the bar's own modules. Think conky panels: each widget
has its own placement, size, opacity and theming, and can be enabled/disabled
independently from the settings window's **Widgets** page.

This document is the design/plan for the feature and the map of the scaffolded
code.

---

## Architecture

```
src/hyprtk_bar/desktop/
├── __init__.py       exports DesktopWidgetManager
├── base.py           DesktopWidgetWindow — layer-shell surface, positioning, theming
├── theme.py          build_widget_css() — per-widget scoped CSS
├── manager.py        DesktopWidgetManager — build/reload/theme/teardown diffing
├── clock.py          ClockWidget — digital / text / dials
├── clock_theme.py    clock theme file loader (bundled + user dirs)
├── weather.py        WeatherWidget + Open-Meteo client (city geocoding)
└── visualizer.py     VisualizerWidget + cava source + cairo effects
```

The manager is created in `__main__._run_window()` when `widgets.enabled` is
true, receives the bar's palette through the (now multi-callback)
`BarWindow.set_theme_extra_callback`, and is reloaded live by the settings
window via `bar._menu_actions()["set_widgets"]`.

A widget window:

1. builds its content into `self.root` (a `.desktop-widget.widget-<id>` box),
2. positions itself with layer-shell anchors + margins from its config block,
3. loads its own `Gtk.CssProvider` with CSS scoped under `.widget-<id>` so two
   widgets with different colours never fight over one screen-wide cascade,
4. re-renders on `apply_theme(palette)` via the `on_palette()` hook.

### Why a separate package (not `widgets.py`)

`widgets.py` already exists (the bar's shared `Glyph`/`HoverButton` helpers).
A package literally named `widgets/` would shadow it in Python's import order,
so the desktop widgets live in `desktop/`.

---

## Config

All widgets share a `widgets` block. `enabled` is the master switch; each widget
has its own `enabled` plus placement/appearance keys and widget-specific keys.
Defaults live in `config.DEFAULTS["widgets"]`; `config._validate_widgets()`
clamps every field.

```jsonc
"widgets": {
  "enabled": true,
  "clock": {
    "enabled": true,
    "layer": "bottom",           // background | bottom | top
    "position": "top-right",     // 9-way: top/center/bottom x left/center/right
    "margin_x": 40, "margin_y": 40,
    "width": 220, "height": 0,   // 0 = auto
    "style": "digital",          // digital | text | dials
    "theme": "default",          // clock theme file
    "font": "", "scale": 1.0,
    "opacity": 0.75, "radius": 16, "padding": 18,
    "background": "", "foreground": "", "accent": "",  // "" = follow bar palette
    "time_format": "%H:%M", "date_format": "%A, %d %B",
    "show_date": true, "show_seconds": false,
    "dial_count": 1, "ring_thickness": 6
  },
  "weather": {
    "enabled": true,
    "layer": "bottom", "position": "top-left",
    "margin_x": 40, "margin_y": 40, "width": 280, "height": 0,
    "city": "London", "units": "metric", "refresh_minutes": 15,
    "opacity": 0.75, "radius": 16, "padding": 18,
    "background": "", "foreground": "", "accent": "",
    "show_icon": true, "show_temp": true, "show_condition": true,
    "show_feels_like": true, "show_humidity": true, "show_wind": true,
    "show_forecast": true, "forecast_days": 3
  },
  "visualizer": {
    "enabled": false,
    "layer": "bottom", "position": "bottom-center",
    "margin_x": 40, "margin_y": 40, "width": 420, "height": 120,
    "style": "bars",             // bars | wave | mirror | dots | glow
    "bars": 48, "sensitivity": 1.0, "smoothing": 0.6,
    "color_mode": "gradient",    // accent | gradient | pywal | custom
    "color": "", "gradient_from": "", "gradient_to": "",
    "peak_dots": true, "orientation": "horizontal", "fps": 60,
    "source": "cava", "cava_binary": "cava",
    "opacity": 0.6, "radius": 16, "padding": 12, "background": ""
  }
}
```

### Layers

- `background` — below every window (above the wallpaper).
- `bottom` — below normal windows; the usual "desktop widget" layer.
- `top` — above windows (an always-visible HUD).

### Colour overrides

Each widget's `background` / `foreground` / `accent` is `""` to follow the bar
palette (pywal / imported / manual) live, or an explicit `#RRGGBB` to pin it.
The settings UI exposes this as a **Theme** checkbox + colour picker.

---

## The three sample widgets

### Clock

Three looks (`style`), or a theme file that sets one:

- **digital** — large numeric time + date line.
- **text** — the time spelled out ("half past three").
- **dials** — cairo-drawn: one analog face with hour/minute/second hands and
  tick marks, or `dial_count: 3` concentric H/M/S progress rings.

**Clock theme files** are JSON presets in
`~/.config/hyprtk-bar/widget-themes/clock/` (user) and
`<install>/assets/widgets/clock/` (bundled: `default`, `minimal`,
`neon-dials`). A theme's values are overridden by the widget's own config block,
so the settings window always wins. Loader: `desktop/clock_theme.py`.

### Weather

Location is set by **city name**. The city is geocoded with the keyless
Open-Meteo geocoding API, then current conditions + daily forecast come from the
Open-Meteo forecast API. Fetches run on a worker thread; the last good result is
cached at `~/.cache/hyprtk-bar/weather.json` so the widget renders offline and
instantly on restart. WMO codes map to labels + Nerd Font weather glyphs.

### Visualizer

Audio levels come from **cava** in raw-ascii mode (the widget writes a small
cava config, spawns `cava -p <conf>` and reads `;`-separated frames on a worker
thread). When cava is absent it falls back to a **synthetic** animation so the
surface still renders. Effects (`style`): `bars`, `wave`, `mirror`, `dots`,
`glow`; colours from the palette (`accent`/`gradient`/`pywal`) or explicit
overrides (`custom`); plus sensitivity, smoothing, peak dots, FPS, bar count and
horizontal/vertical orientation.

---

## Settings page

A new **Widgets** sidebar entry (settings window) with a master enable and one
notebook tab per widget. Every field maps 1:1 to the config keys above; Apply
writes the config and the manager diffs it — creating, updating or destroying
surfaces live (no bar restart).

---

## Scaffold status / follow-ups

Implemented in this scaffold:

- [x] `widgets` config schema + validation + defaults
- [x] `DesktopWidgetWindow` base (layer-shell, 9-way placement, theming)
- [x] `DesktopWidgetManager` (diffing reload, theme fan-out, teardown)
- [x] Clock (digital/text/dials) + clock theme files + 3 bundled presets
- [x] Weather (Open-Meteo city geocoding, cache, forecast)
- [x] Visualizer (cava + synthetic, 5 effects, colour modes, orientation)
- [x] Settings **Widgets** page (master + per-widget controls)
- [x] Wiring in `app.py` / `bar.py` / `__main__.py`
- [x] `install.sh` installs bundled widget themes

Deliberately left for follow-up:

- [ ] Per-widget monitor selection (currently the primary monitor; the bar's
      `select_monitors` logic could be reused).
- [ ] Drag-to-position on the desktop (currently anchor + margin fields).
- [ ] Clock theme editing/export from the settings UI (`save_clock_theme` exists).
- [ ] Weather: hourly forecast, more providers, manual lat/lon override.
- [ ] Visualizer: per-channel stereo bars; PipeWire-native capture fallback.
- [ ] A widget gallery / "add widget" flow beyond the three built-ins.
