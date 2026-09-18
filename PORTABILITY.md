# Portability

hyprtk targets **Hyprland sessions on any Linux distribution**. It is not
cross-compositor — the dotfiles, keybindings and hyprtk-bar all drive Hyprland
through `hyprctl` and the Hyprland event socket, so they will not run under
GNOME/KDE/X11/sway.

This document scopes what the installer does on each distribution family, what
is Arch-only, and where it degrades gracefully.

## Package-manager abstraction

`installer/scripts/pkgmanager.sh` is the single portability layer. Every
`hypr/packages/*.sh` script, the misc `installer/scripts/*.sh` helpers and the
top-level `1-install.sh` source it. It provides:

| Function | Purpose |
|----------|---------|
| `hyprtk_detect_pm` | Returns `pacman`/`apt`/`dnf`/`zypper`/`xbps`/`apk`/`emerge`/`nix`/`none` |
| `pkg_install` | Install a list; a bad name is isolated, not fatal (batch first, then per-package) |
| `pkg_remove` | Best-effort remove; never fatal |
| `pkg_is_installed` | Query per manager |
| `aur_install` | Arch AUR via `yay`/`paru`; warns (never fails) elsewhere |
| `hyprtk_run_root` | Runs as root directly or through `sudo` |

The historic `_installPackagesPacman` / `_installPackagesYay` /
`_isInstalledPacman` helpers in `library.sh` are kept as thin wrappers, so
existing callers keep working.

### Exhaustive per-family lists

Each package script carries a `case "$HYPRTK_PM"` with the **complete native
package list** for every family it supports. There is no fallback
"assume-the-Arch-name" mapping — names are explicit, and a package that does not
exist on a family is simply absent from that family's list (or isolated by
`pkg_install`). Scripts also support `--list` so the installer can preview the
packages in its spinner.

## Distro support matrix

| Family | Package manager | Status |
|--------|-----------------|--------|
| Arch / Manjaro / CachyOS / EndeavourOS / Garuda / RebornOS / Archbang / Archcraft / Archman / Bluestar / Kiro | pacman (+ AUR) | Supported (baseline, per-distro hooks) |
| Debian / Ubuntu (+ Mint, Pop, Kali, …) | apt | Supported |
| Fedora / RHEL / CentOS / Rocky / Alma (+ Amazon, Oracle) | dnf | Supported |
| openSUSE (Tumbleweed / Leap) | zypper | Supported |
| Void Linux | xbps | Supported |
| Alpine Linux | apk | Supported (needs `bash`) |
| Gentoo | emerge | Manual (packages listed, never installed) |
| NixOS | nix | Declarative (packages listed as inputs) |
| Anything else | — | Detected as `unknown`; dotfiles still install, packages are listed for manual install |

`1-install.sh` auto-detects the family from `/etc/os-release` (`ID` then
`ID_LIKE`), with a manual fallback menu that now includes the generic families.

## What is Arch-only

These features are AUR- or tooling-specific and are **skipped with a warning**
on other families (the rest of the install continues):

| Feature | Why |
|---------|-----|
| AUR packages (`swaylock-effects`, `brave-bin`, `bibata-cursor-theme`, `trizen`, `sublime-text-4`, `sddm-theme-sugar-candy-git`, `pacseek`, `pamac-*`, `github-desktop-bin`, `waypaper`, `hyprquickframe-git`, `thunar-shares-plugin`, `tumbler-extra-thumbnailers`, `vmware-*`, `orca-slicer-bin`, `bambustudio-bin`, `libva-nvidia-driver-git`) | No AUR off Arch. Where a repo equivalent exists it is listed in the family's `PKGS` (e.g. `swaylock`, `papirus-icon-theme`). |
| `hyprviz-bin` build | AUR-only GUI; source build is referenced instead. |
| `pacman -Ssq 'pcp-pmda-*'` (Performance Co-Pilot modules) | Arch packaging only. |
| `mkinitcpio` module edits + `install_boot` splash | Arch initramfs. Other families regenerate with `update-initramfs`/`dracut` where present. |
| `os-release-<distro>` branding → `/usr/lib/` | The 11 Arch-based distros only; other systems keep their own os-release. |
| `snap-pac` | Arch pacman snapshot hook. |
| `pacman -Syu` update alias | Root `.bashrc` now detects the manager instead. |

