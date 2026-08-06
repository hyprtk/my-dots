# Hyprtk — Hyprland Desktop Environment

A complete, opinionated Hyprland desktop setup for Arch-based distributions. One script installs everything: compositor config, status bar, theming, wallpaper management, and 40+ utility scripts.

**Supported distros:** Arch Linux, ArchBang, Archcraft, Archman, BlueStar, CachyOS, EndeavourOS, Garuda, Kiro, Manjaro, RebornOS

---

## Features

### Core Desktop

- **Hyprland** — dynamic tiling Wayland compositor with animations, blur, and shadows
- **Waybar** — status bar with 14 theme variants (dark, light, aero, clear, inverse, negative, reverse)
- **Rofi** — application launcher with 7 theme variants
- **Alacritty** — GPU-accelerated terminal emulator
- **Thunar** — file manager with volume management and custom actions

### Dynamic Theming

- **pywal16** — automatic color scheme generation from wallpapers
- **14 Waybar themes** — dark frosted, light frosted, aero glass, transparent, inverse, negative, reverse (top + bottom variants)
- **7 Rofi themes** — matching the Waybar aesthetic
- **Papirus icons** — 25 custom color variants synced to wallpaper palette
- **matuwall** — wallpaper picker with GTK4 glassmorphism UI

### Scripts & Tools

- **49 utility scripts** in `installer/scripts/` — screenshot, screen recording, clipboard, volume, brightness, wallpaper, cleanup, and more
- **theme-gui** — GTK4 theme manager for switching wallpapers, pywal colors, rofi themes, waybar themes, swaylock colors, and icon colors
- **hyprlogout** — custom logout menu (lock, suspend, logout, reboot, shutdown)
- **wf-recorder** — screen recording with start/stop scripts and notifications

### System Integration

- **SDDM** — login screen with theme support
- **GRUB** — custom splash screen
- **NVIDIA** — optional driver configuration (nvidia.lua)
- **XFCE4** — fallback desktop environment (Thunar, Mousepad, xfce4-terminal)
- **Oh My Zsh + Starship** — shell prompt and plugins

---

## Screenshots

<details>
<summary><b>Arch Linux</b></summary>

![Arch 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/arch1.png)
![Arch 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/arch2.png)
![Arch 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/arch3.png)
</details>

<details>
<summary><b>ArchBang</b></summary>

![ArchBang 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archbang1.png)
![ArchBang 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archbang2.png)
![ArchBang 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archbang3.png)
</details>

<details>
<summary><b>Archcraft</b></summary>

![Archcraft 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archcraft1.png)
![Archcraft 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archcraft2.png)
![Archcraft 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archcraft3.png)
</details>

<details>
<summary><b>Archman</b></summary>

![Archman 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archman1.png)
![Archman 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archman2.png)
![Archman 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/archman3.png)
</details>

<details>
<summary><b>BlueStar</b></summary>

![BlueStar 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/bslx1.png)
![BlueStar 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/bslx2.png)
![BlueStar 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/bslx3.png)
</details>

<details>
<summary><b>CachyOS</b></summary>

![CachyOS 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/cachy1.png)
![CachyOS 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/cachy2.png)
![CachyOS 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/cachy3.png)
</details>

<details>
<summary><b>EndeavourOS</b></summary>

![EndeavourOS 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/endeavour1.png)
![EndeavourOS 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/endeavour2.png)
![EndeavourOS 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/endeavour3.png)
</details>

<details>
<summary><b>Garuda</b></summary>

![Garuda 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/garuda1.png)
![Garuda 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/garuda2.png)
![Garuda 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/garuda3.png)
</details>

<details>
<summary><b>Kiro</b></summary>

![Kiro 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/kiro1.png)
![Kiro 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/kiro2.png)
![Kiro 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/kiro3.png)
</details>

<details>
<summary><b>Manjaro</b></summary>

