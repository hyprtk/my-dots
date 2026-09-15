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
| Hyprland + portals | ✅ repo | ✅ (0.56 PPA¹) | ✅ (COPR for older) | ✅ Tumbleweed | ✅ | ✅ edge | ✅ | ✅ |
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
the gotcha below.

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

Arch/Void and rolling releases ship ≥ 0.55. Ubuntu 26.04's archive ships
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
`hyprtk_run_root` uses `sudo` when present and non-root. Minimal containers
without `sudo` must run the installer as root.

### AUR helper on Arch
`1-install.sh` builds `yay` on Arch when no helper is present (needs
`base-devel` + `git`). Without a helper, AUR packages are skipped with a warning.

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
   The only remaining archive gap is `nvidia-driver` (Ubuntu needs the versioned
   `nvidia-driver-5xx`).

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
