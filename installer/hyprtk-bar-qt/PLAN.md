# hyprtk-bar-qt — Parity Remediation Plan

Source: static audit of `hyprtk-bar-qt` vs the reference GTK4 bar
(`../hyprtk-bar/`). Created 2026-10-08. This is the record of what is
non-functional / missing and the order in which it is being fixed.

Method: read every QML surface/module/component, every backend module, `bin/`,
`install.sh`; map against the GTK bar's `bar.py`, `bar_settings.py`,
`themer.py`, `desktop/*`, `menu/*`, `notifications.py`, `tray.py`, `ipc.py`,
`hypr_animations.py`, and the `tools/e2e` coverage. Claims in `PARITY.md` /
`CHANGELOG.md` were treated as unverified until the code confirmed them.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done

---

## Batch 1 — Install correctness & hygiene  ✅ done

- [x] `install.sh` no-rsync fallback now copies the full runtime tree
      (`surface/`, `components/`, `config/`, `data/`, `state/` were missing) and
      prunes `__pycache__`.
- [x] `install.sh` links every `bin/*` helper into `~/.local/bin`.
- [x] Version aligned: `__init__.py __version__` 0.27.0 → 0.30.0.
- [x] Dead code purged: `palette.py` (+ its 75 lines), `config.load_config()/get()`,
      unused `config`/`sys` imports in `wallpapers.py`, `UiState.closeAll()`,
      `Themer.col()/lockColors()/swatchNames`; CHANGELOG's phantom `arc_toggle.py`
      corrected to `signal_bridge.py`.
- [x] Stale comments updated (`data/Widgets.qml`, `surface/DesktopWidgets.qml`,
      `surface/Themer.qml`).
- [x] `Settings.qml onExited` now warns on non-zero write exit.
- [x] Nerd-Font glyphs pinned in `SysMonitor`, `QuickSettings`, `Themer`,
      `StartMenu`.

## Batch 2 — Dead settings wiring  ✅ done

- [x] A1 start-button Enabled now writes/reads `center.start_button` (new
      `Settings.moduleEnabledKey`), and `StartButton.qml` gates on it.
- [x] A2 `font.icon_size` honoured via new `BarConfig.iconSize()` (matches GTK
      `icon_size_for`); applied to `BarIconButton` + Net/KbState/SysMonitor glyphs.
- [x] A3 "UI animations" toggle now calls `Config.save()` — persists.
- [x] A4 dead Qt geometry keys removed from `config/Config.qml` + `_keys`
      (shared `BarConfig` is authoritative; only `opacity` override remains).
- [x] A5 `Config.menuLayout`, `Config.sysmonMonitor` removed.
- [x] A6 `use_pywal` honoured by `Theme.qml` (legacy seed of `theme.source`);
      redundant `BarConfig.usePywal` removed.
- [x] A9 Settings hint corrected (Low/High are presets; real Hyprland-follow in
      Batch 6).

## Batch 3 — Anchors & multi-monitor  ✅ done