### awww is no longer Arch-only

The wallpaper daemon (`awww`, the renamed swww) is **not** in the AUR-only list
above: `installer/scripts/awww-install.sh` gives it a cross-distro path. Arch
still gets it from the AUR via `hypr/packages/hyprland.sh`; Void and Alpine
install the native `swww` package; Debian/Ubuntu, Fedora/RHEL and openSUSE have
no package at all and **build it from source** (see the gotcha below).

## Feature availability

| Area | Arch | Debian/Ubuntu | Fedora | openSUSE | Void | Alpine | Gentoo | Nix |
|------|------|---------------|--------|----------|------|--------|--------|-----|
| Hyprland + portals | ✅ repo | ✅ (0.56 PPA¹) | ⚠️ COPR³ | ✅ Tumbleweed | ⚠️ community repo³ | ✅ source⁴ | ✅ | ✅ |
| GTK3/4 + gtk-layer-shell | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Python GI bindings | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| XFCE fallback | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (plugins) | ✅ | ✅ |
| Terminal/editor/browser set | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Fonts (Fira / Font Awesome) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| GPU drivers (Intel/AMD/NVIDIA) | ✅ | ✅ | ✅ (RPMFusion) | ✅ | ✅ | ✅ | ✅ | ✅ |
| QEMU/KVM + virt-manager | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| VMware Workstation | ✅ AUR | ✗ bundle | ✗ bundle | ✗ bundle | ✗ bundle | ✗ bundle | ✗ bundle | ✗ | 
| SDDM + Sugar-Candy theme | ✅ | ✅ SDDM (theme AUR) | ✅ SDDM (theme AUR) | ✅ SDDM (theme AUR) | ✅ SDDM | ✅ SDDM | ✅ SDDM | ✅ SDDM |
| pywal16 (`wal`) | ✅ bundled | ✅ bundled | ✅ bundled | ✅ bundled | ✅ bundled | ✅ bundled | ✅ bundled | ✅ bundled |
| Wallpaper daemon (`awww`) | ✅ AUR | ✅ source² | ✅ source² | ✅ source² | ✅ `swww` | ✅ `swww` (3.24+) | ⚠ manual | ✅ flake |
| hyprtk-bar | ✅ | ✅ | ✅ | ✅ | ✅ | ✅* | ✅ | ✅ |

