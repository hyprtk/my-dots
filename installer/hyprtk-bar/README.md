## hyprtk-bar

A modern, feature-complete taskbar for the Hyprland Wayland compositor, built
with GTK3 and the layer-shell protocol. hyprtk-bar is the centerpiece of the
hyprtk desktop: it hosts app launchers, workspaces, a task list, system
monitoring, a system tray, quick settings and a built-in notification center —
all themed live from your pywal16 palette.

---

## Features

- **Fully modular bar** — arrange modules across left / center / right
  sections, show/hide them, and reorder them from the built-in settings window
  (no config-file surgery required).
- **Live theming** — one wallpaper drives the whole palette via **pywal16**.
  The bar re-themes itself the moment the palette changes, with zero restart.
  Themes can also come from an imported waybar theme or a manual color block.
- **Task list** — pinned and running applications grouped by class, with a
  running/active indicator, a hover preview of an app's windows, click to focus
  or minimize, middle-click to close, and launch-on-click for pinned apps.
- **Workspaces** — compact chips for each workspace; click to switch. Shows
  occupied and empty workspaces, with the active one highlighted.
- **Notification center** — a built-in `org.freedesktop.Notifications` daemon
  renders desktop notifications as floating toasts and collects them in a
  center panel with action buttons and "Clear all". No separate daemon needed.
- **System tray** — full StatusNotifier (SNI) support, including native
  `com.canonical.dbusmenu` menus rendered directly in the bar.
- **Quick settings** — Wi-Fi and Bluetooth toggles, a volume slider with mute,
  and a brightness slider (auto-hidden when no backlight device exists).
- **System monitor** — live CPU, RAM and disk readouts with warning levels.
- **Show-desktop sliver** — a slim strip at the end of the bar that minimizes
  and restores every window on the active workspace.
- **Multi-monitor** — one bar per monitor when configured, each with its own
  active workspace; the tray and notification daemon stay on the primary bar.
- **Start menu** — a full application menu built into the bar (search,
  favorites, recents, power buttons; whisker/win7/win11/plasma layouts),
  toggled from the start button or `Super+Space`.
- **Floating settings window** — drag it by its header, change everything
  live, everything applies without restarting the bar.

---

## Screenshots

See the [Showcase](SHOWCASE.md) for screenshots of every feature.

---

## Requirements

- A Hyprland session (the bar talks to the compositor through `hyprctl` and
  the event socket).
- Python ≥ 3.10.
- GTK3 and `gtk-layer-shell` (GObject-Introspection typelibs).
- PyGObject and pycairo — installed from your package manager (they ship no
  binary wheels, so the installer never pip-builds them).
- `dbus-next` — installed into the bar's virtualenv (pure Python).

The installer handles the system packages for you: it detects your package
manager and installs the right typelibs, Python GI bindings and venv tooling
(e.g. `gir1.2-gtk-3.0` + `gir1.2-gtklayershell-0.1` + `python3-gi` on
Debian/Ubuntu, `gtk3` + `gtk-layer-shell` + `python-gobject` on Arch). The bar
runs in a `--system-site-packages` virtualenv, so the distro's own
PyGObject/pycairo are used and no compiler is required. See `PORTABILITY.md` for
the full per-distro mapping, the feature-availability matrix and remaining
caveats.

---

## Installation

Run the bundled installer:

```bash
./install.sh
```

This:

1. Detects the package manager and installs any missing system dependencies
   (skipped automatically when already present).
2. Creates `~/.local/share/hyprtk-bar/` with a `--system-site-packages`
   virtualenv and the source.
3. Pip-installs `dbus-next` into the venv and editable-installs the bar
   (`--no-deps` — PyGObject/pycairo come from the system, not pip).
4. Drops a `hyprtk-bar` launcher on `~/.local/bin`.
5. Vendors pywal16 (`vendor/pywal16/`) and drops a `wal` launcher on
   `~/.local/bin` (real launcher `venv/bin/wal`) — no separate AUR/PyPI pywal
   install is needed. `install.sh --wal-only` provisions just this and exits.
