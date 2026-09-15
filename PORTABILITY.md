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
| Hyprland + portals | ✅ repo | ✅ (PPA/sid for older releases) | ✅ (COPR for older) | ✅ Tumbleweed | ✅ | ✅ edge | ✅ | ✅ |
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

### gtk-layer-shell age
hyprtk-bar needs gtk-layer-shell ≥ 0.9. Families below that floor (Debian ≤ 12,
Ubuntu ≤ 24.04, Fedora ≤ 40, openSUSE Leap 15.x, Alpine ≤ 3.20) need a newer
release or a source build; the bar's own installer warns.

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

## Remaining work

1. Validate the exact package names per family against live distro containers
   (the per-package fallback keeps a bad name from breaking an install, but the
   lists should be confirmed on each release).
2. Add a container matrix to CI (mirroring hyprtk-bar's
   `.github/workflows/install-matrix.yml`).
3. Gentoo/NixOS: provide an ebuild set / Nix expression so those families are
   first-class instead of "listed for manual install".
4. Validate the `awww-install.sh` source build on a live Debian/Ubuntu, Fedora
   and openSUSE container (build deps + rustup + `cargo build --release`), and
   confirm the Void/Alpine `swww` package names.
