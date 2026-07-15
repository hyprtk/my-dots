# Hyprtk-On-Arch Merge Log

**Date:** 2026-07-15
**Source:** `/home/hyprtk/Projects/dots/` (11 distributions)
**Destination:** `/home/hyprtk/Projects/AI/Projects/Hyprtk-On-Arch/`

## Distributions Merged

| # | Distribution | Source Directory | Unique Contributions |
|---|-------------|-----------------|---------------------|
| 1 | Arch Linux | `arch-dots/` | Splash screen (splash-arch.bmp), mkinitcpio -P in cockpit section |
| 2 | ArchBang | `archbang-dots/` | os-release to `/etc/` (not `/usr/lib/`), swaylock removal |
| 3 | ArchCraft | `archcraft-dots/` | `update-dotfiles.sh`, pywal re-init uses `~/.cache/current-wallpaper.png` |
| 4 | ArchMan | `archman-dots/` | Standard variant |
| 5 | BSLX | `bslx-dots/` | `pacman -Rcs` removal, wallpaper to `/boot/grub/` |
| 6 | CachyOS | `cachy-dots/` | CachyOS branding script, multi-path os-release copy |
| 7 | EndeavourOS | `endeavour-dots/` | `dracut/` config, `nvidia/` config, hypr mv ordering in general section |
| 8 | Garuda | `garuda-dots/` | `dracut/` config, `nvidia/` config |
| 9 | Kiro | `kiro-dots/` | Most aggressive cleanup (xfce4, sddm-git, fastfetch-git removed), GRUB config, `update-grub.sh` |
| 10 | Manjaro | `manjaro-dots/` | Standard variant |
| 11 | RebornOS | `reborn-dots/` | Unique sudoers formatting with indentation |

## Project Structure

```
Hyprtk-On-Arch/
├── 1-install.sh              # Unified installer with distro selection
├── scripts/
│   ├── library.sh            # Shared functions (_installSymLink, _installPackages*)
│   ├── set-timezone.sh       # Timezone configuration
│   ├── awww-wrapper.sh       # AWWW wallpaper wrapper
│   ├── update-grub.sh        # GRUB updater (from Kiro)
│   └── ... (45+ utility scripts)
├── hypr/
│   ├── packages/
│   │   ├── graphics-card.sh  # Updated with VM option (4) + dracut/mkinitcpio detection
│   │   ├── hyprland.sh
│   │   ├── xfce4.sh
│   │   └── ... (16 package scripts)
│   └── ...
├── distro/                   # Distribution-specific files preserved
│   ├── arch/
│   │   ├── os-release/
│   │   └── splash/
│   ├── archbang/os-release/
│   ├── archcraft/
│   │   ├── os-release/
│   │   └── update-dotfiles.sh
│   ├── archman/os-release/
│   ├── bslx/os-release/
│   ├── cachy/
│   │   ├── os-release/
│   │   └── cachyos-branding
│   ├── endeavour/
│   │   ├── os-release/
│   │   ├── dracut/nvidia.conf
│   │   └── nvidia/grub-nvidia.conf
│   ├── garuda/
│   │   ├── os-release/
│   │   ├── dracut/nvidia.conf
│   │   └── nvidia/grub-nvidia.conf
│   ├── kiro/
│   │   ├── os-release/
│   │   └── grub/grub.cfg
│   ├── manjaro/os-release/
│   └── reborn/os-release/
├── alacritty/                # Shared dotfiles (identical across all distros)
├── btop/
├── dunst/
├── ... (40+ config directories)
└── Wallpapers/
```

## Key Modifications

### 1. `1-install.sh` — Unified Installer
- **Distribution selector** at start (1-11 for each distro)
- **Initramfs auto-detection**: Detects dracut vs mkinitcpio, prompts user to choose if both available
- **Helper function `_rebuild_initramfs()`**: Works with either dracut or mkinitcpio
- **All distro-specific actions preserved** via case statements:
  - KDE/package removal per distro
  - os-release placement per distro (/etc/ vs /usr/lib/ vs multi-path)
  - CachyOS branding steps
  - Pywal re-init (archcraft uses cached wallpaper)
  - hypr mv ordering (endeavour different)
  - GRUB wallpaper copy (bslx)
  - Sudoers formatting (reborn)
  - Distro-specific dracut/nvidia configs (endeavour, garuda)

### 2. `hypr/packages/graphics-card.sh` — Graphics Card Selection
- **Option 4: Virtual Machine (QEMU/VMware)** added with:
  - `qemu-guest-agent`, `spice-vdagent`, `xf86-video-qxl`, `mesa`, `open-vm-tools`
  - `xf86-video-vmware` from AUR
  - Service enabling for qemu-guest-agent, spice-vdagentd, vmtoolsd
- **All GPU options updated**: Uses `command -v` to detect dracut vs mkinitcpio for initramfs regeneration

### 3. Initramfs Handling
- Auto-detection of `dracut` and `mkinitcpio`
- User can select which tool to use when both are available
- `_rebuild_initramfs()` function writes the appropriate config and regenerates
- All GPU module additions work with both tools

## Install Logging
- All installation output is logged to `/tmp/hyprtk-install.log`
- Timestamps are recorded for each major step
- Distribution selection and initramfs choice are logged

## Verification

- All 11 os-release files preserved in `distro/<name>/os-release/`
- All 16 package scripts in `hypr/packages/`
- All 45+ utility scripts in `scripts/`
- Common dotfiles merged from arch-dots (base)
- 76,984+ total files (wallpapers, themes, fonts, etc.)
