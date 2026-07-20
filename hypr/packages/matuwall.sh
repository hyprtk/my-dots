#!/bin/bash
printf "\n\e[35m%s\e[0m\n" "══════════════════════════════════════════"
printf "\e[35m  %s\e[0m\n" "Matuwall"
printf "\e[35m%s\e[0m\n\n" "══════════════════════════════════════════"
sleep 2
echo ""    
echo "Installing Matuwall wallpaper picker..."
echo ""    
git clone https://github.com/naurissteins/Matuwall.git ~/.local/share/Matuwall
cd ~/.local/share/Matuwall
/usr/bin/python -m venv --system-site-packages .venv
source .venv/bin/activate
pip install --upgrade pip
pip install .
mkdir -p ~/.local/bin
ln -sf "$PWD/.venv/bin/matuwall" ~/.local/bin/matuwall
cd -
echo " Matuwall installed! "
sleep 2
