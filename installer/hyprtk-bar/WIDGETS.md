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
├── base.py           DesktopWidgetWindow — surface, placement, theming, snap layout
├── theme.py          build_widget_css() — per-widget, scale-aware scoped CSS
├── manager.py        DesktopWidgetManager — diffing reload, snap groups, drag
├── placement.py      placement side store (position/margins/snap) persistence
├── control.py        WidgetMoveControl — the Super+Shift move FIFO
├── sampled.py        SampledWidget base — periodic sample + render
├── clock.py          ClockWidget — digital / text / dials
├── clock_theme.py    clock theme file loader (bundled + user dirs)
├── weather.py        WeatherWidget + Open-Meteo client (city geocoding)
├── visualizer.py     VisualizerWidget + cava source + cairo effects
├── disk.py           DiskWidget — per-drive usage + read/write rates
├── network.py        NetworkWidget — interface, IP, up/down rates, graph
├── resources.py      ResourcesWidget — CPU / RAM / swap / temp / load
└── sysinfo.py        SysInfoWidget — host / OS / kernel / CPU / GPU / memory / disks
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
  "transparent": false,          // master: drop every widget's pill bg/border
  "clock": {
    "enabled": true,
    "layer": "bottom",           // background | bottom | top
    "position": "top-right",     // free | 9-way: top/center/bottom x left/center/right
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
    "color_mode": "pywal",       // accent | gradient | pywal | custom
    "color": "", "gradient_from": "", "gradient_to": "",
    "peak_dots": true, "orientation": "horizontal", "fps": 60,
    "source": "cava", "cava_binary": "cava",
    "opacity": 0.6, "radius": 16, "padding": 12, "background": ""
  },
  "disk": {
    "enabled": false, "position": "bottom-left", "width": 300,
    "show_bar": true, "show_rates": true, "drives_max": 3, "refresh_seconds": 2
  },
  "network": {
    "enabled": false, "position": "bottom-left", "width": 300,
    "interface": "auto", "show_ip": true, "show_rates": true,
    "show_graph": true, "refresh_seconds": 1
  },
  "resources": {
    "enabled": false, "position": "bottom-left", "width": 280,
    "show_cpu": true, "show_cores": false, "show_ram": true, "show_swap": true,
    "show_temp": true, "show_load": true, "refresh_seconds": 1
  },
  "sysinfo": {
    "enabled": false, "position": "bottom-left", "width": 320,
    "show_host": true, "show_os": true, "show_kernel": true, "show_uptime": true,
    "show_cpu": true, "show_gpu": true, "show_memory": true, "show_disks": true,
    "refresh_seconds": 10
  }
}
```

Every widget also carries the shared keys `layer`, `margin_x` / `margin_y`,
`opacity`, `radius`, `padding`, `background` / `foreground` / `accent`, `scale`,
and the snap keys (`snap_group`, `snap_axis`, `snap_order`) — see
[Snapping](#snapping). The transparent pill is a **master** switch
(`widgets.transparent`) that applies to every widget at once, not a per-widget
key.

### Layers

- `background` — below every window (above the wallpaper).
- `bottom` — below normal windows; the usual "desktop widget" layer.
- `top` — above windows (an always-visible HUD).

### Placement & dragging

`position` is a 9-way anchor (`top-left` … `bottom-right`) **or `free`**, which
places the widget at an absolute top-left of `margin_x` / `margin_y` on the
monitor (clamped to stay fully on-screen). To move a widget, **hold Super+Shift and
left-drag it on the desktop** — the drag switches it to `free` and persists the
new `margin_x` / `margin_y` to the config on release. `base.py` derives the
surface origin from the anchors so the grab point stays under the pointer.

The move is **compositor-driven**: a layer-shell surface with `keyboard_mode =
none` never receives the Super modifier in GTK, so `Super + Shift + left mouse`
is a Hyprland bind (press/release) that runs `hyprtk-bar-widget-move.sh`. The
bar reads its control FIFO (`desktop/control.py`), polls the cursor over the
command socket and moves the widget under it. Window drag stays on
`Super + left mouse`; widgets are click-through when not being moved.

Placement is kept separate from the rest of the widget config, in
`~/.config/hyprtk-bar/widget-positions.json` (`desktop/placement.py`): the
`position`, `margin_x` / `margin_y` and snap keys only. The manager **overlays**
this store on the widgets on every reload, so an appearance/behaviour change
applied from settings can never reset where a widget was dragged to. It is
re-written on every drag, snap, detach and reload; the settings Apply only
rewrites a widget's placement when that widget's placement controls were
actually edited.

Because a margin means something different per anchor (an absolute offset for
`free`, the distance from the anchored edge otherwise), changing **Position** in
the settings resets `margin_x` / `margin_y` to the default inset — otherwise a
`free`-drag margin carried into an anchored position would push the widget to
the opposite edge.

### Snapping

Widgets that share a non-empty **`snap_group`** are laid out together along
**`snap_axis`** (`horizontal` or `vertical`), ordered by **`snap_order`**. The
group uses one **uniform cell** — the largest member's width/height — and each
member is resized to that cell and its content **scaled to fit**
(`SNAP_SCALE_MIN`–`SNAP_SCALE_MAX`). The scale is passed into the CSS, so text
sizes track the cell.

Groups are formed by **drag-snap**: drop a widget with an edge within
`SNAP_DIST` (28 px) of another and they snap (side-by-side → horizontal, stacked
→ vertical); a joining widget follows the group's existing axis. Dragging a
snapped widget out **detaches** it (its position is frozen as `free`). The
settings **Widgets** page exposes `snap_group` / `snap_axis` / `snap_order`
directly, so a group can also be built by hand.

`DesktopWidgetManager._apply_snap_layout` (deferred to an idle so widgets are
allocated) computes each group's cell and positions; `base.set_snap_layout`
applies the cell size, content scale and absolute position without touching the
persisted config.

### Usable area (bar avoidance)

Widgets never sit under the bar. The usable area is the monitor inset by the
bar's **exclusive-zone thickness** on **all four sides** — the bar thickness
acts as a border that widgets may not overlay. The manager reads it from
Hyprland (`monitors[].reserved`, e.g. `38` for a 38 px bar) in
`_usable_rect()`; `base.set_bounds()` clamps every widget (anchored, `free` or
snapped) into that rect, and `set_fit_scale()` shrinks a standalone widget's
content if it would not otherwise fit. A snap group is clamped and scaled as a
whole so it fits below the bar.

### Colour overrides

Widgets theme from **pywal by default** — `desktop/theme.resolve_widget_palette`
pulls the live wallpaper palette (background / foreground / `color5` accent)
regardless of the bar's own theme source. Each widget's `background` /
`foreground` / `accent` is `""` to follow that palette live, or an explicit
`#RRGGBB` to pin it. The settings UI exposes this as a **Theme** checkbox +
colour picker. The master **Transparent pills** switch (`widgets.transparent`)
drops the background fill and border of every widget so only the content shows
over the wallpaper.

