# GTK3 → GTK4 migration plan

**Status:** planning (not started)
**Owner:** hyprtk (Kori Tk)
**Scope:** *everything GTK3 we own* — `hyprtk-bar` and `hyprtk-usb`
  (GUI), plus the `hyprtk-multi-distro` installer, vendoring, theming and test
  plumbing that carries them.
**Out of scope:** third-party GTK3 applications the distro installs for us
  (Thunar, Mousepad, `swappy`, `nwg-look`, xfce4, `gvfs`); they keep needing the
  GTK3 runtime regardless, so GTK3 does **not** leave the system.

Measured against this box: GTK 4.22.5, gtk4-layer-shell 1.3.0, PyGObject 3.56.3.

---

## 1. Inventory — every GTK3 consumer

| # | Consumer | Kind | Owner | Migrate? |
|---|----------|------|-------|----------|
| 1 | `hyprtk-bar` (`src/hyprtk_bar/`, 41 modules, ~25,300 LOC) | GTK3 app | us | **yes** |
| 2 | `hyprtk-usb-gui` (`installer/hyprtk-usb/hyprtk_usb/gui.py`, ~480 LOC) | GTK3 app | us | **yes** |
| 3 | `configs/gtk/gtk-3.0/` (`settings.ini`, `bookmarks`) | config | us | keep (third-party GTK3 apps) |
| 4 | `configs/gtk/gtk-4.0/` (`settings.ini`) | config | us | already present |
| 5 | `configs/root/.local/share/themes/Kripton-v40/` (gtk-2.0, gtk-3.0, **gtk-4.0**) | theme | us | already has GTK4 |
| 6 | `installer/scripts/gengtk.sh` (oomox → GTK2/3 theme + `~/.gtkrc-2.0`) | theming | us | keep/verify GTK4 |
| 7 | `matuwall` | GTK4 app | third-party | already GTK4 |
| 8 | Thunar, Mousepad, `swappy`, `nwg-look`, xfce4, `gvfs` | GTK3 apps | third-party | no (GTK3 runtime stays) |
| 9 | `hyprtk-bar` vendored copy at `hyprtk-multi-distro/installer/hyprtk-bar/` | vendored tree | us | follows #1 byte-identically |

Only #1 and #2 are code we port. Everything else is packaging, config or
third-party.

---

## 2. GTK3 → GTK4 API delta (measured in `hyprtk-bar`)

| GTK3 construct | count | GTK4 replacement | difficulty |
|---|---:|---|---|
| `.pack_start` / `.pack_end` | 591 / 20 | `Box.append` / `prepend` (order matters) | mechanical |
| `get_style_context().add_class/remove_class` | 298 / 309 / 30 | `add_css_class` / `remove_css_class` | mechanical |
| `.show_all()` | 57 | removed — visible by default; use `set_visible` | mechanical |
| `.destroy()` | 42 | widget destroy gone; unparent / `Window.destroy` | mechanical |
| `.add(child)` | 131 | `set_child` (window) / `append` (box) | mechanical |
| `Gtk.Menu` + `MenuItem`/`CheckMenuItem`/`SeparatorMenuItem`/`ImageMenuItem` | ~30 | **removed** → `Gtk.PopoverMenu` + `GMenu` | **hard** |
| `.new_from_pixbuf` etc. | 34 | `Gtk.Image.new_from_pixbuf` still exists; `IconTheme` API changed | low |
| `Gdk.Screen.get_default()` / monitor geometry | 10 | `Gdk.Display` + `Gdk.Monitor` | low |
| `Gtk.EventBox` | 9 | removed — input via controllers, layout via `Box`/`Grid` | medium |
| `size-allocate` signal, `get_allocated_*`, `do_get_preferred_width` | ~25 | `measure`/`allocate` vfuncs, `get_width/get_height` | **hard** |
| `x_root`/`y_root`/`event.button` + `add_events`/`EventMask` | ~40 | `Gtk.GestureClick` / `GestureDrag` | medium |
| per-widget `get_style_context().add_provider` | 8 | display-level providers only | medium |
| `Gtk.StyleContext.add_provider_for_screen` | 5 | `add_provider_for_display` | mechanical |
| `.get_window()` + `input_shape_combine_region` | 5 + 3 | `get_native()` / surface; input region API changed | **hard** |
| `DrawingArea` `"draw"` signal | 3 | `set_draw_func` | low |
| **`Gtk.main()` / `Gtk.main_quit()`** | 5 sites | **removed** → `Gtk.Application` or `GLib.MainLoop` | **hard** |
| `GtkLayerShell` (0.1) | 7 modules | `Gtk4LayerShell` (1.0) — same API | low |

