<div align="center">

# hyprtk dots

A single installer for a fully themed **Hyprland (Wayland)** desktop on **any Linux distribution** — with **XFCE (Xorg)** kept as a safety net.

**Any distro. One install. One pywal-powered theme.**

`Arch` · `Archbang` · `Archcraft` · `Archman` · `BSLX` · `CachyOS` · `EndeavourOS` · `Garuda` · `Kiro` · `Manjaro` · `RebornOS` · `Debian/Ubuntu` · `Fedora/RHEL` · `openSUSE` · `Void` · `Alpine` · `Gentoo` · `NixOS`

---

[Install](#install) · [Features](#features) · [Portability](#portability) · [Keybindings](#keybindings) · [Applications](#applications) · [Gallery](#gallery)

</div>

---

## What is this?

A curated, consistent desktop configuration that replaces the default look and feel of Arch Linux with a polished Hyprland setup. One wallpaper drives every colour on screen via **pywal16** (bundled) — hyprtk-bar, rofi, the app menu, the lock screen and even your icons all stay in sync.

- **Wayland first** — Hyprland with a floating/split hybrid workflow
- **Xorg fallback** — XFCE stays installed as a safety net
- **Auto-detected distro** — the installer detects your OS and package manager (pacman/apt/dnf/zypper/xbps/apk) and applies the right tweaks
- **No manual colour config** — pywal generates a full palette from your wallpaper
- **No AUR dependency for pywal** — pywal16 is bundled inside hyprtk-bar (`vendor/pywal16`), so colours work out of the box

## Install

> Back up your existing `~/.config` before running.

```bash
git clone https://github.com/hyprtk/dotfiles.git ~/hyprtk
cd ~/hyprtk
sh ./1-install.sh
```

The installer is a guided `gum` TUI: it detects your distro, then asks about
package groups, dotfiles and services before installing everything.

> Every system is different — results can vary. Review the prompts before accepting.

## Portability

The installer works across distribution families via a single package-manager
abstraction (`installer/scripts/pkgmanager.sh`): **Arch** (pacman + AUR),
**Debian/Ubuntu** (apt), **Fedora/RHEL** (dnf), **openSUSE** (zypper), **Void**
(xbps) and **Alpine** (apk), with **Gentoo** and **NixOS** supported as
manual/declarative installs. Arch-only features (AUR packages, `mkinitcpio`
splash, os-release branding) are skipped with a warning elsewhere. The
wallpaper daemon is the exception — **awww** comes from the AUR on Arch, the
native `swww` package on Void/Alpine, and is otherwise built from source by the
installer. On Ubuntu the installer also adds a PPA so **Hyprland ≥ 0.55** (which
the Lua config requires) is installed. Where a distro ships no **Hyprland ≥ 0.55**
and no hyprwm libraries — **Alpine** (0.54.3) and **Void** (packages neither) —
the installer builds the pinned upstream release **and** the library chain from
source (plus `wob` on Void). On systems without a systemd user session
(**Void/runit**, **Alpine/OpenRC**) it also launches the compositor through a
`dbus-run-session` wrapper so D-Bus — portals, notifications and cursor theming —
works. See [`PORTABILITY.md`](PORTABILITY.md) for the full matrix.

## Features

| Area | What you get |
| --- | --- |
| **Terminal** | Alacritty + starship prompt |
| **Editor** | Neovim (Vim fallback) |
| **App launcher** | Rofi (plus the in-bar start menu) |
| **Status bar** | hyprtk-bar — pywal-themed taskbar with built-in menus |
| **Desktop widgets** | Clock, weather, audio visualizer, hard disks, network, CPU/RAM and system info — free-floating surfaces you drag into place and snap into groups, themed by pywal |
| **Theming** | pywal16 (bundled), live, from your wallpaper |
| **Wallpaper** | Matuwall film-strip picker + rofi list + random (awww daemon, installed automatically) |
| **Screenshots** | grim & slurp |
| **Screen recording** | wf-recorder |
| **Clipboard** | cliphist |
| **Screen lock** | swaylock-effects |
| **Logout** | hyprlogout |
| **Files** | Thunar |
| **Icons** | Papirus (recolored to match the theme) |
| **Cursor** | Adwaita (session theme via `XCURSOR_THEME`/`XCURSOR_SIZE`) |
| **Browser** | Brave / Chromium |
| **USB writer** | hyprtk-usb — write a hyprtk ISO to a USB stick (+ optional persistence); CLI/TUI + GTK GUI |
| **VMs** | QEMU/KVM, VMware |

## Keybindings

`Super` = the Windows key.

### Apps & windows

| Key | Action |
| --- | --- |
| `Super + Return` | Terminal (Alacritty) |
| `Super + Space` | Start menu (in-bar) |
| `Super + Q` | Close window |
| `Super + D` | App menu (rofi) |
| `Super + F` | File manager (Thunar) |
| `Super + B` / `Super + Ctrl + B` | Brave / Chromium |
| `Super + X` | Exit session |
| `Super + M` | Toggle fullscreen |
| `Super + V` | Float / resize / center window |
| `Super + J` / `Super + K` | Toggle / swap split |

### Workspaces

| Key | Action |
| --- | --- |
| `Super + 1..0` | Switch to workspace |
| `Super + Shift + 1..0` | Move window to workspace |

### Wallpaper & themes

| Key | Action |
| --- | --- |
| `Super + W` | Matuwall wallpaper picker |
| `Super + Shift + W` | Random wallpaper |
| `Super + Ctrl + W` | Wallpaper list (rofi) |
| `Super + Ctrl + T` | Switch waybar theme |
| `Super + Shift + B` | Reload waybar |

### Media & system

| Key | Action |
| --- | --- |
| `Super + Print` / `Super + P` | Screenshot |
| `Super + Shift + Print` | Start screen recording |
| `Super + Alt + Print` | Stop screen recording |
| `Super + C` | Color picker (hyprpicker) |
| `Super + Ctrl + Q` | Power menu (hyprlogout) |
| `Super + R` | Reload Hyprland config |

### Desktop widgets

| Key | Action |
| --- | --- |
| `Super + left mouse` | Move a window |
| `Super + Shift + left mouse` | Move a desktop widget (drop near another to snap them together) |

## Applications

All system theming (wallpaper, pywal, rofi, icons, swaylock, SDDM/GRUB) now lives in **hyprtk-bar**'s Theme Manager, opened from the wallpaper glyph in the bar. The **start menu** and **arc menu** are both built into **hyprtk-bar** — no separate apps:

| Feature | What it does | Open with |
| --- | --- | --- |
| **Start menu** | Whisker/Win7/Win11/Plasma app menu — search, favorites, recents, power buttons | `Super + Space` or the start button |
| **Arc menu** | FAB in a screen corner that fans its items out on click | `Super + Ctrl + M` (or the FAB) |

Both are configured from the bar settings dialogue (*Menu* and *Arc Menu* tabs) and follow the bar's theme + pywal.

## Gallery

| | | |
| --- | --- | --- |
| ![Arch](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/arch1.png) | ![Arch](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/arch2.png) | ![Arch](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/arch3.png) |
| ![Archbang](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archbang1.png) | ![Archbang](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archbang2.png) | ![Archbang](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archbang3.png) |
| ![Archcraft](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archcraft1.png) | ![Archcraft](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archcraft2.png) | ![Archcraft](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archcraft3.png) |
| ![Archman](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archman1.png) | ![Archman](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archman2.png) | ![Archman](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archman3.png) |
| ![BSLX](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/bslx1.png) | ![BSLX](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/bslx2.png) | ![BSLX](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/bslx3.png) |
| ![CachyOS](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/cachy1.png) | ![CachyOS](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/cachy2.png) | ![CachyOS](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/cachy3.png) |
| ![EndeavourOS](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/endeavour1.png) | ![EndeavourOS](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/endeavour2.png) | ![EndeavourOS](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/endeavour3.png) |
| ![Garuda](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/garuda1.png) | ![Garuda](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/garuda2.png) | ![Garuda](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/garuda3.png) |
| ![Kiro](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/kiro1.png) | ![Kiro](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/kiro2.png) | ![Kiro](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/kiro3.png) |
| ![Manjaro](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/manjaro1.png) | ![Manjaro](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/manjaro2.png) | ![Manjaro](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/manjaro3.png) |
| ![RebornOS](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/reborn1.png) | ![RebornOS](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/reborn2.png) | ![RebornOS](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/reborn3.png) |

More screenshots per distro live in [`assets/screenshots/`](https://github.com/hyprtk/dotfiles/tree/main/assets/screenshots).

## License

[GPL-2.0](LICENSE)