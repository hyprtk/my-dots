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

## 15. Container matrix (T1) — 2026-09-15

`installer/scripts/verify/container-matrix.sh` is the authoritative per-family
package-name check. It collects every native name from `hypr/packages/*.sh`
(`--list`) plus the vendored bar's `DEPS`/`EXTRAS`, then resolves each in a
throwaway rootless-**podman** container of that family *without installing*:
`pacman -Si`/`-Sg`, `apt-get install -s` (Debian 12/13 and Ubuntu 24.04/26.04),
`dnf repoquery`, `zypper install --dry-run`, `xbps-query -R`, `apk search -e`.
Arch misses are checked against the AUR RPC (`.../rpc/v5/info`); the AUR is no
longer a failure. Gentoo/NixOS are advisory (names listed, not resolved, since
`1-install.sh` only prints them). Expected gaps live in
`installer/scripts/verify/container-matrix.allow`.

Result: **1059 resolvable, 21 AUR, 67 allow-listed, 0 unexpected.** The apt
family is checked on both the previous and current release of each
(Debian 12 bookworm / 13 trixie, Ubuntu 24.04 noble / 26.04 resolute); the
newest resolves almost everything (`resolute`: 121 names, only `brave-browser`,
`hyprsunset` and `nvidia-driver` allow-listed).

### Fixes the matrix surfaced (renames / removals)

- pacman: `ttf-font-awesome` → `otf-font-awesome`; `exa` → `eza`. (`xfce4` /
  `xfce4-goodies` are pacman **groups**, now accepted by the resolver.)
- apt: unchanged (Ubuntu resolves; Debian 12 gaps allow-listed).
- dnf: `exa` → `eza`; `ffmpeg` → `ffmpeg-free`; `intel-media-driver` →
  `libva-intel-media-driver`; `fontawesome-fonts` → `fontawesome-fonts-all`;
  `xorg-x11-server-utils` → `xhost`.
- zypper: `gtk-layer-shell` → `libgtk-layer-shell0`; `gtk4-layer-shell` →
  `libgtk4-layer-shell0`; `micro` → `micro-editor`; dropped `xfce4-goodies`
  (the `patterns-xfce-xfce` pattern covers it).
- xbps: `fira-code` → `font-firacode`; `font-manager` → `fontmanager`;
  `mesa-va-drivers` → `mesa-vaapi`; `xfce4-goodies` → `xfce4-plugins`.
- apk: `fira-code` → `font-fira-code-nerd`; `mesa-vulkan-radeon` →
  `mesa-vulkan-ati`; `xfce4-plugins` → `xfce4-panel`.
- `graphics-card.sh` had **no `--list` guard** despite carrying package lists;
  one was added (union of the Intel/AMD/Nvidia branches, no `hyprtk-pkglist`
  marker since it runs outside the spinner loop).
- `3dprinting.sh` `--list` now prints the AUR slicers only on pacman (it is a
  Flatpak hint elsewhere), so they no longer pollute non-Arch families.
- **Vendored bar `DEPS[zypper]`** asked for `typelib-1_0-cairo-1_0` and
  `typelib-1_0-xlib-2_0`, which do not exist on openSUSE. Fixed in the
  **hyprtk-bar** repo (→ `girepository-1_0`, which provides both `cairo-1.0` and
  `xlib-2.0` typelibs) and re-vendored into both trees; openSUSE now resolves
  118/118 and the bar's `--no-extras` install + Gtk/GtkLayerShell import passes.

### Allow-listed (documented) gaps

- apt/Debian 12: `cliphist`, `eza`, `freerdp3-x11`, `nvidia-settings`,
  `intel-media-va-driver-non-free`, `unrar` (Ubuntu-only / non-free).
  apt/Debian 13: the non-free trio plus `policykit-1-gnome` (dropped in 13; use
  `mate-polkit`/`lxpolkit`) and `xautolock` (removed from the archive). Both
  Ubuntu and Debian: `brave-browser` (Brave repo), `fastfetch`,
  `libgtk4-layer-shell0`, `hyprland`/`hyprpicker`/`hyprsunset` (PPA),
  `nvidia-driver` (Debian non-free / Ubuntu versioned), `nwg-look`, `starship`,
  `swappy`.
- dnf: RPMFusion (`akmod-nvidia`, `xorg-x11-drv-nvidia-cuda`, `nvidia-settings`,
  `mesa-va-drivers`), COPR (`hyprland`, `hyprpicker`, `hyprsunset`, `nwg-look`,
  `font-manager`, `starship`) and not-packaged (`polkit-gnome`).
