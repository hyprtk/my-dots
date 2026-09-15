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
    cat > "$HOME/.local/bin/awww" << AWWWEOF
#!/bin/bash
# hyprtk awww wrapper — runs the real awww, then triggers the pywal pipeline
REAL_AWW="$REAL_AWW"
WALLPAPER="\${@: -1}"
"\$REAL_AWW" "\$@"
[ -f "\$WALLPAPER" ] && bash ~/.config/hypr/scripts/wallpaper-colors.sh "\$WALLPAPER" &
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
