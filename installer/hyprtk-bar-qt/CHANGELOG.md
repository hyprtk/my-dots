# Changelog

## 0.40.0 — unreleased

Bar opacity ↔ widgets linking.

- The Theme Manager "Bar opacity" slider now steps in **5% increments**
  (stepSize 0.05).
- Changing the bar opacity now **syncs every desktop widget's opacity** to match
  (Themer and Settings sliders; via `widgets_layout.py set-opacity`).
- Widget colours now follow the bar's **resolved** theme
  (background/foreground/accent — manual, imported or pywal) instead of reading
  pywal directly, so switching the bar theme repaints the widgets too. A
  per-widget colour override still wins.

## 0.39.0 — unreleased

Theme Manager import browse + arc menu interactions.

- **Theme Manager → Import**: added a **Browse…** button that opens a rofi
  folder picker (`backend/.../pickdir.py`) and fills the path field.
- **Arc menu**:
  - The FAB now **left-clicks to open/close the items** (fan in/out) and
    **middle-clicks to close** the menu, instead of any click closing it.
  - Respects `arcmenu.enabled` (it drives `visible`).
- **Keybind helpers** (`hyprtk-bar-qt-*-toggle`) now target the **running**
  instance (they resolve the live root via `pgrep`), so hotkeys work whether the
  bar runs from the installed dir or a dev checkout — previously they always
  addressed the installed copy and missed the running bar.

## 0.38.0 — unreleased

- Fixed the bar right-click menu opening shifted left: `barMenuX` is the cursor
  x relative to the bar window, but the menu is anchored to the screen, so the
  bar's left inset is now added (and the menu is clamped on-screen). It opens
  right under the cursor.
- Settings & Themer: the animated accent border is now drawn **on top** of the
  sidebar + content instead of behind them, so it reads the same on every edge
  (the sidebar used to cover the left/top-left/bottom-left) and animates all
  around.

## 0.37.0 — unreleased

About dialog, settings toggles, and the Modules/Widgets pages.

- Removed all GTK references from the About box.
- Added live version readouts: **hyprtk-bar-qt** (from `__init__.__version__`),
  **Qt** (`qmake6 -query QT_VERSION`) and **Quickshell** (`qs --version`).
- Settings toggles now render as traditional radio buttons (ring + inner dot)
  instead of a square tick box; the check glyph (which fell back to a broken
  `8`) is gone.
- **Modules** and **Widgets** pages rebuilt as clean accordion cards: one card
  per module/widget with a readable name, its Enabled/On toggle, placement and
  reorder controls on the header row, and a chevron that reveals its options
  (grouped as Placement / Colours / Options) — instead of a dense list followed
  by a disconnected wall of controls.

## 0.36.0 — unreleased

Wallpaper thumbnails are cached — the Theme Manager opens with every thumbnail
visible instantly.

- **Thumbnail cache** in the Qt bar's own tree (`~/.cache/hyprtk-bar-qt/thumbs/`):
  `wallpapers.py scan` now returns `{path, thumb}` items and generates missing
  thumbnails (PIL, falling back to ImageMagick/vips). The Wallpaper grid no
  longer decodes full-resolution images (up to ~30s for a large folder).
- **Pre-built on install**: `install.sh` runs `wallpapers.py build-thumbs` for
  the configured wallpaper folder, so thumbnails are ready on first open.
- The `wallpaper` quicklink is renamed to **Theme Manager** (it opens the
  themer); `install.sh` migrates the label.

## 0.35.0 — unreleased

**Fully separated from the GTK `hyprtk-bar`.** The Qt bar now owns its own
scripts, themes, caches and runtime channels instead of reaching into the GTK
bar's tree.

- **Own runtime tree**: scripts + rofi config are vendored into the repo
  (`scripts/`) and installed to `~/.local/share/hyprtk-bar-qt/scripts/`
  (`appsmenu.sh`, `change-icons.sh`, `wallpaper-colors.sh`, `updatewal-awww.sh`,
  `updates.sh`, `installupdates.sh`, `sync-rofi-theme.sh`, `wal-watcher.sh`,
  `rofi/`, …). `Themer`, `Updates`, `icons`, `wallpapers` all point there.
- **Own themes/widget-themes**: the 9 bar themes and the clock widget themes are
  vendored (`themes/`, `assets/widgets/clock/`) and installed to
  `~/.config/hyprtk-bar-qt/{themes,widget-themes/clock}/`.
