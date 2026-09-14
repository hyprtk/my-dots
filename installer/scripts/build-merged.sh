#!/bin/bash
set -euo pipefail

SRC=/home/hyprtk/Projects/AI-Projects/Source-Files/dots
ROOT=/home/hyprtk/Projects/AI-Projects/hyprtk-merged
BASE=arch-dots

# --- directory mapping: source top-level -> merged location ---
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
MAP[waypaper]=configs/waypaper
MAP[wob]=configs/wob
MAP[xfce4]=configs/xfce4
MAP[zshrc]=configs/zshrc
MAP[root]=configs/root
MAP[hypr]=hypr
MAP[os-release]=installer/os-release
MAP[scripts]=installer/scripts
MAP[standalone]=installer/standalone
MAP[dracut]=configs/dracut
MAP[nvidia]=configs/nvidia
MAP[grub]=configs/grub

# top-level files that stay at top level
TOP_FILES="1-install.sh CHANGELOG cheatsheet.md default.png .folder.png .gitattributes LICENSE README.md .zshrc"

# exclude heavy dirs from diff-based overlay generation (verified identical)
EXCL=(--exclude='papirus-icons' --exclude='fonts' --exclude='Wallpapers' --exclude='themes' --exclude='oh-my-zsh' --exclude='os-release')

map_rel() {
  # given a path relative to a distro root (e.g. scripts/library.sh, os-release/os-release)
  # print the merged-relative path (e.g. installer/scripts/library.sh)
  local rel="$1" top="${1%%/*}"
  if [ -n "${MAP[$top]:-}" ]; then
    echo "${MAP[$top]}/${rel#${top}/}"
  elif [ "$top" = "$rel" ]; then
    # top-level file -> stays top-level
    echo "$rel"
  else
    echo "UNMAPPED:$rel"
  fi
}

rm -rf "$ROOT"
mkdir -p "$ROOT"
TMPDIR=$(mktemp -d)

# ---------- 1. canonical core from arch-dots ----------
echo "### Canonical core from $BASE"
# top-level files
for f in $TOP_FILES; do
  if [ -e "$SRC/$BASE/$f" ]; then
    cp -a "$SRC/$BASE/$f" "$ROOT/$f"
    echo "  top: $f"
  fi
done

# mapped dirs
for top in "${!MAP[@]}"; do
  src="$SRC/$BASE/$top"
  dst="$ROOT/${MAP[$top]}"
  if [ "$top" = "os-release" ]; then continue; fi   # os-release handled specially (hyphen variants)
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
    echo "  dir: $top -> ${MAP[$top]}"
  fi
done

# os-release variants: installer/os-release/os-release-<distro> for ALL 11
mkdir -p "$ROOT/installer/os-release"
for d in arch archbang archcraft archman bslx cachy endeavour garuda kiro manjaro reborn; do
  src="$SRC/$d-dots/os-release/os-release"
  if [ -f "$src" ]; then
    cp -a "$src" "$ROOT/installer/os-release/os-release-$d"
    echo "  os-release: $d"
  fi
done
# cachy's extra branding file
if [ -f "$SRC/cachy-dots/os-release/cachyos-branding" ]; then
  cp -a "$SRC/cachy-dots/os-release/cachyos-branding" "$ROOT/installer/os-release/cachyos-branding"
fi

# ---------- 2. distro overlays from real diffs ----------
echo "### Distro overlays"
for d in archbang archcraft archman bslx cachy endeavour garuda kiro manjaro reborn; do
  OVERLAY="$ROOT/distro/$d"
  mkdir -p "$OVERLAY"
  echo "--- $d ---"

  # 2a. files only in this distro (not in arch)
  diff -rq "$SRC/$BASE" "$SRC/$d-dots" "${EXCL[@]}" -x 'screenshots' -x '1-install.sh' 2>/dev/null > "$TMPDIR/diff-only.txt" || true
  while IFS= read -r line; do
    case "$line" in
      "Only in $SRC/$d-dots"*)
        rest="${line#Only in }"
        dir="${rest%%:*}"
        name="${rest##*: }"
        rel="${dir#$SRC/$d-dots}"
        rel="${rel#/}"
        if [ -d "$dir/$name" ]; then
          # top-level dir only-in -> copy whole dir into its mapped location
          top="$name"
          if [ -n "${MAP[$top]:-}" ]; then
            m="${MAP[$top]}"
            mkdir -p "$OVERLAY/$m"
            cp -a "$dir/$name/." "$OVERLAY/$m/"
            echo "  only-in dir: $top -> $m"
          else
            echo "  !!UNMAPPED only-in dir: $top"
          fi
        else
          if [ -n "$rel" ]; then p="$rel/$name"; else p="$name"; fi
          m="$(map_rel "$p")"
          if [ "$m" != "UNMAPPED:$p" ]; then
            mkdir -p "$OVERLAY/$(dirname "$m")"
            cp -a "$dir/$name" "$OVERLAY/$m"
            echo "  only-in: $p -> $m"
          else
            echo "  !!UNMAPPED only-in: $p"
          fi
        fi
        ;;
    esac
  done < "$TMPDIR/diff-only.txt"

  # 2b. files that differ in content
  diff -rq "$SRC/$BASE" "$SRC/$d-dots" "${EXCL[@]}" -x 'screenshots' -x '1-install.sh' -x '*.png' 2>/dev/null > "$TMPDIR/diff-differ.txt" || true
  while IFS= read -r line; do
    case "$line" in
      "Files "*" and "*" differ"*)
        rest="${line#Files }"
        a="${rest%% and *}"
        b="${rest#* and }"; b="${b%% differ}"
        rel="${b#$SRC/$d-dots/}"
        m="$(map_rel "$rel")"
        if [ "$m" != "UNMAPPED:$rel" ]; then
          mkdir -p "$OVERLAY/$(dirname "$m")"
          cp -a "$b" "$OVERLAY/$m"
          echo "  diff: $rel -> $m"
        else
          echo "  !!UNMAPPED diff: $rel"
        fi
        ;;
    esac
  done < "$TMPDIR/diff-differ.txt"

  # 2c. screenshots (per-distro, unique)
  for s in "$SRC/$d-dots"/screenshots/*; do
    [ -e "$s" ] || continue
    mkdir -p "$OVERLAY/assets/screenshots"
    cp -a "$s" "$OVERLAY/assets/screenshots/$(basename "$s")"
  done
done

echo "### Done. Top-level structure:"
ls -la "$ROOT"
echo
echo "### Overlay sizes:"
for d in "$ROOT"/distro/*/; do echo "$(basename "$d"): $(find "$d" -type f | wc -l) files"; done
rm -rf "$TMPDIR"