- xbps: `cockpit`, `gvfs-nfs`, `hyprland`, `hyprsunset` (not packaged);
  `nvidia`, `nvidia-settings`, `unrar` (nonfree repo not enabled).
- apk: `cliphist`, `cockpit`, `hyprpicker`, `ipp-usb`, `nss-mdns`, `nwg-look`,
  `swappy` (not packaged); `nvidia`, `nvidia-settings`, `unrar` (nonfree).

### awww source build (T3) — validated in containers

Ran `installer/scripts/awww-install.sh` end-to-end (build deps + rustup +
`cargo build --release --locked`) in real containers:

- **Ubuntu 24.04, Fedora, openSUSE Tumbleweed** — `awww 0.12.1` builds and
  installs + all four `awww`/`swww` symlinks.
- **Debian 12 (bookworm)** — **cannot build**: it ships libwayland 1.21, and
  awww's daemon implements the `wl_surface` `preferred_buffer_scale` /
  `preferred_buffer_transform` handlers (libwayland **>= 1.22**). The script now
  detects this up front (`pkg-config --modversion wayland-client`) and fails
  fast with a clear reason instead of downloading rustup and compiling first.

## 16. Full installer dry-run in containers (T2) — 2026-09-15

`installer/scripts/verify/container-dryrun.sh` runs the **whole** installer in a
throwaway container per family/variant (the containerised counterpart of
`installer-dryrun.sh`). Sandbox `$HOME` with the repo at `~/hyprtk` (code copied,
bulk assets symlinked), every mutating command + the family PM stubbed, bundled
`gum` replaced by a non-interactive stub, `HYPRTK_DRYRUN=1`, piped `read`
answers. Pass = the `hyprtk installation completed` marker in `install.log` with
no `FATAL`/`FAIL`/`SPIN FAILED`/`RUN FAILED`.

Result: **11/11** — arch, debian 12/13, ubuntu 24.04/26.04, fedora, suse, void,
alpine all complete cleanly; gentoo + nixos complete as advisory (package deps
skipped).

### Bug fixed

- **os-release single quotes.** `_detect_distro` (and `hyprland.sh`'s
  `_hyprtk_is_ubuntu`) stripped only double quotes, so `ID='gentoo'` (Gentoo's
  real os-release uses single quotes) failed auto-detection. Both now strip
  `"` and `'`. Surfaced by the Gentoo container.

### Bootstrap quirks (container base images, not installer bugs)

- openSUSE Tumbleweed base has no `awk` → install `gawk` first.
- Void needs `xbps-install -Syu xbps` before `bash` can be installed.
- `nixos/nix` is a build image: no `/etc/os-release` (detection falls back to the
  manual menu) and no `sed`/`awk` (bootstrap `gnused`/`gawk`).

## 17. Linux Mint 22.3 (Ubuntu-24.04 family) — report + fixes — 2026-09-15

User report: multi-distro "does not install everything" on **Linux Mint 22.3**.
Tested in `linuxmintd/mint22.3-amd64` (Mint's repo layout: `packages.linuxmint.com`
+ Ubuntu `noble` main/restricted/universe/multiverse).

### Finding

Mint 22.3's unresolved apt names were the **exact noble set** (no Mint-specific
drift): `brave-browser`, `fastfetch`, `hyprland`, `hyprpicker`, `hyprsunset`,
`libgtk4-layer-shell0`, `nvidia-driver`, `nwg-look`, `starship`, `swappy`. The
serious one is **`hyprland` itself** — `add-apt-repository -y
ppa:cppiber/hyprland` fails on Mint/Ubuntu containers with *"This codename isn't
currently supported"* (it needs a reachable Launchpad API + software-properties),
so the compositor never installed. The PPA **does** publish `noble` (hyprland
`0.56.2`, plus hyprpicker/hyprsunset/hyprlock/hypridle).

### Fixes

- **`hyprtk_apt_add_ppa`** (new, in `pkgmanager.sh`): adds a Launchpad PPA by
  fetching its signing key into `/etc/apt/keyrings/ppa-<name>.asc` and writing a
  `signed-by` `sources.list.d` entry — no `add-apt-repository`, no Launchpad API.
  Also `hyprtk_ubuntu_codename` (prefers `UBUNTU_CODENAME`, so Mint's
  `VERSION_CODENAME=wilma` still yields `noble`) and `hyprtk_is_ubuntu_family`.
- **`hyprland.sh`**: `install_hyprland_apt` uses `hyprtk_apt_add_ppa
  cppiber/hyprland A54D23B6…F0CCF48E`, falling back to `add-apt-repository` only
  if the key fetch fails. Fixes hyprland/hyprpicker/hyprsunset on Ubuntu 24.04 &
  Mint 22.3.
