# hyprtk-merged — Merge Plan & Build Record

Sources: the 11 distro trees in `/home/hyprtk/Projects/AI-Projects/Source-Files/dots/`
(`arch-dots`, `archbang-dots`, `archcraft-dots`, `archman-dots`, `bslx-dots`,
`cachy-dots`, `endeavour-dots`, `garuda-dots`, `kiro-dots`, `manjaro-dots`, `reborn-dots`).
No reference to any other tree. The 11 source trees are the entire universe of input.

## 1. Baseline finding

`arch-dots` is the natural baseline: every other tree is `arch-dots` plus a small
delta set. All 11 share the same ~45 top-level folders and a ~630-line
`1-install.sh` that differs from arch's by only 5–18 lines per distro.

## 2. Target layout (built)

Four top-level directories keep the parent level clean; only the installer and
docs sit at the root. Paths are relative to the merged repo root (deploys to `~/hyprtk`).

```
hyprtk-merged/
├── 1-install.sh                 # unified installer (single file, top level)
├── CHANGELOG  cheatsheet.md  LICENSE  README.md  .zshrc  .gitattributes   # docs, top level
├── assets/                      # fonts, Wallpapers, themes, papirus-icons, splash, screenshots, thumbnails
├── configs/                     # all app/system configs (alacritty…zshrc, root, dracut, nvidia, grub)
├── hypr/                        # all Hyprland config & settings (lua, conf, scripts, packages)
├── installer/
│   ├── library.sh               # shared helpers
│   ├── os-release/              # os-release-<distro> × 11 + cachyos-branding
│   ├── scripts/                 # helper/utility scripts (+ verify/, build-merged.sh)
│   ├── standalone/              # oh-my-posh, matuwall, awww, papirus-folders, hyprtk-bar
│   └── steps/<distro>.sh        # per-distro hooks × 11
└── distro/<name>/               # per-distro overlays (deltas only, mapped paths)
```

### Directory-to-source mapping

| Source top-level | Merged location |
|---|---|
| `fonts/`, `Wallpapers/`, `themes/`, `papirus-icons/`, `splash/`, `screenshots/` | `assets/` |
| `alacritty btop fastfetch gtk hyprlogout hyprpicker matuwall Mousepad nvim ohmyposh oh-my-zsh ranger rofi sddm smb starship swappy swaylock Thunar User-Management vim wal waypaper wob xfce4 zshrc root dracut nvidia grub` | `configs/` |
| `hypr/` | `hypr/` |
| `os-release/`, `scripts/`, `standalone/` | `installer/` |
| top-level files (`1-install.sh`, `CHANGELOG`, `cheatsheet.md`, `default.png`, `.folder.png`, `.gitattributes`, `LICENSE`, `README.md`, `.zshrc`) | top level |

### Top-level file rule

Every top-level file beside `1-install.sh` in the sources stays top level in the
merged repo. `default.png` is additionally mirrored under `assets/Wallpapers/`.

### Sync exclusions

- `configs/gtk/gtk-3.0/bookmarks` — user-local only, never synced across locations
- `PLANNING.md` — merged only, never copied to live or GitHub

## 3. Unified installer design (built)

Single `1-install.sh` = the arch pipeline, with distro divergences extracted into
hooks in `installer/steps/<distro>.sh`. The installer sources the matching steps
file after auto-detecting the distro (with manual fallback) and calls the hook if
defined:

- `pre_install` — package removals:
  - archbang: `pacman -Rns swaylock`
  - bslx: `pacman -Rcs plasma* kde-applications*`
  - kiro: `pacman -Rns xfce4 xfce4-goodies thunar catfish thunar-shares-plugin` + `yay -Rns sddm-git fastfetch-git` + `sleep 5`
- `install_os_release` — default: `os-release-<distro>` → `/usr/lib/`
  - archbang: → `/etc/`
  - cachy: `/usr/lib/` + `/run/systemd/propagate/.os-release-stage/` + `/run/user/$UID/...` + cachyos-branding hook
- `install_boot` — arch only: splash → `/usr/share/systemd/bootctl/` + `mkinitcpio -P`
- `grudupdater` — kiro: guarded no-op (script has no source in any of the 11 trees)
- `grub_wallpaper` — bslx: copy `current-wallpaper.png` to `/boot/grub/`
- `wal_init` — archcraft: `wal -i ~/.cache/current-wallpaper.png`
- `pre_hypr_symlink` — all but arch: `mv ~/.config/hypr ~/.config/hypr-old`
- `setup_sudoers` — reborn: multiline sudoers

