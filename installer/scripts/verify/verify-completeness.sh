#!/bin/bash
# For each distro tree: reconstruct what the merged install should produce
# (canonical + that distro's overlay), then compare against the original tree.
SRC=/home/hyprtk/Projects/AI-Projects/Source-Files/dots
ROOT=/home/hyprtk/Projects/AI-Projects/hyprtk-merged
declare -A MAP
MAP[fonts]=assets/fonts
MAP[Wallpapers]=assets/Wallpapers
MAP[themes]=assets/themes
MAP[papirus-icons]=assets/papirus-icons
MAP[splash]=assets/splash
MAP[screenshots]=assets/screenshots
MAP[alacritty]=configs/alacritty
MAP[btop]=configs/btop
MAP[fastfetch]=configs/fastfetch
MAP[gtk]=configs/gtk
MAP[hyprlogout]=configs/hyprlogout
MAP[hyprpicker]=configs/hyprpicker
MAP[matuwall]=configs/matuwall
MAP[Mousepad]=configs/Mousepad
MAP[nvim]=configs/nvim
MAP[ohmyposh]=configs/ohmyposh
MAP[oh-my-zsh]=configs/oh-my-zsh
MAP[ranger]=configs/ranger
MAP[rofi]=configs/rofi
MAP[sddm]=configs/sddm
MAP[smb]=configs/smb
MAP[starship]=configs/starship
MAP[swappy]=configs/swappy
MAP[swaylock]=configs/swaylock
MAP[Thunar]=configs/Thunar
MAP[User-Management]=configs/User-Management
MAP[vim]=configs/vim
MAP[wal]=configs/wal
MAP[waybar]=configs/waybar
MAP[waypaper]=configs/waypaper
MAP[wob]=configs/wob
MAP[xfce4]=configs/xfce4
MAP[zshrc]=configs/zshrc
MAP[root]=configs/root
MAP[hypr]=hypr
MAP[scripts]=installer/scripts
MAP[standalone]=installer/standalone
MAP[dracut]=configs/dracut
MAP[nvidia]=configs/nvidia
MAP[grub]=configs/grub

# Intentionally removed from the merged tree (user decision) — excluded from the
# "missing" check. Prefix patterns, matched against merged-relative paths.
REMOVED_EXCLUDE=(
  '^hypr/hyprlock.conf$'
  '^configs/root/.local/share/themes/Arc-Azure-dodger-blue'
  '^configs/root/.config/nwg-look(/|$)'
  '^configs/root/.local/share/nwg-look(/|$)'
  '^configs/waybar(/|$)'   # replaced by hyprtk-bar
  '^configs/figlet(/|$)'   # ASCII/figlet removed (professional headers)
  '^installer/scripts/figlet\.sh$'
)
EXCLUDE_RE="$(IFS='|'; echo "${REMOVED_EXCLUDE[*]}")"

FAIL=0
for d in arch archbang archcraft archman bslx cachy endeavour garuda kiro manjaro reborn; do
  # build expected list: canonical files + overlay files, mapped
  CANON="$ROOT"
  OVER="$ROOT/distro/$d"
  TMP=$(mktemp -d)
  # 1. canonical files
  find "$CANON" -type f -not -path "*/distro/*" -printf "%P\n" | sort > "$TMP/expected.txt"
  # 2. overlay files
  if [ -d "$OVER" ]; then
    find "$OVER" -type f -printf "%P\n" | sort >> "$TMP/expected.txt"
  fi
  sort -u "$TMP/expected.txt" -o "$TMP/expected.txt"
  # 3. actual source files (mapped to merged layout)
  find "$SRC/$d-dots" -type f -printf "%P\n" | sort > "$TMP/actual.txt"
  # exclude things handled specially (installer script differs, os-release variants)
  grep -v -E '^1-install.sh$|^os-release/' "$TMP/actual.txt" > "$TMP/actual2.txt"
  # map actual paths to merged paths
  while IFS= read -r rel; do
    top="${rel%%/*}"
    if [ "$top" = "$rel" ]; then m="$rel"
    elif [ -n "${MAP[$top]:-}" ]; then m="${MAP[$top]}/${rel#${top}/}"
    else m="UNMAPPED:$rel"
    fi
    echo "$m"
  done < "$TMP/actual2.txt" | sort -u > "$TMP/mapped.txt"
  # os-release variants: source os-release/os-release -> installer/os-release/os-release-$d
  echo "installer/os-release/os-release-$d" >> "$TMP/mapped.txt"
  sort -u "$TMP/mapped.txt" -o "$TMP/mapped.txt"
  # diff
  MISSING=$(comm -23 "$TMP/mapped.txt" "$TMP/expected.txt" | grep -vE "$EXCLUDE_RE" || true)
  EXTRA=$(comm -13 "$TMP/mapped.txt" "$TMP/expected.txt")
  if [ -n "$MISSING" ]; then
    echo "[FAIL] $d: files in source NOT in merged:"
    echo "$MISSING" | sed 's/^/  /'
    FAIL=1
  fi
  if [ -n "$EXTRA" ]; then
    echo "[INFO] $d: merged has files not in source (overlay-only additions):"
    echo "$EXTRA" | sed 's/^/  /'
  fi
  echo "[OK] $d: accounted"
  rm -rf "$TMP"
done
echo ""
if [ "$FAIL" = "0" ]; then echo "COMPLETENESS: ALL 11 DISTROS FULLY ACCOUNTED"; else echo "COMPLETENESS: FAILURES ABOVE"; exit 1; fi