6. Installs a desktop entry (and optional GNOME autostart hint).

Skip the system-dependency step with `--no-deps` (e.g. on Gentoo, or when you
manage the typelibs yourself):

```bash
./install.sh --no-deps
```

Uninstall with:

```bash
./install.sh --uninstall
```

### Cross-distro support

`install.sh` detects pacman / apt / dnf / zypper / xbps / apk / emerge / nix and
installs the right typelib + PyGObject/pycairo + venv packages for each (Void
and Alpine need their `-devel`/`-dev` subpackages for the typelibs). It warns —
but does not fail — when `gtk-layer-shell` is below 0.9 (older LTS releases ship
0.5–0.8) and prints the source-build steps. The full per-distro mapping, the
feature-availability matrix and the remaining AUR/niche "theming wall"
(wallpaper daemon, folder-icon colouring — pywal itself is bundled) are
documented in `PORTABILITY.md`, and a container CI matrix
(`.github/workflows/install-matrix.yml`) exercises the installer on seven distro
families.

### NixOS

Use the flake:

```bash
nix run github:hyprtk/hyprtk-bar
```

or add it as an input:

```nix
inputs.hyprtk-bar.url = "github:hyprtk/hyprtk-bar";
```

The derivation (`derivation.nix`) installs the bar, its assets/scripts/themes and
the bundled Nerd Font into the store and surfaces the data dir via
`HYPRTK_BAR_DATA_DIR`. Config stays at `~/.config/hyprtk-bar/config.json`.

### Autostart with Hyprland

Add it to your Hyprland autostart. With the hyprtk Lua config (`autostart.lua`):

```lua
hl.exec_cmd("hyprtk-bar &")
```

Or with a plain `hyprland.conf`:

```
exec-once = $HOME/.local/bin/hyprtk-bar
```

The bar locks itself to a single instance: a second launch simply exits.

### Keybindings (toggle scripts)

The bar's in-process features (start menu, arc menu, clipboard history) are
toggled by sending it a signal — Hyprland keybindings can't talk to the bar
directly, so `install.sh` drops three tiny scripts on `~/.local/bin` that
forward a signal to the running bar:

| Script | Signal | Feature |
|--------|--------|---------|
| `hyprtk-bar-menu-toggle.sh` | `SIGUSR1` | start menu |
| `hyprtk-bar-arc-toggle.sh` | `SIGUSR2` | arc menu |
| `hyprtk-bar-clipboard-toggle.sh` | `SIGHUP` | clipboard history |

Bind them in Hyprland (lua) like:

```lua
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("~/.local/bin/hyprtk-bar-menu-toggle.sh"))
hl.bind("SUPER + CTRL + M", hl.dsp.exec_cmd("~/.local/bin/hyprtk-bar-arc-toggle.sh"))
hl.bind("SUPER + CTRL + C", hl.dsp.exec_cmd("~/.local/bin/hyprtk-bar-clipboard-toggle.sh"))
```

The remaining features (quick settings, theme manager, system monitor,
notification center, settings) are opened by clicking their glyphs in the bar
and have no toggle script.

---

## Configuration

Configuration lives in `~/.config/hyprtk-bar/config.json`. It is created with
sane defaults on first run. The settings window edits this file for you, but
you can also hand-edit it and pick "Reload config" from the bar's right-click
menu.

### Top-level options

| Key | Default | Description |
| --- | --- | --- |
| `position` | `"bottom"` | `bottom` or `top` edge of the monitor. |
| `height` | `42` | Bar pill height in pixels (min 20). |
| `gap_in` | `6` | Transparent gap between the pill and app windows (px). |
| `gap_out` | `6` | Transparent gap between the pill and the screen edge (px). |
| `radius` | `12` | Pill corner radius. |
| `opacity` | `0.95` | Pill background alpha. |
| `width` | `"100%"` | Pill width: a pixel value, or `"NN%"` of the monitor. |
| `align` | `"center"` | Pill placement when `width` < 100%: `left`, `center`, `right`. |
| `monitors` | `"primary"` | `"primary"`, `"all"`, or a list of monitor names, e.g. `["DP-1", "HDMI-A-1"]`. |
| `show_desktop` | `true` | Enable the show-desktop strip at the pill's end. |

