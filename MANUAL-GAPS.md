# Manual install steps for the remaining package-audit gaps

The cross-distro audit (`installer/scripts/verify/package-audit.sh` → `output.html`)
resolves every package the installer requests against each distro's live repos.
After wiring the extra repositories (RPMFusion, Debian non-free, Void nonfree)
and the source builds (`awww`, `gtk4-layer-shell`, `swappy`, `nwg-look`,
`starship`, `cliphist`, `eza`, `ipp-usb`, and the Hyprland library chain for
`hyprpicker`/`hyprsunset`), **seven** entries remain that the installer cannot
provide automatically. This document covers each one: whether it can be
installed manually, and exactly how.

> Reproduce the audit at any time:
> `installer/scripts/verify/package-audit.sh > /tmp/audit.tsv`
> `installer/scripts/verify/package-audit-html.py /tmp/audit.tsv output.html .`

## Summary

| Gap | Verdict | Route |
|-----|---------|-------|
| Alpine — `unrar` | **Installable** | `7zip` / `libarchive-tools`, or build `unrar` from source |
| Void — `nvidia-settings` | **Installable** | build from source (verified below) |
| Alpine — `nvidia` / `nvidia-settings` | Not installable | musl: the proprietary NVIDIA driver is glibc-only. Use the open `nouveau` stack |
| Alpine — `nss-mdns` | Not usable | musl has no glibc NSS module support. Use `avahi` tools instead |
| Alpine — `cockpit` | Not usable | Cockpit requires systemd; Alpine uses OpenRC |
| Void — `cockpit` | Not usable | Cockpit requires systemd; Void uses runit |

---

## Alpine Linux

### `unrar` — extract RAR archives

Alpine does not package `unrar` (non-free licence). Two supported options:

**Option A — extract with a packaged tool (recommended)**

```sh
sudo apk add 7zip            # or: sudo apk add libarchive-tools
7z x archive.rar             # 7-Zip extracts RAR/RAR5
# or:
bsdtar -xf archive.rar       # libarchive reads RAR
```

**Option B — build the real `unrar` from source**

The unrar source is published by RARLAB (non-free, but building it locally for
personal use is permitted; do not redistribute the binary).

```sh
sudo apk add build-base curl
cd /tmp
# check https://www.rarlab.com/rar_add.htm for the current version
curl -LO https://www.rarlab.com/rar/unrarsrc-7.1.6.tar.gz
tar xf unrarsrc-7.1.6.tar.gz
cd unrar
make
sudo install -Dm755 unrar /usr/local/bin/unrar
unrar --help
```

### `nvidia` / `nvidia-settings` — not installable (use nouveau)

Alpine is built on **musl**, and NVIDIA's proprietary driver is glibc-only.
There is no working proprietary NVIDIA driver (or `nvidia-settings`) on Alpine,
and it cannot be built from source. The open-source `nouveau` stack is the only
GPU option:

```sh
sudo apk add mesa-dri-gallium mesa-vulkan-nouveau xf86-video-nouveau
```

- Under Wayland/Hyprland the kernel `nouveau` module + Mesa (`nvk`/`nouveau`)
  drive the card; `xf86-video-nouveau` is only needed for X11.
- There is **no** `nvidia-settings` equivalent — use Hyprland's own monitor/
  gamma controls (`hyprsunset`, monitor rules) and `brightnessctl`.
- Expect lower performance than the proprietary driver. For full NVIDIA
  support, use a glibc distro (Arch/Fedora/Debian/openSUSE/Void), where the
  installer handles the driver + `nvidia-settings` automatically.

### `nss-mdns` — not usable on musl (use avahi)

`nss-mdns` is a **glibc NSS module** (it `#include <nss.h>`). musl has no NSS
plugin interface, so it cannot be built or used on Alpine — this is why Alpine
does not package it. Use Avahi directly for mDNS/DNS-SD:

```sh
sudo apk add avahi avahi-tools
sudo rc-update add avahi-daemon default
sudo rc-service avahi-daemon start

avahi-browse -art            # list services (printers, etc.)
avahi-resolve -n myhost.local   # resolve a .local name
```

Notes:
- `.local` names still will **not** resolve through `getaddrinfo()`/ping,
  because musl's resolver cannot consult an NSS module. Use the Avahi tools
  above, or plain IP addresses.
- For CUPS printing, use the `dnssd://…` URIs that `avahi-browse` reports.

### `cockpit` — not usable (requires systemd)

Cockpit's server integrates tightly with **systemd** (units, sockets, journal).
Alpine uses OpenRC, so Cockpit is unsupported there. For a web dashboard on
Alpine, use a systemd-free alternative such as `netdata` or `glances`:

```sh
sudo apk add netdata          # http://<host>:19999
```

---

## Void Linux

### `nvidia-settings` — build from source (verified)

Void's `nonfree` repo ships the `nvidia` driver (and the installer enables it),
but **not** `nvidia-settings`. It builds cleanly from NVIDIA's source. Verified
on Void with driver `595.99.02`; the build recipe below succeeds end to end.

**1. Build dependencies**

```sh
sudo xbps-install -Sy make gcc pkgconf m4 \
    gtk+3-devel libX11-devel libXext-devel libXxf86vm-devel \
    libXrandr-devel libXv-devel libvdpau-devel jansson-devel Vulkan-Headers
```

**2. Get the source**

Match your installed driver version for best results
(`xbps-query -p pkgver nvidia` shows it, e.g. `595.99.02`):

```sh
cd /tmp
# exact match for the installed driver (e.g. nvidia-595.99.02_1 -> 595.99.02):
DRV="$(xbps-query -p pkgver nvidia | sed 's/^nvidia-//; s/_[0-9]*$//')"
curl -LO "https://download.nvidia.com/XFree86/nvidia-settings/nvidia-settings-${DRV}.tar.gz"
tar xf "nvidia-settings-${DRV}.tar.gz"
cd "nvidia-settings-${DRV}"

# or, to use the current upstream source instead of a version match:
# git clone --depth=1 https://github.com/NVIDIA/nvidia-settings && cd nvidia-settings
```

**3. Build and install**

```sh
make                   # plain `make`; the NVIDIA Makefile is not parallel-safe
sudo make install      # installs /usr/local/bin/nvidia-settings and /usr/local/lib/libnvidia-*.so
sudo ldconfig
nvidia-settings --version
```

Notes:
- `make install` puts the binary in **`/usr/local/bin`** (not `/usr/bin`). If
  `/usr/local/lib` is not on your loader path, add it to
  `/etc/ld.so.conf.d/local.conf` and re-run `sudo ldconfig`.
- The build needs the driver's NV-CONTROL extension at runtime, so run it in a
  session where the NVIDIA driver is loaded (an X11 or Wayland session on the
  NVIDIA GPU). It does not need the kernel headers to compile.
- A small version skew between `nvidia-settings` and the driver is normally
  harmless; prefer the matching version when you can.

### `cockpit` — not usable (requires systemd)

As on Alpine, Cockpit requires systemd; Void uses **runit**, so Cockpit is
unsupported. Use a systemd-free dashboard instead:

```sh
sudo xbps-install -Sy netdata    # or: glances
```

---

## What the installer already handles

For reference, these are obtained automatically and are **not** manual steps:
secondary repos (RPMFusion, Debian non-free, Void nonfree, Brave's repo,
Hyprland COPR/PPA, fastfetch PPA) and source builds (`awww`, `gtk4-layer-shell`,
`swappy`, `nwg-look`, `starship`, `cliphist`, `eza`, `ipp-usb`, and the
Hyprland library chain for `hyprpicker` on Alpine and `hyprsunset` on Void).
