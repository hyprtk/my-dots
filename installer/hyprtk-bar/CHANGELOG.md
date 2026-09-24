# Changelog

All notable changes to hyprtk-bar are documented in this file.
Dates are in YYYY-MM-DD format.

## [Unreleased]

### Added

- **Desktop widgets** — free-floating layer-shell surfaces owned by the bar
  process, separate from the bar's own modules, with their own **Widgets**
  settings page (master enable + per-widget tabs). Everything applies live via
  a diffing manager (create/update/destroy, no restart). Three samples ship:
  - **Clock** — `digital` / `text` / `dials` styles, driven by JSON **clock
    theme files** (`~/.config/hyprtk-bar/widget-themes/clock/` plus bundled
    `default`, `minimal`, `neon-dials`); the widget config overrides the theme.
  - **Weather** — location set by **city**, geocoded and fetched keylessly from
    Open-Meteo on a worker thread, cached for offline restarts, with a daily
    forecast and Nerd Font **weather glyphs** (sun / cloud / rain / snow /
    thunder, `U+E300–U+E3EB`, day + night variants — the old Font Awesome
    `f0xx` codepoints rendered as unrelated icons).
  - **Audio visualizer** — levels from **cava** (raw-ascii subprocess) with a
    synthetic fallback, and `bars` / `wave` / `mirror` / `dots` / `glow`
    effects, accent/gradient/pywal/custom colours, sensitivity, smoothing, peak
    dots, FPS, bar count and orientation.
  Each widget is placed 9-way (layer + position + margins) **or freely**
  (`position: "free"` = absolute `margin_x` / `margin_y`, clamped on-screen),
  sized, themed from **pywal** by default, and can pin its own
  background/foreground/accent. **Hold `Super+Shift` and left-drag a widget on
  the desktop to move it** — the move is driven by a Hyprland press/release bind
  (window drag stays on `Super + left mouse`) and persists the new position.
  Widgets are click-through when not being moved. New `desktop/` package
  (`base`, `theme`, `manager`,
  `clock`, `clock_theme`, `weather`, `visualizer`); design notes in
  `WIDGETS.md`.
- **Desktop widgets: four data widgets.** `disk` (per-drive usage + read/write
  rates), `network` (interface, IP, up/down rates + graph), `resources`
  (CPU / RAM / swap / temp / load) and `sysinfo` (host / OS / kernel / uptime /
  CPU / GPU / memory / disks) — built on a shared `SampledWidget` base and
  reusing the bar's `monitor_data.py` samplers.
- **Desktop widgets: snapping.** Widgets sharing a `snap_group` lay out
  together along `snap_axis` (horizontal/vertical) with a **uniform cell** (the
  largest member) and content **scaled to fit**; dropping a widget within 28 px
  of another **drag-snaps** them (side-by-side → horizontal, stacked →
  vertical), and dragging one out detaches it. Group/axis/order are also
  editable in the settings Widgets page.
- **Desktop widgets: bar avoidance.** Widgets never sit under the bar — the
  usable area is the monitor inset by the bar's exclusive-zone thickness on all
  four sides (the bar thickness acts as a border), read from Hyprland's
  `monitors[].reserved`. Every widget (anchored, `free` or snapped) is clamped
  into that area and its content scaled down if it would not fit; a snap group
  is clamped/scaled as a whole.
- **Fit-to-width content scaling.** When the configured width is smaller than
  the modules' natural width the bar now scales the glyphs/icons, the CSS
  font/chip sizes, the spacings and the button paddings down (to a floor) so
  every module's glyph stays visible inside the border instead of being clipped,
  and returns to 1.0 when there is room. The left/right sections are also given
  **equal widths** instead of fully homogeneous cells (which sized every cell to
  the widest one and wasted ~2x the space) — the center stays centered because
  the side widths match, but narrow widths now actually fit. `window` (fixed
  title width) and `tray` (icon size) gained `apply_font` so they scale too.
- **`install.sh --wal-only`** — provisions just the vendored pywal16 (vendor
  tree + venv + `wal` launcher) and exits. The merged `1-install.sh` calls it
  early, before its pywal init steps and the late full bar install.
- Bundled-first `wal` resolution: `proc.bootstrap_environment()` prepends
  `~/.local/bin` to the bar's PATH and exports `HYPRTK_WAL`; `themer.py` uses
  `HYPRTK_WAL` → `resolve_binary("wal")`, and the bundled scripts use
  `HYPRTK_WAL` → `../venv/bin/wal` → PATH.

### Changed

- **pywal16 is now bundled — no separate install.** The bar vendors pywal16
  under `vendor/pywal16/` (MIT; provenance and update steps in
  `vendor/pywal16/VENDOR.md`) and exposes it as `wal` (`venv/bin/wal`, symlinked
  into `~/.local/bin`). `python-pywal16-git` was removed from the AUR extras, so
  neither the bar nor the merged `1-install.sh` downloads pywal separately.
- `derivation.nix` installs the vendored tree and wraps a `wal` executable;
  the flake devShell exposes `wal` from the source tree.

### Fixed

- **Snapped widgets overflowed and overlapped; content didn't scale.** The snap
  cell scaled only CSS (fonts/padding), so fixed-size content — the
  `HistoryGraph`s, the clock dial, glyph pixel sizes — and `Gtk.Box` spacings
  stayed at full size, leaving each widget taller/wider than its cell and
  overlapping the next. Every widget now scales its fixed content
  (`on_content_scale`), the base scales all box spacings in the content tree,
  CSS scales padding and progress-bar height, and the snap cell is measured from
  the content **minimum** (on the root box) with a small fit margin.