The `pack_start`/`add_class`/`show_all`/`add` bulk (~75% of the diff) is
mechanical and should be a compatibility shim plus scripted sweeps. The real
engineering is: **application lifecycle, custom layout/measure, menus, popovers,
input/gesture handling, and CSS.**

---

## 3. Structural changes (the hard parts)

### 3.1 Application lifecycle — `Gtk.main()` is gone

`__main__.py` is built as a plain `Gtk.main()` loop
(`__main__.py:254`, `bar_settings.py:2294/2456`, `bar.py:438`,
`quicklinks.py:121`). GTK4 removes `gtk_main`/`gtk_main_quit`.

Two options:

- **A (recommended): `Gtk.Application` + `Gtk.Application.run()`.**
  Windows become app-owned; `BarWindow`, `MenuWindow`, `ArcMenuWindow`,
  `Popup`, `DesktopWidgetWindow` become `Gtk.ApplicationWindow` (or are added
  to the app). Cleanest, gives proper `GApplication` D-Bus single-instance, and
  the bar already does its own `flock` single-instance dance that could be
  retired. Caveat: the bar currently builds every surface *before* running the
  loop; app-based startup must move construction into `activate` or
  `startup`/`hold`.
- **B: `GLib.MainLoop()`** — smallest diff: replace `Gtk.main()` with
  `GLib.MainLoop().run()`, `Gtk.main_quit()` with `loop.quit()`. Keeps raw
  `Gtk.Window`s. Less idiomatic but lower risk for a headless-ish layer-shell
  app that manages its own lifetime.

Recommend **B for the first cut** (unblocks the rest of the port with minimal
structural risk), with **A as a follow-up** cleanup if desired.

### 3.2 Custom layout / measure

`bar.py` (`ClipBox.do_get_preferred_width`, `get_allocated_width` at
`:224/240`, `_on_bar_size_allocate` at `:176`), `window.py`
(`do_get_preferred_width:55`), `desktop/base.py` (`_apply_geometry`,
`get_preferred_size`, `input_shape_combine_region:410`) implement manual
sizing/allocation. GTK4:
- vfuncs become `do_measure(orientation, for_size)` and
  `do_size_allocate(width, height, baseline)`.
- `get_allocated_width()` → `get_width()` (post-allocation).
- `size-allocate` signal → use `measure`/`allocate` or `notify::width/height`;
  the sizing loops in `bar.py` and `desktop/base.py` need re-validation (the
  0.3.1 changelog already had a `size-allocate` re-entrancy geometry-loop bug,
  so this code is delicate).

### 3.3 Menus — `Gtk.Menu` is deleted

Three menu systems:
- `dbusmenu.py` (10 refs) — renders SNI `com.canonical.dbusmenu` layouts as
  `Gtk.Menu` with nested submenus, checks, images. **Rewrite** onto
  `Gtk.PopoverMenu` + `GMenu`/`GMenuItem` (or a custom popover list). This is
  the single biggest isolated rewrite.
- `tray.py:592+` — SNI + StatusNotifier item click → dbusmenu popup.
- `bar_menu.py` (5 refs) and `tasklist.py:274` (4 refs) — simple context menus
  → `GMenu`/`PopoverMenu` or `Popover` with a listbox.

Note a GTK4-specific gotcha: `gtk_popover_set_position` and `menu`-style
popovers behave differently on Wayland, and layer-shell surfaces + popovers are
separate surfaces. The existing `popup.py` (415 lines) already exists purely
because *"Gtk.Popover is unusable near screen edges in GTK3/Wayland"*
(`popup.py:3`). GTK4 does not automatically fix this; the workaround likely
needs to be kept (ported) and re-tuned, not deleted.

### 3.4 Input & gestures

~40 sites read `event.button` / `event.x_root` / `event.y_root` and use
`add_events`/`EventMask` (`menu_window.py:1429` resize grip, `bar_settings.py:258`
drag, `themer.py:1238` double-click, `tasklist.py`, `quicklinks.py`,
`workspaces.py`, `clock.py`, `sysmon.py`, `updates.py`, `arcmenu.py`, `bar.py`).
Replace with `Gtk.GestureClick` (buttons + double-click), `Gtk.GestureDrag`
(the window-move/resize grips), and `Gtk.EventControllerMotion`. Coordinates
come from the gesture's current event, not a `GdkEvent`.

