#!/bin/bash
# awww pywal wrapper — runs the real awww, then triggers the pywal pipeline.
#
# The real binary is resolved at install time: the AUR puts awww in /usr/bin,
# the cross-distro source build in /usr/local/bin, and Void/Alpine ship swww
# (symlinked to awww by awww-install.sh). Nothing here hardcodes /usr/bin.

echo "Setting up awww wrapper..."

REAL_AWW=""
for c in /usr/local/bin/awww /usr/bin/awww /bin/awww; do
    if [ -x "$c" ] && [ "$c" != "$HOME/.local/bin/awww" ]; then
        REAL_AWW="$c"
        break
    fi
done
# No awww by that name — fall back to a swww install.
if [ -z "$REAL_AWW" ]; then
    for c in /usr/local/bin/swww /usr/bin/swww /bin/swww; do
        [ -x "$c" ] && { REAL_AWW="$c"; break; }
    done
fi

mkdir -p "$HOME/.local/bin"

if [ -n "$REAL_AWW" ]; then
    cat > "$HOME/.local/bin/awww" << 'AWWWEOF'
#!/bin/bash
# hyprtk awww wrapper — run the real awww/swww, then drive the pywal pipeline.
# Resolve the real binary at runtime: Arch's AUR uses /usr/bin, the cross-distro
# source build uses /usr/local/bin, and Void/Alpine ship it as swww.
REAL_AWW=""
for c in /usr/local/bin/awww /usr/bin/awww /bin/awww \
         /usr/local/bin/swww /usr/bin/swww /bin/swww; do
    if [ -x "$c" ] && [ "$c" != "$0" ]; then REAL_AWW="$c"; break; fi
done
if [ -z "$REAL_AWW" ]; then
    echo "awww: no awww/swww binary found" >&2
    exit 127
fi
WALLPAPER=""
for _a in "$@"; do [ -f "$_a" ] && WALLPAPER="$_a"; done
"$REAL_AWW" "$@"
rc=$?
# wallpaper-colors.sh only regenerates the palette; it must not re-call awww.
if [ -f "$WALLPAPER" ]; then
    bash "$HOME/.config/hypr/scripts/wallpaper-colors.sh" "$WALLPAPER" &
fi
exit "$rc"
AWWWEOF
    chmod +x "$HOME/.local/bin/awww"

    # swww compatibility names beside the real binary (best effort; the
    # installer already creates these for a source build).
    _dir="$(dirname "$REAL_AWW")"
    case "$REAL_AWW" in
        */swww|*/swww-daemon) ;;
        *)
            [ -e "$_dir/swww" ]        || sudo ln -sf awww        "$_dir/swww" 2>/dev/null || true
            [ -e "$_dir/swww-daemon" ] || sudo ln -sf awww-daemon "$_dir/swww-daemon" 2>/dev/null || true
            ;;
    esac
else
    echo "  ! no awww/swww binary found — run installer/scripts/awww-install.sh first"
    echo "    (the pywal wrapper was not installed)"
fi

# Add ~/.local/bin to PATH if not already there
if ! grep -q 'local/bin' ~/.zshrc 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
fi
if ! grep -q 'local/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

# Add pywal terminal color restore
if ! grep -q 'wal/sequences' ~/.zshrc 2>/dev/null; then
    echo '(cat ~/.cache/wal/sequences &)' >> ~/.zshrc
fi

echo "awww wrapper installed!"