- **Bar content was inset twice on the left.** A 6px spacer sat before the pill
  on top of the pill's own 6px CSS margin, so at 100% the bar showed a ~12px gap
  on the left but only 6px on the right (the content looked pushed right). The
  spacer is gone; both ends are inset 6px, as the rounded pill intends.
- **Icons spilled outside the bar's rounded border at narrow widths.** With a
  width smaller than the modules' natural width the overflow was clipped only by
  the layer surface, so it drew into the pill's 6px CSS margin — visible as icon
  edges poking out past the border. The `.taskbar` background, its margins and
  the rounded ends now live on the `ClipBox` (a windowed `Gtk.EventBox`), so GTK
  clips the overflowing content to the pill itself — nothing is drawn outside the
  border. The input-shape inset follows the new allocation (the CSS margin is no
  longer on the child).
- **openSUSE deps use valid package names.** `DEPS[zypper]` requested
  `typelib-1_0-cairo-1_0` and `typelib-1_0-xlib-2_0`, which do not exist on
  openSUSE Tumbleweed (there is no per-namespace GIR package for cairo/xlib).
  Both `cairo-1.0.typelib` and `xlib-2.0.typelib` — the latter required by
  `deps_ok` to import Gtk — are provided by **`girepository-1_0`**, so the
  zypper list now requests that instead.
- **Debian/Ubuntu extras use valid package names.** `EXTRAS[apt]` requested
  `libnotify` and `policykit-1`, which do not exist on Ubuntu 26.04
  (`libnotify` has no candidate; `policykit-1` was superseded by `polkitd` +
  `pkexec`). The apt list now installs `libnotify-bin` (which provides
  `notify-send`) and `polkitd pkexec`.
- **Fedora/openSUSE extras corrected.** `pipewire-pulse` is a Debian name; Fedora
  and openSUSE ship `pipewire-pulseaudio`. openSUSE's `notify-send` lives in
  `libnotify-tools`, not `libnotify`. Fixed in `EXTRAS[dnf]`/`EXTRAS[zypper]`.

## [0.1.0] - 2026-09-12

### Added

- **Liquid Glass theme.** New bundled `hyprtk-liquid-glass` theme — a port of
  Apple's "Liquid Glass" aesthetic: a highly translucent, cool-tinted glass slab
  with a bright specular rim along the top edge, a faint inner under-glow and a
  deep drop shadow. The glass tint is neutral; the accent stays pywal (mauve) so
  it matches the rest of the desktop.
- **Glass effects in the theme pipeline.** Imported themes can now carry a
  `box-shadow` through to the bar: `window#waybar`'s box-shadow (drop shadow +
  specular rim) is applied to the bar surface, and `#workspaces button.active`'s
  box-shadow becomes the focused workspace chip's glow.
- **Manual theme editor.** Selecting `theme.source = "manual"` in Theme Manager →
  Bar Themes now shows a set of colour pickers (Background / Foreground / Accent /
  Running / Hover / Border) that write straight into the config's `theme` block
  on Apply. Manual mode now also draws the same 2px border as pywal, coloured
  from the (new) `theme.border_color` setting, falling back to the accent.
- **`hyprtk-liquid-glass` rofi variant.** A matching Rofi variant (cool-tinted
  translucent glass + bright specular border, pywal accents) pairs with the bar's
  Liquid Glass theme. It is auto-discovered by the Theme Manager's Rofi page and
  linked by `sync-rofi-theme.sh` when the bar uses the `hyprtk-liquid-glass`
  imported theme.

### Changed

- **Deduplicated the `menu/` subpackage.** Deleted `menu/theme_import.py` and
  `menu/hypr_animations.py` — near-verbatim copies of the top-level modules that
  had already drifted (the `_safe_name` theme-name validation never reached the
  menu copy, leaving a traversal guard missing). The menu now imports the
  top-level `theme_import` and `hypr_animations` (which gains a new
  `border_period_ms()` helper wrapping `border_animation`).
- **Consolidated the colour helpers.** `rgba`, `hover_color` and `blend` now
  live in `colors.py` alongside `hex_to_rgb` / `css_rgb` / `contrast_fg`, so
  there is a single colour-parsing implementation across the bar, the menu, the
  arc menu and the theme manager. Removed the duplicated `_rgba` /
  `_hover_color` / `_blend` / `_rgb` helpers and the dead `hue_rotate`.
- **`menu/config.load_pywal_colors` delegates to the top-level reader**, so the
  two pywal readers can no longer diverge.

### Security

- **`updates.install_command` is allowlisted.** The left-click update command is
  user config, so it must reference an allowlisted script (any path token that
  resolves to one — a wrapper like `alacritty -e ~/hyprtk/.../installupdates.sh`
  is fine); otherwise it falls back to the bundled `installupdates.sh`. A
  synced/malicious config can no longer get arbitrary shell on left-click.
- **Theme Manager refuses to run `update.sh` as root via pkexec** when the
  script (or its parent directory) is group/world-writable or owned by another
  user — closing a privilege-escalation foot-gun from a writable dotfile.

### Performance

- **Hyprland refresh off the GTK thread.** The four `hyprctl` queries run on
  every event (focus/move/open/close) now execute on a worker thread and marshal
  results back via `idle_add`, so event bursts no longer stall the bar.
- **System monitor sampling off the GTK thread.** The 1s poll collects all
  samples (lsblk, nvidia-smi, top-processes, hyprctl) on a worker thread and
  applies widget updates on the main thread.
- **Quick Settings refresh off the GTK thread.** State collection
  (nmcli/bluetoothctl/wpctl/brightnessctl) runs on a worker thread.
- **Menu search reuses cached rows.** App-list rows are cached by entry id and
  reparented instead of destroyed and rebuilt, so searching no longer reloads
  every icon on each keystroke.
- **`kbstate` skips no-op polls** when the Caps/Num lock state is unchanged.