- **Own caches**: `~/.cache/hyprtk-bar-qt/` (`weather.json`, `dimm.json`,
  `gpu.json`, `cava-hyprtk.conf`).
- **Own runtime channels**: the widget-move FIFO is `hyprtk-bar-qt-widget-move.fifo`
  and the keybind lock is `hyprtk-bar-qt-<uid>.lock` (no longer shared with the
  GTK bar). New `startmenu` IPC + `hyprtk-bar-qt-menu-toggle` helper.
- **install.sh** lays down the scripts/themes/widget-themes and rewrites any
  `hyprtk-bar/scripts` command paths in the Qt config to the Qt tree.
- **Hyprland config** (`keybindings.lua` / `autostart.lua`) switched to bar-qt:
  Super+Space → `hyprtk-bar-qt-menu-toggle`, Super+D / Super+Ctrl+Return →
  `~/.local/share/hyprtk-bar-qt/scripts/appsmenu.sh`, Super+Shift+W → its
  `updatewal-awww.sh`, Super+Ctrl+C/M → the Qt clipboard/arc toggles,
  Super+Shift+LMB → `hyprtk-bar-qt-widget-move`, autostart launches
  `hyprtk-bar-qt`.
- The GTK config is still read **once** for first-run migration (`paths.py`),
  but nothing else crosses over.
- **Quicklink fix**: the `apps` quicklink now runs its configured command
  (`appsmenu.sh` → rofi drun) instead of opening the Qt start menu.

## 0.34.0 — unreleased

Optional extras and remaining parity polish (the non-blocking frontier from the
0.33.0 session).

- **Media (MPRIS) module** — new optional `media` bar module (`bar/modules/Media.qml`)
  built on Quickshell's MPRIS service: now-playing text plus previous / play-pause /
  next controls, a hover tooltip (title · artist · album) and right-click to raise
  the player. Hidden when no player is present. Config block `media`
  (`enabled` / `show_controls` / `show_text` / `max_length` / `text_width`) with a
  Modules-page editor; place it left/center/right like any other module. Note: the
  reference GTK bar has no media module — this is purely additive.
- **Snap groups: full GTK layout parity** — each member's content now scales to fill
  the uniform cell (`SNAP_SCALE_MIN/MAX` 0.4/2.0 × `SNAP_FIT_MARGIN` 0.97; consumed
  via `WidgetFrame.effScale`), and a dropped widget becomes the group anchor so it
  stays where released while the others reflow (mirrors GTK `_snap_anchor`). The
  inter-member gap is now `SNAP_GAP=10` (was 8) to match the GTK bar.
- **Weather forecast fits one row** — the forecast cells shrink (`forecastCellW`)
  to the widget's actual width so a snap cell shrunk to the usable area still shows
  the whole forecast in one row instead of wrapping.
- **Start-menu places** — added **Games** to the Win7 places and **Trash** /
  **Network** to the Plasma file-browser sidebar; URI places (`network:///`) open in
  the desktop file manager, local places browse in-menu.

## 0.33.0 — unreleased

Widget parity, drag-to-snap, and border widths.

- **Drag-to-snap**: dropping a widget next to another joins them into a snap
  group (`widgets_layout.snap`, `SNAP_DIST=28`, axis detection) and the group
  reflows to a uniform cell so the smaller widgets resize to the largest.
  `WidgetMove` now passes the on-screen rects so the nearest neighbour is
  chosen and members are ordered along the axis.
- **Snap cell sizing**: widgets register their **natural** (unconstrained)
  size, so the snap cell = the largest natural member instead of collapsing to
  the last constrained height (sysinfo is no longer squashed).
- **Border width**: new top-level `border_width` (default **2**) drives the bar,
  the dialogue panels and the desktop-widget borders. Added a "Border width
  (bar & panels)" spin on Settings → Bar. The bar keeps a 2px border even when
  the border animation is off.
- **Animated dialogue borders**: Settings / Themer / SysMonitor / Clipboard /
  Notification Center / Quick Settings / Start Menu / Bar Menu / About now draw
  a 2px border that cycles accent↔accent2 like the bar (new `data/Chrome.qml`,
  honouring `theme.border_animation` + the UI-animations switch and the real
  Hyprland animation speed).
- **Widget content parity with GTK**:
  - Weather: details read "Humidity X%" / "Wind X km/h", temp shows "13°", and
    the forecast is a horizontal day/icon/hi-lo row that **wraps** (and widens
    the widget) so a 7-day forecast is never clipped.
  - SysInfo: glyphs pinned to the Nerd Font (restores the Uptime clock glyph)
    and the widget sizes to its content so long CPU/GPU model names aren't cut.
  - Resources: label dim / value accent (was reversed); SysInfo/Network/Disk
    font sizes, weights and accent colours aligned to the GTK theme.

