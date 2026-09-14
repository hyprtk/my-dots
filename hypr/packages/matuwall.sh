#!/bin/bash
# ── matuwall ─────────────────────────────────────────────────────────
_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
. "$_PKGDIR/../../installer/scripts/pkgmanager.sh"

echo ""
sleep 2
echo " Matuwall Installer "
echo ""
echo "Installing Matuwall wallpaper picker..."
echo ""
git clone https://github.com/naurissteins/Matuwall.git ~/.local/share/Matuwall
cd ~/.local/share/Matuwall
python3 -m venv --system-site-packages .venv
. .venv/bin/activate
pip install --upgrade pip
pip install .
mkdir -p ~/.local/bin
ln -sf "$PWD/.venv/bin/matuwall" ~/.local/bin/matuwall
deactivate 2>/dev/null || true
cd - >/dev/null
echo " Matuwall installed! "
sleep 2
