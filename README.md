# Hyprtk — Hyprland Desktop Environment

A complete, opinionated Hyprland desktop setup for Arch-based distributions. One script installs everything: compositor config, status bar, theming, wallpaper management, and 40+ utility scripts.

<p align="center">
<img src="https://github.com/hyprtk/dotfiles/blob/main/assets/thumbnails/arch1-thumb.png" width="48%">
<img src="https://github.com/hyprtk/dotfiles/blob/main/assets/thumbnails/arch2-thumb.png" width="48%">
</p>

**Supported distros:** Arch Linux, ArchBang, Archcraft, Archman, BlueStar, CachyOS, EndeavourOS, Garuda, Kiro, Manjaro, RebornOS

---

## Features

<table>
<tr>
<td width="50%">

### Core Desktop

- **Hyprland** — dynamic tiling compositor with animations, blur, shadows
- **Waybar** — status bar with 14 theme variants
- **Rofi** — application launcher with 7 theme variants
- **Alacritty** — GPU-accelerated terminal
- **Thunar** — file manager with custom actions

</td>
<td width="50%">

### Dynamic Theming

- **pywal16** — color scheme from wallpapers
- **14 Waybar themes** — dark, light, aero, clear, inverse, negative, reverse
- **7 Rofi themes** — matching Waybar aesthetic
- **Papirus icons** — 25 custom color variants
- **matuwall** — GTK4 wallpaper picker

</td>
</tr>
<tr>
<td>

### Scripts & Tools

- **49 utility scripts** — screenshot, recording, clipboard, volume, brightness
- **theme-gui** — GTK4 theme manager (wallpapers, colors, icons)
- **hyprlogout** — custom logout menu
- **wf-recorder** — screen recording with notifications

</td>
<td>

### System Integration

- **SDDM** — login screen with theme support
- **GRUB** — custom splash screen
- **NVIDIA** — optional driver config (nvidia.lua)
- **XFCE4** — fallback desktop environment
- **Oh My Zsh + Starship** — shell prompt and plugins

</td>
</tr>
</table>

---

## Quick Start

```bash
git clone https://github.com/hyprtk/dotfiles.git ~/hyprtk
cd ~/hyprtk
./1-install.sh
```

> **Backup your existing `~/.config` before installing.**

<details>
<summary><b>Installation details</b></summary>

The installer will:
1. Detect your distro automatically
2. Present a TUI selector (gum) to choose your distribution
3. Install 147 packages via pacman/yay
4. Configure Hyprland, Waybar, Rofi, and all utilities
5. Set up SDDM, GRUB splash, and NVIDIA drivers (if selected)

**Requirements:** Arch-based distro, internet connection, ~2GB disk space
</details>

---

## Tech Stack

<table>
<tr>
<td width="50%">

| Category | Components |
|----------|------------|
| Compositor | Hyprland (Lua) |
| Status Bar | Waybar (14 themes) |
| Launcher | Rofi (7 themes) |
| Terminal | Alacritty |
| Shell | Zsh + Starship |
| File Manager | Thunar + GVFS |
| Wallpaper | matuwall + swww |

</td>
<td width="50%">

| Category | Components |
|----------|------------|
| Theming | pywal16 + theme-gui |
| Icons | Papirus (25 variants) |
| Screen Lock | swaylock-effects |
| Screenshots | grim + slurp + swappy |
| Recording | wf-recorder |
| Clipboard | cliphist + wl-clipboard |
| Display Manager | SDDM |

</td>
</tr>
</table>

---

## Keybindings

All keybinds use `SUPER` (Windows key) as the modifier.

<table>
<tr>
<td width="50%">

### Core

| Key | Action |
|-----|--------|
| `SUPER + Return` | Terminal |
| `SUPER + Q` | Close window |
| `SUPER + M` | Fullscreen |
| `SUPER + F` | File manager |
| `SUPER + B` | Browser |
| `SUPER + D` | App menu |
| `SUPER + V` | Toggle float |
| `SUPER + X` | Exit |
| `SUPER + R` | Reload config |
| `SUPER + C` | Color picker |

### Wallpapers & Theming

