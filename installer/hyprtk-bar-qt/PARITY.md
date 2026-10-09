# hyprtk-bar ↔ hyprtk-bar-qt parity matrix

Goal: **like-for-like** with the GTK4 `hyprtk-bar` — all modules, settings,
popups, menus, config and theming components.

Legend: ✅ done · ◐ partial · ☐ todo

## Bar modules (`bar/modules/`)

| GTK module | Purpose | Qt status |
|---|---|---|
| `start_button` | start-menu button | ✅ button + `surface/StartMenu.qml` v1 |
| `quicklinks` | configurable launcher glyph row (L/R/M click) | ✅ `Quicklinks.qml` |
| `workspaces` | Hyprland workspaces | ✅ `Workspaces.qml` |
| `tasklist` | open windows | ✅ `Tasklist.qml` |
| `window` | active window title | ✅ `ActiveWindow.qml` |
| `updates` | package-update count | ✅ `Updates.qml` |
| `sysmon` | CPU/RAM/disk + click → monitor | ✅ `SysMonitor.qml` + `surface/SysMonitor.qml` dialog |
| `kbstate` | Caps/Num lock LEDs | ✅ `KbState.qml` |
| `clock` | time/date (styles, dials, seconds) | ✅ `Clock.qml` (format + hover date/calendar popups) |
| `media` | (optional extra — not in GTK) now-playing + transport | ✅ `Media.qml` (Quickshell MPRIS; prev/play-pause/next, tooltip, raise; hidden with no player) |
| `notifications` | daemon + center (bell) | ✅ `NotificationsButton.qml` bell + unread badge, `surface/NotificationCenter.qml` history; toasts on by default (opt out with `HYPRTK_BAR_QT_NOTIFICATIONS=0`) |
| `tray` | SNI tray + dbusmenu | ✅ `Tray.qml` (icons + activate + right-click DBusMenu via `QsMenuAnchor`) |
| `quicksettings` | Win11 flyout | ✅ `surface/QuickSettings.qml` (volume/mic/brightness/Wi-Fi/Bluetooth) |
| graphs | cpu/mem/net history | ✅ `components/Sparkline.qml`, `Net.qml` |

## Surfaces / popups / menus

| GTK | Qt status |
|---|---|
| Bar settings window (9 pages) | ✅ `surface/Settings.qml` — centred layer-shell panel; edits the Qt bar's own config (bar geometry, theme, font, animations, arc menu, menu, quicklinks, modules, widgets) |
| System monitor dialog (CPU/Mem/Disks/Network/GPU/Apps, cairo graphs) | ✅ `surface/SysMonitor.qml` (six pages, QML graphs, DIMM slots) |
| Themer dialog (Wallpaper/Pywal/Rofi/Bar themes/Matuwall/Swaylock/Icons/SDDM+GRUB) | ✅ `surface/Themer.qml` — centred layer-shell panel; all nine pages, incl. the Matuwall TOML editor |
| Clipboard history dialog | ✅ `surface/Clipboard.qml` (cliphist list/copy/delete/wipe, search) |
| Notification center | ✅ `surface/NotificationCenter.qml` (history, actions, clear all, unread badge) |
| Quick-settings flyout | ✅ |
| Arc menu (radial FAB) | ✅ `surface/ArcMenu.qml` (position/radius/sizes/colours/animation/items from config) |
| Start menu (whisker / win7 / win11 / plasma layouts, search, favorites, recents, places, power) | ✅ `surface/StartMenu.qml` (4 layouts, search, favourites, recents, category sidebar, win7 places, plasma file browser, power) |
| Bar right-click menu | ✅ `surface/BarMenu.qml` |
| Theme import dialog | ✅ Themer `Import` page (importable list, path, remove) |

## Settings pages (`bar_settings.py`)

Bar · Fonts · Themes · Animations · Arc Menu · Menu · Quicklinks · Modules · Widgets

✅ all nine pages in `surface/Settings.qml`: Bar, Themes (pywal/imported/manual
+ installed-theme picker), Fonts (installed-font picker), Animations, Arc Menu
(items incl. `action`), Menu (enabled/follow/gaps/layout/position/align/power/
favourites), Quicklinks, Modules (show/hide, section, reorder + per-module
options for workspaces/clock/updates/window/tray/notifications), Widgets
(placement, size, radius/padding/scale, snap + per-widget options). The `theme`
edit and the Qt `Config` override are kept in sync. See `PLAN.md` for the
fix history.

## Config schema (`~/.config/hyprtk-bar-qt/config.json`)

The Qt bar reads its **own** config, separate from the GTK bar's
(`~/.config/hyprtk-bar/config.json`); on first run it is migrated from the GTK
config so an existing setup carries over (see `backend/.../paths.py`).

