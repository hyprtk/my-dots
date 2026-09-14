#!/bin/bash
SRC=/home/hyprtk/Projects/AI-Projects/Source-Files/dots
ROOT=/home/hyprtk/Projects/AI-Projects/hyprtk-merged
cd "$ROOT"

extract_cmds() {
  grep -oE "(sudo )?(pacman|yay|systemctl|cp|mv|mkdir|chsh|wal|xdg-user-dirs[^ ]*)[^#\"']*" "$1" \
    | grep -vE '^\s*(echo|#)' | sed 's/[[:space:]]*$//' | sort -u
}

# canonicalize a source-tree path to the merged layout
canon() {
  local c="$1"
  c="${c//os-release\/os-release/os-release/os-release-\$DISTRO}"
  for d in fonts Wallpapers themes papirus-icons splash screenshots; do
    c="${c//~/hyprtk\/$d\//~/hyprtk\/assets\/$d\/}"
  done
  for d in alacritty btop fastfetch gtk hyprlogout hyprpicker matuwall Mousepad nvim ohmyposh oh-my-zsh ranger rofi sddm smb starship swappy swaylock Thunar User-Management vim wal waybar waypaper wob xfce4 zshrc root scripts standalone; do
    c="${c//~/hyprtk\/$d\//~/hyprtk\/configs\/$d\/}"
  done
  c="${c//~/hyprtk\/themes/~/hyprtk\/assets\/themes}"
  echo "$c"
}

for d in arch archbang archcraft archman bslx cachy endeavour garuda kiro manjaro reborn; do
  STEP="$ROOT/installer/steps/$d.sh"
  MISSING=0
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    norm=$(canon "$cmd")
    if ! grep -qF "$norm" 1-install.sh && ! grep -qF "$norm" "$STEP" 2>/dev/null; then
      echo "  [$d] NOT COVERED: $cmd  (looked for: $norm)"
      MISSING=1
    fi
  done < <(extract_cmds "$SRC/$d-dots/1-install.sh")
  if [ "$MISSING" = 0 ]; then echo "[OK] $d: all installer commands covered"; fi
done
