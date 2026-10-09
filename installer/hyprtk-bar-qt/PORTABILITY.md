# Portability

hyprtk-bar-qt is a Quickshell (Qt6) app with a stdlib-only Python backend. The
hard requirement is **Quickshell** (`qs`) plus the Qt6 QML modules
(`QtQuick`, `QtQuick.Layouts`, `QtQuick.Controls.Basic`, SVG). `install.sh`
installs the per-family packages below via its `DEPS` array (`--no-deps` skips
it); Quickshell is the common blocker — where a family does not package it,
build it from source and rerun with `--no-deps`.

## Required (bar cannot run without it)

| Family | Packages |
|--------|----------|
| pacman | `quickshell qt6-base qt6-declarative qt6-svg` |
| apt    | `quickshell qt6-base-dev qt6-declarative-dev libqt6svg6-dev` |
| dnf    | `quickshell qt6-qtbase qt6-qtdeclarative qt6-qtsvg` |
| zypper | `quickshell libQt6Core6 libQt6Gui6 libQt6Qml6 libQt6Quick6 libQt6Svg6` |
| xbps   | `quickshell qt6-base qt6-declarative qt6-svg` |
| apk    | `quickshell qt6-qtbase qt6-qtdeclarative qt6-qtsvg` |
| emerge | `gui-apps/quickshell dev-qt/qtbase dev-qt/qtdeclarative dev-qt/qtsvg` |
| nix    | `quickshell qt6.qtbase qt6.qtdeclarative qt6.qtsvg` |

Python 3.10+ and the `venv` module are needed (the venv only runs the bundled
`wal`). Quickshell's optional service modules (SystemTray, Notifications,
Mpris, Hyprland) ship with the Quickshell package.

## Optional feature binaries (degrade gracefully)

NetworkManager/nmcli, bluez/bluetoothctl, pipewire/wpctl, brightnessctl,
hyprsunset, dmidecode, pciutils, cliphist + wl-clipboard, rofi, libnotify,
wob, papirus-icon-theme + papirus-folders, polkit/pkexec, awww/swww, matugen,
cava, ImageMagick, Pillow. Installed by `install.sh`'s `EXTRAS` array
(`--no-extras` skips them).

## Notes

- The bar is Wayland/Hyprland-oriented; layer-shell placement is provided by
  Quickshell itself (no separate `gtk4-layer-shell`).
- `qs` is invoked as `qs -p ~/.config/quickshell/hyprtk-bar-qt`.
- Nix users can use the shipped `flake.nix`/`derivation.nix`.