- **`terminaltools.sh`**: adds the `zhangsongcui3371/fastfetch` PPA
  (`EB65EE19…D4865F21`) on the Ubuntu family when `fastfetch` does not resolve
  (noble has no `fastfetch`; the PPA ships `2.68.1~noble`).

### Coverage

- Mint added to both harnesses: T1 (`container-matrix.sh` apt row `mint22`) →
  114 ok / 10 allowed / 0 unexpected; T2 (`container-dryrun.sh`) → the row rewrites
  os-release to real-Mint values so detection + codename logic are exercised.
- Full re-runs: **T1 1173 resolvable / 21 AUR / 77 allowed / 0 unexpected**;
  **T2 12/12**.

### Remaining Mint/noble archive gaps (documented, allow-listed)

`libgtk4-layer-shell0` (matuwall `LD_PRELOAD`), `nwg-look`, `swappy`, `starship`,
`nvidia-driver` (Ubuntu wants `nvidia-driver-5xx`). No clean PPA; candidates for a
source build (gtk4-layer-shell) or upstream install script (starship).
## 18. Source-build fallbacks for unpackaged apps — 2026-09-15

The Mint/noble gaps no PPA carried (`libgtk4-layer-shell0`, `swappy`, `nwg-look`,
`starship`) are now closed by `installer/scripts/srcapps-install.sh`, called from
`1-install.sh` after the awww steps. It is idempotent (skips when present),
non-fatal (a failed build warns and the install continues) and `HYPRTK_DRYRUN`-
aware (prints the plan).

- **gtk4-layer-shell `v1.3.0`** — meson build with `-Dvapi=false
  -Dintrospection=false` (the `vapi` option forces `valac` even when examples are
  off). Needed by matuwall's `LD_PRELOAD`; the script also creates
  `/usr/lib/libgtk4-layer-shell.so` for the dotfiles' Arch-path `LD_PRELOAD`,
  located via `pkg-config --variable=libdir` with `lib`/`lib64` fallbacks.
- **swappy `v1.8.0`** — meson; `grim.sh`'s screenshot editor.
- **nwg-look `v1.1.1`** — `go build`.
- **starship `v1.26.0`** — upstream installer (`starship.rs/install.sh -b
  /usr/local/bin`).

Per-family build-dep maps for `apt`/`dnf`/`zypper`/`xbps`/`apk`. Verified with
**real builds in containers**: Linux Mint 22.3, Alpine and Fedora all install all
four (the symlink resolves on multiarch and `lib64`). `bash -n` clean; host suite
(installer-dryrun 11/11, refs 45/45, completeness) and T2 (12/12) still green.
## 19. Graphics-card Nvidia — versioned fallback + an arm-order bug — 2026-09-15

- **Bug (real, user-facing):** `graphics-card.sh`'s Nvidia menu `case` arms were
  ordered `1)` / `2|*)` / `3)`, so the `*` catch-all swallowed `3` — **choosing
  "Nvidia" installed the AMD stack**, and no Nvidia driver was ever installed.
  Reordered to `1)` / `3)` / `2|*)` (AMD keeps the catch-all/default), with a
  comment so it does not regress.
- **Versioned fallback:** Ubuntu/Mint ship no generic `nvidia-driver` meta, only
  `nvidia-driver-5xx`. The apt Nvidia arm now probes the generic meta and, when
  absent, selects the newest versioned driver (Mint 22.3 → `nvidia-driver-610`).
- Verified on Mint: inputs 1/2/3 now select Intel/AMD/Nvidia correctly (dry-run
  shows the chosen package lists). T2 12/12; host suite green (11/11, 45/45,
  completeness); T1 unchanged.
## 20. Void Linux — Hyprland is not packaged (documented note) — 2026-09-15

Void's repositories ship `hyprutils`/`hyprwayland-scanner` but **not `hyprland`**
(a packaging-philosophy conflict — confirmed against `repo-default`). The
documented path is the community binary repo **void-land/hyprland-void-packages**.

- `hypr/packages/hyprland.sh` now prints the exact steps when the compositor is
  still missing on xbps (add the repo, `xbps-install -Sy hyprland
  xdg-desktop-portal-hyprland`), plus the build-from-source link. The installer
  deliberately does **not** add a third-party repo on its own.
- `PORTABILITY.md` feature table now marks Void as ⚠️ community-repo (and Fedora
  as ⚠️ COPR), footnote ³.
- The note is a no-op in the dry-run (the stubbed `xbps-query` reports Hyprland
  installed), so T2 stays green; `bash -n` clean.