### Fixed

- **Blank app list after switching menu layouts.** The app-row cache retained
  references to destroyed rows across a layout rebuild, so the list rendered
  empty after changing from whisker to win7/plasma and back. The cache is now
  reset whenever a new list is built.
- **Search-selection contrast.** The search field's selected text now uses a
  contrast-correct `@accent_fg` token (contrast against the solid accent)
  instead of hardcoded black, so it stays readable with a light accent.
- **Reverted a menu accent unification** that made the win7/plasma selected app
  rows unreadable (a bright-pink solid background under hardcoded white text).

## [Unreleased]

### Added

- **`wal-watcher.sh` bundled and autostarted.** It watches `awww` for wallpaper
  changes made by any tool and regenerates the palette, copied configs and icon
  colours — using the bar's bundled `change-icons.sh`, so no `~/hyprtk` install
  is required.
- **Bundled default wallpapers.** Four wallpapers (`3.png`, `14.png`, `66.png`,
  `default.png`) ship in `Wallpapers/` and the installer copies them into
  `~/Pictures/Wallpapers/` (no-clobber — files the user already has are kept).
- **Bundled bar themes.** The nine hyprtk bar themes (`hyprtk`, `hyprtk-aero`,
  `hyprtk-clear`, `hyprtk-glass`, `hyprtk-inverse`, `hyprtk-light`,
  `hyprtk-liquid-glass`, `hyprtk-negative`, `hyprtk-reverse`) now ship in
  `themes/` and the installer copies them into `~/.config/hyprtk-bar/themes/`,
  so Theme Manager → Bar Themes has them available without importing by hand.
- **Hyprland autostart is configured by the installer.** `install.sh` adds the
  bar to the user's Hyprland Lua config — `~/.config/hypr/autostart.lua` when it
  exists, otherwise `~/.config/hypr/hyprland.lua` — as an idempotent
  `hl.on("hyprland.start", …)` block, and removes it again on `--uninstall`.
- **Bundled Nerd Font + AUR helper bootstrap in the installer.** The bar's
  icons are Nerd Font glyphs, so `install.sh` now installs the bundled
  `assets/fonts/SymbolsNerdFont-Regular.ttf` into `~/.local/share/fonts` and
  refreshes the font cache — glyphs render without a system font package. On
  Arch, when no AUR helper is present, it builds `yay` (installing `base-devel`
  + `git`) before installing the AUR extras.
- **`--dry-run` flag** — checks the required typelibs, Python/venv, `PATH` and
  Wayland/Hyprland environment and reports what is missing without changing
  anything.
- **Post-install self-test** — the installer now imports GTK + gtk-layer-shell
  through the venv and fails loudly with the cause if the runtime is unusable,
  instead of installing "successfully" and leaving a bar that cannot launch.
- **Cross-distro installer** — `install.sh` now detects the system package
  manager (pacman, apt, dnf, zypper, xbps, apk, emerge, nix) and installs the
  GTK3 / gtk-layer-shell GObject-Introspection typelibs and Python tooling the
  bar needs, instead of requiring a manual step. It probes for the `Gtk-3.0`
  and `GtkLayerShell-0.1` typelibs first so it skips sudo when they are already
  present.
- **`--no-deps` and `--help` flags** — `--no-deps` installs without touching
  system packages (for Gentoo/Nix or when deps are managed externally);
  `--help` prints usage.
- **No PyGObject/pycairo wheels → `--system-site-packages` venv.** PyGObject and
  pycairo publish **no binary wheels at all** (verified: `pip download` fetches
  `.tar.gz` source distributions), so a plain venv pip-install would build them
  from source — needing a C compiler + GI/cairo headers — on *every* distro, not
  just musl. The installer now installs the distro's own pygobject/pycairo via
  the package manager and runs the bar in a `--system-site-packages` venv; only
  the pure-Python `dbus-next` is pip-installed, so no compiler is required
  anywhere.
- **Corrected per-distro package maps.** Void ships the GI typelibs in its
  `-devel` subpackages and Alpine in `-dev`; pycairo added to pacman/dnf/xbps/
  apk/emerge; openSUSE uses the `typelib-1_0-*` names; `dbus-next` pinned `<0.3`.
- **Portability documentation** — new `PORTABILITY.md` scopes the dependency
  model (GI typelibs vs. venv Python vs. subprocess tools), the distro support
  matrix, the per-distro package-name mapping, and the remaining Arch /
  `~/hyprtk` assumptions.
- **Distro-agnostic `updates` module.** The package-update indicator no longer
  assumes pacman. Two bundled scripts — `scripts/updates.sh` (pending count)
  and `scripts/installupdates.sh` (apply) — detect the package manager (pacman,
  apt, dnf, zypper, xbps, apk, emerge, nix) and run the matching query/upgrade.
  The module's default `script` and `install_command` now resolve to these
  bundled scripts (dotfiles copy as fallback), so the indicator works standalone
  on any distro instead of showing `?` off Arch. `installupdates.sh` also
  self-launches inside the first terminal emulator it finds (alacritty, kitty,
  foot, wezterm, xfce4-terminal, gnome-terminal, konsole, terminator, xterm),
  so the click no longer assumes alacritty.
- **Quicklinks editor + system-preferred defaults.** The bar settings gained a
  **Quicklinks** page where the terminal, file-manager and web-browser quick
  links can each "Choose…" their app from the installed applications (or reset
  to "System default"). When a link's command is empty, it resolves at click
  time to the session's preferred app — new `sysapps.py` resolves the default
  terminal (env → GNOME/portal setting → candidates), file manager
  (`xdg-mime inode/directory`) and web browser (`xdg-settings`), so a fresh
  standalone install no longer hardcodes alacritty/thunar/brave.