### Theme

| Key | Default | Description |
| --- | --- | --- |
| `theme.source` | `"pywal"` | `pywal` (live palette), `imported` (an imported theme), or `manual` (colors below). |
| `theme.theme_name` | `""` | Name of an imported theme (used when source is `imported`). |
| `theme.background` / `foreground` / `accent` / `hover` / `running` | … | Manual palette (used when source is `manual`). |

With `pywal` the bar reads `~/.cache/wal/colors.json` and tracks the whole
`~/.cache/wal` directory — re-theming happens automatically whenever the
wallpaper changes.

### Layout

`layout` places modules into the three sections. Each section is a list of
module ids:

```json
"layout": {
  "left":   ["start_button", "workspaces", "tasklist"],
  "center": [],
  "right":  ["sysmon", "kbstate", "clock", "notifications", "tray", "quicksettings"]
}
```

Module ids:

| Id | Module |
| --- | --- |
| `start_button` | Opens the in-bar start menu. |
| `quicklinks` | Launcher buttons with Nerd Font glyphs (terminal, files, apps, browser, wallpaper, clipboard, screenshot). |
| `workspaces` | Workspace chips. |
| `tasklist` | Pinned + running application buttons. |
| `sysmon` | CPU / RAM / disk readout. |
| `kbstate` | Caps Lock / Num Lock indicators (from the keyboard LEDs). |
| `clock` | Time, date and a calendar popup. |
| `notifications` | Bell button with an unread badge + notification center. |
| `tray` | StatusNotifier system tray. |
| `quicksettings` | Wi-Fi / Bluetooth / volume / brightness flyout. |

If your config predates `layout`, it is migrated from the legacy `*.enabled`
flags automatically.

### Module options

```json
"center": {
  "start_button": true,
  "start_icon": "view-grid-symbolic",
  "start_glyph": "\uf015",
  "start_command": "~/.local/bin/hyprtk-bar-menu-toggle.sh",
  "pinned": [
    { "class": "firefox", "command": "firefox", "icon": "firefox" }
  ]
},
"quicklinks": {
  "enabled": true,
  "glyph_font": "Symbols Nerd Font",
  "glyph_color": "accent",
  "icon_size": 0,
  "links": [
    { "id": "terminal", "label": "Terminal", "icon": "\uf120", "command": "alacritty" }
  ]
},
"workspaces": { "enabled": true, "show_empty": true, "max": 5 },
"clock":      { "enabled": true, "format": "%H:%M", "date_format": "%a %d %b", "calendar": true },
"sysmon":     { "enabled": true, "interval": 2, "disk_path": "/" },
"kbstate":    { "enabled": true, "poll_ms": 500 },
"tray":       { "enabled": true, "icon_size": 20, "reset_nm_applet": true },
"quicksettings": { "enabled": true },
"notifications": {
  "enabled": true,
  "max_stored": 50,
  "default_timeout": 5000
}
```

- **pinned** entries: `class` is matched against running windows, `command` is
  launched on click when the app is not running, `icon` overrides the icon.
- **start_glyph**: the start button's Nerd Font glyph (default `\uf015`, fa-home).
  Module icons (start button, quick settings, notification bell, keyboard state,
  system monitor) are all Nerd Font glyphs sized by the Fonts tab's *Icon size*
  setting (0 = auto with the font size).
- **quicklinks.links** entries: `icon` is a Nerd Font glyph (any font glyph the
  bar can render), `label` is the hover tooltip, `command` runs on left-click;
  optional `command_right` / `command_middle` run on right- / middle-click.
  `quicklinks.glyph_font` is the font used to render the glyphs (default
  `Symbols Nerd Font`) — it must be a font that actually contains them, since
  the system font's glyph fallback renders PUA codepoints as the wrong glyphs
  (e.g. an apps-menu grid showing as "5"). A link whose `command` is empty (e.g.
  the default browser link) resolves its launch command from `xdg-settings`.
  Commands containing shell operators (`&&`, `;`) are run through a shell
  automatically.
