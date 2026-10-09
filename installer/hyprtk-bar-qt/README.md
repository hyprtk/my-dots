# hyprtk-bar-qt

The hyprtk taskbar, rewritten on Qt. **QML presentation + Python/IPC logic**,
built on [Quickshell](https://quickshell.org/) (a QtQuick toolkit that provides
Wayland layer-shell surfaces, Hyprland IPC, SNI tray, MPRIS, PipeWire and more).

This is the Qt counterpart to the GTK4 `hyprtk-bar`. It exists because
PySide6/QtWidgets has **no supported layer-shell binding for Python** — the
supported route for a Wayland bar is QML — so the shell is QML and any logic
that is awkward in QML lives in a toolkit-free Python backend.

See `../hyprtk-bar/QT-MIGRATION.md` for the full assessment and rationale.

## Architecture

```
shell.qml                     Quickshell entry — bar per screen + surfaces
bar/
  Bar.qml                     the frosted panel + module row
  modules/
    Workspaces.qml            Hyprland workspaces (Quickshell.Hyprland), click to switch
    Tasklist.qml              open windows (Toplevel): activate / middle-click close
    Tray.qml                  system tray (SystemTray / SNI)
    Clock.qml                 Quickshell SystemClock (format from Config)
    SysMonitor.qml            CPU/mem % + rolling sparklines (shared SysData)
    Net.qml                   rx/tx rates + rolling sparklines
surface/
  QuickSettings.qml           volume/brightness/Wi-Fi/Bluetooth flyout (wpctl, brightnessctl, nmcli, bluetoothctl)
  Settings.qml                settings panel (centred layer-shell; edits the Qt bar's own config)
  ArcMenu.qml                 corner FAB with an item arc; IPC-toggleable
  SysMonitor.qml              Mission Center-style system monitor dialog (CPU/Mem/Disks/Network/GPU/Apps)
  NotificationCenter.qml      notification history panel (bell)
  Notifications.qml           transient toast stack (opt-in daemon, see below)
  Clipboard.qml               cliphist history (search/copy/delete/wipe)
  Themer.qml                  theming panel (centred layer-shell; Wallpaper grid, bar themes, import)
  About.qml                   about panel (centred layer-shell; bar menu → About)
  DesktopWidgets.qml          instantiates the enabled desktop widgets
  StartMenu.qml               start menu (whisker/win7/win11/plasma, favourites, recents)
theme/
  Theme.qml                   singleton: live pywal + Qt config colours
  qmldir
config/
  Config.qml                  singleton: own settings (~/.config/hyprtk-bar-qt/config.json)
state/
  UiState.qml                 singleton: which surface is open
data/
  SysData.qml                 singleton: runs the backend once, exposes cpu/mem/net + histories
  MonitorData.qml             singleton: runs the rich monitor backend while the dialog is open
  NotifyData.qml              singleton: notification daemon + history + unread count
  Widgets.qml                 singleton: desktop-widget config (Qt config block)
  WidgetData.qml              singleton: telemetry for the sampled desktop widgets
  WidgetLayout.qml            singleton: snap-group layout overrides
  WidgetMove.qml              singleton: cursor-polling widget move mode
  MenuConfig.qml              singleton: start-menu config (Qt config block)
  BarConfig.qml               singleton: module/font/animation/monitors config (Qt config)
surface/widgets/
  WidgetFrame.qml             desktop-widget base (placement, pill, pywal theming)
  ClockWidget.qml             digital / text clock
  ResourcesWidget.qml         CPU graph + RAM/swap bars + temp/load
  DiskWidget.qml              per-drive usage + I/O rates
  NetworkWidget.qml           interface / IP / rates + download graph
  WeatherWidget.qml           current conditions + daily forecast (Open-Meteo)
  SysInfoWidget.qml           host / OS / kernel / CPU / GPU / memory / disks
  VisualizerWidget.qml        cava audio bars / wave / mirror / dots / glow
components/
  TButton.qml / TTextField.qml / TComboBox.qml / TCheckBox.qml / TSpinBox.qml / TSlider.qml
                              themed QtQuick Controls (replace the default look)
  Toggle.qml                  pill toggle
  Sparkline.qml               Canvas line + gradient-area graph
backend/
  hyprtk_bar_qt/
    paths.py                  config paths (Qt vs GTK) + first-run seed
    config.py                 pywal palette reader (live colours)
    sysmon.py                 /proc sampler (cpu/mem/net), streams JSON lines on stdout
    monitor.py                rich system-monitor sampler (cpu/mem/disk/net/gpu/apps), streams JSON lines
    monitor_data.py           toolkit-free readers (cpu cores/temps, mem, disk, net, gpu, drives, dimms, procs)
    proc_action.py            one-shot kill/launch helper for the Apps page
    dimm.py                   one-shot DIMM-slot reader (SMBIOS/dmidecode)
    clipboard.py              cliphist wrapper (list/copy/delete/wipe)
    theme_import.py           waybar-CSS decoder -> palette (ported, toolkit-free)
    themes.py                 list/parse/import/remove the bar themes for the themer
    wallpapers.py             scan a wallpaper folder + apply one (pywal regen)
    weather.py                Open-Meteo weather (geocode + forecast, cached)
    sysinfo.py                host/OS/kernel/CPU/GPU/memory/disks snapshot
    visualizer.py             cava audio levels (synthetic fallback), JSON lines
    menu.py                   start-menu favourites/recents (Qt config)
    matuwall.py               matuwall config.toml read/write (themer page)
    files.py                  directory listing for the plasma file browser
    barsettings.py            Qt bar config editor (settings window)
    widgets_layout.py         desktop-widget snap-group layout + position save
    widget_move.py            desktop-widget move FIFO (start/stop)
tests/
  test_sysmon.py              backend unit tests
  test_monitor.py             monitor backend unit tests
bin/hyprtk-bar-qt             launcher wrapper (qs -p <root>)
bin/hyprtk-bar-qt-arc-toggle  hotkey helper (qs ipc call arcmenu toggle)
bin/hyprtk-bar-qt-settings-toggle  hotkey helper (qs ipc call settings toggle)
bin/hyprtk-bar-qt-themer-toggle    hotkey helper (qs ipc call themer toggle)
bin/hyprtk-bar-qt-widget-move  desktop-widget move start/stop (Hyprland bind)
Makefile                      make test / run / install
install.sh                    copy into the Quickshell config dir
```