- **Nix flake.** `flake.nix` + `derivation.nix` package the bar for NixOS
  (`buildPythonApplication` + `wrapGAppsHook` + `gobject-introspection`, data
  files installed to `$out/share/hyprtk-bar` and surfaced via
  `HYPRTK_BAR_DATA_DIR`); a dev shell ships the same deps.
- **Cross-distro CI install matrix** (`.github/workflows/install-matrix.yml`) —
  one container per distro family (Arch, Debian, Ubuntu, Fedora, openSUSE, Void,
  Alpine) runs the installer dry-run, a real `--no-extras` install, and a
  headless GTK import, so the per-distro package names stay honest.
- **gtk-layer-shell version floor check** — `--dry-run` reports the installed
  version and the installer warns (doesn't fail) when it is below 0.9, printing
  the source-build steps (older LTS releases ship 0.5–0.8, Ubuntu 20.04 ships
  0.1.0).
- **Feature-availability matrix** (PORTABILITY.md) — every feature mapped to its
  backing binary and its availability across the 8 distro families; the core
  surface works everywhere, only the theming wall (wallpaper daemon / pywal /
  folder colours) is Arch/AUR-centric and degrades to the built-in palette.

### Changed

- **`HYPRTK_BAR_DATA_DIR`** — `config.py` honours this env var so a store-based
  (Nix/flatpak) install can point the bar at its read-only data (assets, scripts,
  themes); the menu's theme module reuses `config.INSTALL_DIR` instead of walking
  four parent hops from `__file__`.
- **Start menu power/settings icons are now Nerd Font glyphs.** The power
  buttons used bundled PNGs and the settings button a system symbolic icon
  (which rendered as a blank placeholder where the icon theme lacked it). Both
  now use glyphs from the bundled Nerd Font, matching the bar's icon style.
- **Clearer memory and disk glyphs.** The system monitor's Memory tab and
  readouts used `fa-database`, and Disks used `fa-hdd_o` (which reads as a
  server box); they now use `fa-memory` (a RAM DIMM) and `md-harddisk`. Applied
  to the monitor, the bar's compact readouts and the HDD drive-type badge.

### Fixed

- **System monitor → Network used the wrong interface glyphs.** The
  Interface/Type/IP readouts were hardcoded to `fa-wifi`, so a wired connection
  showed a Wi-Fi glyph; they now follow the active interface. In the interface
  list, Ethernet and Loopback shared `fa-link` (a chain link); Ethernet now uses
  `fa-ethernet` and Loopback `fa-exchange`.
- **System monitor → Disks and Network showed no devices.** `_work()` stores
  the samples under `disk`/`net`, but `_apply_refresh()` gated their handlers on
  `"disks"`/`"network"` — keys that were never present — so `_update_disks()` /
  `_update_network()` never ran. The drive cards, interface list and their
  readouts stayed empty ("--"). The gates now match the stored keys, so both
  pages populate.
- **Security (code review).** Consolidated `_contrast_fg` into one WCAG
  implementation (`colors.py`) shared by the bar, menu, arc menu and themer
  (the four copies had diverged). Remote icon names from the session bus
  (notifications/tray/dbusmenu) are sanitised via `safe_icon_name` so a
  path-like name can't reach GTK's path loader; `sync-rofi-theme.sh` passes the
  config path as argv (no string interpolation) and validates `theme_name`
  before `ln -sf`; `import_theme` rejects unsafe theme names.
- **Compatibility (code review).** Workspace/window dispatch falls back to the
  classic Hyprland commands below 0.55 (cached version check); the tray adopts
  foreign-watcher items via a callback (the sync getter deadlocked inside
  dbus-next's dispatch); the wallpaper-daemon autostart is gated on `awww`/`swww`
  being installed; hardcoded `~/hyprtk`/host paths in quicklinks, start-command
  and the network monitor resolve via `resolve_script` (and the `enp7s0` NIC
  hardcode is gone); `gi.require_version` ordering fixed in the menu modules.
- **Design (code review).** The menu's `*` font-family + scrollbar rules are
  scoped to `.menu-root` (they leaked screen-wide at APPLICATION priority);
  warn/danger/drive/interface colours follow the pywal palette instead of
  hardcoded hexes; settings icon tint uses the theme foreground (was `#000000`);
  the notification center sits above toasts (OVERLAY layer); reduced-motion is
  respected; keyboard focus rings and larger touch targets added.
- **Performance (code review).** `top_processes` no longer sleeps (it diffs
  against the previous poll's sample); the bar refresh makes one fewer
  `hyprctl` call (shares the monitors query); `lsblk`/`ip`/`nvidia-smi` results
  are TTL-cached; quick settings reads volume/mic once per refresh; the arc
  menu reuses one CSS provider instead of churning screen-wide each frame;
  keyboard-state globs resolve once; rofi sync only runs when the theme changes.
- **Dialogs showed a double border.** The choose-app and arc-item dialogs were
  `Gtk.Dialog`s, whose internal `dialog-vbox` picks up GTK-theme chrome (a CSD
  decoration margin/shadow) that drew a second frame around the `popup-box`.
  They are now frameless `Gtk.Window`s with a single `popup-box` root (like the
  About window), using a nested main loop for the modal behaviour — one bordered
  box, no second frame.
- **The "Choose app" and arc-menu item dialogs ignored the bar's theme.** They
  are plain `Gtk.Dialog`s, which paint the GTK theme's own background. They now
  use a shared `_theme_dialog()` helper — transparent window + `popup-box` glass
  on the content area — so they match the pywal/imported palette like the
  settings and About windows. The buttons now live inside the content area
  (single popup-box) rather than a separate action area, so there is one
  bordered box, not a double border.
- **Re-enabling quicklinks didn't show the module until a reload.** Disabling
  quicklinks pops its widget from the module cache, so re-enabling rebuilt it
  fresh — but a freshly built widget is created hidden and `rebuild_layout`
  packs it into an already-shown box, so it stayed invisible. `_ensure_module`
  now `show_all()`s a newly built widget, so any module re-enabled mid-session
  appears immediately.
- **Module tooltips appeared at the screen edge instead of above their module.**
  The tooltip x used the pill/widget's *surface-local* allocation as if it were
  *monitor-local*; with a constrained bar width (the surface is inset from the
  monitor edge) every tooltip was clamped to one side. Positions now translate
  to monitor coordinates and add the surface offset.

- **Confirmation dialogs opened *behind* the popup that launched them.** The
  menu, system monitor and Theme Manager are layer-shell surfaces, so their
  plain `Gtk.MessageDialog`s rendered behind. All confirms now use a shared
  `center_layer_dialog()` helper (OVERLAY layer, centred) and sit on top.

- **Confirmation dialogs (reboot / shutdown / empty trash) had light buttons.**
  They are separate GTK dialogs, so the menu-wide `.menu button` reset didn't
  reach them, and `.confirm-dialog button` set only `background-color` — the GTK
  theme's `background-image` gradient showed through. It now resets
  `background-image`/`box-shadow`/`text-shadow` too.

- **Selecting a wallpaper (or Random) did nothing on a standalone install.**
  `awww img` needs `awww-daemon` running, which the standalone setup never
  started — so the call failed silently. `wallpaper-colors.sh` and
  `updatewal-awww.sh` now start the daemon if it isn't running (awww, with a
  swww fallback), and the installer's autostart block also starts
  `awww-daemon`.

- **Plasma "Computer" tab had dark, unreadable text.** `.plasma-place-label`
  set no `color`, so the places/content labels fell back to the GTK theme's text
  colour (dark, on a light theme) on the dark panel. They now use `@text`.

- **Selected/active app text was black and unreadable.** The menu chose the
  selected-text colour by contrasting against the raw accent, but the selected
  background is a *translucent* accent over the panel — so a light accent
  (e.g. the default blue) produced black text on a dark row. The colour is now
  contrasted against the accent blended over the background, so it stays
  readable for light and dark palettes.

- **Menu buttons/entries showed the GTK theme's light background.** The GTK
  theme paints these with its own `background-image` gradient and shadow, which
  sit on top of any `background-color` we set — so pinned tiles, plasma tabs,
  the "All apps"/"More" pills, the power/settings buttons and the search box
  looked light and off-theme. A menu-wide reset (`background-image`/
  `box-shadow`/`text-shadow: none` inside `.menu`) makes only the palette
  colours show.

- **Start menu's settings (cog) button rendered unthemed.** The bar's global
  CSS (loaded at a higher GTK provider priority) defined `.settings-btn` for its
  own settings dialogue, which overrode the menu's `.settings-btn` and left the
  cog button transparent with no border. The menu's classes are now
  `menu-settings-btn` / `menu-settings-icon`, so the two no longer collide.

- **Bar width/alignment did not work on smaller displays.** The width was
  applied to the pill, whose minimum width (~the modules' content, ~1388px)
  clamps it — so a percentage/px below that minimum was ignored, and on a small
  monitor the surface grew wider than the screen and ran off the right edge.
  Width is now applied to the layer **surface** via left/right margins
  (percentages measured against the monitor, not the shrinking surface — that
  caused a hover flicker), and the pill is wrapped in a clip container so its
  content minimum no longer forces the surface wider than the monitor. 20%/50%/
  px widths and left/center/right alignment all work; content clips if the
  requested width is smaller than the modules need.

- **Bar could not launch after a clean install on some systems.** Importing
  `Gtk` needs the `xlib-2.0` GObject-Introspection typelib (GDK pulls GdkX11
  into the namespace). On Arch that ships in `gobject-introspection-runtime`,
  which the installer did not install — and the probe only checked
  `Gtk-3.0`/`GtkLayerShell-0.1`, so it skipped the dependency step entirely.
  `gobject-introspection-runtime` is now in the dependency list and
  `xlib-2.0` is part of the probe.

- **`hyprtk-bar: command not found` after install.** `~/.local/bin` is not on
  PATH on a fresh Arch, and Hyprland's `exec-once` does not source shell rc
  files, so the launcher was unreachable. When `~/.local/bin` is off PATH the
  installer now symlinks `hyprtk-bar` and the toggle scripts into
  `/usr/local/bin` (removed on `--uninstall`).

- **Spurious "refusing non-allowlisted script" warning on standalone installs.**
  The updates module warned and disabled polling whenever its configured script
  did not exist — the normal case without the dotfiles. It now stays quiet when
  the script is absent and only warns when a script is present but outside the
  allowlisted locations.

- **Startup crash on a system without a wallpaper palette (`KeyError: 'red'`).**
  `resolve_palette` only defined `red` when pywal colours were available, but
  the CSS always renders the cliphist delete-hover rule, so a fresh install (no
  `~/.cache/wal/colors.json`) crashed on launch. `red` now has a default.

- **Stale `~/hyprtk` fallback paths.** `config.py` / `themer.py` fell back to
  pre-bundling dotfiles locations (`configs/rofi/scripts/…`,
  `installer/scripts/…`, `hypr/scripts/…`) that no longer exist now the feature
  scripts are vendored under `installer/hyprtk-bar/scripts/`; the dotfiles
  fallback now resolves there. `BUNDLING.md`'s inventory was updated to the
  bundled paths.

- **System monitor → Apps lists dropped quiet apps.** The four tabs ranked
  processes by CPU, discarded anything under 0.05% and kept only the top 15, so
  an idle app such as a terminal vanished as soon as it went quiet. The lists
  now show every running app/process, and rows are reconciled in place each poll
  instead of being cleared and rebuilt — entries stay put and the selection
  survives.

## [0.1.0] - 2026-09-09

### Added

- **About hyprtk-bar** — right-click menu entry that opens a branded, themed
  About window (frameless, popup-box glass + animated border) showing the
  Hyprtk brand, version and the project repo.

### Changed

- **Hyprtk watermark** — every module now carries a branded header
  (`# HYPRTK · hyprtk-bar · <module>` / `Part of the Hyprtk desktop suite ·
  github.com/hyprtk`) after its docstring, unifying the project under the
  Hyprtk brand.

### Fixed

- **Theme colours on slider / option controls** — the GTK theme paints
  `Gtk.Switch`, `Gtk.Scale`, check/radio indicators and the spinbutton up/down
  arrows with its own `background-image` / `-gtk-icon-source` assets, which sat
  on top of the palette colours, so those controls kept the GTK theme's accent
  (e.g. Kripton's teal) instead of the pywal / imported theme. Switches and
  scales now reset the theme image and take the palette accent; check/radio use
  recoloured symbolic indicators; spinbutton entries and arrows follow the
  palette fg/accent. Covers Quick Settings, Bar Settings and the Theme Manager.

## [0.1.0] - 2026-09-09

### Added

- **System monitor Apps page** — four views (User apps / System apps / User
  processes / System processes); "apps" are processes owning a compositor
  window, "processes" are everything owned by that user. Each row shows
  process, CPU and memory; **Kill**, **Force kill** and **Launch** act on the
  selected process (Launch re-runs its command line). Killing a system-owned
  process goes through the scoped `hyprtk-system-kill` sudo helper (installed
  to /usr/local/bin by setup-sudoers.sh alongside dmidecode — never NOPASSWD
  ALL); user-owned processes are killed directly.

### Fixed

- **Memory leaks** — SNI items now detach their D-Bus signal subscriptions on
  unregister (nm-applet resets / name flaps no longer pin zombie items in the
  bus handler registry); DBusMenu icons are dimension-capped and each menu is
  destroyed on dismissal; removed widget rows are now destroyed (not just
  removed) across the menu (app list, favorites, recents, pinned grid, plasma
  browser/trash), themer (theme list, thumbnail/pywal/variant/icon grids), and
  the notification center. Module poll timers (clock, kbstate, updates, sysmon)
  are stopped on shutdown and wired into the bar's teardown.
- **Notification name-owner fight** — the 150 ms retry+pkill loop is bounded
  (5 tries, linear backoff) so an unknown/stubborn daemon can't churn forever.

### Changed

- **Security hardening** — SNI `IconPixmap` dimensions are capped (512px) so a
  remote client can't force huge allocations; SNI `IconThemePath` is validated
  (existing absolute dir under home/system icon locations) before being injected
  into GTK's global icon search path. Imported-theme names are validated against
  a whitelist (`_safe_theme_dir`) before touching the filesystem, and themer
  bar/swaylock config writes are atomic.
- **Responsiveness** — SDDM/GRUB update (pkexec) and the package-update check
  now run on worker threads (no more UI-thread stalls). The Themer and System
  Monitor dialogs build lazily on first open instead of at startup. Border
  animations tick at ~15fps with a color-change skip (arc border only animates
  while open).
- **Menu integration fixes** — `menu.enabled` is honoured at runtime (off hides
  the menu and toggle no-ops); the start button no-ops when the menu is
  disabled; settings Apply preserves `position: "auto"` (new Auto radio); menu
  saves route through the bar's config save (last-good backup); the menu's 2s
  wal-watcher timer is released on destroy.

### Added

- **Start menu merged into the bar** — the standalone hyprtk-menu app is gone;
  the bar now owns the start menu (search, favorites, recents, power bar, four
  layouts: whisker/win7/win11/plasma). New `menu` config block in the bar config
  (legacy `~/.config/hyprtk-menu/config.json` is auto-imported on first run), a
  **Menu** tab in the bar settings dialogue (enabled/layout/position/align/gaps/
  follow), toggling via the start button or `Super+Space` (SIGUSR1 from
  `installer/scripts/hyprtk-bar-menu-toggle.sh`), live re-theme from the bar's
  palette + pywal, and live layout/position reload when settings change.
  Vendored under `src/hyprtk_bar/menu/` with its assets in `assets/`.
- **Follow hyprtk-bar** toggle (`menu.follow_bar`, default on): anchors the menu
  to the bar's edge and aligns it to the bar pill (width + align + gaps) instead
  of the screen edge; off places it at the chosen screen corner. It also controls
  theming — off resolves the menu's own pywal palette rather than the bar's theme.

## [0.1.0] - 2026-09-08

### Added

- **Arc menu overlay merged into the bar** — the standalone hyprtk-arc-menu app
  is gone; the bar now owns the arc menu (a FAB in a screen corner that fans its
  items out on click). New `arcmenu` config block in the bar config (legacy
  `~/.config/hyprtk-arc-menu/config.json` is auto-imported on first run), a
  **Arc Menu** tab in the bar settings dialogue (position/shape/sizes/colours/
  toggles + item editor with installed-app search), toggling via `Super+Ctrl+M`
  (SIGUSR2 from `installer/scripts/hyprtk-bar-arc-toggle.sh`) or the FAB, and
  live theming from the bar's palette + pywal.

## [0.1.0] - 2026-09-08

### Fixed

- **Theme Manager → SDDM & GRUB background preview** — the wallpaper preview is
  now scaled down (contain fit) to fit within the dialogue instead of being
  shown at full image size and overflowing the panel. Aspect ratio is preserved
  and small images are not upscaled.

## [0.1.0] - 2026-09-08

### Changed

- **Theme Manager → Bar Themes applies themes without restarting** — selecting
  a source (pywal / imported / manual) or an imported theme now re-themes the
  bar live instead of closing and reopening it. The Theme Manager uses the same
  in-place re-theme path as the bar settings dialogue (`Bar.apply_theme`), which
  updates the shared config, saves it, and re-themes. "Restart Bar" still
  restarts explicitly.

## [0.1.0] - 2026-09-08

### Changed

- **Theme Manager quick-link tooltip** — the wallpaper glyph's hover tooltip now
  reads **Theme Manager** instead of "Wallpaper", since it opens the Theme
  Manager dialogue.

## [0.1.0] - 2026-09-08

### Changed

- **Theme Manager → Bar Themes page now matches the bar settings Themes tab** —
  it gained a theme **Source** selector (Pywal (dynamic) / Imported theme /
  Manual (config)), a check-list of the imported themes (enabled only when the
  source is "imported"), and an **Import theme…** button that copies a theme
  folder into the bar's themes dir and applies it. Selecting a source or an
  imported theme writes the bar config and restarts the bar, so both the bar
  settings dialogue and the Theme Manager expose the same options and behaviour.

## [0.1.0] - 2026-09-08

### Fixed

- **Pywal palette grid went blank** (Theme Manager → Pywal) — re-rendering the
  colour grid while the dialogue was open (Refresh, or after applying a scheme
  / wallpaper) left every swatch hidden, because GTK3 keeps children added
  after a container is shown invisible. The grid now calls `show_all()` after
  building, and the palette is refreshed each time the Pywal page is opened so
  it always shows the current pywal colours.

## [0.1.0] - 2026-09-08

### Added

- **Wallpaper preview cache build** (Theme Manager → Wallpaper) — a new
  **Build Cache** button regenerates a cover-cropped thumbnail for every image
  in the wallpaper directory, with a live `N/total` progress bar. The cache is
  built incrementally (one image per idle step, so a large directory never
  blocks the UI) and resumes after an interruption, so thumbnails appear on
  first scroll instead of only after a full blocking pass.
- **Directory-aware cache validity** — the cached index is only trusted when it
  belongs to the currently selected wallpaper directory, so switching folders
  no longer briefly shows another folder's thumbnails.

### Fixed

- **Not all wallpapers displayed when scrolling** — the thumbnail grid is now
  driven by the scrollbar adjustment (value-changed near the bottom) in
  addition to the unreliable `edge-reached` signal, and every newly-added
  thumbnail is shown (`show_all`). Previously GTK3 kept every batch after the
  first one hidden, so scrolling stopped partway through a large directory.
- **Cleaner directory switch** — choosing a new wallpaper directory now cancels
  any in-flight cache build and rebuilds for the new folder without double
  triggering.

## [0.1.0] - 2026-09-07

### Changed

- **Waybar theme schema renamed to hyprtk-native** — `theme.source: "waybar"`
  is now `"imported"` and `theme.waybar_theme` is now `theme.theme_name`.
  Old configs auto-migrate (source waybar→imported, `waybar_theme` pops into
  `theme_name`); the `waybar_theme.py` module is now `theme_import.py`.
  All consumers (menu, arc-menu, theme-gui, rofi sync) follow the new schema.
- **Settings dialogue applies the theme's transparency** — the window is now a
  transparent toplevel (`set_app_paintable` + rgba visual, same as the monitor
  popups) and no longer forces an opaque background, so the imported theme /
  pywal opacity shows through to the desktop.
- **Settings header background is transparent** — removed the
  `alpha(currentColor, 0.06)` band behind the "Bar Settings" title (was a grey
  block on light themes).

## [0.1.0] - 2026-09-07

### Added

- **Animated border mirroring Hyprland** — the pill border color loops through
  hues at the same pace as Hyprland's `borderangle` animation. Which speed is
  used is chosen from the bar settings Animations tab: `low`/`high` read the
  matching `animations-<mode>.lua` file from the Hyprland config dir
  (borderangle speed 8 / 30), `custom` uses its own speed independent of
  Hyprland. The active Hyprland config dir is watched, so toggling the
  animations file re-paces the border live.
- **Animations settings tab** — enable/disable the animated border, choose
  Low / High / Custom mode, and set a custom Hyprland-style speed (only
  enabled for Custom). Applies live via the new `set_border_animation` action.
- **Border animation speed fix** — the period now exactly matches Hyprland's
  documented semantics: `speed` is the animation duration in ds (1 ds =
  100 ms), so a full borderangle rotation takes `speed * 100` ms (e.g. speed 30
  → 3000 ms). Previously the bar cycled ~3x too fast.

### Changed

- **GPU page supports all three vendors** — the system monitor's GPU page now
  auto-picks the primary GPU (discrete NVIDIA > discrete AMD > discrete Intel
  Arc > integrated AMD > integrated Intel) and reads from the right vendor
  source:
  - AMD: amdgpu sysfs (`gpu_busy_percent`, `mem_info_vram_*`, `pp_dpm_*`,
    card-scoped hwmon temps/power/fan).
  - NVIDIA: one `nvidia-smi --query-gpu=...` per poll — utilization, VRAM,
    temperature, power, fan%, core/mem clocks; graceful fallback when the
    driver or binary is missing.
  - Intel: pure sysfs (no extra tools/root) — busy% from the GT idle/RC6
    residency delta, clocks from i915 `rps_*` / xe `freq0/*` nodes, hwmon
    temps/power; VRAM shown as "shared (system RAM)".
- Static GPU identity is now pinned to the selected card: `lspci` matches that
  GPU's vendor/device IDs, so multi-GPU systems report the right model.

## [0.1.0] - 2026-09-06

### Added

- **Mission Center-style system monitor dialog** (click the sysmon glyph):
  a fixed 940x640 layer-shell panel with a sidebar of resource pages —
  CPU / Memory / Disks / Network / GPU / Apps — and live cairo graphs.
  - CPU: per-thread multi-series graph + 2-column per-core list, load,
    processes/threads, uptime, current/max frequency, temperature.
  - Memory: RAM + swap graphs, used/available/buffers/cached, and a DIMM slot
    graphic (populated + size) from `dmidecode` via passwordless `sudo -n`
    (cached 24h).
  - Disks: clickable per-drive cards (NVMe/HDD/SSD/USB/reader glyphs); the
    usage/read/write/Total-I/O graphs track the selected drive (default = the
    system drive), per-device rates from `/proc/diskstats`.
  - Network: download/upload graphs + every interface with type glyph, IP and
    live down/up rates.
  - GPU: usage/VRAM graphs, temps/power/fan/clocks (AMD at this point).
  - Apps: top processes by CPU%.
- **Passwordless sudo for the bar** — `setup-sudoers.sh` installs
  `/etc/sudoers.d/hyprtk-bar` (visudo-validated) so the DIMM readout never
  prompts; wired into `1-install.sh` in the merged installer.
- **GPU identity + live clocks** — model/manufacturer/CUs/max-clock via
  `rocminfo` (lspci fallback), cached to `~/.cache/hyprtk-bar/gpu.json`.
- **Package-update indicator module** (`updates`) — glyph + count from the
  installer's `updates.sh`, 60s poll, green/yellow/red thresholds, click opens
  the installer in a floating terminal.
- **Tray DBusMenu positioning** — tray menus anchor to the tray button
  (bar-edge aware) instead of center-screen; applet pixmaps are scaled to the
  icon size (fixes oversized Whatsie icon + a right-click segfault).

### Changed

- Notification center keeps history when toasts close/dismiss (badge clears,
  entries stay for the center); per-row dismiss and Clear all.
- Toasts float from the bar edge (below a top bar / above a bottom bar),
  centered horizontally; the notification daemon reclaims
  `org.freedesktop.Notifications` from competing daemons (`dunst` dropped from
  the kill list).
- Workspaces cluster is truly centered on the bar (homogeneous pill sections).

## [0.1.0] - 2026-09-04

### Added

- **Module icons as Nerd Font glyphs** — shared `Glyph` widget rendered with
  `Symbols Nerd Font` at pixel-accurate size (absolute Pango size), colorized
  with the pywal accent; quicklink glyphs get a configurable color.
- **Quicklinks module** — launcher buttons (apps menu, terminal, file manager,
  web, wallpaper, cliphist, screenshot) with per-button left/right/middle
  commands; empty command resolves the default browser via `xdg-settings`.
- **Keyboard-state module** (`kbstate`) — Caps/Num lock icons polling sysfs LED
  brightness, accent when on, dimmed when off.
- **Themed popup tooltips** on all bar modules (glass `.popup-box`).
- **Quick settings Mic slider** under Volume (`wpctl @DEFAULT_AUDIO_SOURCE@`).
- **Tasklist** — running/active dot on the icon corner (distinct colors),
  right-click a running app to pin/unpin (asks generic symbolic vs actual
  icon), pinned-class matching to running classes, phantom-pinned fix.
- **gap_in / gap_out** replace `margin` — layer height + exclusive zone =
  height + gap_in + gap_out; zero is a valid gap; settings control.
- **Active-window module** — true fixed width so titles never shift neighbors.
- **Clock date hover popup** + calendar; notification badge overlay (numbered
  dot, no bar resize); notification center no longer auto-hides.
- **Multi-monitor bars** — `monitors: primary | all | [names]`, one bar per
  monitor sharing a single HyprIPC, per-monitor active workspace.
- **DBusMenu tray menus** — native `com.canonical.dbusmenu` rendering for SNI
  items (verified against blueman / nm-applet).
- **Built-in notification center** — `org.freedesktop.Notifications` daemon
  (toasts + bell with unread badge + center with actions and Clear all).
- **Imported theme mapping** — waybar themes import border/spacing/padding/
  radius/colors/background alpha/fonts/chip styling, track live pywal colors,
  and apply to popups + right-click menu.
- **Settings window** — frameless floating draggable window (Hyprland rule
  floats+centers it): tabbed Bar/Fonts/Themes/Modules; width as a percentage,
  height, align, position, opacity, gaps, font picker (FontButton) + size +
  icon sizes, theme source + import, per-module show/position/order.
- **Start button** home icon + left spacing; single-instance flock; reload
  config restarts the bar.

### Changed

- Removed the show-desktop strip (not working as designed).
- `hyprtk-*` themes match the pywal theme's font; module icons scale with the
  font; bar border is 2px in the pywal accent.
- Rofi variant syncs to the bar theme on every re-theme.

## [0.1.0] - 2026-09-03

Initial release. A Windows 11-style taskbar for Hyprland (GTK3 +
gtk-layer-shell).

### Added

- Fully modular bar: modules arranged across left/center/right sections,
  show/hide/reorder from the settings window.
- Task list (pinned + running grouped by class, click to focus/minimize,
  middle-click to close, hover window-title preview popup), workspace chips,
  clock + calendar, sysmon (CPU/RAM/disk), quick settings flyout, SNI system
  tray, show-desktop strip.
- Live pywal16 theming (re-themes instantly on wallpaper change); theming
  sources: pywal / imported waybar theme / manual config.
- Layer-shell surface with exclusive zone, input shape (only the pill is
  clickable), per-monitor bars.
- `install.sh` (install / uninstall) to `~/.local/share/hyprtk-bar/` and
  `~/.local/bin/hyprtk-bar`; `--print-config`; single-instance lock.