## 0.32.0 — unreleased

Desktop-widget fixes.

- **Drag now sticks**: `widgets_layout.set_position` clears the widget's
  `snap_group` when it is moved, so a dragged widget is detached from its snap
  group instead of snapping straight back (matches the GTK bar's `_detach`).
- **Drag keeps working after the first move**: `WidgetFrame` only re-registered
  its hit-test rect on width/height/`hasOver` changes, so after a move (which
  changes the margin) the rect went stale and the widget could no longer be
  grabbed. It now re-registers when the effective position changes too.
- **No more drop "boomerang"**: on release the move override was dropped
  immediately, so the widget snapped back to its old margin for a frame while
  the async save landed, then jumped to the new spot. The dropped position is
  now held (`WidgetMove.committed`) until the config reload confirms it.
- **Clock content centred**: the clock's time/date used `Layout.alignment:
  Qt.AlignHCenter`, which did not centre them; they now fill the column with
  `horizontalAlignment: Text.AlignHCenter`, so they sit centred in the widget.
- **Snap groups actually apply**: `data/WidgetLayout.qml` re-ran its backend
  with a stale (empty) config because the `Process` started before the config
  binding settled; it now reloads explicitly on config/size changes, and feeds
  the backend each widget's **measured** size so auto-height widgets no longer
  collapse onto each other (uniform cell = tallest member), scaled/clamped to
  fit the monitor.
- **Clock widget theming**: `ClockWidget` passed an empty override colour to
  `WidgetFrame`, which QML treats as opaque black — hence black-on-charcoal.
  Empty overrides now fall back to `transparent` like every other widget, so the
  clock uses the same pywal background/foreground/accent.

## 0.31.0 — unreleased

Separate config from the GTK bar.

- **Own config file**: the Qt bar now reads and writes
  `~/.config/hyprtk-bar-qt/config.json` exclusively (`data/BarConfig.qml`,
  `data/MenuConfig.qml`, `data/Widgets.qml`, `theme/Theme.qml`,
  `config/Config.qml`) instead of sharing `~/.config/hyprtk-bar/config.json`
  with the GTK bar, so the two can be configured independently.
- **First-run migration**: the launcher (`bin/hyprtk-bar-qt`) and `install.sh`
  build the Qt config from the GTK config (full bar schema), re-applying any
  Qt-only keys from an existing legacy Qt config, so an existing setup carries
  over before the two diverge (new `backend/.../paths.py`).
- **`Config.animations` → `Config.uiAnimations`**: the Qt-only "UI animations"
  toggle no longer clashes with the shared `animations` block (mode/speed) now
  that both live in one file.
- Backends repointed at the Qt config: `barsettings.py`, `menu.py`,
  `widgets_layout.py`, `hypr_animations.py`.

## 0.30.0 — unreleased

Themer parity + arc keybind.

- **Notifications on by default**: the `org.freedesktop.Notifications` daemon is
  now enabled automatically (competing daemons — dunst/mako/swaync/xfce4-notifyd
  — are killed so the bar owns the bus name); opt out with
  `HYPRTK_BAR_QT_NOTIFICATIONS=0` or `notifications.enabled=false`.
- **Themer — Wallpaper**: search, "Apply Selected" + "Random" buttons, selectable
  thumbnails (single-click selects, double-click applies), and a rescan that also
  refreshes the current-wallpaper preview.
- **Themer — Pywal**: 16-colour palette grid (was 7), click-to-inspect, special
  background/foreground swatches, wal dir + re-run + refresh, and the saved
  colour-scheme list from `~/.cache/wal/schemes` (click to apply).
- **Themer — Bar Themes**: 16-colour palette swatches (was 7).
- **Themer — Lock Screen**: lists every setting from the active lock config
  (swaylock or hyprlock) with editable values + colour swatches, plus re-apply.
- **Themer — Icons**: current folder colour + preview row, the 25 Papirus preset
  grid (with folder SVGs), custom hex, and the pywal auto-match button.
- **System monitor**: glyphs pinned to the Nerd Font family (were rendering via
  fallback); new `sysmon` IPC handler.
- **Arc menu**: `signal_bridge.py` handles the dotfiles' `Super+Ctrl+M` keybind
  (SIGUSR2 to the lock-file PID) to the Qt bar, so it opens without a Qt-specific
  bind.
- New toolkit-free backends: `pywal.py`, `icons.py`, `lock.py`, `signal_bridge.py`
  (+ tests).

## 0.29.1 — unreleased

Desktop-widget move fixed.

- `backend/.../widget_move.py` now watches the **shared** control FIFO
  (`hyprtk-bar-widget-move.fifo`), so the existing `Super + Shift + left mouse`
  bind (which calls `hyprtk-bar-widget-move.sh`) drives the Qt bar too —
  previously the bind reached only the GTK bar and, with no reader, the write
  blocked. Also arms `PR_SET_PDEATHSIG` so a killed bar no longer leaves
  orphaned FIFO readers (which raced over the command).
- `bin/hyprtk-bar-qt-widget-move`: writes to the shared FIFO and opens it
  read-write so it never blocks when no bar is running.

## 0.29.0 — unreleased

Bar icons standardised on Nerd Font glyphs.

- **All bar glyphs pinned to a Nerd Font family** (`BarConfig.glyphFont`,
  default `Symbols Nerd Font`, overridable via `quicklinks.glyph_font`) instead
  of relying on per-codepoint font fallback — which rendered some glyphs wrong
  or blank (e.g. the start button).
- **Text/unicode symbols → glyphs** (matching the GTK bar): start button now
  reads the shared `center.start_glyph` (`\uf015`), quick settings `\uf013`,
  sysmon `\uf2db`/`\uefc5`, kbstate `\uf023`/`\uf11c`, updates `\uf0ab`,
  net `\uf063`/`\uf062`, arc button `\uf0e7`.
- **System tray** draws a per-item glyph chosen from the SNI id/icon/title
  (e.g. nm-applet's wired vs wireless icon → ethernet vs Wi-Fi glyph, blueman →
  bluetooth glyph, dimmed when disabled) instead of the app-provided pixmap.

## 0.28.0 — unreleased

Dialogue polish: floating panels.

- **Settings / Themer / About** converted from `FloatingWindow` (xdg toplevels,
  which Hyprland tiles) to centred layer-shell `PanelWindow`s, so they float
  over the desktop like the bar's other panels (own rounded background + border,
  same reveal animation). Sidebars round their left corners to match.
- **IPC toggles**: `settings`, `themer` and `about` surfaces gain `IpcHandler`s
  (`toggle`/`open`/`close`), matching `clipboard`/`arcmenu`; new
  `bin/hyprtk-bar-qt-settings-toggle` and `bin/hyprtk-bar-qt-themer-toggle`.

## 0.27.0 — unreleased

Dialogue parity round 2.

- **Animated bar border**: `Bar.qml` animates its border colour when
  `theme.border_animation` is on, at the `animations` mode/speed (low/high/
  custom) — matching the GTK bar.
- **Quick Settings**: adds the microphone slider + mute (wpctl
  `@DEFAULT_AUDIO_SOURCE@`) alongside volume/brightness/Wi-Fi/Bluetooth.
- **Bar menu**: adds "About hyprtk-bar" and a themed `surface/About.qml`.

## 0.26.0 — unreleased

Look-and-feel parity with the GTK bar.

- **Themed controls**: `components/TButton|TTextField|TComboBox|TCheckBox|
  TSpinBox|TSlider` replace the raw QtQuick Controls (no more default white
  boxes/buttons); swapped in across every dialog.
- **Shared bar geometry/layout**: `shell.qml`, `Bar.qml` and the overlay margins
  (sysmon/clipboard/notification center/bar menu) now read the shared top-level
  config (`position`/`height`/`gap_in`/`gap_out`/`radius`/`opacity`/`width`/
  `align`) and the shared `layout` block — the Qt bar now renders at the same
  2880×38 / 75% / centred geometry as the GTK bar.
- **Shared quicklinks**: `Quicklinks.qml` reads the shared `quicklinks.links`
  (icon/command/command_right/command_middle + `icon_size`), with id-based
  surface actions (apps/cliphist/wallpaper).
- **Settings rewritten** to edit `~/.config/hyprtk-bar/config.json` via
  `backend/.../barsettings.py` (debounced atomic patches): full Bar / Themes /
  Fonts / Animations / Arc Menu / Menu / Quicklinks / Modules / Widgets pages.
- Tests: `tests/test_barsettings.py`.

## 0.25.0 — unreleased

Parity pass 22: desktop-widget drag (move mode).

- `backend/.../widget_move.py`: a FIFO streamer (`hyprtk-bar-qt-widget-move.fifo`)
  that relays `start` / `stop` from a Hyprland bind.
- `data/WidgetMove.qml`: while moving, polls `hyprctl cursorpos` and offsets the
  widget under the cursor; on release persists its free `margin_x/y` via
  `widgets_layout.py set`. `WidgetFrame` registers its rect and applies the
  move override (move > snap > config).
- `bin/hyprtk-bar-qt-widget-move`: writes start/stop to the FIFO (bind Super +
  Shift + left mouse press/release).
- Tests: `widgets_layout.set_position`.

## 0.24.0 — unreleased

Parity pass 21: desktop-widget snap groups.

- `backend/.../widgets_layout.py`: lays out widgets sharing a `snap_group` along
  `snap_axis`, ordered by `snap_order`, in a uniform cell.
- `data/WidgetLayout.qml` + `WidgetFrame` read the override per widget id, so a
  configured snap group is positioned and sized together.

## 0.23.0 — unreleased

Parity pass 20: per-module `enabled` flags.

- Modules honour the shared `enabled` key from their config block (workspaces,
  clock, sysmon, updates, window, tray, quicksettings, notifications, themer,
  quicklinks, arcmenu): a disabled module is hidden.
- `notifications.enabled` also gates the daemon.

## 0.22.0 — unreleased

Parity pass 19: live surface animations.

- Overlays (quick settings, system monitor, notification center, clipboard,
  start menu, bar menu, settings, themer) fade + slide in on open, gated by the
  `animations` switch and `animationDuration`.

## 0.21.0 — unreleased

Parity pass 18: arc-menu config + animation.

- `surface/ArcMenu.qml` reads the shared `arcmenu` block: position, radius,
  fab/item size, margin, colours (`use_pywal` / fab_color / item_color),
  `animation_time` (gated by the `animations` mode) via animated fan
  transitions, `close_on_click`, items, and `enabled`.
- `ArcButton` hides when `arcmenu.enabled` is false.

## 0.20.0 — unreleased

Parity pass 17: Plasma in-menu file browser.

- `surface/StartMenu.qml`: the plasma layout gains Applications / Computer /
  Recently Used tabs; Computer is an in-menu file browser (places sidebar,
  back/up/path nav, directory listing, click to enter folders or open files).
- `backend/.../files.py`: directory listing (dirs first, hidden skipped).
- Tests: `tests/test_files.py`.

## 0.19.0 — unreleased

Parity pass 16: small config/placement completions.

- Desktop widgets: a usable-area clamp keeps every widget clear of the bar
  (whichever edge it is on).
- `notifications` config (`max_stored`, `default_timeout`) is honoured by the
  center + toasts.
- `font` family/size now also applied to the tasklist, kbstate and quicklinks
  modules; `BarConfig` exposes the `notifications` / `arcmenu` blocks.

## 0.18.0 — unreleased

Parity pass 15: in-bar Matuwall TOML editor (themer complete).

- `surface/Themer.qml`: the Matuwall page is now a full form (every schema
  section: general/window/input/animation/grid/thumbnail/colors/backends/hooks)
  with bool/int/str/choice/list controls and Save.
- `backend/.../matuwall.py`: reads/parses `~/.config/matuwall/config.toml`,
  writes through the pywal symlink and rewrites existing template key lines
  (preserving comments, skipping pywal-rendered colour keys). Ported from the
  GTK themer.
- Tests: `tests/test_matuwall.py`.

## 0.17.0 — unreleased

Parity pass 14: shared bar config (module options, font, monitors).

- `data/BarConfig.qml`: reads the shared hyprtk-bar config blocks.
- `shell.qml`: the `monitors` selector (`primary` / `all` / `[connector, …]`)
  now controls which screens show the bar.
- `workspaces` (show_empty, max), `clock` (strftime `format`), `updates`
  (interval + scripts), `window` (max_length/width) and `tray` (icon_size)
  options are honoured; `font` family/size applied to the clock, workspaces,
  active-window, net, updates, sysmon and tray modules.

## 0.16.0 — unreleased

Parity pass 13: start-menu categories + places.

- `surface/StartMenu.qml`: the whisker sidebar now lists the app categories
  (Accessories / Development / … from the XDG categories), and the win7 layout
  gains a Places panel (Documents / Pictures / Music / Videos / Computer).

## 0.15.0 — unreleased

Parity pass 12: start-menu layouts + favourites/recents.

- `surface/StartMenu.qml`: layout variants (whisker / win7 / win11 / plasma),
  a whisker sidebar (All / Favorites / Recently Used) + recent panel, an app
  list or grid per layout, favourite toggles, and a power footer.
- `data/MenuConfig.qml`: reads the shared hyprtk-bar `menu` block.
- `backend/.../menu.py`: favourites/recents store (atomic writes into the shared
  config) — `record` / `favorite` / `unfavorite` / `get`.
- Tests: `tests/test_menu.py`.

## 0.14.0 — unreleased

Parity pass 11: visualizer + clock dials (desktop widgets complete).

- `surface/widgets/VisualizerWidget.qml` + `backend/.../visualizer.py`: cava
  raw-ascii levels streamed as JSON (synthetic fallback when cava is absent),
  drawn on a Canvas as bars / wave / mirror / dots / glow with accent / pywal /
  gradient / custom colours.
- `surface/widgets/ClockWidget.qml`: `dials` style — a Canvas analog face
  (ticks + hour/minute/second hands) alongside the existing digital/text.
- All seven desktop widgets now have a Qt implementation; only drag / snap /
  usable-area placement remains.

## 0.13.0 — unreleased

Parity pass 10: weather + sysinfo desktop widgets.

- `surface/widgets/WeatherWidget.qml` + `backend/.../weather.py`: Open-Meteo
  geocode + current/daily forecast (keyless), cached to
  `~/.cache/hyprtk-bar/weather.json`; renders icon/condition/feels/humidity/wind
  and a daily forecast with WMO/Nerd-Font-Weather-Icons mapping.
- `surface/widgets/SysInfoWidget.qml` + `backend/.../sysinfo.py`: host, OS,
  kernel, uptime, CPU, GPU, memory and disk summary.
- Tests: `tests/test_widgets.py` (weather codes/cache, sysinfo shape).

## 0.12.0 — unreleased

Parity pass 9: desktop widgets (framework + four widgets).

- `data/Widgets.qml`: reads the shared hyprtk-bar `widgets` config block.
- `data/WidgetData.qml`: runs the monitor backend only while a sampled widget is
  on, exposing sample + histories.
- `surface/widgets/WidgetFrame.qml`: layer-shell base — 9-way / `free` placement,
  size, opacity, radius, padding and pywal theming (`transparent` master switch).
- Widgets: **clock** (digital/text), **resources** (CPU graph, RAM/swap bars,
  temp/load), **disk** (per-drive bars + I/O rates), **network** (iface/IP/rates
  + download graph). Weather/visualizer/sysinfo are a later pass.
- `surface/DesktopWidgets.qml` instantiates the enabled widgets.

## 0.11.0 — unreleased

Parity pass 8 (theming, part 3): the remaining Themer pages.

- `surface/Themer.qml` now has all nine pages: **Pywal** (live swatches +
  regenerate), **Rofi** (variant list, apply via symlink + `sync-rofi-theme.sh`,
  regenerate), **Lock Screen** (re-apply pywal + current `hyprlock-colors.conf`),
  **Icons** (papirus pywal colour match + custom hex), **SDDM & GRUB**
  (pkexec `update.sh` with wallpaper preview) and **Matuwall** (opens its
  config; in-bar TOML editor deferred).

## 0.10.0 — unreleased

Parity pass 7 (theming, part 2): Wallpaper picker + theme import.

- `surface/Themer.qml`: restructured into a sidebar of pages.
  - **Wallpaper**: current-wallpaper preview + a thumbnail grid of the folder;
    click applies via the hyprtk wallpaper script (regenerates pywal).
  - **Bar Themes**: the 9 shipped themes (unchanged picker).
  - **Import**: importable waybar themes from disk (name + path) and an
    imported-themes list with remove.
- `backend/hyprtk_bar_qt/wallpapers.py`: scan a folder for images, report the
  current wallpaper, apply one (runs `wallpaper-colors.sh`).
- `backend/hyprtk_bar_qt/themes.py`: `installed` / `import` / `remove`
  subcommands.
- `Config`: `wallpaperDir`.
- Tests: `tests/test_wallpapers.py`, import/remove coverage in `test_themes.py`.

## 0.9.0 — unreleased

Parity pass 6 (theming, part 1): shipped bar themes.

- `backend/hyprtk_bar_qt/theme_import.py`: ported the toolkit-free waybar-CSS
  decoder (resolve `@import`/`@define-color`, derive
  background/foreground/accent/etc.).
- `backend/hyprtk_bar_qt/themes.py`: CLI over `theme_import` — `list` returns
  the installed themes with hexified swatches, `palette <name>` one theme.
- `backend/hyprtk_bar_qt/config.py`: `PYWAL_PATH` + `load_pywal_colors`.
- `surface/Themer.qml`: a "Bar themes" picker (name + swatches) writes Theme
  overrides; "Follow hyprtk-bar / pywal" clears them.
- Tests: `tests/test_themes.py`.

## 0.8.0 — unreleased

Parity pass 5: clipboard history + tray context menu.

- `surface/Clipboard.qml`: in-bar clipboard history (cliphist) — search, click to
  copy (text/image), per-row delete, two-step "Clear all", Esc to close. Toggle
  from the clipboard quicklink or `qs ipc call clipboard toggle`
  (`bin/hyprtk-bar-qt-clipboard-toggle`).
- `backend/hyprtk_bar_qt/clipboard.py`: toolkit-free cliphist wrapper
  (list/copy/delete/wipe) with a testable `parse_list`.
- `bar/modules/Tray.qml`: right-click now opens the item's DBusMenu via
  `QsMenuAnchor` (items with `onlyMenu` open it on left-click too).
- `bar/modules/Quicklinks.qml`: quicklinks can carry a built-in `action`
  (`clipboard` / `themer` / `settings`) instead of a command; defaults now
  include Wallpaper and Clipboard.

## 0.7.0 — unreleased

Parity pass 4: notification center.

- `data/NotifyData.qml`: singleton owning the notification daemon (gated behind
  `HYPRTK_BAR_QT_NOTIFICATIONS=1`), the tracked history, arrival timestamps, the
  unread count and the transient toast queue.
- `surface/NotificationCenter.qml`: Win11-style history panel — newest first,
  per-row dismiss + actions, "Clear all", relative time, unread badge reset on
  open.
- `bar/modules/NotificationsButton.qml`: bell with a numbered unread badge;
  registered in the default right layout and the Settings module list.
- `surface/Notifications.qml`: reworked to render only the transient toasts from
  `NotifyData` (history outlives the toast).

## 0.6.0 — unreleased

Parity pass 3: Mission Center-style system monitor dialog.

- `surface/SysMonitor.qml`: layer-shell panel floated above the bar, opened by
  left-clicking the sysmon module. Sidebar (CPU / Memory / Disks / Network /
  GPU / Apps) + `StackLayout`, live QML graphs (`Sparkline`), stat readouts, a
  per-core bar grid, a clickable drive grid, a network-interface list and an
  Apps page (user/system apps + processes, Launch / Kill / Force kill with a
  confirm dialog). Page set follows `Config.sysmonPages`; graph colours follow
  the live pywal palette.
- `backend/hyprtk_bar_qt/monitor.py`: streams a full JSON sample per interval
  (selected pages only) — a `MonitorSampler` over the ported readers. The
  process walk is gated on `--active apps` so it only runs while the Apps page
  is on screen.
- `backend/hyprtk_bar_qt/proc_action.py`: one-shot `kill` / `launch` helper the
  Apps page buttons invoke (reuses `monitor_data.kill_process`/`launch_process`).
- Memory Slots section on the Memory page: DIMM cards (populated/size/locator)
  from SMBIOS, read from the cache on first open and refreshed on demand via
  `backend/hyprtk_bar_qt/dimm.py` (may prompt once through pkexec).
- `backend/hyprtk_bar_qt/monitor_data.py`: ported the GTK bar's toolkit-free
  readers (CPU cores/load/temps, memory, disk I/O, network interfaces, GPU across
  AMD/NVIDIA/Intel, drives via lsblk, processes, DIMMs). Shares the
  `~/.cache/hyprtk-bar` caches with the GTK bar.
- `data/MonitorData.qml`: singleton that runs the backend only while the dialog
  is open and exposes the latest sample + rolling histories.
- `Config`: `sysmonMonitor`, `sysmonInterval`, `sysmonDataPoints`,
  `sysmonDiskPath`, `sysmonNetworkIface`, `sysmonPages`.
- `Theme.walColor(n, fallback)` helper for arbitrary pywal palette indices.
- Tests: `tests/test_monitor.py`.

## 0.5.0 — unreleased

Parity pass 2: data-driven layout, full settings window, config writer.

- **Data-driven bar layout**: `Config.layoutLeft/Center/Right` hold module names;
  `Bar.qml` renders them via a `DelegateChooser` registry. `shell.qml` honours
  `barPosition`, `barHeight`, `gapOut`, `radius`, `barWidth` (px or %) and
  `barAlign`, computing layer-shell margins per screen.
- **Settings window**: nine pages (Bar / Themes / Fonts / Animations / Arc Menu /
  Menu / Quicklinks / Modules / Widgets) with a sidebar + StackLayout.
- **Config writer**: `Config` now persists ~30 keys generically (`_keys`
  load/save); geometry, layout, theme overrides, fonts, animations, quicklinks,
  menu, arc menu, power.
- **Theme overrides**: `Config.themeBackground/Foreground/Accent/themeName/source`
  take precedence over the hyprtk-bar config, then pywal.
- New `Quicklinks` module + `BarIconButton` component; button modules
  (`StartButton`/`ThemerButton`/`SettingsButton`/`ArcButton`/`QuickSettingsButton`)
  registered in the layout.

## 0.4.0 — unreleased

Parity pass 1: bar menu, start menu, themer, more modules.

- `surface/BarMenu.qml`: right-click the bar → Start Menu / Settings / Themer /
  Quick Settings / Arc Menu / Reload / Lock.
- `surface/StartMenu.qml`: searchable app grid (`DesktopEntries` + icon lookup),
  Settings/Themer shortcuts, power footer (lock/suspend/logout/reboot/shutdown).
- `surface/Themer.qml` v1: live palette swatches, bar-opacity override,
  regenerate-palette / save / close.
- Modules: `ActiveWindow.qml` (focused title), `KbState.qml` (Caps/Num LEDs via
  new `backend/.../kbleds.py`), `Updates.qml` (pending-update count).
- `Config`: opacity override, `showWindow`/`showUpdates`/`showKbState`,
  `menuPower`. `UiState`: `startMenuOpen`/`themerOpen`/`barMenuOpen`/`barMenuX`.
- Bar: start button (left) + Themer/Settings/Arc/Quick-Settings buttons (right).
- `PARITY.md`: full like-for-like matrix vs `hyprtk-bar`.

## 0.3.0 — unreleased

Graph widgets + arc menu.

- `components/Sparkline.qml`: Canvas line + gradient-area graph.
- `data/SysData.qml`: shared singleton running the backend once, exposing
  cpu/mem/net + rolling histories.
- `Net` module (rx/tx rates + sparklines) and `SysMonitor` now shows CPU/mem
  sparklines; backend `sysmon.py` extended with network byte rates.
- `surface/ArcMenu.qml`: corner FAB with items fanned along an arc
  (position/items from `Config`), toggleable via `qs ipc call arcmenu toggle`
  (`bin/hyprtk-bar-qt-arc-toggle`).
- `Config` gained `arcMenuPosition` / `arcMenuItems`; `UiState` gained
  `arcMenuOpen`.
- Added `tests/test_sysmon.py` + `Makefile` (`make test`).

## 0.2.0 — unreleased

Modules and surfaces.

- Modules: `Tasklist` (open windows — activate / middle-click close), `Tray`
  (SNI system tray), plus the existing `Workspaces`, `Clock`, `SysMonitor`.
- `surface/QuickSettings.qml`: volume (wpctl), brightness (brightnessctl),
  Wi-Fi (nmcli), Bluetooth (bluetoothctl) + Settings/Lock shortcuts.
- `surface/Settings.qml`: edits `config/Config.qml` (bar height, clock format,
  module visibility) and writes `~/.config/hyprtk-bar-qt/config.json`.
- `surface/Notifications.qml`: notification daemon + toast stack, opt-in behind
  `HYPRTK_BAR_QT_NOTIFICATIONS=1` (one owner of the notifications bus name).
- New singletons `Config` and `UiState` (named to avoid QtQuick `Palette`/`State`
  clashes) and a `Toggle` component.

## 0.1.0 — unreleased

Initial Qt/QML rewrite scaffold (Quickshell + Python backend).

- `shell.qml`: layer-shell `PanelWindow` per screen via Quickshell.
- `bar/`: frosted panel with `Workspaces` (Hyprland), `Clock` (SystemClock) and
  `SysMonitor` modules.
- `theme/Palette.qml`: singleton resolving live pywal colours + the existing
  `hyprtk-bar` config (source, theme block, opacity).
- `backend/hyprtk_bar_qt/`: toolkit-free Python logic — `palette.py`,
  `config.py`, and `sysmon.py` (streams CPU/memory as JSON lines over stdout).
- `bin/hyprtk-bar-qt`, `install.sh`, packaging metadata.

Chosen architecture: QML presentation + Python/IPC logic, because PySide6/
QtWidgets has no supported Wayland layer-shell binding.
