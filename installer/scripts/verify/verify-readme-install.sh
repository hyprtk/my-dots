#!/bin/bash
# verify-readme-install.sh — the dotfiles READMEs must always show the canonical
# install command, and never link to the removed per-distro repositories.
#
# Canonical block (whitespace-insensitive):
#     git clone https://github.com/hyprtk/dotfiles.git ~/hyprtk
#     cd ~/hyprtk
#     sh ./1-install.sh
#
# Checked: the root README.md and every distro/<name>/README.md.
set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

EXPECTED='git clone https://github.com/hyprtk/dotfiles.git ~/hyprtk
cd ~/hyprtk
sh ./1-install.sh'

norm() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

FILES=()
[ -f "$ROOT/README.md" ] && FILES+=("$ROOT/README.md")
for f in "$ROOT"/distro/*/README.md; do
    [ -f "$f" ] && FILES+=("$f")
done

PASS=0
FAIL=0
for f in "${FILES[@]}"; do
    rel="${f#"$ROOT"/}"
    errs=""

    # 1) No references to the removed per-distro repositories (e.g. archbang-dots).
    if grep -qE 'github\.com/hyprtk/[a-z0-9-]+-dots' "$f"; then
        errs="${errs}references a removed per-distro repo (*-dots)\n"
    fi

    # 2) Every `git clone` line must be exactly the canonical dotfiles clone,
    #    followed by the canonical `cd` + run lines.
    mapfile -t clone_lines < <(grep -nE '^[[:space:]]*git clone' "$f" | cut -d: -f1)
    if [ "${#clone_lines[@]}" -eq 0 ]; then
        if grep -q '1-install.sh' "$f"; then
            errs="${errs}mentions 1-install.sh but has no canonical clone block\n"
        fi
    else
        for n in "${clone_lines[@]}"; do
            got="$(sed -n "${n},$((n + 2))p" "$f" | norm)"
            if [ "$got" != "$EXPECTED" ]; then
                errs="${errs}non-canonical install block at line $n\n"
            fi
        done
    fi

    if [ -z "$errs" ]; then
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $rel"
        printf "        ${errs}"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== readme install check: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
