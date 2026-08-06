#!/bin/bash
# Theme-GUI Installer for Hyprtk
# Creates venv, installs app, creates launcher scripts, installs desktop file

set -euo pipefail

APP_NAME="theme-gui"
INSTALL_DIR="$HOME/.local/share/$APP_NAME"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ":: Installing theme-gui..."

# Create install directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$APPS_DIR"

# Copy source
cp -r "$SCRIPT_DIR/src" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/pyproject.toml" "$INSTALL_DIR/"

# Create venv and install
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install -e "$INSTALL_DIR" --quiet 2>/dev/null || \
"$INSTALL_DIR/venv/bin/pip" install -e "$INSTALL_DIR" --quiet

# Create launcher script (theme-gui)
cat > "$BIN_DIR/theme-gui" << LAUNCHER
#!/bin/bash
exec "$INSTALL_DIR/venv/bin/python3" -m theme_gui "\$@"
LAUNCHER
chmod +x "$BIN_DIR/theme-gui"

# Create wrapper script (hyprtk-themer) for desktop launcher
cat > "$BIN_DIR/hyprtk-themer" << 'WRAPPER'
#!/bin/bash
exec theme-gui "$@"
WRAPPER
chmod +x "$BIN_DIR/hyprtk-themer"

# Install desktop file
cp "$SCRIPT_DIR/hyprtk-themer.desktop" "$APPS_DIR/"
update-desktop-database "$APPS_DIR" 2>/dev/null || true

echo ":: theme-gui installed to $BIN_DIR/theme-gui"
echo ":: hyprtk-themer desktop launcher installed"