### 3.5 Theming / CSS

`themer.py` (2,426 lines) + `theme.py` (726) + `menu/theme.py` +
`desktop/theme.py` generate and load large CSS blobs, plus 8 per-widget
providers and 5 screen-level providers. GTK4 CSS is *not* source-compatible
with GTK3:
- node names and some selectors changed (e.g. `decoration`, `window.background`,
  header bars, popovers);
- several CSS properties were dropped or renamed;
- per-widget `add_provider` is gone → providers must be registered on the
  `Gdk.Display` (scoped by class).
Expect a non-trivial **styling retune** across all bar containers, popups,
menus and desktop widgets — visual regressions are the most likely
"functional but wrong" outcome, so the Showcase screenshots
(`SHOWCASE.md`) become a regression baseline.

### 3.6 Layer shell

`GtkLayerShell` (typelib `GtkLayerShell-0.1`) → `Gtk4LayerShell` (typelib
`Gtk4LayerShell-1.0`). Same C API (`init_for_window`, `set_layer`,
`set_anchor`, `set_margin`, `auto_exclusive_zone_enable`, `set_keyboard_mode`,
`set_namespace`, `set_monitor`), same enums; mostly a `require_version` +
import-alias sweep across the 7 files. Verified present on this box.

**Packaging caveat (important):** `gtk4-layer-shell` must be built with
introspection enabled for the GI typelib to exist. `hyprtk-multi-distro`
currently builds it with `-Dintrospection=false`
(`installer/scripts/srcapps-install.sh:175`) because only `matuwall` used it
via `LD_PRELOAD`. A PyGObject GTK4 bar **requires the typelib**, so that flag
must become `-Dintrospection=true` (and the `.typelib`/`.gir` install paths
verified) on distros that don't package it.

---

## 4. `hyprtk-bar` module plan

Per-module GTK3 weight (highest first) — use as the work order:

| Module | pack | css | show_all | add | menus | eventbox | Gdk.Screen |
|---|---:|---:|---:|---:|---:|---:|---:|
| `bar_settings.py` | 198 | 27 | 7 | 20 | 0 | 2 | 0 |
| `themer.py` | 95 | 29 | 8 | 16 | 0 | 0 | 0 |
| `monitor.py` | 89 | 54 | 5 | 33 | 0 | 1 | 0 |
| `menu/menu_window.py` | 72 | 127 | 10 | 36 | 0 | 2 | 2 |
| `notifications.py` | 24 | 13 | 3 | 3 | 0 | 0 | 1 |
| `quicksettings.py` | 15 | 3 | 2 | 1 | 0 | 1 | 0 |
| `desktop/*` (10 files) | ~65 | ~15 | 2 | 1 | 0 | 0 | 1 |
| `tasklist.py` | 11 | 5 | 3 | 1 | 4 | 0 | 0 |
| `clipboard.py` | 7 | 8 | 2 | 4 | 0 | 0 | 0 |
| `bar_menu.py` | 5 | 7 | 1 | 1 | 5 | 0 | 0 |
| `bar.py` (layout engine) | 4 | 1 | 2 | 1 | 0 | 1 | 0 |
| `tray.py` + `dbusmenu.py` | 2 | 1 | 2 | 0 | 12 | 0 | 1 |
| `popup.py` | 1 | 2 | 3 | 1 | 0 | 0 | 2 |
| rest (`app/window/layout/graphs/widgets/…`) | ~10 | ~10 | ~3 | ~10 | 0 | 2 | 0 |

Suggested order (each a phase, each shippable to a branch):

1. **Foundation** — `compat.py` shim; `require_version` sweep
   (`Gtk 4.0`, `Gdk 4.0`, `Gtk4LayerShell 1.0`); lifecycle (§3.1); providers
   (§3.5). Get a blank layer-shell bar to appear.
2. **Shell** — `window.py`, `app.py`, `bar.py`, `layout.py` (measure/allocate
   port), `widgets.py`.
