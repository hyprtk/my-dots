#!/bin/bash
# ── matuwall ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

echo ""
echo "Installing Matuwall wallpaper picker..."
echo ""
if [ ! -d "$HOME/.local/share/Matuwall/.git" ]; then
    git clone https://github.com/naurissteins/Matuwall.git "$HOME/.local/share/Matuwall"
fi
if [ -d "$HOME/.local/share/Matuwall" ]; then
    cd "$HOME/.local/share/Matuwall" || exit 1
    python3 -m venv --system-site-packages .venv
    . .venv/bin/activate
    pip install --upgrade pip
    pip install .
    deactivate 2>/dev/null || true
    # Point the PATH entry at the venv binary only once it actually exists —
    # never leave a dangling ~/.local/bin/matuwall behind.
    if [ -x "$HOME/.local/share/Matuwall/.venv/bin/matuwall" ]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$HOME/.local/share/Matuwall/.venv/bin/matuwall" "$HOME/.local/bin/matuwall"
    fi
fi
echo " Matuwall installed! "
sleep 2