Singletons avoid QtQuick name clashes: the theme is `Theme` (not `Palette`) and
UI state is `UiState` (not `State`).

**The split:** QML renders; Python computes. Backend modules never import
Qt/PySide, so they are unit-testable headlessly. QML drives them with
Quickshell `Process` (JSON lines on stdout) and Quickshell `IpcHandler` for
the reverse direction.

## Requirements

- Quickshell (`quickshell` / `qs`) — Arch `extra`, Debian, NixOS
- Qt 6 (QtQuick, QtQuick.Layouts) — pulled in by Quickshell
- Python 3.10+ (backend only; no third-party deps)

No PySide6 required: the shell runs inside Quickshell's own Qt.

## Run

```sh
./bin/hyprtk-bar-qt          # from the repo
qs -p /path/to/hyprtk-bar-qt # explicitly
```

Install into the Quickshell config dir:

```sh
./install.sh                 # -> ~/.config/quickshell/hyprtk-bar-qt
hyprtk-bar-qt                # launcher on ~/.local/bin
# or: qs -c hyprtk-bar-qt
```

## Status

Working bar: workspaces, tasklist, tray, clock, CPU/memory sparklines and a
network-rate graph (all fed by the Python backend), plus a quick-settings
flyout, a settings panel, a corner arc menu and a Mission Center-style system
monitor dialog (CPU / Memory / Disks / Network / GPU / Apps, opened from the
sysmon module), a notification center (bell + history panel), cliphist
clipboard history, and free-floating desktop widgets (clock / resources / disk /
network) driven by the Qt bar's own `widgets` config. Theming reads the live
pywal palette and the Qt config's `theme` block, so it matches the desktop while
the GTK bar still runs alongside it with its own separate config.

`make test` runs the toolkit-free backend unit tests. The arc menu, clipboard,
settings and themer panels can be bound to hotkeys with
`hyprtk-bar-qt-arc-toggle`, `hyprtk-bar-qt-clipboard-toggle`,
`hyprtk-bar-qt-settings-toggle` and `hyprtk-bar-qt-themer-toggle` (each calls
`qs ipc call <target> toggle`).

Desktop widgets can be dragged with Super + Shift + left mouse once these
Hyprland binds are set (the bar watches its own move FIFO):

```
bind  = SUPER SHIFT, mouse:272, exec, hyprtk-bar-qt-widget-move start
bindr = SUPER SHIFT, mouse:272, exec, hyprtk-bar-qt-widget-move stop
```

Notifications (the `org.freedesktop.Notifications` daemon + toasts) are
**enabled by default**; only one process can own that bus name, so the bar kills
any competing daemon (dunst/mako/swaync/xfce4-notifyd) before registering. Opt
out with:

```sh
HYPRTK_BAR_QT_NOTIFICATIONS=0 hyprtk-bar-qt
```

(also settable via `notifications.enabled=false` in the Qt config).

Roadmap (see `CHANGELOG.md`): arc menu, graph widgets, per-display desktop
widgets, MPRIS media control, and theming to full visual parity.