3. **Simple modules** — `workspaces.py`, `clock.py`, `kbstate.py`,
   `sysmon.py`, `updates.py`, `graphs.py` (draw func), `quicklinks.py`,
   `quicklinks` + `clock` popups.
4. **Desktop widgets** — `desktop/base.py` first (measure/input/shape), then
   `clock/weather/disk/network/sysinfo/visualizer/sampled/resources/manager`
   (DrawingArea → `set_draw_func`).
5. **Complex modules** — `tasklist.py`, `notifications.py`,
   `quicksettings.py`, `clipboard.py`, `arcmenu.py`, `bar_settings.py`,
   `themer.py`, `theme_import.py`, `monitor.py`, `menu/menu_window.py`.
6. **Menus (isolated rewrite)** — `dbusmenu.py`, `tray.py`, `bar_menu.py`,
   `tasklist.py` context menu → popover/GMenu.
7. **Popover** — port and re-tune `popup.py` for GTK4/layer-shell.
8. **CSS retune** — `themer.py` + `theme.py` + `menu/theme.py` +
   `desktop/theme.py`; diff against `SHOWCASE.md` screenshots.

A `compat.py` shim (e.g. `box_append(box, child)`, `add_class(w, c)`,
`screens()`) lets the bulk sweeps land early and keeps the diff reviewable.

---

## 5. `hyprtk-usb-gui` module plan — DONE (2026-10-01)

Small (~480 LOC, 56 GTK refs) and self-contained. **Ported** (see P7 below);
as-built notes in brackets:

- `Gtk.Application` + `Gtk.ApplicationWindow` already used → lifecycle is fine.
- `Gtk.Box` fine; `row.add_events(Gdk.EventMask…)` + button handler →
  `GestureClick` (one site). *[As built: a `Gtk.WindowHandle` wraps the header
  and drags the toplevel — GTK4 also removed `Gtk.Window.begin_move_drag`, so
  the gesture route would not have moved a Wayland window.]*
- `Gtk.CssProvider` / `add_provider_for_screen(Gdk.Screen)` → display-based
  provider (one site).
- `Gtk.ComboBoxText` (3), `Gtk.Switch` (2), `Gtk.ProgressBar`, `Gtk.FileFilter`
  all survive; `Gtk.FileChooserDialog` + `dlg.run()` → `Gtk.FileDialog` async
  (or `FileChooserNative`) because `Dialog.run()` is removed in GTK4.
  *[As built: kept `Gtk.FileChooserDialog` (exists since GTK 4.0 and through
  4.22; `Gtk.FileDialog` is 4.10+, which would break Debian 12 / Ubuntu 22.04),
  driven by its `response` signal with `get_file()` — `FileChooser.get_filename`
  is gone.]*
- `Gtk.MessageDialog`/`ResponseType` (if used in the write/confirm flow) →
  `Gtk.AlertDialog` or a custom `Window`. *[Not used.]*

