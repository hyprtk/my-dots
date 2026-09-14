# Bundling — merging the external scripts into hyprtk-bar

Goal: make hyprtk-bar a **self-contained** app so it does not depend on the
`~/hyprtk` dotfiles tree (or third-party installs) for its feature scripts. This
document is the working plan; it is intentionally a **first-pass inventory** —
see "Not yet audited" at the bottom.

Two axes are involved:

1. **Scripts** — the `.sh` files the bar shells out to.
2. **Dependencies** — the external binaries those scripts (or the bar) call, and
   the on-disk assets they read.

"Incorporating" therefore means two things: (a) vendor the scripts into the bar,
(b) install the binaries via `install.sh` and repoint the hardcoded paths.

---

## Current inventory

Scripts now resolve **bundled-first** through `resolve_script()`
(`~/.local/share/hyprtk-bar/scripts/`), falling back to the `~/hyprtk` dotfiles
tree. Three surfaces reference them:

- **`themer.py` constants** (`HYPRTK = ~/hyprtk`, plus rofi / swaylock / matuwall /
  papirus / wallpaper paths).
- **`config.py` defaults** (quicklinks commands, `start_command`, `updates.script`).
- **`app.py`** (`ROFI_SYNC_SH`).

### Directly-called scripts (12)

| # | Script (resolved path) | Trigger | Category |
|---|------------------------|---------|----------|
| 1 | `~/hyprtk/installer/hyprtk-bar/scripts/wallpaper-colors.sh` | themer → wallpaper apply | B |
| 2 | `~/hyprtk/installer/hyprtk-bar/scripts/change-icons.sh` | themer → icons | B |
| 3 | `~/hyprtk/installer/hyprtk-bar/scripts/sync-rofi-theme.sh` | themer → rofi | A |
| 4 | (same file as #3, resolved bundled) | app.py → on re-theme | A |
| 5 | `~/hyprtk/configs/sddm/update.sh` | themer → SDDM & GRUB (pkexec) | C |
| 6 | `~/.local/share/icons/papirus-folders.sh` | themer → icons | D (third-party) |
| 7 | `~/hyprtk/installer/scripts/updates.sh` | updates module poll | C |
| 8 | `~/hyprtk/installer/scripts/installupdates.sh` | updates module click | C |
| 9 | `~/hyprtk/installer/hyprtk-bar/scripts/appsmenu.sh` | quicklinks → apps | A |
| 10 | `~/hyprtk/installer/hyprtk-bar/scripts/updatewal-awww.sh` | quicklinks → wallpaper (right-click) | B |
| 11 | (in-bar clipboard manager — no external script) | quicklinks → clipboard | A |
| 12 | `~/hyprtk/installer/scripts/ssdetect.sh` | quicklinks → screenshot | C |
| 13 | `~/hyprtk/installer/hyprtk-bar/scripts/hyprtk-bar-menu-toggle.sh` | start button (fallback) | A |

(13 call sites; #3 and #4 are the same underlying script.)

### Transitive scripts (called by the 12)

| Script | Called by |
|--------|-----------|
| `change-icons.sh` | wallpaper-colors.sh, updatewal-awww.sh |
| `papirus-folders.sh` | change-icons.sh |
| `screenshot.sh` (286 lines) | ssdetect.sh |
| `sshot.sh` | ssdetect.sh |
| `library.sh` (105 lines) | installupdates.sh (sources it) |
| `update-TS-run.sh` | installupdates.sh |

### Path / asset dependencies (read, not scripts)

| Path | Used by |
|------|---------|
| `~/hyprtk/assets/Wallpapers` | themer wallpaper dirs |
| `~/.config/rofi/variants/*.rasi` (10 variants) | themer rofi page + sync-rofi-theme |
| `~/.config/rofi/config-apps-menu.rasi` | appsmenu.sh |
| `~/.config/rofi/config-cliphist.rasi`, `config-short.rasi` | cliphist.sh |
| `~/.config/swaylock/config` | themer swaylock page (read/write) |
| `~/.config/matuwall/config.json` | themer matuwall page (read/write) |
| `~/.local/share/icons/Papirus-Dark` | change-icons.sh + themer icon previews |
| `~/.cache/wal/*` | pywal cache (colors.sh/colors.json/…), written by `wal` |
| `~/.cache/theme-gui/*` | thumbnail cache (shared with archived theme-gui) |
| `~/.config/hyprtk-bar/themes/` | imported-theme dir |

### Binary dependencies

| Binary | Package (Arch) | Needed for |
|--------|----------------|------------|
| `awww` | `awww` (AUR) | wallpaper set |
| `wal` | **bundled** (`vendor/pywal16`) | pywal colors |
| `rofi` | `rofi` | apps menu, clipboard |
| `cliphist` | `cliphist` | clipboard history |
| `wl-copy`/`wl-paste` | `wl-clipboard` | clipboard |
| `wob` | `wob` | volume OSD |
| `notify-send` | `libnotify` | update / icon notifications |
| `checkupdates` | `pacman-contrib` | updates module |
| `trizen` | AUR | updates module |
| `yay` | AUR | installupdates |
| `timeshift` | `timeshift` | installupdates snapshot |
| `nvidia-smi` | `nvidia-utils` | ssdetect GPU branch |
| `papirus-folders` | `papirus-folders` | folder colour |
| `papirus-icon-theme` | `papirus-icon-theme` | Papirus-Dark theme |
| `hyprctl` | (with hyprland) | compositor IPC |
| `sudo`/`pkexec` | `sudo`/`polkit` | SDDM/GRUB, DIMM, system kill |

> **`wal` is bundled.** pywal16 is vendored under `vendor/pywal16/` (MIT, see
> `vendor/pywal16/VENDOR.md`) and exposed by `install.sh` as `~/.local/bin/wal`
> (the real launcher is `venv/bin/wal`) — no `python-pywal16-git`/AUR/PyPI
> install is needed. `themer.py` and the bundled scripts resolve it
> bundled-first via `HYPRTK_WAL` → beside-install `../venv/bin/wal` →
> `~/.local/bin` → PATH.

---

## Categorisation

- **A — bundleable now** (self-contained or only need a binary + a small config):
  `sync-rofi-theme.sh`, `appsmenu.sh`, `cliphist.sh`, `hyprtk-bar-menu-toggle.sh`.
- **B — bundleable with binaries** (thin wrappers over `awww`/`wal`/`wob`):
  `wallpaper-colors.sh`, `updatewal-awww.sh`, `change-icons.sh`.
- **C — stay in dotfiles / optional integration** (system-level, root, or Arch/AUR):
  `sddm/update.sh`, `updates.sh`, `installupdates.sh`, `ssdetect.sh`.
- **D — third-party, install as dep**: `papirus-folders.sh`.

---

## Issues resolved during the merge

1. **`CHANGE_ICONS_SH` resolves bundled-first.** `themer.py` now prefers the
   bundled `change-icons.sh`, falling back to
   `~/hyprtk/assets/papirus-icons/scripts/change-icons.sh`.
2. **`sync-rofi-theme.sh` is a single bundled copy.** Both `themer.py` and
   `app.py` resolve it through `ROFI_SYNC_SH`; no duplicate `~/.config/rofi`
   path remains.
3. **`start_command` keeps the toggle script only as a fallback.** The bar
   toggles the in-process menu directly; the script serves the Hyprland
   keybinding.
4. **Quicklink/update defaults are bundled-first.** `config.py` resolves them via
   `resolve_script()` (`SCRIPTS_DIR`, i.e. `~/.local/share/hyprtk-bar/scripts/`),
   falling back to the `~/hyprtk` dotfiles tree — no hardcoded
   `~/hyprtk/installer/scripts/…` defaults.

---

## Plan

> **Status: complete.** Phases 1–4 are done; only the "Not yet audited" closure
> below remains as optional follow-up.

### Phase 1 — vendor the A + B scripts into the bar ✅
- Added `scripts/` to the repo; `install.sh` copies it to
  `~/.local/share/hyprtk-bar/scripts/`.
- Vendored `wallpaper-colors.sh`, `change-icons.sh`, `sync-rofi-theme.sh`,
  `appsmenu.sh`, `updatewal-awww.sh` (+ the 3 toggle scripts + rofi variants +
  `config-apps-menu.rasi` under `scripts/rofi/`). `cliphist.sh` was **replaced**
  by the in-bar clipboard manager rather than vendored.
- Repointed `themer.py` / `config.py` to resolve bundled scripts via
  `SCRIPTS_DIR` / `resolve_script()`, keeping `~/hyprtk` as a runtime fallback.

### Phase 2 — extend install.sh dependency install ✅
- `install.sh` now installs the feature binaries by default (`EXTRAS` map per
  package manager + `EXTRAS_AUR` for `papirus-folders` via yay/paru), with
  `--no-extras` to skip and `--no-deps` implying `--no-extras`.

### Phase 5 — vendored pywal16 (`wal`) ✅
- pywal16 (MIT) vendored under `vendor/pywal16/` (`VENDOR.md` records upstream,
  commit, and the update procedure); `install.sh` copies it into
  `~/.local/share/hyprtk-bar/vendor/pywal16/`.
- New `--wal-only` mode provisions just the vendor tree + venv + `wal` launcher
  and exits — the merged `1-install.sh` calls it early (replacing the old
  `yay -S python-pywal16-git`), before its pywal init steps and the late full
  bar install.
- `wal` launcher lives at `venv/bin/wal`; `~/.local/bin/wal` (and
  `/usr/local/bin/wal` when needed) symlink to it. Removed
  `python-pywal16-git` from `EXTRAS_AUR`.
- Bundled-first resolution: `proc.bootstrap_environment()` puts `~/.local/bin`
  on the bar's PATH and exports `HYPRTK_WAL`; `themer.py` uses
  `HYPRTK_WAL` → `resolve_binary("wal")`; the scripts use
  `HYPRTK_WAL` → `../venv/bin/wal` → PATH.

### Phase 3 — decide C scripts explicitly ✅
- `sddm/update.sh`, `updates.sh`, `installupdates.sh`, `ssdetect.sh` (and their
  transitives) stay **dotfiles-owned**. The bar toasts "not found" / shows `?`
  when absent — no crash. Not vendored into the bar.

### Phase 4 — verify + sync ✅
- Verified (headless, simulated no-`~/hyprtk`):
  - bundled scripts + rofi variants resolve via `SCRIPTS_DIR`;
  - `resolve_script()` falls back to `~/hyprtk` when a bundled script is absent;
  - `updates._allowed_script()` rejects an absent `updates.sh` → polling disabled;
  - themer guards (`is_file()` → toast) cover wallpaper / change-icons / sddm /
    papirus-folders / wal absence.
- Synced merged / live / GitHub.

---

## Closure audit (complete)

The full `bash` / `source` / `exec` closure is mapped below. It cleanly
partitions into two disjoint sets — no further bar-bundling is needed.

### Bar-bundled scripts (closed set — no dotfiles deps)

| Script | Reaches |
|--------|---------|
| `wallpaper-colors.sh` | `change-icons.sh` (bundled), `awww`, `wal`, `hyprctl`, `wob` |
| `change-icons.sh` | `papirus-folders.sh` (third-party), `notify-send`, `sed`/`tr` |
| `sync-rofi-theme.sh` | `python3`, `ln` (variants bundled) |
| `appsmenu.sh` | `rofi` (config bundled) |
| `updatewal-awww.sh` | `change-icons.sh` (bundled), `wal`, `awww`, `hyprctl`, `notify-send`, `source ~/.cache/wal/colors.sh` (pywal cache) |
| 3× toggle scripts | `kill` / `cat` / `flock` |

The only non-bundled reference is `~/.cache/wal/colors.sh` — a pywal-generated
cache file, not a dotfiles script.

### Dotfiles-owned C-scripts + their full transitive closure

These are reached only via the C-scripts (never by the bundled set) and stay in
the dotfiles; the bar degrades gracefully when any of them is absent.

| Script | Reaches |
|--------|---------|
| `ssdetect.sh` | `screenshot.sh` + `sshot.sh` |
| `screenshot.sh` | `notification-handler` (sourced), `installer/scripts/settings/*`, `grim`/`slurp`/`hyprpicker`/`rofi`/`notify-send` |
| `sshot.sh` | `hyprquickframe` |
| `installupdates.sh` | `library.sh` (sourced: pacman/yay/sudo helpers), `update-TS-run.sh`, `yay`, `timeshift` |
| `update-TS-run.sh` | `sudo`/`sed`/`tee`/`grub-mkconfig` |
| `sddm/update.sh` | `grub-mkconfig`/`fc-cache`/`sudo`/`sed`/`tee` + `sddm.conf`/`theme.conf` |
| `updates.sh` | `checkupdates`/`trizen` |

### Desktop-wide config the bar reads/writes

| Path | Decision |
|------|----------|
| rofi `variants/` | **bundled** (`scripts/rofi/variants/`) |
| rofi `variant.rasi` symlink + base rofi config | rofi/user responsibility (rofi is a separate app) |
| `~/.config/swaylock/config` | dotfiles (swaylock is a separate app; themer edits if present) |
| `~/.config/matuwall/config.json` | dotfiles (matuwall is a separate app; themer edits if present) |
| `~/.local/share/icons/Papirus-Dark` | install.sh-managed (`papirus-icon-theme` extras) |
| `~/.cache/theme-gui` | bar-owned (auto-generated thumbnail cache) |
