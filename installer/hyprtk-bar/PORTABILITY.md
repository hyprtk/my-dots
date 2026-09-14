# Portability

hyprtk-bar targets Hyprland sessions on any Linux distribution. It is **not**
cross-compositor — the bar drives Hyprland through `hyprctl` and the Hyprland
event socket, so it will not run under GNOME/KDE/X11/sway.

This document scopes what it takes to install the bar on a non-Arch distro, and
what still assumes Arch or the full hyprtk dotfiles tree.

## Dependency model

The bar's dependencies split into three layers:

1. **GObject-Introspection typelibs** (system packages, required to run). The
   bar loads GTK through PyGObject's GI, not direct C linking, so the *typelib*
   packages are what matter, not `-dev` headers — except on Void and Alpine,
   where the typelibs themselves live in the `-devel`/`-dev` subpackages.
2. **Python bindings** — `pygobject` (PyGObject), `pycairo`, `dbus-next`
   (pure-Python). PyGObject and pycairo publish **no binary wheels**, so
   `install.sh` installs them from the distro's package manager (not pip) and
   runs the bar in a `--system-site-packages` venv; only `dbus-next` is
   pip-installed. This removes any compiler requirement.
3. **Subprocess tools** — called on demand; each feature degrades gracefully
   when its tool is missing.

### GI typelibs used

| Typelib            | Used by                        |
|--------------------|--------------------------------|
| `Gtk-3.0`          | everything                     |
| `Gdk-3.0`          | windows / pixbuf               |
| `GtkLayerShell-0.1`| layer-shell anchoring          |
| `GLib-2.0`         | proc / GObject                 |
| `Pango-1.0`        | font + glyph sizing            |
| `GdkPixbuf-2.0`    | themer image handling          |
| `cairo`            | graphs + swaylock preview      |

### Subprocess tools

| Tool             | Feature                          |
|------------------|----------------------------------|
| `hyprctl`        | required (compositor IPC)        |
| `nmcli`          | quick settings network + tray    |
| `bluetoothctl`   | quick settings bluetooth + tray  |
| `wpctl`          | volume / mic (wireplumber)       |
| `brightnessctl`  | brightness (no backlight → hidden)|
| `dmidecode`      | memory DIMM readout (sudo)       |
| `lsblk`/`lspci`  | disks / GPU identity             |
| `rocminfo`       | AMD GPU clocks                  |
| `checkupdates`   | pacman update query (Arch)       |
| `pkexec`         | SDDM/GRUB update, system kill    |
| `xdg-settings`   | default-browser resolution       |
| `gtk-update-icon-cache` | icon cache refresh         |
| `update-desktop-database` | desktop entry install     |

## Feature availability

Each feature degrades gracefully when its backing binary is absent — the bar
never crashes and never requires a binary that isn't installed. The core
surface works on every distro; only the *theming* wall is Arch/AUR-centric.