Distro detection: reads `/etc/os-release` ID, maps (arch, archbang, archcraft,
archman, bluestar/bslx, cachyos/cachy, endeavour/endeavouros, garuda, kiro,
manjaro, reborn/rebornos), with an interactive fallback.

### Shebangs

All `.sh` files use correct shebangs (`#!/bin/bash` or `#!/bin/sh`). Fixed from
`#/bin/bash` (missing `!`) which caused silent failures when invoked via `./script.sh`.

### Intentionally removed (excluded from completeness check)

User removed the following from the merged tree; `verify-completeness.sh` excludes
them via `REMOVED_EXCLUDE` (see `installer/scripts/verify/verify-completeness.sh`):

- `configs/root/.local/share/themes/Arc-Azure-dodger-blue*` — 3 GTK themes (large)
- `configs/root/.config/nwg-look/` + `configs/root/.local/share/nwg-look/`
- `configs/waybar/` (and the source waybar theme set) — removed outright:
  hyprtk-bar is the taskbar and owns the notification daemon.
  `hypr/scripts/generate-aero-colors.sh` (only used by the waybar launcher) is
  gone too.

### Standalone wrappers

All standalone scripts in `installer/standalone/` use `$HOME` instead of hardcoded
paths to work on any user account.

### hyprtk-menu (removed 2026-09-09 — merged into hyprtk-bar)

The start menu is now built into hyprtk-bar: vendored at `installer/hyprtk-bar/src/
hyprtk_bar/menu/`, owned by the bar process, toggled by the start button or
`Super + Space` (`installer/scripts/hyprtk-bar-menu-toggle.sh` → SIGUSR1).
Its settings live in the bar config under `menu` (first-run migration imports
`~/.config/hyprtk-menu/config.json`) and are edited from the bar settings
dialogue's *Menu* tab. The standalone app, its vendored tree, install script and
PATH wrapper were removed; the hyprtk-menu GitHub repo is archived.

### theme-gui (removed 2026-09-08 — superseded by hyprtk-bar's Theme Manager)

Theme-gui was archived and its functionality moved into hyprtk-bar's Theme
Manager (opened from the wallpaper glyph). The vendored `installer/theme-gui/`,
its `installer/standalone/{theme-gui,hyprtk-themer}` wrappers, the
`SUPER+ALT+T` keybinding, and the `windowrules.lua` rule were all removed.

### hyprtk-arc-menu (merged into hyprtk-bar 2026-09-08 — no separate app)

The arc menu (Material-style radial launcher: a FAB-style button in a screen
corner that fans its items out on click — 180° at top/bottom center, 90° at
corners — each item launching a command) is now built into **hyprtk-bar**. The
standalone app, its vendored `installer/hyprtk-arc-menu/` tree, its
`install.sh` step, its autostart line, and the `hyprtk-arc-menu-toggle` wrapper
were all removed.

- The overlay window is owned by the bar process (`src/hyprtk_bar/arcmenu.py`):
  created when the `arcmenu` config block is enabled, themed from the bar's
  resolved palette + live pywal, rebuilt live from the settings dialogue.
- Config lives under `arcmenu` in `~/.config/hyprtk-bar/config.json`; a first-run
  migration imports the legacy `~/.config/hyprtk-arc-menu/config.json` if present.
- Settings live in the bar settings dialogue's **Arc Menu** tab (position,
  shape, sizes, colours, toggles, and the item list with add/edit/remove,
  move up/down, and installed-app search).
- Toggle: `SUPER+CTRL+M` → `installer/scripts/hyprtk-bar-arc-toggle.sh`
  (signals the running bar with SIGUSR2), or click the FAB. Escape closes,
  middle-click closes.

## 4. Verification (all PASSED)

1. **Completeness diff** — every file in all 11 source trees is accounted for in
   the canonical core or its `distro/<name>/` overlay. `COMPLETENESS: ALL 11
   DISTROS FULLY ACCOUNTED`.
2. **Reference audit** — every `~/hyprtk/...` path in the merged tree resolves.
   The only whitelisted ref is `installer/os-release/os-release-` (a regex false
   positive: `os-release-$DISTRO` truncates at `$`). Refs containing a `...`
   prose placeholder are skipped. See §9.