| Key | Action |
|-----|--------|
| `SUPER + W` | Wallpaper picker |
| `SUPER + Shift + W` | Random wallpaper |
| `SUPER + Ctrl + W` | Wallpaper selector |
| `SUPER + Ctrl + T` | Switch Waybar theme |

</td>
<td width="50%">

### Screenshots & Recording

| Key | Action |
|-----|--------|
| `SUPER + Print` | Screenshot |
| `SUPER + P` | Screenshot |
| `SUPER + Shift + Print` | Start recording |
| `SUPER + Alt + Print` | Stop recording |

### Workspaces

| Key | Action |
|-----|--------|
| `SUPER + 1-5` | Switch workspace |
| `SUPER + Shift + 1-5` | Move to workspace |
| `SUPER + Scroll` | Cycle workspaces |

### Applications

| Key | Action |
|-----|--------|
| `SUPER + Ctrl + Q` | Logout menu |
| `SUPER + Ctrl + C` | Clipboard history |
| `SUPER + Ctrl + F` | File manager |
| `SUPER + Shift + P` | Passthrough (VMs) |

</td>
</tr>
</table>

Full keybindings reference: [`cheatsheet.md`](cheatsheet.md)

---

## Waybar Themes

14 theme variants organized by position (top/bottom) and style:

<table>
<tr>
<td width="50%">

| Theme | Style |
|-------|-------|
| hyprtk-top/bottom | Dark frosted |
| hyprtk-aero-top/bottom | Aero glass |
| hyprtk-clear-top/bottom | Transparent |
| hyprtk-light-top/bottom | Light frosted |

</td>
<td width="50%">

| Theme | Style |
|-------|-------|
| hyprtk-inverse-top/bottom | Inverse |
| hyprtk-reverse-top/bottom | Reverse |
| hyprtk-negative-top/bottom | Negative |

</td>
</tr>
</table>

Switch themes at runtime with `SUPER + Ctrl + T` or from theme-gui.

---

## Project Structure

```
hyprtk/
├── 1-install.sh              # Main installer
├── hypr/                     # Hyprland config (Lua)
│   ├── keybindings.lua       # Keybindings
│   ├── autostart.lua         # Autostart apps
│   ├── scripts/              # 17 utility scripts
│   └── packages/             # Package scripts
├── configs/                  # 36 dotfile dirs
│   ├── waybar/               # 14 themes
│   ├── rofi/                 # 7 themes
│   ├── theme-gui/            # GTK4 theme manager
│   └── ...                   # 33 more configs
├── installer/                # Install support
│   ├── scripts/              # 49 utility scripts
│   ├── standalone/           # Standalone binaries
│   └── os-release/           # Distro detection
├── assets/                   # Screenshots, fonts, wallpapers
├── CHANGELOG
├── LICENSE                   # GPL-2.0
└── cheatsheet.md             # Keybinding reference
```

---

## Screenshots

<details>
<summary><b>Click to expand distro screenshots (12 distros)</b></summary>

<table>
<tr>
<td><b>Arch Linux</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/arch1.png?raw=true" width="100%"></td>
<td><b>ArchBang</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archbang1.png?raw=true" width="100%"></td>
<td><b>Archcraft</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archcraft1.png?raw=true" width="100%"></td>
</tr>
<tr>
<td><b>Archman</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archman1.png?raw=true" width="100%"></td>
<td><b>BlueStar</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/bslx1.png?raw=true" width="100%"></td>
<td><b>CachyOS</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/cachy1.png?raw=true" width="100%"></td>
</tr>
<tr>
<td><b>EndeavourOS</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/endeavour1.png?raw=true" width="100%"></td>
<td><b>Garuda</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/garuda1.png?raw=true" width="100%"></td>
<td><b>Kiro</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/kiro1.png?raw=true" width="100%"></td>
</tr>
<tr>
<td><b>Manjaro</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/manjaro1.png?raw=true" width="100%"></td>
<td><b>RebornOS</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/reborn1.png?raw=true" width="100%"></td>
<td><b>Dev Dots</b><br><img src="https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/mydots1.png?raw=true" width="100%"></td>
</tr>
</table>

</details>

---

## Credits

Built by [Kori Tk](https://github.com/hyprtk) — inspired by the Hyprland community and projects like ml4w, JaKooLit.

## License

GPL-2.0 — see [LICENSE](LICENSE) for details.
