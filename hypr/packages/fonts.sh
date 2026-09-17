# ── fonts ─────────────────────────────────────────────────────────
#!/bin/bash
echo ""
echo ""
echo "-> Install fonts"
while true; do
    read -p "Do you want to clone the fonts? ~/fonts (Yy/Nn): " yn
    case $yn in
        [Yy]* )
            # ~/.local/share/fonts may already exist (and be empty) on some
            # distros, so decide on content, not existence: only skip the clone
            # when there are fonts already there. git clone accepts an existing
            # empty directory, so an empty one is safe to clone into.
            if [ -d ~/.local/share/fonts/ ] && [ -n "$(ls -A ~/.local/share/fonts 2>/dev/null)" ]; then
                if [ -d ~/.local/share/fonts/.git ]; then
                    git -C ~/.local/share/fonts pull --ff-only 2>/dev/null || true
                    echo "user fonts updated."
                else
                    echo "fonts folder already exists."
                fi
            else
                git clone https://github.com/hyprtk/fonts.git ~/.local/share/fonts
                echo "user fonts installed."
            fi
            echo "User Fonts Installed."
        break;;
        [Nn]* ) 
            if [ -d ~/.local/share/fonts/ ]; then
                echo "fonts folder already exists."
            else
                mkdir ~/.local/share/fonts
            fi
            _PKGDIR="$(cd "$(dirname "$0")" && pwd)"
            sudo cp -r "$_PKGDIR/../../assets/fonts/"* /usr/share/fonts 2>/dev/null || true
            sudo cp -r ~/.local/share/fonts/* /usr/share/fonts 2>/dev/null || true
            echo "System Fonts Installed."
        break;;
        * ) echo "Please answer yes or no.";;
    esac
done