#!/bin/bash
# ── Allow pywal's ImageMagick TXT coder ───────────────────────────────────
# pywal reads a wallpaper's palette with
#     magick <img> -resize 25% -colors 16 -unique-colors txt:-
# ImageMagick 7 ships a security policy that denies the TXT coder, in which
# case the command exits 0 with NO output: pywal retries larger palette sizes,
# then gives up and ~/.cache/wal/colors.json is never written — a silent
# no-result "success". Remove TXT — and only TXT — from the module restriction
# in whatever ImageMagick policy is present so colour extraction works.
#
# Idempotent. The original policy is backed up once as *.hyprtk-bak.
# Needs root (callers run it after elevation is set up).
# ──────────────────────────────────────────────────────────────────────────

set -u

POLICIES=(
    /etc/IM-7/policy.xml
    /etc/ImageMagick-7/policy.xml
    /etc/ImageMagick-6/policy.xml
)

if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
    echo "imagemagick not installed; nothing to do"
    exit 0
fi

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

changed=0
for f in "${POLICIES[@]}"; do
    [ -f "$f" ] || continue
    grep -qE 'domain="module"[^>]*TXT' "$f" || continue
    as_root cp -n "$f" "$f.hyprtk-bak" 2>/dev/null || true
    as_root sed -i 's/TXT,//; s/,TXT//' "$f"
    echo "allowed TXT coder in $f"
    changed=1
done

[ "$changed" -eq 0 ] && echo "no ImageMagick TXT restriction found"
exit 0