---

## The widgets

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
instantly on restart. WMO codes map to labels + **Nerd Font Weather Icons**
(sun / cloud / rain / snow / thunder …, `U+E300–U+E3EB`, with day and night
variants). The Font Awesome `f0xx` codepoints must not be used — in "Symbols
Nerd Font" they render as unrelated icons (e.g. `f00d` is "times").

### Visualizer

Audio levels come from **cava** in raw-ascii mode (the widget writes a small
cava config, spawns `cava -p <conf>` and reads `;`-separated frames on a worker
thread). When cava is absent it falls back to a **synthetic** animation so the
surface still renders. Effects (`style`): `bars`, `wave`, `mirror`, `dots`,
`glow`; colours from the palette (`accent`/`gradient`/`pywal`) or explicit
overrides (`custom`); plus sensitivity, smoothing, peak dots, FPS, bar count and
horizontal/vertical orientation.

### Hard disks (`disk`)

Per-drive usage from `monitor_data.drives()` (`lsblk`): type glyph, model,
`used / size` and a usage bar, up to `drives_max`, plus aggregate read/write
rates from `DiskSampler`. All data comes from the bar's `monitor_data` module.

### Network (`network`)

The active interface (or a pinned one), its IP, up/down rates and a rolling
rate graph (`graphs.HistoryGraph`). Interface auto-selection, per-interface
rates and glyphs come from `NetSampler` / `iface_kind`.

### Processor / RAM (`resources`)

Overall CPU % + bar + a rolling graph (`show_cores` switches it to a per-core
multi-series graph), RAM and swap `used / total` with bars, CPU temperature and
the load average — from `CpuSampler` + `memory()`.

### System information (`sysinfo`)

Host, OS (`/etc/os-release`), kernel, uptime, CPU model, GPU (fetched off-thread
via `gpu_static`), total memory and a disk summary. Rows toggle individually;
refreshes slowly (default 10 s).

The four data widgets share the `SampledWidget` base (`desktop/sampled.py`):
`collect()` returns a data dict and `render()` updates the built GTK widgets on
a timer.

---

## Settings page

A new **Widgets** sidebar entry (settings window) with a master **Desktop
widgets** enable, a master **Transparent pills** switch, and one notebook tab per
widget. Every field maps 1:1 to the config keys above; Apply writes the config
and the manager diffs it — creating, updating or destroying surfaces live (no bar
restart). Placement controls are tracked separately from the rest of a widget's
fields, so an Apply only rewrites the placement a widget's controls actually
edited and everything else keeps its live position (see
[Placement & dragging](#placement--dragging)).

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
- [x] pywal-default theming (`resolve_widget_palette`)
- [x] Free placement + **Super+Shift + left-drag to move** (persists `position: free`
      and the new margins); widgets are click-through when not being moved
- [x] Nerd Font Weather Icons (`U+E300–U+E3EB`) for the weather glyphs
- [x] Four data widgets: **disk**, **network**, **resources** (CPU/RAM), **sysinfo**
      (shared `SampledWidget` base, reusing `monitor_data.py`)
- [x] **Snapping**: drag-snap into horizontal/vertical groups with a uniform cell
      and content scaled to fit (`snap_group` / `snap_axis` / `snap_order`)
- [x] **Bar avoidance**: widgets are clamped into the monitor minus the bar's
      exclusive zone (bar thickness as a border) and scaled down to fit
- [x] Master **Transparent pills** switch (`widgets.transparent`) — every widget's
      pill background/border on or off at once
- [x] **Placement store** (`desktop/placement.py`) — position/margins/snap persist
      in `widget-positions.json` and survive an appearance/behaviour Apply
- [x] Position change resets margins to the default inset (no opposite-edge flip)

Deliberately left for follow-up:

- [ ] Per-widget monitor selection (currently the primary monitor; the bar's
      `select_monitors` logic could be reused) — free placement is also
      primary-monitor relative.
- [ ] Clock theme editing/export from the settings UI (`save_clock_theme` exists).
- [ ] Weather: hourly forecast, more providers, manual lat/lon override.
- [ ] Visualizer: per-channel stereo bars; PipeWire-native capture fallback.
- [ ] A widget gallery / "add widget" flow beyond the three built-ins.