- **quicklinks.icon_size**: glyph size in px for the quicklink icons (default
  `0` = follow the global icon size). Editable in the settings window under
  *Fonts → Quicklink icons*. Glyphs render in pixels (like other module icons),
  so they scale with the font/icon size settings.
- **quicklinks.glyph_color**: glyph color (default `accent`, the pywal accent
  like the other icon modules). Accepts a palette key (`accent`, `fg`/`foreground`,
  `running`) or an explicit CSS color (hex/rgba).
- **notifications**: `max_stored` caps the center history; `default_timeout`
  is the toast duration in ms (0 persists). Urgent notifications and those
  with actions persist until dismissed.
- **tray.reset_nm_applet**: if enabled, the bar restarts `nm-applet` on startup
  so it re-registers with this bar's tray watcher.

---

## Usage

### Mouse interactions

| Area | Action |
| --- | --- |
| Start button | Left-click: open the start menu. |
| Workspace chip | Left-click: switch to that workspace. |
| Task button | Left-click: focus the most recent window (minimize if already focused). Middle-click: close. Right-click / hover: window preview. |
| Pinned app (not running) | Click: launch it. |
| Tray icon | Left-click: activate. Middle-click: secondary action. Right-click: menu (DBusMenu if the app exports one, otherwise the app's own context menu). |
| Bell (notifications) | Left-click: open the notification center; the unread badge resets. |
| Quick settings | Left-click: open the flyout. |
| Empty bar space | Right-click: bar menu → *Bar settings…* and *Reload config*. |
| Reload config | Restarts the bar process so the latest source **and** config are loaded (a plain config reload cannot pick up new modules). |
| Show-desktop strip | Left-click: minimize / restore all windows on the active workspace. |

### The start menu

hyprtk-bar ships the application menu built in (the former standalone
hyprtk-menu): search, category sidebar, pinned favorites, recently used, and a
power bar, in four layouts — `whisker`, `win7`, `win11`, `plasma`.

- **Open** — the start button, or `Super+Space` (a script signals the bar with
  SIGUSR1: `~/.local/bin/hyprtk-bar-menu-toggle.sh`).
- **Follow hyprtk-bar** — with `menu.follow_bar` on (default) the menu anchors
  to the bar's edge and aligns horizontally to the bar pill (its width + align
  + gaps); off positions it at the chosen screen corner. It themes from the
  bar's palette (pywal / imported / manual) and re-themes live.
- **Configure** — from the bar settings dialogue's *Menu* tab: enabled, layout,
  position, alignment, gaps, follow toggle. Legacy `menu` settings from the
  standalone app (`~/.config/hyprtk-menu/config.json`) auto-import on first run.

### The settings window

Opened from the bar's right-click menu. Every control applies live on *Apply*:

- **Bar** — height, width (`NN%` or px), alignment.
- **Theme** — source (pywal / imported / manual), imported theme, and
  *Import…* to pull a theme folder into the bar.
- **Animations** — enable the pill border animation and pick its mode/speed.
- **Arc Menu** — the FAB overlay: position, shape, sizes, colours, theming
  source, and its item list (add/edit/remove/reorder with installed-app search).
- **Menu** — the start menu: enabled, layout, position, alignment, gaps, and a
  *Follow hyprtk-bar* toggle that anchors the menu to the bar's edge + pill.
- **Modules** — show/hide each module, assign it to left / center / right, and
  reorder it within its section.
- **Reset layout** — restore the default arrangement.

The window is frameless and draggable by its header; `Esc` closes it.

---

## Notifications

hyprtk-bar ships its own notification daemon. It owns the
`org.freedesktop.Notifications` bus name and renders toasts above the bar,
right-aligned to the bar's edge.

- **Toasts** auto-dismiss after `default_timeout`; urgent notifications and
  ones with action buttons persist until acted on. Hovering pauses a toast.
- **Action buttons** invoke the notification's action and report it back to
  the sending app via `ActionInvoked`.
