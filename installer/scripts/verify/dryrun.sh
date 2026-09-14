#!/bin/bash
# Simulate deployment per distro: canonical + overlay -> verify every referenced
# ~/hyprtk path resolves. Known source-level dead refs are whitelisted.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# Known dead refs that cannot be resolved by design:
#   os-release-<distro> paths are written as `os-release-$DISTRO`; the `$` ends
#   the match, so the variable-suffixed ref is a false positive.
DEAD_REFS=(
  "/installer/os-release/os-release-"
)

PASS=0
FAIL=0
for d in arch archbang archcraft archman bslx cachy endeavour garuda kiro manjaro reborn; do
  TMP=$(mktemp -d)
  rsync -a --exclude='distro' --exclude='installer/steps' --exclude='installer/scripts/build-merged.sh' --exclude='PLANNING.md' "$ROOT/" "$TMP/" 2>/dev/null
  [ -d "$ROOT/distro/$d" ] && rsync -a "$ROOT/distro/$d/" "$TMP/" 2>/dev/null
  DFAIL=0
  while IFS= read -r ref; do
    # `~/hyprtk/...` prose placeholders in docs are not paths.
    case "$ref" in *"..."*) continue ;; esac

    rel="${ref#\~/hyprtk}"

    # Skip known dead refs
    skip=0
    for dead in "${DEAD_REFS[@]}"; do
      case "$rel" in
        "$dead") skip=1; break ;;
      esac
    done
    [ "$skip" -eq 1 ] && continue

    [ -e "$TMP$rel" ] || { echo "  [$d] MISSING: $ref"; DFAIL=1; }
  done < <(grep -rhoE "~/hyprtk/[A-Za-z0-9._/-]+" "$TMP" --include="*" 2>/dev/null | sed 's|/*$||' | sort -u)
  if [ "$DFAIL" -eq 0 ]; then
    echo "[OK] $d: all refs resolve"
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$TMP"
done

echo ""
echo "=== $PASS/11 distros passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