| Feature              | Backing binary | Arch | Debian/Ubuntu | Fedora | openSUSE | Void | Alpine | Nix |
|----------------------|----------------|------|---------------|--------|----------|------|--------|-----|
| Bar / window control | `hyprctl` (required) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Workspaces / tasklist| `hyprctl`      | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Notifications        | in-bar (D-Bus) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| System tray          | in-bar (SNI)   | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Volume / mic         | `wpctl`        | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Network              | `nmcli`        | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Bluetooth            | `bluetoothctl` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Brightness           | `brightnessctl`| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| System monitor       | `/proc`+`/sys`+`lsblk`+`lspci` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| DIMM readout         | `dmidecode`    | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| GPU stats            | `rocminfo`/`lspci` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Clipboard history    | `cliphist`+`wl-clipboard` | ✅ | ✅ | ✅ | ✅ | ✅ | ✗(edge) | ✅ |
| Apps menu            | in-bar (+`rofi`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Rofi theming         | `rofi`         | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Updates              | bundled sh (distro-agnostic) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Wallpaper daemon     | `awww`/`swww`  | AUR | ✗ | ✗ | ✗ | ✅ | ✅(3.24+) | ✅(26.05+) |
| Pywal colours        | bundled (`vendor/pywal16`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Gamma (no backlight) | `hyprsunset`   | ✅ | backports/sid | ✗ | Factory | ✗ | edge | ✅ |
| Folder-icon colour   | `papirus-folders` | AUR | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Matuwall integration | `matugen`      | ✅ | ✗ | ✗ | ✗ | ✗ | ✗ | ✅ |
| SDDM & GRUB          | `sddm/update.sh` | ✅* | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Screenshot           | `ssdetect.sh`  | ✅* | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

`✅*` = dotfiles-owned (needs the full hyprtk tree, not a standalone install).

The **theming wall** — the wallpaper daemon (`awww`/`swww`) and folder-icon
colouring (`papirus-folders`) — degrades to the bar's built-in default palette
when its (AUR/niche) binaries are absent. pywal colours are **bundled**
(`vendor/pywal16`, exposed as `wal`), so palette generation is always available;
without a wallpaper daemon the bar simply doesn't re-tint automatically from the
wallpaper, so a standalone install keeps a fixed accent rather than dynamic
wallpaper colours.

## Distro support matrix

| Family           | Package manager | Status |
|------------------|-----------------|--------|
| Arch / Manjaro   | pacman          | Supported (baseline) |
| Debian / Ubuntu  | apt             | Supported (needs `python3-venv`) |
| Fedora / RHEL    | dnf             | Supported |
| openSUSE         | zypper          | Supported |
| Void Linux       | xbps            | Supported (needs bash; typelibs in `-devel`) |
| Alpine           | apk             | Supported (needs bash; typelibs in `-dev`) |
| Gentoo           | emerge          | Manual (packages listed) |
| NixOS            | nix             | Flake (`flake.nix` + `derivation.nix`) |

The cross-distro CI matrix (`.github/workflows/install-matrix.yml`) runs the
installer in a container per family to keep these rows honest.

## Package mapping

`install.sh` installs these automatically per detected package manager. Manual
reference for the rest:

| Dep                | pacman | Debian/Ubuntu | Fedora | openSUSE | Void | Alpine | Gentoo |
|--------------------|--------|---------------|--------|----------|------|--------|--------|
| GTK3 typelib       | `gtk3` | `gir1.2-gtk-3.0` | `gtk3` | `typelib-1_0-Gtk-3_0` | `gtk+3` | `gtk+3.0` | `x11-libs/gtk+:3` |
| layer-shell        | `gtk-layer-shell` | `gir1.2-gtklayershell-0.1` | `gtk-layer-shell` | `gtk-layer-shell` | `gtk-layer-shell` | `gtk-layer-shell` | `gui-libs/gtk-layer-shell` |
| PyGObject          | `python-gobject` | `python3-gi` + `python3-gi-cairo` | `python3-gobject` | `python3-gobject` + `python3-gobject-Gdk` | `python3-gobject` | `py3-gobject3` | `dev-python/pygobject` |
| GdkPixbuf          | `gdk-pixbuf2` | `gir1.2-gdkpixbuf-2.0` | `gdk-pixbuf2` | `typelib-1_0-GdkPixbuf-2_0` | `gdk-pixbuf` | `gdk-pixbuf` | `x11-libs/gdk-pixbuf` |
| Pango              | `pango` | `gir1.2-pango-1.0` | `pango` | `typelib-1_0-Pango-1_0` | `pango` | `pango` | `x11-libs/pango` |
| cairo              | `cairo` | `gir1.2-cairo-1.0` | `cairo` | `cairo` | `cairo` | `cairo` | `x11-libs/cairo` |
| venv tooling       | built-in | `python3-venv` + `python3-pip` | `python3-pip` | built-in | built-in | `py3-pip` + `py3-virtualenv` | built-in |

## Gotchas

### venv / ensurepip
- Debian & Ubuntu split `ensurepip` out of the base interpreter, so
  `python3 -m venv` fails without `python3-venv`. Most other distros ship venv
  in the base `python3`. Alpine additionally needs `py3-virtualenv`.
- The installer installs `python3-venv`/`python3-pip` on apt systems (and the
  Alpine equivalents) automatically.
- The venv is created with `--system-site-packages` so the distro's own
  PyGObject/pycairo (installed via `DEPS`) are used; only `dbus-next` is
  pip-installed into it.

### PyGObject / pycairo have no wheels
- **Neither PyGObject nor pycairo publishes binary wheels at all** — pip can
  only install them from source, which needs a C compiler plus GI/cairo headers
  on *every* distro, not just musl. Verified: `pip download PyGObject pycairo`
  fetches `.tar.gz` source distributions (only `dbus-next` ships a `.whl`).
- `install.sh` therefore never pip-installs them. It installs the distro's own
  `python-gobject`/`python3-gi`/`py3-gobject3` (+ the pycairo equivalent) via
  the package manager, then runs the bar in a `--system-site-packages` venv.
  No compiler is required anywhere.

### `updates` module is distro-agnostic
- The module's default `updates.sh` and `installupdates.sh` are now **bundled**
  with the bar (`scripts/`), not the pacman-only dotfiles copies. Each script
  detects the package manager (pacman, apt, dnf, zypper, xbps, apk, emerge,
  nix) and runs the matching query/upgrade, so the indicator works standalone
  on any distro.
- Config stays overridable (`updates.script` + `updates.install_command`) for
  anyone who wants a custom updater. `update.sh`/`installupdates.sh` resolve
  bundled-first, dotfiles-copy as fallback.

### `~/hyprtk/...` assumptions
Several paths assume the full hyprtk dotfiles are installed at `~/hyprtk`, not
a standalone bar:
- `themer.py` — `wallpaper-colors.sh`, `change-icons.sh`, `sync-rofi-theme.sh`,
  `sddm/update.sh`, `assets/Wallpapers`.
- `config.py` quicklinks defaults (`updatewal-awww.sh`, `cliphist`, `ssdetect`).
- `menu/hypr_animations.py` — `~/hyprtk/hypr`.
- `center.start_command` — `hyprtk-bar-menu-toggle.sh`.

These must become configurable (or skip gracefully when the tree is absent)
before the bar is a fully standalone install.

### gtk-layer-shell age
Every distro family packages `gtk-layer-shell`, but older LTS releases ship
ancient versions. Use a reasonably current release (≥ 0.9) to avoid missing
layer-shell API.

Families below 0.9 (need a source build of gtk-layer-shell, or a newer distro
release):

- Debian ≤ 12 (0.8.0), Ubuntu ≤ 24.04 (0.8.2) — Ubuntu 20.04 ships 0.1.0, unusable
- Fedora ≤ 40, openSUSE Leap 15.x (0.8.2)
- Alpine ≤ 3.20, nixpkgs ≤ 24.05

Arch/Void/Gentoo and the newest releases of the others are ≥ 0.9.

## Remaining work

1. `yum` (RHEL/CentOS 7) detection is currently folded into `dnf` — verify the
   older `yum` install flags if those systems matter.
2. Auto-build gtk-layer-shell from source when it is present but < 0.9 (the
   installer currently warns and prints the manual steps instead).
3. Validate the `-devel`/`-dev` package names for Void/Alpine and the openSUSE
   `typelib-1_0-*` names via the CI matrix (the workflow exists; it needs a
   first run on GitHub Actions to confirm each name resolves).