| Section | Qt status |
|---|---|
| `bar` (position/height/gaps/radius/opacity/width/align) | ✅ |
| `monitors` (primary / all / [connector]) | ✅ `shell.qml` screen filter |
| `theme` (source/theme_name/background/foreground/accent) | ✅ writer + `Theme` overrides |
| `animations`, `font` | ✅ animated bar border (`theme.border_animation` + mode/speed) + surface reveal; `font` applied to the bar modules |
| `layout` (left/center/right module lists) | ✅ data-driven (`DelegateChooser`) |
| `quicklinks` | ✅ |
| `menu` (layout/position/align/gaps/favourites/recents/power/enabled/follow_bar) | ✅ |
| `sysmon` (interval/data_points/disk_path/network_iface/pages/monitor) | ✅ |
| `workspaces` (show_empty/max), `clock` (format), `updates` (interval/scripts), `window` (max_length/width), `tray` (icon_size) | ✅ |
| `notifications` (max_stored / default_timeout) | ✅ |
| per-module `enabled` (`workspaces`/`clock`/`sysmon`/`updates`/`window`/`tray`/`quicksettings`/`notifications`/`themer`/`quicklinks`/`arcmenu`) | ✅ |
| `arcmenu` (position/geometry/colours/animation/items/enabled) | ✅ |
| `quicksettings` | ✅ |
| `widgets` (master + per-widget placement/options, `border`/`transparent`) | ✅ |
| reader/writer | ✅ `config/Config.qml` (Qt-only keys) + `data/BarConfig.qml` / `MenuConfig.qml` / `Widgets.qml` / `theme/Theme.qml` (blocks); written by `surface/Settings.qml` via `backend/.../barsettings.py` |

## Theming components

| GTK | Qt status |
|---|---|
| Live pywal palette | ✅ `theme/Theme.qml` |
| Bar `theme` block (manual/imported source) | ✅ Themer writes the override keys |
| 9 shipped themes (`themes/`) | ✅ Themer picker (`backend/.../themes.py` + `theme_import`) |
| `theme.py` / `menu/theme.py` / `desktop/theme.py` CSS builders | ☐ (QML uses colour tokens only) |
| `theme_import.py` (decode waybar CSS) | ✅ ported to `backend/.../theme_import.py` |
| rofi variants, hyprlock, SDDM/GRUB, icons | ✅ Themer pages (script-driven, as GTK) |
| gengtk/oomox GTK theme generation | ☐ (out of scope — GTK-only tooling) |

## Desktop widgets (`desktop/`)

`surface/DesktopWidgets.qml` + `surface/widgets/` — free-floating layer-shell
surfaces reading the Qt bar's own `widgets` config.

| Widget | Qt status |
|---|---|
| `clock` | ✅ digital / text / dials (1 analog face or 3 H/M/S rings), seconds, ring width, theme files |
| `resources` | ✅ CPU graph + RAM/swap bars + temp/load |
| `disk` | ✅ per-drive bars + I/O rates |
| `network` | ✅ iface/IP/rates + download graph |
| `weather` | ✅ current + feels/humidity/wind + daily forecast (Open-Meteo, cached; cells shrink to keep one row in a constrained cell) |
| `visualizer` | ✅ cava/synthetic; bars / wave / mirror / dots / glow; sensitivity, smoothing, orientation, peak dots |
| `sysinfo` | ✅ host/OS/kernel/uptime/CPU/GPU/memory/disks |
| placement: 9-way + `free` | ✅ (`WidgetFrame`) |
| placement: usable-area clamp | ✅ (kept clear of the bar) |
| placement: snap groups (`snap_group`/`snap_axis`/`snap_order`) | ✅ config-driven (`widgets_layout`); per-member cell scale + dropped-widget anchor (GTK `_snap_anchor`), gap 10 |
| placement: drag (Super+Shift move) | ✅ cursor-polling move mode via `widget_move` FIFO + `hyprtk-bar-qt-widget-move` |

## Backend (Python, toolkit-free)

| Module | Qt status |
|---|---|
| `sysmon` (cpu/mem/net) | ✅ `backend/.../sysmon.py` |
| `monitor` (cpu cores/mem/disk/net/gpu, rich stream) | ✅ `backend/.../monitor.py` |
| `monitor_data` (dmidecode/lspci/lsblk) | ✅ `backend/.../monitor_data.py` |
| `clipboard` (cliphist list/copy/delete/wipe) | ✅ `backend/.../clipboard.py` |
| `proc_action` / `dimm` helpers | ✅ |
| palette / config readers | ✅ |
| `hypr_animations` (border period from active animations file) | ✅ `backend/.../hypr_animations.py` + `data/HyprAnim.qml` |
| `ipc` (hyprctl + socket2) | ◐ (Hyprland service + `IpcHandler` used instead) |

## Next passes

Parity remediation (see **`PLAN.md`**, Batches 1–6) is complete. Remaining known
differences, both deliberate:

- **`theme.py` / `menu/theme.py` / `desktop/theme.py` CSS builders** — N/A: the Qt
  bar renders from QML colour tokens, not generated CSS; behaviour matches.

Optional polish: start-menu Places now cover Games + Trash + Network; GTK-only
tooling (gengtk/oomox theme generation) is intentionally out of scope. The
**MPRIS media module** (`Media.qml`) is an additive extra the GTK bar does not ship.

The dialogs (Settings / Themer / About) are now centred layer-shell panels
rather than tiled xdg windows, and expose `IpcHandler`s (`toggle`/`open`/`close`)
alongside `clipboard`/`arcmenu`.