- **The center** (bell button) lists the history newest-first, with per-item
  action buttons, a dismiss button, and *Clear all*.
- Closing notifications emits `NotificationClosed` to the sending app.

Because the bar provides the daemon, do **not** run another notification
daemon (e.g. mako, swaync, xfce4-notifyd) at the same time — only one process
can own the bus name.

Send a test notification with:

```bash
notify-send -a "Test" -i dialog-information "Hello" "From hyprtk-bar"
```

---

## System tray

The tray implements the `org.kde.StatusNotifierWatcher` service and renders
registered StatusNotifier items as icons. It cooperates with other watchers:
if another process already owns the watcher name, the bar adopts its items
instead of fighting over it.

Tray items that export a `com.canonical.dbusmenu` menu get their menu rendered
natively in the bar — with icons, separators, check/radio toggles and nested
submenus — instead of asking the applet to draw its own popup. Activation and
menu events are forwarded back to the applet over D-Bus.

---

## Multi-monitor

`monitors` controls which monitors get a bar:

```json
"monitors": "primary",              // default: only the primary monitor
"monitors": "all",                  // one bar on every monitor
"monitors": ["DP-1", "HDMI-A-1"]    // only these monitors (names or models)
```

Each bar shows the active workspace **for its own monitor**, and popups,
toasts and tray menus are clamped to the bar's monitor — not the whole screen.
Only the primary bar hosts the tray and the notification daemon, so there is a
single SNI watcher and a single notifications bus owner.

---

## Troubleshooting

- **Bar does not appear after login** — confirm `hyprtk-bar` is on `PATH`
  (`~/.local/bin`) and that autostart ran. Check the bar's log:
  `hyprtk-bar --verbose` from a terminal, or the session journal.
- **"another hyprtk-bar is already running"** — a second instance exits by
  design. Restart the running one:
  `pkill -f "python3 -m hyprtk_bar" && hyprtk-bar &`
- **Notifications don't show** — another daemon (mako/swaync/xfce4-notifyd) may
  hold `org.freedesktop.Notifications`. Stop it and restart the bar.
- **Tray icons missing** — some applets only register after a host announces
  itself. `tray.reset_nm_applet` restarts `nm-applet` on startup; restart other
  applets the same way if needed.
- **Wrong monitor** — with `monitors: "all"` or a name list, make sure the
  names match your `hyprctl monitors` output (connector names like `DP-1` or
  model names).

---

## Project layout

```
src/hyprtk_bar/
├── __main__.py        entry point (single-instance lock, per-monitor windows)
├── app.py             layer-shell window, Hyprland IPC wiring, monitor selection
├── bar.py             the bar itself: sections, modules, menu actions
├── bar_settings.py    the settings window
├── config.py          config loading / validation / defaults
├── colors.py          shared colour parsing / contrast / blending helpers
├── theme.py           palette resolution + GTK CSS generation
├── theme_import.py    imported-theme parsing (former waybar_theme.py)
├── arcmenu.py         the arc menu overlay (FAB + fan-out items)
├── menu/              the in-bar start menu (hyprtk-menu merged in)
│   ├── menu_window.py layer-shell start menu (layouts, power bar)
│   ├── apps.py        .desktop scan, categories, search, launch
│   ├── theme.py       menu CSS assembly (pywal + bar palette)
│   └── config.py      menu config block read/write (in the bar config)
├── ipc.py             hyprctl queries + Hyprland event socket
├── layout.py          left/center/right section boxes
├── popup.py           layer-shell popups (calendar, previews, panels)
├── dbusmenu.py        com.canonical.dbusmenu client
├── notifications.py   notification daemon, toasts, notification center
├── tray.py            StatusNotifier tray + watcher
├── tasklist.py        pinned + running app buttons with previews
├── workspaces.py      workspace chips
├── sysmon.py          CPU / RAM / disk monitoring
├── clock.py           clock widget + calendar popup
└── quicksettings.py   quick-settings flyout
```

---

## License

GPL-2.0 — see [LICENSE](LICENSE).