3. **bash -n** — all shell scripts pass.
4. **Dry-run** — for each distro, canonical+overlay deployed to sandbox; all
   referenced paths resolve. All 11 pass.
5. **os-release** — all 11 `installer/os-release/os-release-<distro>` byte-match
   sources; cachyos-branding matches.
6. **Installer hooks** — each distro's steps file exports exactly the hooks its
   original installer diverged with.

### Verification scripts

Located in `installer/scripts/verify/`:
- `verify-completeness.sh` — checks all source files accounted for
- `audit-references.sh` — checks all `~/hyprtk/` refs resolve (dead refs whitelisted)
- `audit-installer.sh` — checks installer commands covered
- `dryrun.sh` — simulates per-distro deployment, checks all refs resolve

Both `audit-references.sh` and `dryrun.sh` auto-detect ROOT via `$(dirname "$0")`
and centralize dead refs in a `DEAD_REFS` array.

Rebuild script: `installer/scripts/build-merged.sh` (recreates canonical tree +
overlays from the 11 sources). NOTE: it `rm -rf`s the target — run with care.

## 5. Location sync

Three copies of the installer exist:

| Location | Purpose |
|----------|---------|
| `~/Projects/AI-Projects/hyprtk-merged/` | Source of truth (merged build) |
| `~/hyprtk/` | Live install (symlinked to `~/.local/bin`) |
| `~/Documents/GitHub/dotfiles/` | GitHub push target |

Sync flow: merged → live → GitHub. All verified via `md5sum` and `diff -rq`.

## 6. Recent tweaks & additions (2026-09-02)

- **hyprtk-arc-menu project added** — new standalone app vendored at
  `installer/hyprtk-arc-menu/`, wired into `1-install.sh` (step mirrors
  theme-gui). See the project section above.
- **hypr config additions** (in `hypr/`, same in merged + live):
  - `keybindings.lua` — added
    `hl.bind(mainMod .. " + CTRL + M", hl.dsp.exec_cmd("$HOME/.local/bin/hyprtk-arc-menu-toggle"))`
  - `autostart.lua` — added `hl.exec_cmd("hyprtk-arc-menu")`
- **README.md** — added an **Applications** section documenting the three
  bundled apps (theme-gui, hyprtk-menu, hyprtk-arc-menu) with their config
  JSON and theming notes.
- **Sync note** — `README.md` and the app bundles are kept identical across
  merged / live / GitHub. `PLANNING.md` remains merged-only (see sync
  exclusions).

## 7. Recent tweaks & additions (2026-09-08)

- **hyprtk-arc-menu merged into hyprtk-bar** — the standalone app (vendored
  `installer/hyprtk-arc-menu/`, its `1-install.sh` step, the autostart line,
  and the `-toggle` wrapper) was removed. The arc menu overlay now lives in the
  bar (`src/hyprtk_bar/arcmenu.py`), themed + toggled by the bar, configured
  from the bar settings dialogue's **Arc Menu** tab, with config under
  `arcmenu` in the bar config (legacy config auto-imported on first run).
- **hypr config** — `keybindings.lua` now binds `SUPER+CTRL+M` to
  `installer/scripts/hyprtk-bar-arc-toggle.sh` (signals the bar with SIGUSR2);
  the `hyprtk-arc-menu` autostart line was removed (the bar owns the overlay).
- **new script** — `installer/scripts/hyprtk-bar-arc-toggle.sh`.

## 8. Recent tweaks & additions (2026-09-09)

- **hyprtk-menu merged into hyprtk-bar** — the standalone app (vendored
  `installer/hyprtk-menu/`, its `1-install.sh` step, the
  `hyprtk-menu-install.sh` script, and the `installer/standalone/hyprtk-menu`
  PATH wrapper) was removed. The start menu now lives in the bar
  (`src/hyprtk_bar/menu/` subpackage), owned by the bar process, themed + pywal
  following the bar, configured from the bar settings dialogue's **Menu** tab,
  with config under `menu` in the bar config (legacy `~/.config/hyprtk-menu/
  config.json` auto-imported on first run).
- **toggle** — the start button toggles the in-bar menu; `Super + Space`
  (`installer/scripts/hyprtk-bar-menu-toggle.sh`) signals the bar with SIGUSR1.