`✅*` = hyprtk-bar supports Alpine from edge (gtk-layer-shell ≥ 0.9).<br>
`¹` = Ubuntu: the installer adds the `cppiber/hyprland` PPA so Hyprland ≥ 0.55
(the Lua config) is installed; see the Hyprland gotcha below.<br>
`²` = built from source by `awww-install.sh`; needs a Rust toolchain (rustup when
the distro's rustc is older than upstream's MSRV) and the build deps listed in
the gotcha below.<br>
`³` = Fedora packages Hyprland only in a **COPR** (`solopasha/hyprland`); Void
packages it — and none of its libraries — not at all (a packaging-philosophy
conflict). On Void `hyprland-src-install.sh` builds the pinned release **and** the
whole hyprwm library chain from source (see the Hyprland gotcha below); the
community **[hyprland-void-packages](https://github.com/void-land/hyprland-void-packages)**
binary repo is the documented manual fallback if that build fails.<br>
`⁴` = Alpine: no version of Hyprland ≥ 0.55 is packaged (3.24 **and** edge ship
0.54.3), so `hyprland-src-install.sh` builds the pinned upstream release from
source — see the Hyprland gotcha below.

## Gotchas

### bash is required
`1-install.sh`, the package scripts and the misc helpers use bash (arrays,
`BASH_SOURCE`). The package scripts are now invoked with `bash` explicitly, not
`sh`. On Alpine (and minimal Void) install bash first:

```sh
apk add bash   # or: xbps-install -S bash
```

### Repository availability varies by release
`hyprland`, `xdg-desktop-portal-wlr`, `cliphist`, `nwg-look`, `hyprsunset`,
`gtk4-layer-shell`, `mission-center` and friends are recent packages. On older
LTS releases they need a backport/PPA/COPR/sid; the installer's per-package
fallback warns and continues if one is unavailable.

### Package names differ per family
Names are not portable — each `hypr/packages/*.sh` keeps an explicit list per
family. Audited corrections (see CHANGELOG): `libgtk-layer-shell0` /
`libgtk4-layer-shell0` (apt, not `gtk-layer-shell`), `printer-driver-cups-pdf`
(apt, not `cups-pdf`), `fonts-firacode` (apt) vs `fira-code-fonts`
(Fedora/openSUSE) vs `fira-code` (Void/Alpine), `freerdp3-x11` (apt),
`7zip`/`Thunar`/`libusb1`/`pipewire-pulseaudio` (Fedora), `micro-editor` and
`libnotify-tools` (openSUSE), `Thunar` (Void, capitalised). `mission-center`
and `thunar-shares-plugin` are Arch-only. A wrong name is isolated by
`pkg_install` and only warns — so verify each name in every family's repo when
adding a package.

### gtk-layer-shell age
hyprtk-bar needs gtk-layer-shell ≥ 0.9. Families below that floor (Debian ≤ 12,
Ubuntu ≤ 24.04, Fedora ≤ 40, openSUSE Leap 15.x, Alpine ≤ 3.20) need a newer
release or a source build; the bar's own installer warns.

### Hyprland ≥ 0.55 (Lua config)
Since Hyprland 0.55 the config language is Lua (`hyprland.lua`). The dotfiles are
entirely Lua-based (`hypr/hyprland.lua` + `require(...)`), so **Hyprland < 0.55
ignores them and generates a stock `hyprland.conf`** — autostart, keybindings and
windowrules then never apply.

Arch and rolling releases ship ≥ 0.55; Void ships no Hyprland at all (built from
source — see below). Ubuntu 26.04's archive ships
`0.53.3`, so `hypr/packages/hyprland.sh` adds the community PPA
[`ppa:cppiber/hyprland`](https://launchpad.net/~cppiber/+archive/ubuntu/hyprland)
(0.56.2 for resolute) on Ubuntu before installing. The PPA's `libhyprcursor1` /
`libudis86.1` supersede the archive's `libhyprcursor0` / `libudis86-0` without
declaring `Replaces`, so the step installs with
`-o Dpkg::Options::=--force-overwrite` to get past the overlapping file lists.

Debian has no equivalent PPA and its archive Hyprland predates 0.55, so the
installer warns and installs it anyway (the desktop won't read the Lua config
until Debian — or a backport — provides ≥ 0.55). Verify a live session with:

    Hyprland --version                 # >= 0.55
    hyprctl configerrors               # empty
    hyprctl binds | grep -c dispatcher # > 0

**Alpine** ships 0.54.3 on 3.24 *and* edge, so `hyprland-src-install.sh` builds
the pinned upstream release (`v0.56.2`) from source into `/usr` — idempotent
(skips once `Hyprland --version` is ≥ 0.55) and non-fatal, like `awww-install.sh`.
It also ensures the two deps Alpine is too old for:

- **wayland-protocols ≥ 1.49** (3.24 has 1.48) — the XML-only release is built
  with meson;
- **hyprutils ≥ 0.14.0** (3.24/edge have 0.13.1) — built with cmake.

The rest of the stack is already new enough (`aquamarine` 0.12, `hyprlang`
0.6.8, `hyprcursor` 0.1.13, `hyprgraphics` 0.5.1, `hyprwayland-scanner` 0.4.6),
and the build needs Lua **5.5** (`lua5.5-dev`), `glslang-dev`,
`spirv-tools-dev` (glslang's CMake config pulls in `SPIRV-Tools-opt`),
`libei-dev` (for `libeis-1.0`) and `readline-dev`. Alpine's libstdc++ (GCC
15.2) has no `std::ranges::starts_with` (C++23), so the script patches that one
call in `src/helpers/MiscFunctions.cpp` before configuring. Expect the build to
take a few minutes; a reboot is required to start the new session.

**Void** packages neither Hyprland nor any of its libraries, so
`hyprland-src-install.sh` builds the pinned `v0.56.2` **and** the whole hyprwm
library chain into `/usr`, at the exact revisions Hyprland's `flake.lock` pins
(so the ABI matches). This step now runs **before** `srcapps-install.sh`, so
`hyprsunset`/`hyprpicker` link the same chain. Build order: `hyprland-protocols`,
`hyprutils`, `hyprlang`, `hyprcursor`, `hyprgraphics`, `hyprwire`, `aquamarine`
(`hyprwayland-scanner` only when the Void package ships no CMake config; `glaze`
is fetched by Hyprland's own CMake). Because Void's `hyprutils` (0.11.0) and
`hyprlang` are too old for 0.56, those two are version-checked and rebuilt from
the pinned revision *first*, so every consumer links one `libhyprutils`;
everything else is skipped when its `pkg-config` module resolves.

Void's toolchain is **GCC 14.2**, whose libstdc++ predates several C++23/26
library features the 0.56 stack uses, so the build patches them:

- `std::vector::append_range` (hyprwire, 16×) and `insert_range` (Hyprland) —
  replaced with a local helper (`_patch_gcc14_range_members`);
- `std::ranges::starts_with` — one call in `MiscFunctions.cpp`;
- `std::string + std::string_view` (C++26 P2591) — supplied by
  `installer/scripts/hyprtk-gcc14-compat.hpp`, force-included via
  `-DCMAKE_CXX_FLAGS`;
- `#embed` (C++26) — the example config is re-emitted as a raw string literal;
- `cond ? classWithPtrConversion : nullptr` — made explicit in `XWM.hpp`.

`wayland-protocols` 1.49 is new enough. Build deps are the Void `-devel`
packages (wayland, Mesa, cairo, pango, pixman, libXcursor, libei, libdrm,
libinput, libliftoff, libseat, elogind, libdisplay-info, re2, muparser, udis86,
xcb-\*, librsvg, file/libmagic, libwebp, libpng, tomlplusplus, readline) plus
`base-devel cmake ninja samurai meson pkgconf git jq python3 lua55-devel glslang
SPIRV-Tools-devel`. `wob` (the volume/brightness overlay) is unpackaged on Void
and is built by `srcapps-install.sh` too.

### Session lock can hang the compositor (aquamarine DRM page-flip race)
On some DRM drivers — most reliably in a VM (virtio-gpu) — aquamarine can hit
`drm: Cannot commit when a page-flip is awaiting` during a modeset/commit; the
compositor then hangs and the session is lost (no coredump). Locking the screen
forces a commit, so it is a common way to trigger it. This is an upstream
aquamarine/Hyprland bug (hyprwm/Hyprland#15469, hyprwm/aquamarine#343) — the
dotfiles cannot fix the hang itself, but they keep the session **recoverable**:

- `hypr/misc.lua` sets `misc.allow_session_lock_restore = true`, so a replacement
  lockscreen can take over a session that is still locked after the lock client
  died (Hyprland's default refuses it, which needs a reboot);
- the logout menu locks through `hypr/scripts/lock.sh`, which restarts swaylock
  after an abnormal exit instead of leaving the session locked.

### Wallpaper daemon (awww)
`installer/scripts/awww-install.sh` (called by `1-install.sh` before the wrapper)
acquires awww without the AUR:

- **Already installed** — nothing to do.
- **Native package** — Void and Alpine ship `swww`; the script installs it and
  adds `awww`/`awww-daemon` symlinks in `/usr/local/bin` so the dotfiles' `awww`
  calls work unchanged.
- **Source build** — Debian/Ubuntu, Fedora/RHEL and openSUSE (and any family
  whose native package is missing) build the pinned upstream release
  (`LGFae/awww` `v0.12.1`, GPL-3) with `cargo build --release --locked`. Build
  deps per family (from `common/build.rs`'s `liblz4` probe and the daemon's
  wayland-protocol XML needs):

  | Family | Build deps |
  |--------|------------|
  | apt | `build-essential pkg-config git curl ca-certificates libwayland-dev wayland-protocols liblz4-dev libxkbcommon-dev` |
  | dnf | `gcc gcc-c++ make pkgconf-pkg-config git curl ca-certificates wayland-devel wayland-protocols-devel lz4-devel libxkbcommon-devel` |
  | zypper | `gcc gcc-c++ make pkg-config git curl ca-certificates wayland-devel wayland-protocols-devel liblz4-devel libxkbcommon-devel` |
  | xbps | `base-devel pkg-config git curl wayland-devel wayland-protocols liblz4-devel libxkbcommon-devel` |
  | apk | `build-base pkgconf git curl wayland-dev wayland-protocols lz4-dev libxkbcommon-dev` |

  Upstream's MSRV (`rust-version = 1.89.0`, edition 2024) is newer than every
  LTS release's packaged `rustc`, so when the system `cargo` is missing or too
  old the script bootstraps Rust with **rustup** (`--profile minimal`) into
  `~/.cargo`. The binaries land in `/usr/local/bin` with `swww` compatibility
  symlinks.
- **No route** (Gentoo/NixOS, or a failed build) — a warning with the manual
  steps, never a fatal error; the rest of the install continues and the bar
  degrades to its fixed palette until awww is present.

Because the source build needs network + a Rust toolchain and can take a few
minutes, expect that step to be the slowest part of a non-Arch install. Set
`HYPRTK_DRYRUN=1` to have the script print its plan without building.

### sudo vs root
`hyprtk_run_root` uses `sudo` when present, then `doas`, and runs directly when
already root. On doas-only systems (Alpine) `pkgmanager.sh` also defines and
exports a `sudo`→`doas` compatibility function so every existing `sudo ...`
call site (including `bash -c` subshells and scripts invoked as `bash foo.sh`)
works unchanged, and `1-install.sh`'s `_sudo_bootstrap` authenticates once and
installs a temporary `/etc/doas.d/99-hyprtk-install.conf` nopass drop-in for the
rest of the install (removed on exit — doas.d is last-match, so the drop-in must
sort last). Minimal containers without `sudo`/`doas` must run as root.

### Alpine needs eudev, OpenRC services and XDG_RUNTIME_DIR
Alpine defaults to busybox **mdev**, which never applies elogind's udev rules,
so the DRM card is not tagged `master-of-seat`. elogind then reports
`CanGraphical=no` and **SDDM never starts a greeter**, and a session started
from a tty dies with `XDG_RUNTIME_DIR is not set`. The installer therefore, on
`apk`:

- installs **eudev**/**eudev-openrc** and enables the `udev`, `udev-trigger`,
  `udev-settle` (sysinit) and `udev-postmount` (default) services, removing
  `mdev` from sysinit — **a reboot is required** for the graphical seat;
- enables the OpenRC services the desktop needs at boot (`dbus`, `elogind`,
  `sddm`), which Alpine does not enable by itself;
- writes `/etc/profile.d/99-xdg-runtime-dir.sh` so a plain tty login (busybox
  `login` is not PAM-aware, so nothing sets `XDG_RUNTIME_DIR`) gets one.

Alpine's SDDM is Qt6-only (`sddm-greeter-qt6`); the upstream Sugar-Candy theme
metadata has no `QtVersion`, so SDDM looks for the Qt5 greeter, fails to find
it and silently falls back to its built-in theme — `sddmgrub.sh` appends
`QtVersion=6` to the theme metadata alongside the existing QML import patch.

### SDDM Sugar-Candy greeter (Qt6): input driver and theme patches
The X11 greeter needs its own X input driver: `xorg-server` alone is not enough,
and on Alpine (no `xf86-input-libinput`) Xorg logs *"No input driver specified,
ignoring this device"* for every keyboard and pointer, so **the password box
cannot be typed into at all**. `sddmgrub.sh` now installs the input driver
alongside the X server for every off-Arch family
(`xserver-xorg-input-libinput`, `xorg-x11-drv-libinput`, `xf86-input-libinput`).

Two Sugar-Candy theme bugs also show up under Qt6 (`Components/Input.qml`),
patched idempotently by `sddmgrub.sh` (`// hyprtk:` markers):

- the user-field icon is a `Button` with no `background`, so Qt6's default style
  paints a **black square behind the white user glyph** (seen on Alpine, Fedora
  and openSUSE) — it gets a transparent background;
- the login handler reads the `username` TextField, whose `ForceLastUser`
  binding is empty at click time under Qt6, so SDDM authenticates with an empty
  username and always fails — it now falls back to the user selector's
  `currentText`.

### AUR helper on Arch
`1-install.sh` builds `yay` on Arch when no helper is present (needs
`base-devel` + `git`). Without a helper, AUR packages are skipped with a warning.

### apt installs must be lock-tolerant and non-interactive (Mint/Ubuntu)
On a real Linux Mint / Ubuntu desktop the package phase can appear to **freeze
("go stale")** — most visibly in the largest batch (`system.sh`). Two causes,
both invisible inside the `gum spin` that wraps each `hypr/packages/*.sh` step:

1. **The dpkg/apt lock.** Mint's background updaters (`mintupdate` /
   `mintupdate-tool`, `unattended-upgrades`, `packagekit`, the `apt-daily`
   timers) can hold `/var/lib/dpkg/lock-frontend`, and a plain `apt-get` waits
   for it indefinitely while the spinner shows nothing.
2. **Interactive prompts.** `debconf` and `needrestart` can ask questions
   ("Which services should be restarted?") whose prompt is buried in the spinner.

`pkgmanager.sh` therefore funnels every apt call through `_apt`, which sets
`DEBIAN_FRONTEND=noninteractive` + `NEEDRESTART_MODE=a` and passes
`-o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef
--force-confold`. `1-install.sh` also calls `hyprtk_apt_wait_lock` before the
core package loop: it waits *visibly* (via `flock -n` on the dpkg/apt locks, 5s
steps, 10-minute cap) and announces "apt is locked by a background updater —
waiting…", so a held lock is explained rather than looking frozen. The in-script
apt calls (`hyprland.sh`, `webtools.sh`) use `_apt` too.

## Verification

The dry-run harness (`installer/scripts/verify/installer-dryrun.sh`) stubs every
system-mutating command and runs the full installer for all 11 Arch-based
distros. A parallel non-Arch harness exercises the generic families
(`debian`, `fedora`, `suse`, `void`, `alpine`, `gentoo`, `nixos`). Both must
reach `INSTALLATION COMPLETE` with no `FATAL`/`FAIL`/`SPIN FAILED`/`RUN FAILED`
entries and a clean run log.

### Package-name container matrix (T1)

`installer/scripts/verify/container-matrix.sh` is the authoritative check that
every native package name the installer uses resolves on its family. For each
family it collects the names from `hypr/packages/*.sh` (`--list`) plus the
vendored bar's `DEPS`/`EXTRAS`, then resolves them in a throwaway **rootless
podman** container *without installing*:

| family | image | resolve with |
|--------|-------|--------------|
| pacman | `archlinux:latest` | `pacman -Si` / `-Sg` (+ AUR RPC for misses) |
| apt | `debian:bookworm`, `debian:trixie`, `ubuntu:24.04`, `ubuntu:26.04`, `linuxmintd/mint22.3-amd64` | `apt-get install -s` |
| dnf | `fedora:latest` | `dnf repoquery --available` |
| zypper | `opensuse/tumbleweed` | `zypper install --dry-run` |
| xbps | `voidlinux/voidlinux` | `xbps-query -R -p pkgver` |
| apk | `alpine:latest` | `apk search -e` |

Arch names absent from the official repos but present in the **AUR** are
reported `AUR` (expected, not a failure). Gentoo/NixOS are advisory —
`1-install.sh` only prints their names, so they are listed but not resolved.
Known-acceptable gaps (third-party repos, non-free components, packages not in a
release) live in `installer/scripts/verify/container-matrix.allow`. Current
result: **1173 resolvable, 21 AUR, 77 allow-listed, 0 unexpected.**

On a host whose kernel lacks overlayfs (e.g. this one), rootless podman needs a
storage-driver drop-in; `~/.config/containers/storage.conf.d/00-vfs.conf` selects
`vfs` (Arch's `/usr/share/containers/storage.conf.d/00-storage-arch.conf` forces
`overlay`). The matrix images bake the resolver query, so no extra host tooling
is required.

### Full installer dry-run in containers (T2)

`installer/scripts/verify/container-dryrun.sh` is the containerised counterpart
of `installer-dryrun.sh`: it runs the **whole** installer inside a throwaway
container for every family/variant (Arch, Debian 12/13, Ubuntu 24.04/26.04,
Fedora, openSUSE, Void, Alpine; Gentoo/NixOS advisory). Inside the container it
builds a sandbox `$HOME` with the repo at `~/hyprtk` (code copied, the large
read-only asset trees symlinked), stubs every mutating command **and the
family's package manager**, swaps the bundled `gum` for a non-interactive stub,
and runs `1-install.sh` with `HYPRTK_DRYRUN=1`. It requires the
`hyprtk installation completed` marker in `install.log` and no
`FATAL`/`FAIL`/`SPIN FAILED`/`RUN FAILED` (or run-log errors). Gentoo/NixOS are
advisory: the run must complete, but the bar's dependency step is allowed to
fail there (the installer never installs packages automatically on those
families).

Result: **12/12** — the ten installable family/variant rows (Arch, Debian 12/13,
Ubuntu 24.04/26.04, **Linux Mint 22.3**, Fedora, openSUSE, Void, Alpine) complete
cleanly; Gentoo and NixOS complete with package deps skipped. Base-image quirks
handled by the row bootstrap: openSUSE ships no `awk` (install `gawk`), Void
needs an `xbps` self-update before `bash`, and the `nixos/nix` build image has no
`/etc/os-release` and no `sed`/`awk` (bootstrap `gnused`/`gawk` + a stub
os-release). The Mint row rewrites the image's os-release to real-Mint values
(`ID=linuxmint`, `VERSION_CODENAME=wilma`, `UBUNTU_CODENAME=noble`) so detection
and the PPA codename logic are genuinely exercised.

## Remaining work

1. Package names are audited across all families by the container matrix (see
   above): 1173 resolve, 0 unexpected. The remaining 77 are documented in
   `container-matrix.allow` — third-party repos (RPMFusion, COPR, Brave, PPAs),
   non-free components (Debian/Void/Alpine), and packages genuinely absent from
   a release (e.g. `cliphist`, `swappy`, `nss-mdns`, `ipp-usb`). Closing these
   means adding the third-party repos at install time (as `webtools.sh` already
   does for Brave) — not renaming. On the Ubuntu family the installer now adds
   the **cppiber/hyprland** PPA (Hyprland `>= 0.55` + hyprpicker/hyprsunset) and
   the **zhangsongcui3371/fastfetch** PPA via `hyprtk_apt_add_ppa` (explicit
   keyring + `sources.list.d`, since `add-apt-repository` needs a reachable
   Launchpad API and fails on minimal/containerised Ubuntu & Mint). Packages no
   archive carries are then built/installed by `srcapps-install.sh` (see below).
   `nvidia-driver` is handled by a versioned fallback in `graphics-card.sh`
   (Ubuntu/Mint ship no generic meta; the newest `nvidia-driver-5xx` is picked).

### Source-built apps (`srcapps-install.sh`)

Some apps are absent from the archives of several families. `installer/scripts/
srcapps-install.sh` fills those gaps after the package steps — idempotent (skips
when already present) and non-fatal (a failed build warns and the install
continues), like `awww-install.sh`. `HYPRTK_DRYRUN=1` prints the plan.

| app | how | why |
|-----|-----|-----|
| gtk4-layer-shell | meson build, `v1.3.0` (`-Dvapi=false -Dintrospection=false`) | matuwall's `LD_PRELOAD`; missing on noble/Mint/bookworm |
| swappy | meson build, `v1.8.0` | `grim.sh` screenshot editor; missing on noble/bookworm/Alpine |
| nwg-look | `go build`, `v1.1.1` | GTK settings tool; missing on Ubuntu/Debian/Alpine, COPR on Fedora |
| starship | upstream installer (`starship.rs/install.sh`, `v1.26.0`) | shell prompt; missing on noble/bookworm/Fedora/Alpine |

The build deps are defined per family (`apt`/`dnf`/`zypper`/`xbps`/`apk`). For
gtk4-layer-shell it also creates `/usr/lib/libgtk4-layer-shell.so` pointing at the
real library (via `pkg-config --variable=libdir`, with `lib`/`lib64` fallbacks),
because the dotfiles' matuwall launch hard-codes that Arch path. Verified with
real builds in containers: **Linux Mint 22.3**, **Alpine** and **Fedora** all
install all four; the `LD_PRELOAD` symlink resolves on multiarch
(`x86_64-linux-gnu`) and Fedora (`lib64`) layouts.
2. Add the matrix to CI (mirroring hyprtk-bar's `.github/workflows/install-matrix.yml`)
   so the per-family lists are validated on every push without a VM.
3. Gentoo/NixOS: provide an ebuild set / Nix expression so those families are
   first-class instead of "listed for manual install".
4. `awww-install.sh` source build is validated (T3): Ubuntu 24.04, Fedora and
   openSUSE Tumbleweed all build `awww 0.12.1`. **Debian 12 cannot** — it ships
   libwayland 1.21 and awww needs >= 1.22; the script now detects this and fails
   fast with a clear message. Void/Alpine use the native `swww` package (the
   `swww`→`awww` symlink path is exercised by the `NATIVE_PKG` branch).
