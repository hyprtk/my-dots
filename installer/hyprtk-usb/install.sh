#!/bin/bash
# ── hyprtk-usb GUI installer ──────────────────────────────────────────────
# Installs the GTK front end of hyprtk-usb. The CLI/TUI is already on PATH as a
# single-file zipapp from installer/standalone; the GUI additionally needs the
# Python package (for hyprtk_usb.gui / hyprtk_usb.helper) and PyGObject/GTK.
#
# It builds a venv with system site-packages (so it can see the distro's
# PyGObject + GTK), pip-installs this directory into it, links the GUI launchers
# into ~/.local/bin and drops a desktop entry + icon.
#
#   bash installer/hyprtk-usb/install.sh
#
# Env: HYPRTK_USB_VENV (default ~/.local/share/hyprtk-usb/venv), PYTHON.
# Idempotent and non-fatal: a failure leaves the CLI/TUI untouched.
# ──────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PY="${PYTHON:-python3}"
VENV="${HYPRTK_USB_VENV:-$HOME/.local/share/hyprtk-usb/venv}"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
# The icon lives under the app's own data dir, not ~/.local/share/icons: the
# dotfiles symlink that whole dir to the repo's papirus theme, so writing a
# hicolor icon there would pollute the repo clone (and fail on a read-only one).
ICON="$HOME/.local/share/hyprtk-usb/hyprtk-usb.svg"

echo ":: installing hyprtk-usb (GUI) into $VENV"

"$PY" -m venv --system-site-packages "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet "$SCRIPT_DIR"

mkdir -p "$BIN" "$APPS"
# Only the GUI launchers: `hyprtk-usb` stays the vendored CLI/TUI zipapp, so the
# two never fight over the same name in ~/.local/bin.
ln -sf "$VENV/bin/hyprtk-usb-gui" "$BIN/hyprtk-usb-gui"
ln -sf "$VENV/bin/hyprtk-usb-helper" "$BIN/hyprtk-usb-helper"
# The compositor session's PATH does not include ~/.local/bin (SDDM starts
# Hyprland without it), so a bare `Exec=hyprtk-usb-gui` would not resolve when
# the entry is launched from the app menu. Write the entry with an absolute Exec
# and an absolute Icon path (both the launcher and the icon live off-repo).
install -Dm644 "$SCRIPT_DIR/data/hyprtk-usb.svg" "$ICON"
_tmp="$(mktemp)"
sed -e "s|^Exec=.*|Exec=$BIN/hyprtk-usb-gui|" \
    -e "s|^Icon=.*|Icon=$ICON|" \
    "$SCRIPT_DIR/data/hyprtk-usb.desktop" > "$_tmp"
install -Dm644 "$_tmp" "$APPS/hyprtk-usb.desktop"
rm -f "$_tmp"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" >/dev/null 2>&1 || true

echo ":: hyprtk-usb GUI installed — launch it with 'hyprtk-usb-gui', or from the app menu as 'hyprtk-usb'"