- **hypr config** — `keybindings.lua` adds `SUPER+SPACE` → the menu toggle;
  the dead `hyprtk-menu settings` floating windowrule was removed from
  `windowrules.lua`.
- **new script** — `installer/scripts/hyprtk-bar-menu-toggle.sh`.
- **hyprtk-menu GitHub repo archived.**

## 9. Dead-ref cleanup (2026-09-14)

Resolved every stale `~/hyprtk/...` reference in the merged tree and pruned the
verification whitelists.

### Remapped (target existed; source fixed)

| Ref | Fixed in | Now points to |
|---|---|---|
| `hypr/conf/nvidia.conf` | `cheatsheet.md` | `hypr/nvidia.lua` |
| `installer/scripts/applauncher.sh` | `configs/zshrc/25-aliases` + `distro/{endeavour,garuda}/configs/zshrc/25-aliases` | `~/.local/share/hyprtk-bar/scripts/appsmenu.sh` |
| `configs/rofi/scripts/sync-rofi-theme.sh` | `hyprtk-bar/{config,themer}.py` fallbacks | `installer/hyprtk-bar/scripts/sync-rofi-theme.sh` |
| `installer/scripts/{appsmenu,updatewal-awww,hyprtk-bar-menu-toggle}.sh` | `hyprtk-bar/config.py` fallbacks | `installer/hyprtk-bar/scripts/…` |

- `resolve_script()` in `config.py` / `themer.py` now falls back to the bundled
  hyprtk-bar script locations instead of the pre-bundling dotfiles paths.

### Removed (no target — genuinely dead)

- `configs/root/.bashrc` — dropped 4 commented dead aliases (`growthrate.py`,
  `looking-glass.sh`, `qtile/config.py`, `picom/picom.conf`).
- `installer/steps/kiro.sh` — reworded the `grudupdater` comment so it no longer
  names the nonexistent script path.

### Verify scripts

- `audit-references.sh` / `dryrun.sh` — `DEAD_REFS` pruned from 10 stale entries
  to 1 (`/installer/os-release/os-release-`, a `$DISTRO` regex false positive).
- Both now skip `~/hyprtk/...` prose placeholders (`...` in doc prose).
- `installer/hyprtk-bar/BUNDLING.md` table rewritten to the bundled/resolved
  paths and its "known issues" marked resolved, so it no longer needs an audit
  exclusion.

### Results

- `audit-references.sh` → all refs resolve.
- `dryrun.sh` → 11/11.
- `installer-dryrun.sh` → 11/11.

### Correction

- §8 lists the menu-toggle script as
  `installer/scripts/hyprtk-bar-menu-toggle.sh`; it is actually vendored at
  `installer/hyprtk-bar/scripts/hyprtk-bar-menu-toggle.sh`.

## 10. Bundled pywal16 (2026-09-14)

The merged installer no longer installs pywal16 from the AUR. pywal16 is now
vendored inside hyprtk-bar and provisioned by the bar's installer.

- **Vendored** — `hyprtk-bar/vendor/pywal16/` (MIT; upstream `eylles/pywal16`,
  fork `hyprtk/pywal16`, pinned commit `a04c3e3`, v3.8.15). Provenance and the
  update procedure are in `vendor/pywal16/VENDOR.md`.
- **`install.sh --wal-only`** — new mode that copies the vendor tree into
  `~/.local/share/hyprtk-bar/vendor/pywal16/`, creates the venv if missing, and
  drops the `wal` launcher (`venv/bin/wal`; `~/.local/bin/wal` symlink, plus a
  `/usr/local/bin/wal` fallback when `~/.local/bin` is off PATH). `--uninstall`
  removes both. `python-pywal16-git` dropped from `EXTRAS_AUR`.
- **Merged `1-install.sh`** — the `yay --noconfirm -S python-pywal16-git` block
  (with its `/usr/bin/wal` skip) is replaced by `install.sh --wal-only`, run at
  the same early point so the pywal init steps (line ~479) and the dotfiles'
  `wal` templates (line ~560) keep working; the full bar install near the end
  reuses the venv.
