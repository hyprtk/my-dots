# Changelog

All notable changes to **Hyprtk-ISO-Creator** are documented in this file.
Dates are in `YYYY-MM-DD` format.

## [2026-10-07]

### Changed

- **`hyprlock` + `hypridle` are now the default locker/idle daemon** (official
  repos; added to `packages.hyprtk`). The dotfiles' `hypr/scripts/lock.sh` and
  `hypr/autostart.lua` prefer them and fall back to `swaylock`/`swayidle`,
  which stay in the image (`swayidle` + AUR `swaylock-effects`) as the fallback.
  `hyprtk-first-run` keeps its plain-swaylock fallback for when the AUR build
  is absent. No skel/link changes were needed: `~/.config/hypr` and
  `~/.config/wal` are already linked wholesale, so `hyprlock.conf`,
  `hypridle.conf` and the pywal colour fragment ship automatically.

## [2026-10-06]

### Added

- **A GTK 4 GUI** (`python/hyprtk_isocreator/`, launcher `hyprtk-iso-creator`).
  It is a short wizard over the same `hyprtk-iso-builder.sh`: choose the dotfiles
  source, name/label and output locations, toggle the AUR/matuwall/profile-only
  options, review, then watch the builder's **live output** as the ISO is
  assembled. The app runs unprivileged; only the builder (which needs root for
  `mkarchiso`) is elevated, by `hyprtk_isocreator.helper` launched through
  `pkexec`. Themed from the running hyprtk-bar theme, like the hyprtk-usb GUI.
  Install with `bash install.sh`; `python/pyproject.toml` packages it and
  `python/tests/` covers the option/argument and log-parsing logic.

### Changed

- **`install.sh` is now self-contained.** It copies the builder and the profile
  assets it reads (`hyprtk-iso-builder.sh`, `airootfs/`, `packages.hyprtk`,
  `aur-packages.txt`) into `~/.local/share/hyprtk-iso-creator/repo/` and records
  that path, so the installed app no longer depends on the checkout surviving.

## [Unreleased] - 2026-09-22

### Changed

- **Repository renamed** `Arch-Linux-ISO-Creator` → `Hyprtk-ISO-Creator`
  (<https://github.com/hyprtk/Hyprtk-ISO-Creator>). The README clone URL and the
  `git` remote are updated; GitHub keeps a redirect from the old name.
- **Builder renamed** `arch-iso-builder.sh` → `hyprtk-iso-builder.sh`.
- **Default hyprtk source is now `~/hyprtk`**, falling back to cloning
  `hyprtk/dotfiles` when it is absent. `--hyprtk-dir` / `$HYPRTK_DIR` still take
  precedence.
- **`python-dbus-next` is baked into the image**, so the bar's venv finds it in
  `--system-site-packages` and first login (`hyprtk-first-run`) needs no network.

### Added

- **`CHANGELOG.md`** (this file).
- **USB writing + persistence** is provided by the standalone
  [hyprtk-usb](https://github.com/hyprtk/hyprtk-usb) Go app; the README's *Make a
  USB stick* section points at it.

### Removed

- The bundled `hyprtk-usb` shell writer — superseded by the standalone
  [hyprtk-usb](https://github.com/hyprtk/hyprtk-usb) Go app (`dd` the ISO, append
  a 1 MiB-aligned `hyprtk-persist` ext4 partition, preserving the ISO's MBR
  entries).

### Fixed

- **Papirus icons and their colour scripts were missing from the ISO.** The skel
  builder trimmed `assets/papirus-icons/` out of `~/hyprtk`, which also removed
  `papirus-folders.sh` and the `hyprtk-*.sh` recolour scripts, so the icon-colour
  menu did nothing. They are baked into `/etc/skel` again (the ISO grows by only
  ~4 MiB because squashfs dedups the icon data against the packaged
  `papirus-icon-theme`).
- **The bar (and rofi app menu) never launched on an installed system.** On the
  build host `~/.local/bin` is a symlink into `installer/standalone`, so running
  the bar installer wrote its launchers there; the skel rsync then vendored those
  host-specific launchers (with hardcoded `/home/<builder>` paths) into the ISO.
  On the target the stale `~/.local/bin/hyprtk-bar` existed and was executable
  while the venv behind it was gone, and `hyprtk-first-run` gated on that
  launcher — so it skipped the install entirely. The builder now excludes the
  generated launchers, and first-run gates on the venv, clears stale launchers
  and only stamps after a successful install.

## [2026-09-21]

### Added

- **Live ISO** from the archiso `releng` profile with the hyprtk desktop
  preinstalled: every package in `packages.hyprtk`, the host-built AUR extras,
  matuwall built from source, the dotfiles vendored into `/etc/skel`, and SDDM
  autologin straight into Hyprland for the live user `hyprtk`.
- **`hyprtk-deploy`** — the offline live-to-disk installer (GPT single disk,
  `rsync` clone, GRUB for UEFI + BIOS, identity setup), with non-interactive flags
  (`--target`, `--user`, `--hostname`, … `--yes`) and a refusal to target the live
  medium.
- The `/etc/skel` tree is packed as `skel.tar` (mkarchiso strips overlay modes)
  and `oh-my-zsh` + its three plugins are baked for offline first login.
- The per-user pywal cache is provisioned at install time so the first boot is
  already themed.

### Fixed

- matuwall built from the new C/meson source; AUR GPG verification handled;
  staged AUR packages installed one at a time through a throwaway `pacman.conf`
  (`CheckSpace` off, `SigLevel = Never`).
- `/etc/skel` and `/usr/lib/os-release` staged under `/usr/share/hyprtk-iso/` to
  avoid `pacstrap` file conflicts.

## [2026-02-23]

### Added

- Initial `arch-iso-builder.sh`, building the stock archiso `releng` profile.