This is a **1–2 session** port once the patterns from the bar exist; it can
share the same `compat.py` idioms. (`hyprtk-usb` has no `compat.py`; the port is
plain GTK4, no GTK3 fallback, matching the bar's 0.4.x state.)

---

## 6. GTK theme / config assets

- `configs/gtk/gtk-4.0/settings.ini` and the Kripton-v40 `gtk-4.0/` variant
  already exist — no new theme work required beyond verifying the Kripton GTK4
  CSS covers the widgets the ported apps use.
- `configs/gtk/gtk-3.0/` **stays** (third-party GTK3 apps).
- `installer/scripts/gengtk.sh` writes `~/.gtkrc-2.0` and an oomox GTK2/3
  theme; check that oomox's GTK4 output (if enabled) is used, or note GTK2 as
  legacy. Not a blocker for the app ports.

---

## 7. `hyprtk-multi-distro` installer / packaging

### 7.1 Dependencies (keep GTK3, add GTK4)

The dotfiles must ship **both** GTK3 (third-party apps) and GTK4 (our apps).
Add a GTK4 typelib + `Gtk4LayerShell-1.0` GI typelib to the relevant profiles:

| Family | GTK4 typelib to add | gtk4-layer-shell typelib |
|--------|--------------------|--------------------------|
| pacman | `gtk4` (already in `hypr/packages/hyprland.sh`) | `gtk4-layer-shell` (already there; ships GI) |
| apt | `gir1.2-gtk-4.0` (**missing today**; only `libgtk-4-1` listed) | not in archive ≤24.04 → source build with introspection |
| dnf | `gtk4` (already) | `gtk4-layer-shell` |
| zypper | `typelib-1_0-Gtk-4_0` / `gtk4` | `gtk4-layer-shell` |
| xbps | `gtk4`/`-devel` typelibs | `gtk4-layer-shell` or source |
| apk | `gtk4.0`/`gtk4.0-dev` | source build with introspection |
| nix | `gtk4` | `gtk4-layer-shell` |

- The bar's own `install.sh` `DEPS[...]` (`install.sh:115–124`) must switch the
  GTK/layer-shell entries from GTK3 to GTK4 **and** add the GTK4 layer-shell
  typelib. Its **self-test** (`install.sh:611`) changes to
  `require_version("Gtk","4.0")` + `require_version("Gtk4LayerShell","1.0")`,
  and `deps_ok()` / `layer_shell_version()` / the `xlib-2.0` note
  (`install.sh:170–188`) need equivalents for GTK4.
- **Version floor:** pin a gtk4-layer-shell floor (v1.1+ recommended; the box
  has 1.3.0) and keep the source-build fallback pattern already used for
  GTK3.
- `PORTABILITY.md` typelib/matrix tables and `README.md` Requirements section
  update from “GTK3” to “GTK4 (and GTK3 for third-party apps)”.

### 7.2 `srcapps-install.sh`

- Flip the `gtk4-layer-shell` build to `-Dintrospection=true` (drop
  `-Dintrospection=false` at `installer/scripts/srcapps-install.sh:175`) and
  confirm the typelib lands where `GI_TYPELIB_PATH` finds it.
- `have_gtk4_layer_shell` currently only checks the shared library
  (`:121`); add a typelib check so the bar's import can't silently break.

### 7.3 Vendoring

- Port in the `hyprtk-bar` repo, then vendor **byte-identically** into
  `hyprtk-multi-distro/installer/hyprtk-bar/` (the promotion gate asserts this).
- `1-install.sh` already invokes `installer/hyprtk-bar/install.sh`
  (`1-install.sh:1013`) and `installer/hyprtk-usb/install.sh` (`:1018`); no
  call-site change, only the deps inside.

### 7.4 Nix

- `hyprtk-bar/derivation.nix`: `gtk3` → `gtk4`,
  `gtk-layer-shell` → `gtk4-layer-shell`, `wrapGAppsHook` → the GTK4 wrap hook
  (`wrapGAppsHook4`/`wrapGAppsNoGuiHook` as nixpkgs versions dictate), and
  `flake.nix` devShell likewise.
- Add `gtk4` + `gtk4-layer-shell` to the devShell inputs.

### 7.5 Tests / gates

The promotion gate (`promote-to-prod.md` step 1) must stay green through the
migration:

- **T1** `installer/scripts/verify/container-matrix.sh` — the new GTK4
  package names resolve; add `gtk4-layer-shell` GI gaps to
  `container-matrix.allow` with reasons where unavoidable.
- **T2** `installer/scripts/verify/container-dryrun.sh`.
- `package-audit.sh` → `output.html` (0 Extra/0 Unexpected).
- `hyprtk-bar/.github/workflows/install-matrix.yml` — extend the self-test to
  import GTK4 + `Gtk4LayerShell` and, ideally, add a headless smoke launch.
- **Bar has no automated tests** (`find` found none). Before a port this big,
  add a minimal smoke layer: import-all-modules, construct the bar headless
  under `xvfb`/`WAYLAND_DISPLAY` stub where possible, and a screenshot diff
  against `SHOWCASE.md`.
- VM end-to-end install on fedora + openSUSE (and Void/Alpine if touched).

---

## 8. Sync / release workflow

Stay inside the existing rules:

- All port work in `hyprtk-bar` (own repo) and `hyprtk-multi-distro`.
- Vendor the bar into multi-distro byte-identically once the port is on the
  bar's `main`.
- Publish via the routine **dev publish** (`multi-distro → my-dots`); promote
  only on the explicit **"promote to prod"** (which carries the vendored bar
  into merged/live/dotfiles).
- Never hand-edit merged/live.

---

## 9. Phased plan & milestones

| Phase | Deliverable | Exit criteria |
|-------|-------------|---------------|
| P0 | Branch `gtk4`; `compat.py`; version sweep; lifecycle | blank layer-shell bar appears under Hyprland |
| P1 | Shell (`window/app/bar/layout/widgets`) | bar renders, anchors, no measure loops |
| P2 | Simple modules + desktop widgets | workspaces/clock/sysmon/graphs/widgets work |
| P3 | Complex modules | tasklist, notifications, quick settings, clipboard, arc menu, monitor, settings |
| P4 | Menus rewrite (`dbusmenu`/`tray`/`bar_menu`) | SNI menus + nested/check items work |
| P5 | `popup.py` port + CSS retune | visual parity vs `SHOWCASE.md` |
| P6 | Landing: installer deps, Nix, vendor, docs | T1/T2/audit green; VM install passes |
| P7 | `hyprtk-usb-gui` port (can run parallel to P2+) — **DONE 2026-10-01** | GUI flows work on GTK4 |
| P8 | Release | CHANGELOG + bar version bump + tag on dev repo |

Rollback: the GTK3 `main` stays untouched until parity; the installer keeps
installing GTK3 until the GTK4 branch is vendored. **No distro loses the bar
mid-migration.**

---

## 10. Risks

1. **CSS/visual regressions** — highest-probability “works but wrong” outcome;
   mitigate with `SHOWCASE.md` baseline screenshots.
2. **Menu rewrite** (`dbusmenu.py`) — `Gtk.Menu` is deleted; `GMenu`/popover
   semantics (nested submenus, radio/check, icons, D-Bus `Event` dispatch) must
   be re-mapped carefully.
3. **Layer-shell + GTK4 popovers** — popovers are separate Wayland surfaces;
   the existing edge/popup workaround may need re-engineering.
4. **Custom measure/allocate** — re-entrancy/geometry loops already bit once
   (0.3.1); port incrementally with live testing.
5. **Cross-distro typelib availability** — GTK4 GI + `Gtk4LayerShell-1.0` are
   the new install frontier; the source-build introspection flip is mandatory
   on apt ≤24.04 and Alpine.
6. **`Gtk.main()` removal** — touches every entry point (bar, settings dialogs).
7. **Two apps + vendoring + Nix** mean the change surface spans three repos
   (bar, usb, multi-distro) plus release gates.
8. **GTK4 still evolving** — target a floor (4.10+ for `ColorDialog`/
   `AlertDialog`, 4.12+/4.14+ for stable popover/texture APIs); older LTS
   distros may need a newer GTK4 or won't be supportable for the GTK4 bar.

---

## 11. Effort estimate

- **Mechanical bulk** (`pack`, css classes, `show_all`, `add`, version sweep,
  providers, layer-shell rename): ~60–70% of the raw diff; a few focused days
  with a shim and scripted sweeps.
- **Lifecycle + measure/layout + input**: ~1–2 weeks.
- **Menus (`dbusmenu`/tray) rewrite**: ~1–2 weeks (the true unknown).
- **Popover + CSS retune to visual parity**: ~1–2 weeks.
- **`hyprtk-usb-gui`**: ~1–2 sessions.
- **Installer / Nix / vendor / docs / gates**: ~1 week.
- **Total (bar + usb + multi-distro)**: order of **6–10 focused weeks** for
  one person, with the menu rewrite and CSS retune as the schedule risk.

---

## 12. Open questions

1. Target GTK4 floor — 4.10 / 4.12 / 4.14? Determines which LTS distros can
   run the GTK4 bar at all.
2. Is `hyprtk-usb-gui` ported in the same release, or a follow-up?
3. Keep the raw-`GLib.MainLoop` lifecycle (§3.1 option B) or move to
   `Gtk.Application` (A)? A enables clean single-instancing but is a bigger
   refactor.
4. Do we keep a GTK3 fallback path in the installer during the transition, or
   hard-cut once parity lands?
5. Should the bar gain a real test harness (screenshot diff / headless smoke)
   as a prerequisite, given there are currently zero tests?

---

## 13. Options considered

- **Stay on GTK3** — viable (GTK3 ships everywhere and will for years), zero
  work. Rejected only because the goal is forward-looking GTK4 parity.
- **Port to another toolkit** (Qt/Adwaita/`relm4`/webview) — larger rewrite,
  loses the existing layer-shell + pywal theming investment. Rejected.
- **Incremental GTK4 via a fork** — not possible to run GTK3 and GTK4 in one
  process; must be a branch-and-swap, which is the plan above.