- **Bundled-first resolution** — `proc.bootstrap_environment()` prepends
  `~/.local/bin` to the bar's PATH and exports `HYPRTK_WAL`; `themer.py` prefers
  `HYPRTK_WAL` / `resolve_binary("wal")`; `wallpaper-colors.sh`,
  `wal-watcher.sh` and `updatewal-awww.sh` prefer `HYPRTK_WAL` →
  `../venv/bin/wal` → PATH, so a stale system `wal` can't shadow the bundled
  one.
- **Nix + CI** — `derivation.nix` copies `vendor/` and wraps `wal`; the flake
  devShell exposes it; `install-matrix.yml` gains a bundled-pywal self-test.
- **Docs** — `BUNDLING.md`, `PORTABILITY.md`, `README.md` and `CHANGELOG.md`
  updated.

Verified: `install.sh --help/--dry-run/--wal-only` (idempotent), a full
`--no-deps --no-extras` install in an isolated `$HOME`, `wal -v` plus a
`wal -i default.png` init producing `~/.cache/wal/colors.json`, and the merged
`--wal-only` call from `installer/hyprtk-bar/`.

## 11. Multi-distro install (2026-09-14)

Applied the hyprtk-bar portability model to the whole desktop: hyprtk now
installs across distribution families, not just the 11 Arch-based ones.

### New abstraction

`installer/scripts/pkgmanager.sh` (sourced, never executed) detects the host
manager (`pacman`/`apt`/`dnf`/`zypper`/`xbps`/`apk`/`emerge`/`nix`) and provides
`hyprtk_detect_pm`, `hyprtk_pm_name`, `hyprtk_run_root`, `pkg_install`,
`pkg_remove`, `pkg_is_installed`, `aur_helper`/`aur_available`/`aur_install`.
`pkg_install` isolates a bad package name instead of aborting the batch.
`library.sh` delegates to it, keeping `_installPackagesPacman` /
`_installPackagesYay` / `_isInstalledPacman` / `_isInstalledYay` as wrappers.

### Exhaustive per-family lists

Every `hypr/packages/*.sh` (plus the `distro/reborn` overlay) now carries a
`case "$HYPRTK_PM"` with the complete native package list per family and an
Arch AUR list. Scripts support `--list` (marker `# hyprtk-pkglist`) so
`_script_packages` previews the resolved packages in the spinner.

### Installer

`1-install.sh`:
- sources `pkgmanager.sh` early and exports `SCRIPT_DIR`/`HYPRTK_PM` for the
  `_spin` subshells;
- detects the generic families via `ID` then `ID_LIKE`, computes `DISTRO_FAMILY`
  (`_distro_family`), and shows family + manager in the detection box;
- expands the manual menu with Debian/Ubuntu, Fedora/RHEL, openSUSE, Void,
  Alpine, Gentoo, NixOS, and an "Other / unknown" fallback;
- installs the AUR helper (`yay`) only when `HYPRTK_PM = pacman`;
- uses `pkg_remove` for the leftover-package step and `_installPackagesPacman`
  for `zsh`; resolves `zsh` via `command -v` for `chsh`;
- guards the `os-release-<distro>` branding copy (Arch-family files only) and
  tolerates both `smb/nmb` and `smbd/nmbd` samba unit names;
- invokes all package/utility scripts with `bash` (they use arrays), not `sh`.

### Misc scripts made PM-aware

`rm-dm-managers.sh`, `cleanup.sh`, `installupdates.sh`, `updates.sh`,
`snapper-setup.sh`, `vmware-setup.sh`, `qemu-virt-setup.sh` and
`appimage-setup.sh`. `graphics-card.sh` installs the Intel/AMD/NVIDIA stack per
family and guards `mkinitcpio`/GRUB; `sddm-check.sh`/`sddmgrub.sh` use
repo-relative paths and `hyprtk_run_root`. Steps `pre_install` hooks use
`pkg_remove`.

### Docs

`PORTABILITY.md` added; `README.md` intro/portability section and `CHANGELOG`
updated. The `.bashrc` `update` alias is now a distro-aware function.

### Verification (all PASSED)

- `bash -n` on every shell script (the only failure is the pre-existing zsh
  `configs/oh-my-zsh/oh-my-zsh.sh`, which is not bash).
- `dryrun.sh` → 11/11; `audit-references.sh` → all 45 refs resolve.
- `installer-dryrun.sh` → 11/11 Arch-based distros, no run-log errors.
- A parallel non-Arch harness (modified package-manager probes) → 7/7 for
  `debian`, `fedora`, `suse`, `void`, `alpine`, `gentoo`, `nixos`.
