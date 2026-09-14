#!/bin/bash
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
TMP=$(mktemp -d)

# Known dead refs that cannot be resolved by design:
#   os-release-<distro> paths are written as `os-release-$DISTRO`; the `$` ends
#   the match, so the variable-suffixed ref is a false positive.
DEAD_REFS=(
  "/installer/os-release/os-release-"
)

find "$ROOT" -type f \
  -not -path "*/assets/papirus-icons/*" \
  -not -name "PLANNING.md" \
  -not -name "1-install.sh" \
  -print0 2>/dev/null | while IFS= read -r -d '' f; do
    grep -hoE "~/hyprtk/[A-Za-z0-9._/-]+" "$f" 2>/dev/null
  done | sed 's|/*$||' | sort -u > "$TMP/refs.txt"

MISSING=0
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

  # Top-level files
  case "$rel" in
    /.zshrc|/README.md|/CHANGELOG|/cheatsheet.md|/LICENSE|/default.png|/.folder.png|/.gitattributes|/1-install.sh)
      [ -e "$ROOT${rel}" ] || { echo "  MISSING(TOP): $ref"; MISSING=1; }
      continue ;;
  esac

  [ -e "$ROOT${rel}" ] || { echo "  MISSING: $ref"; MISSING=1; }
done < "$TMP/refs.txt"

TOTAL=$(wc -l < "$TMP/refs.txt")
rm -rf "$TMP"

if [ "$MISSING" -eq 0 ]; then
  echo "[OK] all $TOTAL refs resolve (known dead refs excluded)"
else
  echo "[FAIL] $TOTAL refs checked, missing found above"
  exit 1
fi