![Manjaro 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/manjaro1.png)
![Manjaro 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/manjaro2.png)
![Manjaro 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/manjaro3.png)
</details>

<details>
<summary><b>RebornOS</b></summary>

![RebornOS 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/reborn1.png)
![RebornOS 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/reborn2.png)
![RebornOS 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/reborn3.png)
</details>

<details>
<summary><b>Dev Dots</b></summary>

![Dev 1](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/mydots1.png)
![Dev 2](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/mydots2.png)
![Dev 3](https://github.com/hyprtk/dotfiles/blob/main/assets/screenshots/mydots3.png)
</details>

---

## Tech Stack

| Category | Components |
|----------|------------|
| **Compositor** | Hyprland (Lua config) |
| **Status Bar** | Waybar (14 themes, pywal-driven colors) |
| **Launcher** | Rofi (7 theme variants) |
| **Terminal** | Alacritty |
| **Shell** | Zsh + Oh My Zsh + Starship prompt |
| **File Manager** | Thunar + GVFS |
| **Wallpaper** | matuwall + swww/awww (animated transitions) |
| **Theming** | pywal16 (dynamic) + GTK4 theme-gui |
| **Icons** | Papirus (25 custom color variants) |
| **Screen Lock** | swaylock-effects |
| **Screenshots** | grim + slurp + swappy (annotation) |
| **Screen Record** | wf-recorder |
| **Clipboard** | cliphist + wl-clipboard |
| **Notifications** | dunst + wob (overlay bar) |
| **Display Manager** | SDDM |

---

## Keybindings

All keybinds use `SUPER` (Windows key) as the modifier.

### Core

| Key | Action |
|-----|--------|
| `SUPER + Return` | Terminal (Alacritty) |
| `SUPER + Q` | Close window |
| `SUPER + M` | Fullscreen toggle |
| `SUPER + F` | File manager (Thunar) |
| `SUPER + B` | Browser (Brave) |
| `SUPER + D` | Application menu |
| `SUPER + V` | Toggle floating |
| `SUPER + X` | Exit Hyprland |
| `SUPER + R` | Reload config |
| `SUPER + C` | Color picker (hyprpicker) |

### Wallpapers & Theming

| Key | Action |
|-----|--------|
| `SUPER + W` | Open matuwall wallpaper picker |
| `SUPER + Shift + W` | Random wallpaper |
| `SUPER + Ctrl + W` | Wallpaper selector (rofi) |
| `SUPER + Ctrl + T` | Switch Waybar theme |

### Screenshots & Recording

| Key | Action |
|-----|--------|
| `SUPER + Print` | Screenshot (region/window/full) |
| `SUPER + P` | Screenshot (same as above) |
| `SUPER + Shift + Print` | Start screen recording |
| `SUPER + Alt + Print` | Stop screen recording |

### Workspaces

| Key | Action |
|-----|--------|
| `SUPER + 1-5` | Switch to workspace 1-5 |
| `SUPER + Shift + 1-5` | Move window to workspace 1-5 |
| `SUPER + Scroll` | Cycle workspaces |

### Applications

| Key | Action |
|-----|--------|
| `SUPER + Ctrl + Q` | Logout menu |
| `SUPER + Ctrl + C` | Clipboard history |
| `SUPER + Ctrl + F` | File manager (alt) |
| `SUPER + Shift + P` | Passthrough mode (VMs) |

Full keybindings reference: `cheatsheet.md`

---

## Installation

> **Backup your existing `~/.config` before installing.**

```bash
git clone https://github.com/hyprtk/dotfiles.git ~/hyprtk
cd ~/hyprtk
./1-install.sh
```

The installer will:
1. Detect your distro automatically
2. Present a TUI selector (gum) to choose your distribution
3. Install 147 packages via pacman/yay
4. Configure Hyprland, Waybar, Rofi, and all utilities
5. Set up SDDM, GRUB splash, and NVIDIA drivers (if selected)

### Requirements

- Arch-based distribution (Arch, EndeavourOS, CachyOS, Garuda, Manjaro, etc.)
- Internet connection
- ~2GB disk space for packages + dotfiles

---

## Project Structure

```
hyprtk/
├── 1-install.sh              # Main installer script
├── hypr/                     # Hyprland configuration (Lua)
│   ├── keybindings.lua       # All keybindings
│   ├── autostart.lua         # Autostart apps
│   ├── environment.lua       # Environment variables
│   ├── scripts/              # 17 utility scripts
│   └── packages/             # Package installation scripts
├── configs/                  # 36 dotfile directories
│   ├── waybar/               # Waybar config + 14 themes
│   ├── rofi/                 # Rofi config + 7 themes
│   ├── papirus-icons/        # Icon theme scripts
│   ├── theme-gui/            # GTK4 theme manager
│   ├── swaylock/             # Screen locker config
│   ├── dunst/                # Notification daemon
│   ├── alacritty/            # Terminal config
│   ├── btop/                 # System monitor
│   ├── nvim/                 # Neovim config
│   └── ...                   # 26 more configs
├── installer/                # Installation support
│   ├── scripts/              # 49 utility scripts
│   ├── standalone/           # Standalone binaries (gum)
│   └── os-release/           # Distro detection files
├── assets/                   # Static assets
│   ├── screenshots/          # 36 screenshots (3 per distro)
│   ├── thumbnails/           # 39 thumbnails
│   ├── fonts/                # Custom fonts
│   ├── Wallpapers/           # Default wallpapers
│   └── themes/               # GTK themes
├── CHANGELOG                 # Version history
├── LICENSE                   # GPL-2.0
└── cheatsheet.md             # Quick keybinding reference
```

---

## Waybar Themes

14 theme variants organized by position (top/bottom) and style:

| Theme | Style | Description |
|-------|-------|-------------|
| hyprtk-top/bottom | Dark frosted | Default dark glass aesthetic |
| hyprtk-aero-top/bottom | Aero glass | Windows 7-inspired white glass |
| hyprtk-clear-top/bottom | Transparent | See-through bar |
| hyprtk-light-top/bottom | Light frosted | Light mode with dark text |
| hyprtk-inverse-top/bottom | Inverse | Transparent bar, light pills |
| hyprtk-reverse-top/bottom | Reverse | Solid colored pills |
| hyprtk-negative-top/bottom | Negative | Photo-negative light theme |

Switch themes at runtime with `SUPER + Ctrl + T` or from theme-gui.

---

## Scripts Overview

49 scripts in `installer/scripts/` covering:

- **Screenshots:** `screenshot.sh`, `ssdetect.sh`, `sshot.sh`, `grim.sh`
- **Recording:** `wf-record-start.sh`, `wf-record-stop.sh`
- **Wallpaper:** `wallpaper.sh`, `wallpaper-awww.sh`, `updatewal.sh`, `updatewal-awww.sh`
- **Clipboard:** `cliphist.sh`
- **Volume:** `Volume.sh` (with wob overlay)
- **Brightness:** `brightness-up.sh`, `brightness-down.sh`
- **System:** `cleanup.sh`, `bash-cleanup.sh`, `installupdates.sh`, `updates.sh`
- **Icons:** `change-icons.sh`, `icon-color-select.sh`
- **Apps:** `appsmenu.sh`, `filemanager.sh`, `calculator.sh`
- **VMs:** `vmware-setup.sh`, `qemu-virt-setup.sh`, `appimage-setup.sh`
- **System Info:** `figlet.sh`, `keyhint.sh`, `fontsearch.sh`

---

## Credits

Built by [Kori Tk](https://github.com/hyprtk) — inspired by the Hyprland community and projects like ml4w, JaKooLit.

## License

GPL-2.0 — see [LICENSE](LICENSE) for details.