- `--list` output verified for all six supported managers.

## 12. Cross-distro awww (2026-09-15)

Closed the gap that left the wallpaper daemon missing on non-Arch installs
(found when installing the any-distro tree on Ubuntu).

### Root cause

- `awww` (the renamed `swww`) is AUR-only. On Arch `hypr/packages/hyprland.sh`
  installs it from the AUR; the apt/dnf/zypper package lists had no wallpaper
  daemon, and Ubuntu/Fedora/openSUSE package neither `awww` nor `swww`.
- `installer/scripts/awww-wrapper.sh` only wrapped an already-installed awww —
  it hardcoded `REAL_AWW=/usr/bin/awww` and `sudo ln -s /usr/bin/awww …`, both
  of which fail when nothing installed awww.

### Fix

- **New `installer/scripts/awww-install.sh`** — acquisition ladder: skip if
  present (Arch AUR handled elsewhere); native `swww` on Void/Alpine (with
  awww/swww symlinks); otherwise a pinned source build of `LGFae/awww` `v0.12.1`
  (`cargo build --release --locked`) with per-family build deps and a rustup
  bootstrap when the distro `cargo` is below upstream's 1.89 MSRV; install to
  `/usr/local/bin` + `swww` compatibility symlinks; manual instructions (never
  fatal) when no route exists. `HYPRTK_DRYRUN=1` prints the plan.
- **`awww-wrapper.sh` rewritten** to resolve the real binary (AUR
  `/usr/bin`, source-build `/usr/local/bin`, or `swww`), guard the symlinks, and
  warn instead of writing a broken wrapper when awww is absent.