- [x] A7 `BarMenu` + notification toasts now honour `barPosition` (anchor to the
      bar's edge, top or bottom) instead of hardcoding top.
- [x] A14 desktop widgets place on the focused monitor captured at startup
      (matches GTK `manager.py`, which uses the focused monitor; GTK itself does
      not do per-display widgets — that stays on GTK's roadmap).
- [x] A15 new `data/Screens.qml` (name→ShellScreen + focused monitor). Bar
      modules register their monitor (`BarAnchors`); popups set `screen:` to the
      clicked monitor (bell/QS/start/menu) or the focused monitor on open
      (SysMonitor/Clipboard/Settings/Themer/About/toasts).
- [x] A16 Tasklist restores a window from a negative-id (special/minimized)
      workspace before focusing it (GTK `tasklist.py:576`).

## Batch 4 — Settings parity UI  ✅ done

- [x] Widgets page rebuilt: per widget — layer, margin X/Y, width/height,
      radius, padding, scale, snap group/axis/order, colours, plus widget-specific
      options (clock, weather, visualizer, disk, network, resources, sysinfo)
      in wrapping `Flow` rows.
- [x] Menu page: `enabled`, `follow_bar`, `gap_in`, `gap_out` added; `MenuConfig`
      exposes enabled/followBar and `StartMenu` gates + centres when not following.
- [x] Modules page: up/down reorder (`moveModule`) + section radios retained.
- [x] Fonts page: installed-font picker (`Qt.fontFamilies()`).
- [x] Themes page: `imported` source + installed-theme picker; `setTheme()`
      keeps the shared `theme` block and the Qt `Config` override in sync (A13).
- [x] Per-module option editors added to the Modules page (workspaces, clock,
      updates, window, tray, notifications).
- [x] Arc-item editor: `action` field (settings/themer/clipboard).
- [x] Menu favourites: `addFavorite()` wired to a field + Add button.

## Batch 5 — Widget parity  ✅ done

- [x] Clock widget: theme-file loading (user dir, widget block wins),
      `show_seconds` (precision + hand/ring), `dial_count` (1 face or 3 H/M/S
      rings), `ring_thickness`.
- [x] Visualizer widget: `source` (backend `--source` auto/cava/synthetic),
      `sensitivity`, `smoothing` (temporal), `orientation` (up/down), `peak_dots`.
- [x] Widget global border (`widgets.border`) wired in `WidgetFrame` + a master
      toggle in Settings.
- [x] QuickSettings brightness falls back to `hyprctl hyprsunset gamma` (min 30%)
      when there is no kernel backlight.
- [x] QuickSettings Lock uses `MenuConfig.power("lock")`, not a hardcoded command.
- [x] Quicklinks glyph-font fallback → `BarConfig.glyphFont`.

## Batch 6 — Missing features  ✅ done (MPRIS deferred)

- [x] `hypr_animations` ported to `backend/.../hypr_animations.py` (+ tests); new
      `data/HyprAnim.qml` feeds `Bar.qml`'s `borderMs`, so low/high follow the
      real Hyprland animation files. Settings hint restored.
- [x] Notifications: toasts + center now render the app icon, image and action
      buttons (action `invoke()`); toasts gained a close button.
- [x] Themer persists Qt-config edits without Save (A12): apply/clear theme,
      wallpaper dir, opacity (debounced).
- [x] SDDM/GRUB updater path resolved from the live tree instead of a hardcoded
      `~/hyprtk/configs/sddm/update.sh` (A23); errors surfaced if not found.
- [x] MPRIS media control — **optional extra** (the reference GTK bar ships none).
      Implemented as the `media` bar module (`bar/modules/Media.qml`) on Quickshell's
      MPRIS service, with a Settings Modules-page editor. See CHANGELOG 0.34.0.

## Batch 7 — Verification  ✅ done

- [x] `PARITY.md` updated row-by-row (clock, menu, settings pages, widgets,
      theming, `hypr_animations`); "Next passes" now honest.
- [x] `make test` 88 passed; whole-tree `qmllint` clean; added
      `tests/test_hypr_animations.py`.
- [x] Live shell restarted several times; each surface exercised with `grim`
      captures (bar, Quick Settings, Settings Widgets/Modules pages, toast).
- [x] Independent re-audit subagent run; its remaining findings fixed here:
      - `clock.calendar` now gates the calendar popup.
      - top-level `gap_in` consumed (`shell.qml` exclusive zone).
      - bar-anchored popups (QuickSettings/NotificationCenter/Clipboard/SysMonitor/
        BarMenu/toasts/widgets) clear `barHeight + gap_in + gap_out`.
      - `menu.gap_in`/`menu.gap_out` consumed by the start menu (follow + screen
        -anchored branches, as GTK).
      - Bar right-click Lock uses `MenuConfig.power("lock")`.
      - ArcMenu opens on the focused monitor.
      - Dead code removed (`BarConfig.opacity`, `MenuConfig.maxRecents`,
        `Widgets.ids`/`activeIds`, `shell._width`, `Themer.lockVars`) and unused
        `QtQuick.Controls.Basic` / `../../config` imports dropped.
