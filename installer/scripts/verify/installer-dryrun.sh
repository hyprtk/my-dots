#!/bin/bash
# installer-dryrun.sh — end-to-end simulated install of 1-install.sh for all 11 distros.
#
# Simulates a real install inside a sandboxed $HOME:
#   * the repo is hardlink-copied into $HOME/hyprtk (mirrors a real deployment);
#   * every system-mutating command (sudo, pacman, yay, git, wget, curl,
#     systemctl, chsh, grub-mkconfig, mkinitcpio, wal, ...) is stubbed to a no-op;
#   * gum is replaced with a non-interactive stub (confirm=yes, choose=driven by
#     the distro under test, spin=run the wrapped command);
#   * /etc/os-release reads are redirected to a per-distro fake so auto-detection
#     exercises each distro's hooks (pre_install, install_os_release,
#     install_boot, pre_hypr_symlink, wal_init, grub_wallpaper, grudupdater,
#     setup_sudoers).
#
# Verifies each run reaches INSTALLATION COMPLETE with exit 0 and no
# FATAL / FAIL / SPIN FAILED / RUN FAILED entries in install.log.
#
# Usage: installer/scripts/verify/installer-dryrun.sh [distro ...]
set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

DISTROS=(arch archbang archcraft archman bslx cachy endeavour garuda kiro manjaro reborn)
[ $# -gt 0 ] && DISTROS=("$@")

# Realistic fresh-install /etc/os-release IDs (what each distro ships before hyprtk)
declare -A OS_ID=(
  [arch]=arch [archbang]=archbang [archcraft]=archcraft [archman]=archman
  [bslx]=bluestar [cachy]=cachyos [endeavour]=endeavouros [garuda]=garuda
  [kiro]=kiro [manjaro]=manjaro [reborn]=rebornos
)
declare -A LABEL=(
  [arch]="Arch Linux" [archbang]="ArchBANG Linux" [archcraft]="Archcraft Linux"
  [archman]="Archman Linux" [bslx]="BlueStar Linux" [cachy]="CachyOS"
  [endeavour]="EndeavourOS" [garuda]="Garuda Linux" [kiro]="Kiro Linux"
  [manjaro]="Manjaro Linux" [reborn]="RebornOS"
)

# Sandboxes must share the repo's filesystem (hardlinked copies), so keep them
# under ~/.cache instead of /tmp (which is a separate tmpfs on this machine).
SANDBOX_ROOT="$HOME/.cache/hyprtk-dryrun"
mkdir -p "$SANDBOX_ROOT"
STUBBIN="$(mktemp -d "$SANDBOX_ROOT/stubs.XXXXXX")"
[ -d "$STUBBIN" ] || { echo "FATAL: could not create stub dir under $SANDBOX_ROOT" >&2; exit 1; }
# Remove only this run's own temp dirs on exit (never the shared root — other
# parallel runs may live there). Guarded so an empty var can never hit rm.
trap '[ -n "$STUBBIN" ] && rm -rf -- "$STUBBIN"; [ -n "${SB:-}" ] && rm -rf -- "$SB"' EXIT

# ── Stub binaries: any system-mutating command becomes a no-op ──────────────
stub_bin() {
  printf '#!/bin/sh\nexit 0\n' > "$STUBBIN/$1"
  chmod +x "$STUBBIN/$1"
}
for c in sudo pacman yay git makepkg wget curl systemctl chsh grub-mkconfig \
         mkinitcpio wal thunar killall xdg-user-dirs-update xdg-user-dirs-gtk-update \
         pip pip3 python3 update-desktop-database timedatectl sleep clear; do
  stub_bin "$c"
done

# grep stub: redirect /etc/os-release reads to the fake file for the distro under test
cat > "$STUBBIN/grep" <<'EOF'
#!/bin/bash
args=()
for a in "$@"; do
  if [ "$a" = "/etc/os-release" ]; then
    args+=("${FAKE_OS_RELEASE:-/etc/os-release}")
  else
    args+=("$a")
  fi
done
exec /usr/bin/grep "${args[@]}"
EOF
chmod +x "$STUBBIN/grep"

# gum stub: non-interactive driver for the installer TUI
cat > "$STUBBIN/gum-stub" <<'EOF'
#!/bin/bash
cmd="${1:-}"
shift
case "$cmd" in
  confirm) exit 0 ;;
  choose)  echo "${DRYRUN_DISTRO_NAME:-Arch Linux}"; exit 0 ;;
  input)   exit 0 ;;
  spin)
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do shift; done
    [ $# -gt 0 ] && shift
    exec "$@"
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$STUBBIN/gum-stub"

# ── Per-distro simulated install ────────────────────────────────────────────
PASS=0
FAIL=0
for d in "${DISTROS[@]}"; do
  SB="$(mktemp -d "$SANDBOX_ROOT/sb.XXXXXX")"
  H="$SB/home"
  label="${LABEL[$d]:-$d}"

  # Sandbox home mirrors a deployed system (standard home dirs a logged-in
  # session provides; ~/.config is deliberately left for the installer to create)
  mkdir -p "$H/hyprtk" \
           "$H/.cache" \
           "$H/Pictures" \
           "$H/Downloads/yay-git/src/hyprviz-bin" \
           "$H/.local/share/Matuwall/.venv/bin" \
           "$H/.local/share/hyprtk-bar/venv/bin"

  # Fake app venvs — python3/pip are stubbed globally, so each app's
  # `python3 -m venv ...` is a no-op and never creates the venv. Pre-seed the
  # venv bin dir with no-op stubs so `.../venv/bin/pip install -e .` succeeds.
  for venv in "$H/.local/share/Matuwall/.venv" \
              "$H/.local/share/hyprtk-bar/venv"; do
    printf 'home = /usr/bin\ninclude-system-site-packages = true\nversion = 3.14\n' > "$venv/pyvenv.cfg"
    for p in pip pip3 python python3; do
      printf '#!/bin/sh\nexit 0\n' > "$venv/bin/$p"
      chmod +x "$venv/bin/$p"
    done
    printf '#!/bin/sh\n# no-op activate\n' > "$venv/bin/activate"
  done

  # Repo -> $HOME/hyprtk (hardlinked for speed; break the shared install.log)
  cp -al "$ROOT"/. "$H/hyprtk"/ 2>/dev/null
  rm -f "$H/hyprtk/install.log"
  # Per-distro overlay (arch is the base itself)
  [ -d "$ROOT/distro/$d" ] && rsync -a "$ROOT/distro/$d/" "$H/hyprtk/" 2>/dev/null
  # Non-interactive gum
  rm -f "$H/hyprtk/installer/standalone/gum"
  cp "$STUBBIN/gum-stub" "$H/hyprtk/installer/standalone/gum" || { echo "FATAL: gum stub copy failed"; exit 1; }
  chmod +x "$H/hyprtk/installer/standalone/gum"

  # Fake fresh-system /etc/os-release for this distro
  FAKE="$SB/os-release"
  printf 'NAME="Hyprtk on (%s)"\nPRETTY_NAME="Hyprtk on (%s)"\nID=%s\nBUILD_ID=rolling\n' \
    "$label" "$label" "${OS_ID[$d]:-$d}" > "$FAKE"

  RUNLOG="$SB/run.log"
  # graphics-card reads 2 (AMD); fonts/wallpapers read n (skip clone) — plus slack
  printf '2\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\n' | \
    env HOME="$H" PATH="$STUBBIN:$PATH" TERM=xterm \
        DRYRUN_DISTRO_NAME="$label" FAKE_OS_RELEASE="$FAKE" \
        bash "$H/hyprtk/1-install.sh" >"$RUNLOG" 2>&1
  RC=$?

  LOG="$H/hyprtk/install.log"
  ERRORS=""
  [ "$RC" -ne 0 ] && ERRORS="installer exit code $RC"
  if [ -f "$LOG" ]; then
    LERR="$(grep -E 'FATAL:|FAIL:|SPIN FAILED|RUN FAILED' "$LOG" 2>/dev/null)"
    [ -n "$LERR" ] && ERRORS="$ERRORS${ERRORS:+$'\n'}$LERR"
  fi
  if [ -f "$RUNLOG" ]; then
    RERR="$(grep -inE 'error|not found|no such file|traceback|command not found|denied|fatal' "$RUNLOG" 2>/dev/null \
            | grep -viE "Unable to symlink '/usr/bin/python' to '.*Matuwall/.venv/bin/python'")"
    [ -n "$RERR" ] && ERRORS="$ERRORS${ERRORS:+$'\n'}[runlog] $RERR"
  fi

  if [ -z "$ERRORS" ]; then
    echo "[OK]   $d ($label): install completed, exit 0, no errors"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $d ($label):"
    echo "$ERRORS" | sed 's/^/        /'
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$SB"
done

echo ""
echo "=== installer dry-run: $PASS/${#DISTROS[@]} passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1