- **`1-install.sh`** runs `awww-install.sh` then the wrapper at the existing
  awww step (before the bar install, so the bar's autostart gating sees awww).

### Docs

`PORTABILITY.md` (new feature row, "awww is no longer Arch-only" note, gotcha
with per-family build deps, Remaining-work item), `README.md`, `CHANGELOG`.

### Verification

- `bash -n` on `awww-install.sh`, `awww-wrapper.sh`, `1-install.sh`.
- `ver_ge` unit-checked (1.75/1.88 < 1.89 ≤ 1.90/2.0).
- `HYPRTK_DRYRUN=1` plan output checked for `apt` and `xbps`; `pacman` path
  verified to skip (already installed).
- `installer-dryrun.sh` → 11/11 (see session log).

## 13. Hyprland ≥ 0.55 on Ubuntu (2026-09-15)

Live validation on a real Ubuntu 26.04 VM (QEMU/KVM, via the qemu guest agent)
exposed a second blocker: the session came up but none of the dotfiles applied.

### Root cause

- Hyprland moved to a **Lua config** in **0.55**; the dotfiles are entirely Lua
  (`hypr/hyprland.lua` + `require(...)`) and ship no `hyprland.conf`.
- Ubuntu 26.04's archive ships **Hyprland 0.53.3** (pre-Lua). It ignored
  `hyprland.lua`, generated a stock `hyprland.conf`, and logged
  `Using config: …/hyprland.conf`. Result: no autostart, no keybindings, no
  windowrules, no bar.
- Evidence: `strings /usr/bin/Hyprland` had no `.lua` references.

### Fix

- **`hypr/packages/hyprland.sh`** — on apt, `install_hyprland_apt` checks the
  installed Hyprland via `dpkg-query`; if < 0.55 and the host is Ubuntu
  (`ID`/`ID_LIKE` contains `ubuntu`), it installs `software-properties-common`,
  adds `ppa:cppiber/hyprland` (0.56.2 for resolute), `apt-get update`, then
  installs `hyprland` with `-o Dpkg::Options::=--force-overwrite` (the PPA's
  `libhyprcursor1`/`libudis86.1` overwrite the archive's `libhyprcursor0`/
  `libudis86-0` files without declaring `Replaces`). Debian (no PPA) warns and
  falls through to the archive package.
- Docs: `PORTABILITY.md` (feature row footnote + gotcha), `README.md`,
  `CHANGELOG`.

### Live verification (on the VM)

- Upgraded to **Hyprland 0.56.2** (same commit as the host's Arch): `dpkg -l`
  all `ii` after `apt-get -f install` with force-overwrite.
- Restarted the session; the log showed
  `[cfg] Using lua config found at /home/test/.config/hypr/hyprland.lua`.
- `hyprctl configerrors` → empty; `hyprctl binds` → **65** dispatchers.
- Autostart ran: **hyprtk-bar** (`python3 -m hyprtk_bar`) and **awww-daemon**
  running; awww set the wallpaper from `wallpaper-restore.sh`.
- (VM prep needed to reach a session: `usermod -aG video,render,input test`,
  then `openvt`+`su` onto tty3.)

### Verification

- `bash -n` clean; branch logic unit-tested with stubbed `dpkg-query` +
  fake os-release: Ubuntu/0.53.3 → PPA+force-overwrite, Ubuntu/0.56.2 → skip,
  Debian/0.53.3 → warn (no PPA). `--list` unchanged.

## 14. Package-name audit (2026-09-15)

Live Ubuntu 26.04 finding: several `apt` package names never installed (the
per-package fallback isolates them and only warns, so the install reported
success with the packages missing): `gtk-layer-shell`, `gtk4-layer-shell`,
`cups-pdf`, `fonts-fira-code`, `freerdp2-x11`, `mission-center`,
`thunar-shares-plugin`; the bar's `EXTRAS[apt]` asked for `libnotify` /
`policykit-1`.

### Method

- **apt (authoritative):** resolution linter on the Ubuntu VM — for every
  `hypr/packages/*.sh --list` (marker + `--list` guard only) and the bar's
  `EXTRAS[apt]`, run `apt-get install -s` per name. (An earlier `apt-cache
  policy` check gave false positives for virtual/t64 packages; `-s` doesn't.)
- **Fedora:** `mdapi.fedoraproject.org/rawhide/pkg/<name>` (200/400).
- **openSUSE:** Tumbleweed `primary.xml.zst` grepped for `<name>`.
- **Void:** repo directory listing grepped for `>name-<ver>.x86_64.xbps`.
- **Alpine:** `APKINDEX.tar.gz` (main + community) grepped for `^P:name$`.
- Repology was DNS-blocked on the host; the web status-check method was too
  noisy (Provides/aliases/repo scope), so per-distro metadata was used.

### Fixes applied

- apt: `libgtk-layer-shell0`, `libgtk4-layer-shell0`, `printer-driver-cups-pdf`,
  `fonts-firacode`, `freerdp3-x11`; dropped `mission-center`,
  `thunar-shares-plugin`. `python3-venv` etc. unchanged (resolve fine).
- Fedora: `7zip` (was `p7zip`), `Thunar` (case), `libusb1` (was `libusb`),
  dropped `thunar-shares-plugin`/`mission-center`/`xfce4-goodies`; bar extras
  `pipewire-pulseaudio`.
- openSUSE: `micro-editor`, dropped `mission-center`; bar extras
  `pipewire-pulseaudio` + `libnotify-tools`.
- Void: `Thunar` (case), dropped `mission-center`.
- bar: `libnotify-bin` + `polkitd pkexec`.

### Also fixed here

- `manual_package_installs.sh` and `3dprinting.sh` were **never invoked** by
  `1-install.sh`; both are now in the core loop (3dprinting gained a `--list`
  handler). Most of `manual_package_installs`' packages are duplicated in other
  scripts; its unique items (`xautolock`, AUR extras) now install.
- `rm-dm-managers.sh` sets `/etc/X11/default-display-manager=/usr/bin/sddm` on
  apt (Debian/Ubuntu's `sddm.service` `ExecStartPre` requires it) — the reason
  the Ubuntu VM had no login screen.

### Verified

- Ubuntu 26.04 VM: refined apt linter → **zero MISSING** across all scripts +
  bar extras; `sddm.service` active after the display-manager fix; Sugar-Candy
  theme best-effort install; `brave-browser 1.95` installs from Brave's repo.
- `bash -n` clean; audit 45/45; dryrun 11/11; completeness all-11;
  installer-dryrun 11/11.

### Left for the container matrix

Alpine gaps (`cliphist`, `nss-mdns`, `ipp-usb`, `nwg-look`, `xfce4-plugins`,
`swappy`, `unrar`, `cockpit`) and openSUSE `python3*`/`gtk3`/`gtk4`
(provides/aliases) need a real container run to finalise.

