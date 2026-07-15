#!/bin/bash
#
# install.sh - Declarative Arch Linux dotfiles provisioner
#
# Usage:
#   install.sh                        # full run from config.yaml
#   install.sh --dry-run              # preview changes
#   install.sh --only packages        # run only packages section
#   install.sh --skip theming,shell   # run everything except those
#   install.sh --stop-at services     # run detect → packages → symlinks → services, stop
#   install.sh -c ./custom.yaml       # use custom config
#   install.sh -y                     # skip all prompts
#

set -uo pipefail

# ===================== DEFAULTS =====================

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_CONFIG="$SCRIPT_DIR/config.yaml"
CONFIG_FILE="$DEFAULT_CONFIG"
DRY_RUN=false
ASSUME_YES=false
VERBOSE=false
ONLY_SECTIONS=()
SKIP_SECTIONS=()
STOP_AT=""

readonly SECTIONS=(detect packages symlinks services theming shell)
ERROR_COUNT=0
declare -A SECTION_ERRORS
SECTION_ERRORS=()
# Config values (populated by load_config)
DISTRO=""
INSTALL_PACMAN=()
REMOVE_PACMAN=()
INSTALL_AUR=()
SYMLINKS=()
SERVICES_ENABLE=()
SERVICES_DISABLE=()
THEMING_DISPLAY_MANAGER=""
THEMING_COLOR_BACKEND=""
THEMING_COLOR_SOURCE=""
THEMING_FONTS=()
THEMING_ICONS=""
SHELL_DEFAULT=""
SHELL_PLUGINS=()

# ===================== CLI PARSING =====================

usage() {
    cat <<EOF
Usage: install.sh [options]

Declarative Arch Linux dotfiles provisioner.

Options:
  -c, --config FILE     Config file path (default: $DEFAULT_CONFIG)
  -n, --dry-run         Preview changes without applying
  -y, --assume-yes      Skip all confirmation prompts
  -v, --verbose         Detailed output
  --only SECTIONS       Comma-separated list of sections to run
  --skip SECTIONS       Comma-separated list of sections to skip
  --stop-at SECTION     Run sections up to and including this one
  -g, --gui             Launch graphical installer
  -h, --help            Show this message

Sections: detect, packages, symlinks, services, theming, shell
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config) CONFIG_FILE="$2"; shift 2 ;;
            -n|--dry-run) DRY_RUN=true; shift ;;
            -y|--assume-yes) ASSUME_YES=true; shift ;;
            -v|--verbose) VERBOSE=true; shift ;;
            --only) IFS=',' read -ra ONLY_SECTIONS <<< "$2"; shift 2 ;;
            --skip) IFS=',' read -ra SKIP_SECTIONS <<< "$2"; shift 2 ;;
            --stop-at) STOP_AT="$2"; shift 2 ;;
            -g|--gui)
                GUI_SCRIPT="$(cd "$(dirname "$0")" && pwd)/install-gui.sh"
                if [[ -f "$GUI_SCRIPT" ]]; then
                    exec "$GUI_SCRIPT" "$CONFIG_FILE"
                else
                    echo "Error: install-gui.sh not found next to install.sh"
                    exit 1
                fi
                ;;
            -h|--help) usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done
}

# ===================== MINIMAL YAML PARSER =====================

# Parses our specific YAML config structure into the global vars above.
# Handles: key: value, nested keys, and list items (- item).
# No external deps needed.

parse_yaml_config() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1

    local current_section=""
    local current_subsection=""
    local in_list=false
    local list_target=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip trailing whitespace, skip blank/comment lines
        line="${line%%#*}"
        [[ -z "${line// /}" ]] && continue

        local indent=0
        local stripped="$line"
        while [[ "$stripped" =~ ^[[:space:]] ]]; do
            stripped="${stripped:1}"; ((indent++))
        done
        [[ -z "$stripped" ]] && continue

        if [[ "$stripped" =~ ^-\ (.*) ]]; then
            local item="${BASH_REMATCH[1]}"
            item="${item#\"}"; item="${item%\"}"
            item="${item#\'}"; item="${item%\'}"
            case "$list_target" in
                INSTALL_PACMAN) INSTALL_PACMAN+=("$item") ;;
                REMOVE_PACMAN) REMOVE_PACMAN+=("$item") ;;
                INSTALL_AUR) INSTALL_AUR+=("$item") ;;
                SYMLINKS) SYMLINKS+=("$item") ;;
                SERVICES_ENABLE) SERVICES_ENABLE+=("$item") ;;
                SERVICES_DISABLE) SERVICES_DISABLE+=("$item") ;;
                THEMING_FONTS) THEMING_FONTS+=("$item") ;;
                SHELL_PLUGINS) SHELL_PLUGINS+=("$item") ;;
            esac
            continue
        fi

        if [[ "$stripped" =~ ^([a-zA-Z_-]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            value="${value#\"}"; value="${value%\"}"
            value="${value#\'}"; value="${value%\'}"

            in_list=false
            list_target=""

            if [[ $indent -eq 0 ]]; then
                current_section="$key"
                current_subsection=""
                case "$key" in
                    distro) DISTRO="$value" ;;
                esac
            elif [[ $indent -eq 2 ]]; then
                current_subsection="$key"
                case "${current_section}.${key}" in
                    packages.pacman) ;;
                    services.enable) list_target="SERVICES_ENABLE"; in_list=true ;;
                    services.disable) list_target="SERVICES_DISABLE"; in_list=true ;;
                esac
            fi

            [[ "$indent" -eq 2 ]] && continue

            if [[ -n "$value" ]]; then
                case "${current_section}.${key}" in
                    packages.pacman) ;;
                    packages.aur) list_target="INSTALL_AUR"; in_list=true ;;
                    symlinks.*) SYMLINKS+=("$key: $value") ;;
                    services.*) ;;
                    theming.display-manager) THEMING_DISPLAY_MANAGER="$value" ;;
                    theming.color-scheme) ;;
                    theming.fonts) list_target="THEMING_FONTS"; in_list=true ;;
                    theming.icons) THEMING_ICONS="$value" ;;
                    shell.default) SHELL_DEFAULT="$value" ;;
                    shell.plugins) list_target="SHELL_PLUGINS"; in_list=true ;;
                esac
            fi
        fi

        # Handle deeper key:value pairs within sections
        if [[ $indent -eq 4 && -n "$current_section" && -n "$current_subsection" && "$stripped" =~ ^([a-zA-Z_-]+):[[:space:]]*(.*)$ ]]; then
            local subkey="${BASH_REMATCH[1]}"
            local subvalue="${BASH_REMATCH[2]}"
            subvalue="${subvalue#\"}"; subvalue="${subvalue%\"}"
            subvalue="${subvalue#\'}"; subvalue="${subvalue%\'}"

            case "${current_section}.${current_subsection}.${subkey}" in
                packages.pacman.add) list_target="INSTALL_PACMAN"; in_list=true ;;
                packages.pacman.remove) list_target="REMOVE_PACMAN"; in_list=true ;;
                theming.color-scheme.backend) THEMING_COLOR_BACKEND="$subvalue" ;;
                theming.color-scheme.source) THEMING_COLOR_SOURCE="$subvalue" ;;
                services.enable.*) ;;
                services.disable.*) ;;
            esac
        fi
    done < "$file"
}

# ===================== LOAD CONFIG =====================

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        if command -v yq &>/dev/null; then
            # Convert YAML to bash vars using yq if available
            local tmp
            tmp=$(mktemp)
            yq eval '.distro // "auto"' "$CONFIG_FILE" 2>/dev/null | tr -d '"' > "$tmp" && DISTRO=$(cat "$tmp")
            # ... would do more but yq JSON parsing in bash is verbose
            # Fall through to native parser for all values
            rm -f "$tmp"
        fi
        parse_yaml_config "$CONFIG_FILE" || {
            echo "Warning: Could not parse $CONFIG_FILE, using defaults"
        }
    else
        echo "Config file not found: $CONFIG_FILE"
        echo "Running with built-in defaults..."
    fi

    # Set defaults for empty values
    if [[ -z "$DISTRO" ]]; then
        DISTRO="auto"
    fi
}

# ===================== UTILITY FUNCTIONS =====================

log()  { echo "  $1"; }
warn() { echo "  [WARN] $1" >&2; }

_fail() {
    echo "  [FAIL] $1" >&2
    ((ERROR_COUNT++))
}

run() {
    if $DRY_RUN; then
        echo "  [DRY-RUN] $*"
        return 0
    fi
    if $VERBOSE; then
        echo "  + $*"
    fi
    "$@" || {
        local rc=$?
        warn "Command failed (exit $rc): $*"
        ((ERROR_COUNT++))
        return $rc
    }
}

_run_each() {
    local label="$1"
    shift
    for cmd in "$@"; do
        if $DRY_RUN; then
            echo "  [DRY-RUN] $cmd"
        else
            $cmd || _fail "$label: '$cmd' failed"
        fi
    done
}

confirm() {
    local prompt="$1"
    $ASSUME_YES && return 0
    local yn
    while true; do
        read -p "  $prompt (Yy/Nn): " yn
        case $yn in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

_header() {
    clear
    echo "=============================================================================="
    printf "  %-76s\n" "$1"
    echo "=============================================================================="
    echo ""
}

_footer() {
    echo ""
    echo "------------------------------------------------------------------------------"
    printf "  \342\234\223 %-74s\n" "$1 completed"
    echo "------------------------------------------------------------------------------"
    $DRY_RUN || sleep 2
}

# Distro detection
detect_distro() {
    if [[ "$DISTRO" != "auto" ]]; then
        return
    fi
    DISTRO=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
    fi
}

_isInstalledPacman() {
    package="$1"
    check="$(pacman -Qs --color always "${package}" 2>/dev/null | grep "local" | grep "${package} " || true)"
    [[ -n "${check}" ]]
}

_isInstalledYay() {
    package="$1"
    check="$(yay -Qs --color always "${package}" 2>/dev/null | grep "local" | grep "${package} " || true)"
    [[ -n "${check}" ]]
}

_installPackagesPacman() {
    local toInstall=()
    for pkg; do
        if _isInstalledPacman "${pkg}"; then
            $VERBOSE && echo "  ${pkg} is already installed."
            continue
        fi
        toInstall+=("${pkg}")
    done
    [[ ${#toInstall[@]} -eq 0 ]] && return
    printf "  Packages not installed:\n%s\n" "${toInstall[*]}"
    run sudo pacman --noconfirm -S "${toInstall[@]}"
}

_installPackagesYay() {
    local toInstall=()
    for pkg; do
        if _isInstalledYay "${pkg}"; then
            $VERBOSE && echo "  ${pkg} is already installed."
            continue
        fi
        toInstall+=("${pkg}")
    done
    [[ ${#toInstall[@]} -eq 0 ]] && return
    printf "  AUR packages not installed:\n%s\n" "${toInstall[*]}"
    run yay --noconfirm -S "${toInstall[@]}"
}

_regenerate_initramfs() {
    if command -v dracut &>/dev/null; then
        run sudo dracut --force
    else
        run sudo mkinitcpio --config /etc/mkinitcpio.conf --generate /boot/initramfs-custom.img
    fi
}

_regenerate_all_initramfs() {
    if command -v dracut &>/dev/null; then
        run sudo dracut --regenerate-all --force
    else
        run sudo mkinitcpio -P
    fi
}

_installSymLink() {
    local name="$1" symlink="$2" linksource="$3" linktarget="$4"

    if ! $ASSUME_YES && ! confirm "Install ${name}? (existing will be removed)"; then
        return
    fi

    if $DRY_RUN; then
        echo "  [DRY-RUN] ln -s ${linksource} ${linktarget}"
        return
    fi

    if [[ -L "$symlink" ]]; then
        rm "$symlink"
        ln -s "$linksource" "$linktarget"
        echo "  Symlink ${linksource} -> ${linktarget} created."
    elif [[ -d "$symlink" ]]; then
        rm -rf "${symlink}/"
        ln -s "$linksource" "$linktarget"
        echo "  Symlink for directory ${linksource} -> ${linktarget} created."
    elif [[ -f "$symlink" ]]; then
        rm "$symlink"
        ln -s "$linksource" "$linktarget"
        echo "  Symlink to file ${linksource} -> ${linktarget} created."
    else
        ln -s "$linksource" "$linktarget"
        echo "  New symlink ${linksource} -> ${linktarget} created."
    fi
}

# ===================== SECTION: detect =====================

section_detect() {
    detect_distro
    _header "Hyprland & XFCE Installation - Detected: ${DISTRO:-unknown}"
    echo ""
    echo "  Root password will be required to proceed."
    echo ""
    $DRY_RUN || sleep 2
}

# ===================== SECTION: packages =====================

section_packages() {
    detect_distro

    _header "Removing leftover packages"
    case $DISTRO in
        bslx)
            run sudo pacman -Rcs plasma-meta kde-applications-meta --noconfirm
            run sudo pacman -Rcs plasma kde-applications --noconfirm
            ;;
        kiro)
            run sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm
            run sudo pacman -Rns plasma kde-applications --noconfirm
            run sudo pacman -Rns xfce4 xfce4-goodies thunar catfish thunar-shares-plugin --noconfirm
            run yay -Rns sddm-git fastfetch-git --noconfirm
            ;;
        archbang)
            run sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm
            run sudo pacman -Rns plasma kde-applications --noconfirm
            run sudo pacman -Rns swaylock --noconfirm
            ;;
        *)
            run sudo pacman -Rns plasma-meta kde-applications-meta --noconfirm
            run sudo pacman -Rns plasma kde-applications --noconfirm
            ;;
    esac
    _footer "Removing leftover packages"

    # Install yay if needed
    if ! command -v yay &>/dev/null; then
        _header "Installing Yay (AUR helper)"
        run sudo pacman -S --noconfirm base-devel
        run git clone https://aur.archlinux.org/yay-git.git ~/Downloads/yay-git
        (cd ~/Downloads/yay-git && run makepkg -si)
        _footer "Installing Yay"
    fi

    # Graphics card setup
    if ! $ASSUME_YES && confirm "Proceed with full installation?"; then
        :
    elif ! $ASSUME_YES; then
        exit
    fi

    _header "Graphics Card Setup"
    echo "  1) Intel"
    echo "  2) AMD"
    echo "  3) Nvidia"
    echo "  4) Virtualization (QEMU/virt & VMware)"
    echo ""

    local gpu_choice
    if [[ -n "${GPU_CHOICE:-}" ]]; then
        gpu_choice=$GPU_CHOICE
    elif $ASSUME_YES; then
        gpu_choice=2
    else
        read gpu_choice
    fi

    case $gpu_choice in
        1)
            run sudo pacman -S --noconfirm xf86-video-intel mesa vulkan-intel
            ;;
        2|"")
            run sudo pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon vdpauinfo corectrl libvdpau
            run sudo sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
            _regenerate_initramfs
            ;;
        3)
            run sudo sed -i 's/GRUB_CMDLINE_LINUX="rootfstype=ext4"/GRUB_CMDLINE_LINUX="rootfstype=ext4 nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprob.blacklist=nouveau"/' /etc/default/grub
            run sudo grub-mkconfig -o /boot/grub/grub.cfg
            run sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
            echo -e "options nvidia-drm modeset=1" | run sudo tee -a /etc/modprobe.d/nvidia.conf
            run sudo pacman -S --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings qt5-wayland qt5ct qt6-wayland qt6ct libva
            run yay --noconfirm -S libva-nvidia-driver-git
            _regenerate_initramfs
            ;;
        4)
            run sudo pacman -S --noconfirm qemu-guest-agent spice-vdagent xf86-video-qxl mesa open-vm-tools
            run yay --noconfirm -S xf86-video-vmware
            run sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
            run sudo systemctl enable --now spice-vdagentd 2>/dev/null || true
            run sudo systemctl enable --now vmtoolsd 2>/dev/null || true
            ;;
    esac
    _footer "Graphics Card Setup"

    if ! $ASSUME_YES && ! confirm "Install core applications?"; then
        echo "Installation aborted."
        exit
    fi

    # Install packages from config or defaults
    _header "Installing core packages"

    if [[ ${#INSTALL_PACMAN[@]} -gt 0 ]]; then
        local chunks=()
        for pkg in "${INSTALL_PACMAN[@]}"; do
            chunks+=("$pkg")
            if [[ ${#chunks[@]} -ge 25 ]]; then
                run sudo pacman -S --noconfirm "${chunks[@]}"
                chunks=()
            fi
        done
        [[ ${#chunks[@]} -gt 0 ]] && run sudo pacman -S --noconfirm "${chunks[@]}"
    fi

    if [[ ${#INSTALL_AUR[@]} -gt 0 ]]; then
        local chunks=()
        for pkg in "${INSTALL_AUR[@]}"; do
            chunks+=("$pkg")
            if [[ ${#chunks[@]} -ge 15 ]]; then
                run yay --noconfirm -S "${chunks[@]}"
                chunks=()
            fi
        done
        [[ ${#chunks[@]} -gt 0 ]] && run yay --noconfirm -S "${chunks[@]}"
    fi

    # Always install core package groups
    local common_pacman=(
        hyprland xdg-desktop-portal-wlr swayidle swappy cliphist xorg-xhost nwg-look
        mission-center curl imagemagick jq bc brightnessctl playerctl libadwaita
        gtk-layer-shell python python-pip python-virtualenv python-gobject gtk4 wob
        xfce4 xfce4-goodies parole thunar mousepad chromium
        cups cups-pdf cups-filters nss-mdns system-config-printer cups-browsed
        libusb ipp-usb xdg-utils colord logrotate
        networkmanager network-manager-applet git freerdp curl gvfs
        gvfs-afc gvfs-dnssd gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-onedrive
        gvfs-smb gvfs-wsdd ntfs-3g samba
        xclip pamixer wf-recorder pavucontrol tumbler vlc mpv ffmpeg
        eza micro xfce4-terminal btop alacritty kitty starship ranger nano figlet neovim
        timeshift file-roller gparted xfce4-power-manager rofi dunst cockpit
        sddm blueman pacman-contrib fzf font-manager awesome-terminal-fonts
        ttf-font-awesome ttf-fira-sans ttf-fira-code ttf-firacode-nerd
        python-pip python-psutil python-rich python-click xdg-desktop-portal-gtk
        xdg-user-dirs xdg-user-dirs-gtk os-prober polkit-gnome gnome-keyring
        pcp pcp-gui gtk4-layer-shell hyprpicker zsh
    )
    run sudo pacman -S --noconfirm "${common_pacman[@]}"
    run sudo pacman -S --noconfirm $(pacman -Ssq 'pcp-pmda-*' 2>/dev/null || true)

    local common_aur=(
        awww swaylock-effects gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb
        7zip unzip unrar waybar-git tumbler-extra-thumbnailers
        thunar-shares-plugin brave-bin github-desktop-bin
        fastfetch gnome-disk-utility
        bibata-cursor-theme trizen sublime-text-4 sddm-theme-sugar-candy-git pacseek
        python-pywal16-git hyprquickframe-git
    )

    if [[ "$DISTRO" != "reborn" ]]; then
        common_aur+=(pamac-all libpamac-full pamac-cli)
    fi

    run yay --noconfirm -S "${common_aur[@]}"

    # Install Papirus folder icons
    echo ""
    echo "  Installing Papirus folder icons..."
    if ! $DRY_RUN; then
        wget -qO- https://git.io/papirus-folders-install | env PREFIX=$HOME/.local sh
    else
        echo "  [DRY-RUN] wget -qO- https://git.io/papirus-folders-install | ..."
    fi

    _footer "Core packages"

    # HyprViz
    _header "HyprViz (Hyprland config tool)"
    if ! $DRY_RUN; then
        cd $HOME/Downloads/yay-git/src/
        run git clone https://aur.archlinux.org/hyprviz-bin.git
        cd hyprviz-bin
        run makepkg -si
        cd "$SCRIPT_DIR"
    fi
    _footer "HyprViz"

    # pywal16
    _header "Installing Pywal16"
    if [[ -f /usr/bin/wal ]]; then
        echo "  pywal16 already installed."
    else
        run yay --noconfirm -S python-pywal16-git
    fi
    _footer "Pywal16"
}

# ===================== SECTION: symlinks =====================

section_symlinks() {
    detect_distro
    local CWD="$SCRIPT_DIR"

    # Wallpaper setup
    _header "Installing Wallpapers"
    if ! $ASSUME_YES && confirm "Clone wallpaper repository?"; then
        if [[ -d ~/Pictures/Wallpapers ]]; then
            echo "  Wallpaper folder already exists."
        else
            run git clone https://github.com/hyprtk/wallpaper.git ~/Pictures/Wallpapers
        fi
    else
        if [[ -d ~/Pictures/Wallpapers ]]; then
            echo "  Wallpapers folder already exists."
        else
            run mkdir -p ~/Pictures/Wallpapers
        fi
        run cp -n ~/hyprtk/Wallpapers/* ~/Pictures/Wallpapers 2>/dev/null || true
    fi
    _footer "Installing Wallpapers"

    # Fonts
    _header "Installing Fonts"
    if ! $ASSUME_YES && confirm "Clone font repository?"; then
        if [[ -d ~/.local/share/fonts ]]; then
            echo "  Fonts folder already exists."
        else
            run git clone https://github.com/hyprtk/fonts.git ~/.local/share/fonts
        fi
    else
        run mkdir -p ~/.local/share/fonts
        run cp -r -n ~/hyprtk/fonts/* /usr/share/fonts 2>/dev/null || true
        run cp -r -n ~/.local/share/fonts/* /usr/share/fonts 2>/dev/null || true
    fi
    _footer "Installing Fonts"

    # Root icons
    _header "Installing Root Icons"
    if ! $DRY_RUN; then
        wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | DESTDIR="/root/.local/share/icons" sh
    fi
    _footer "Installing Root Icons"

    # Pywal16 init
    _header "Initializing Pywal16"
    run wal -i ~/hyprtk/Wallpapers/default.png
    run cp ~/hyprtk/Wallpapers/default.png ~/.cache/current-wallpaper.png
    run sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png
    case $DISTRO in
        bslx)
            run sudo cp ~/.cache/current-wallpaper.png /boot/grub/current-wallpaper.png
            ;;
    esac
    run xdg-user-dirs-update --force
    run xdg-user-dirs-gtk-update --force
    _footer "Initializing Pywal16"

    # Dotfiles confirmation
    if ! $ASSUME_YES && ! confirm "Apply dotfiles configuration?"; then
        echo "Installation aborted."
        exit
    fi

    # Thunar xfconf
    echo "  Generating xfconf via Thunar..."
    if ! $DRY_RUN; then
        thunar & sleep 3; killall thunar 2>/dev/null || true
    fi

    # Hyprland dotfiles confirmation
    _header "Hyprland dotfiles setup"
    echo "  Symbolic links will be created from the merged dots directory."
    if ! $ASSUME_YES && ! confirm "Apply Hyprland dotfiles now?"; then
        exit
    fi

    # .config directory
    _header "Checking ~/.config directory"
    run mkdir -p ~/.config
    sleep 1

    # Symbolic links
    _header "Creating symbolic links"
    case $DISTRO in
        endeavour) run mv ~/.config/hypr ~/.config/hypr-old 2>/dev/null || true ;;
    esac

    _installSymLink alacritty ~/.config/alacritty "$CWD/alacritty/" ~/.config
    _installSymLink ranger ~/.config/ranger "$CWD/ranger/" ~/.config
    _installSymLink vim ~/.config/vim "$CWD/vim/" ~/.config
    _installSymLink nvim ~/.config/nvim "$CWD/nvim/" ~/.config
    _installSymLink starship ~/.config/starship.toml "$CWD/starship/starship.toml" ~/.config/starship.toml
    _installSymLink rofi ~/.config/rofi "$CWD/rofi/" ~/.config
    _installSymLink dunst ~/.config/dunst "$CWD/dunst/" ~/.config
    _installSymLink wal ~/.config/wal "$CWD/wal/" ~/.config
    _installSymLink btop ~/.config/btop "$CWD/btop/" ~/.config

    # Re-init pywal16
    _header "Re-initializing Pywal16"
    case $DISTRO in
        archcraft) run wal -i ~/.cache/current-wallpaper.png ;;
        *) run wal -i "$CWD/Wallpapers/default.png" ;;
    esac
    _footer "Pywal16 re-initialization"

    # GTK
    _header "Linking GTK configuration"
    _installSymLink gtk-3.0 ~/.config/gtk-3.0 "$CWD/gtk/gtk-3.0/" ~/.config/
    _installSymLink gtk-4.0 ~/.config/gtk-4.0 "$CWD/gtk/gtk-4.0/" ~/.config/
    _installSymLink themes ~/.local/share/themes "$CWD/themes" ~/.local/share/
    _installSymLink icons ~/.local/share/icons "$CWD/papirus-icons/icons" ~/.local/share/
    _footer "GTK configuration"

    # XFCE
    _header "Linking XFCE configuration"
    _installSymLink xfce4 ~/.config/xfce4 "$CWD/xfce4" ~/.config/
    _installSymLink Thunar ~/.config/Thunar "$CWD/Thunar" ~/.config/
    _installSymLink Mousepad ~/.config/Mousepad "$CWD/Mousepad" ~/.config/
    _footer "XFCE configuration"

    # Hyprland
    _header "Linking Hyprland configuration"
    case $DISTRO in
        arch|archbang|endeavour) ;;
        *) run mv ~/.config/hypr ~/.config/hypr-old 2>/dev/null || true ;;
    esac
    _installSymLink hypr ~/.config/hypr "$CWD/hypr/" ~/.config
    _installSymLink fastfetch ~/.config/fastfetch "$CWD/fastfetch/" ~/.config
    _installSymLink waybar ~/.config/waybar "$CWD/waybar/" ~/.config
    _installSymLink swaylock ~/.config/swaylock "$CWD/swaylock/" ~/.config
    _installSymLink swappy ~/.config/swappy "$CWD/swappy/" ~/.config
    _installSymLink hyprlogout ~/.config/hyprlogout "$CWD/hyprlogout/" ~/.config
    _installSymLink waypaper ~/.config/waypaper "$CWD/waypaper/" ~/.config
    _installSymLink zshrc ~/.config/zshrc "$CWD/zshrc/" ~/.config
    _installSymLink ohmyposh ~/.config/ohmyposh "$CWD/ohmyposh/" ~/.config
    _installSymLink matuwall ~/.config/matuwall "$CWD/matuwall/" ~/.config
    _installSymLink wob ~/.config/wob "$CWD/wob/" ~/.config
    run mkdir -p ~/.local/bin
    _footer "Hyprland configuration"

    # Standalone utilities
    _header "Linking standalone utilities"
    _installSymLink standalone ~/.local/bin "$CWD/standalone/" ~/.local/bin
    _installSymLink oh-my-zsh ~/.oh-my-zsh/oh-my-zsh.sh "$CWD/oh-my-zsh/oh-my-zsh.sh" ~/.oh-my-zsh
    _footer "Standalone utilities"
}

# ===================== SECTION: services =====================

section_services() {
    detect_distro
    local CWD="$SCRIPT_DIR"

    _header "Configuring system services"

    # Bluetooth
    echo ""
    echo "  Enabling Bluetooth..."
    run sudo systemctl start bluetooth
    run sudo systemctl enable bluetooth

    # Cockpit
    echo ""
    echo "  Configuring Cockpit..."
    case $DISTRO in
        cachy)
            run sudo cp "$CWD/os-release/distros/cachy" /usr/lib/os-release
            run sudo cp "$CWD/os-release/distros/cachy" /run/systemd/propagate/.os-release-stage/
            run sudo cp "$CWD/os-release/distros/cachy" "/run/user/$UID/systemd/propagate/.os-release-stage/"
            run sudo cp "$CWD/os-release/distros/cachyos-branding" /usr/share/libalpm/scripts/
            run sudo bash /usr/share/libalpm/scripts/cachyos-branding
            ;;
        arch|archcraft)
            run sudo cp "$CWD/os-release/distros/$DISTRO" /usr/lib/os-release
            run sudo cp "$CWD/splash/splash-arch.bmp" /usr/share/systemd/bootctl/
            _regenerate_all_initramfs
            ;;
        archbang)
            run sudo cp "$CWD/os-release/distros/archbang" /etc/os-release
            ;;
        *)
            if [[ -f "$CWD/os-release/distros/$DISTRO" ]]; then
                run sudo cp "$CWD/os-release/distros/$DISTRO" /usr/lib/os-release
            else
                run sudo cp "$CWD/os-release/os-release" /usr/lib/os-release
            fi
            ;;
    esac
    run sudo cp ~/hyprtk/User-Management/manage-users.desktop /usr/share/applications/ 2>/dev/null || true
    run sudo systemctl enable --now cockpit.socket
    run sudo systemctl start cockpit.socket

    # Samba
    echo ""
    echo "  Enabling Samba..."
    run sudo cp ~/hyprtk/smb/smb.conf /etc/samba/
    run sudo systemctl enable smb nmb
    run sudo systemctl start smb nmb
    run sudo systemctl restart smb nmb
    echo "  Update the interfaces section of /etc/samba/smb.conf with your IP address."
    sleep 3

    # Other services from config
    for svc in "${SERVICES_ENABLE[@]}"; do
        case "$svc" in
            bluetooth|cups|cockpit|sddm|NetworkManager) ;;
            *)
                run sudo systemctl enable "$svc" 2>/dev/null || warn "Could not enable $svc"
                ;;
        esac
    done

    for svc in "${SERVICES_DISABLE[@]}"; do
        run sudo systemctl disable "$svc" 2>/dev/null || true
    done

    _footer "System services"
}

# ===================== SECTION: theming =====================

section_theming() {
    local CWD="$SCRIPT_DIR"

    _header "SDDM Configuration"
    run sh ~/hyprtk/scripts/rm-dm-managers.sh 2>/dev/null || true
    run mkdir -p /etc/sddm.conf.d
    run sudo cp ~/hyprtk/sddm/sddm.conf /etc/sddm.conf.d/
    _footer "SDDM Configuration"

    _header "SDDM & GRUB Theming"
    run mkdir -p /etc/sddm.conf.d
    run sudo rm -rf /usr/share/grub/themes/*
    run sudo rm -rf /boot/grub/themes/*
    run sudo cp ~/hyprtk/sddm/sddm.conf /etc/sddm.conf.d/
    run cp ~/hyprtk/default.png ~/.cache/current-wallpaper.png 2>/dev/null || true
    run sudo cp ~/.cache/current-wallpaper.png /usr/share/sddm/themes/Sugar-Candy/Backgrounds/ 2>/dev/null || true
    run sudo cp ~/hyprtk/sddm/theme.conf /usr/share/sddm/themes/Sugar-Candy/ 2>/dev/null || true
    run sudo cp ~/.cache/current-wallpaper.png /root/.cache/current-wallpaper.png 2>/dev/null || true
    run sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    run sudo sed -i '/^GRUB_BACKGROUND/d' /etc/default/grub
    run sudo sed -i '/^GRUB_COLOR_NORMAL/d' /etc/default/grub
    run sudo sed -i '/^GRUB_COLOR_HIGHLIGHT/d' /etc/default/grub
    echo -e 'GRUB_BACKGROUND="/root/.cache/current-wallpaper.png"' | run sudo tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_NORMAL="white/black"' | run sudo tee -a /etc/default/grub
    echo -e 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' | run sudo tee -a /etc/default/grub
    run sudo grub-mkconfig -o /boot/grub/grub.cfg
    run sudo sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    _footer "SDDM & GRUB Theming"

    # Matuwall
    _header "Matuwall (Wallpaper picker)"
    if ! $DRY_RUN; then
        git clone https://github.com/naurissteins/Matuwall.git ~/.local/share/Matuwall 2>/dev/null || true
        cd ~/.local/share/Matuwall
        /usr/bin/python -m venv --system-site-packages .venv 2>/dev/null || true
        source .venv/bin/activate 2>/dev/null || true
        pip install --upgrade pip 2>/dev/null || true
        pip install . 2>/dev/null || true
        mkdir -p ~/.local/bin
        ln -sf "$PWD/.venv/bin/matuwall" ~/.local/bin/matuwall 2>/dev/null || true
        cd "$CWD"
    fi
    _footer "Matuwall"

    # AWWW
    _header "AWWW Wallpaper utility"
    run sh ~/hyprtk/scripts/awww-wrapper.sh 2>/dev/null || true
    _footer "AWWW Wallpaper utility"

    # GRUB updater for Kiro
    case $DISTRO in
        kiro)
            _header "GRUB Updater (Kiro-specific)"
            run sh ~/hyprtk/scripts/grudupdater.sh 2>/dev/null || true
            _footer "GRUB Updater"
            ;;
    esac
}

# ===================== SECTION: shell =====================

section_shell() {
    local CWD="$SCRIPT_DIR"

    _header "Installing ZSH"
    run sudo pacman -S zsh --noconfirm
    if ! $DRY_RUN; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>/dev/null || true
    fi
    _footer "ZSH"

    _header "Installing ZSH plugins"
    run git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions 2>/dev/null || true
    run git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting 2>/dev/null || true
    run git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting 2>/dev/null || true
    _footer "ZSH plugins"

    _header "Configuring .zshrc"
    _installSymLink .zshrc ~/.zshrc "$CWD/.zshrc" ~/.zshrc
    run sudo chsh -s /bin/zsh
    run chsh -s /bin/zsh
    _footer ".zshrc configuration"
}

# ===================== MAIN =====================

main() {
    parse_args "$@"
    load_config

    # Clean up old dotfiles directory
    run rm -Rf "$HOME/dotfiles" 2>/dev/null || true

    for section in "${SECTIONS[@]}"; do
        # --only: skip if section not in list
        if [[ ${#ONLY_SECTIONS[@]} -gt 0 ]]; then
            local found=false
            for s in "${ONLY_SECTIONS[@]}"; do
                [[ "$s" == "$section" ]] && found=true && break
            done
            $found || continue
        fi

        # --skip: skip if section in list
        for s in "${SKIP_SECTIONS[@]}"; do
            [[ "$s" == "$section" ]] && continue 2
        done

        local prev_errors=$ERROR_COUNT
        case "$section" in
            detect) section_detect ;;
            packages) section_packages ;;
            symlinks) section_symlinks ;;
            services) section_services ;;
            theming) section_theming ;;
            shell) section_shell ;;
        esac

        if [[ $ERROR_COUNT -gt $prev_errors ]]; then
            SECTION_ERRORS[$section]=$(( ERROR_COUNT - prev_errors ))
            _fail "Section '$section' completed with errors"
        fi

        if [[ "$section" == "$STOP_AT" ]]; then
            echo ""
            echo "  Stopped after '$section' (--stop-at)."
            break
        fi
    done

    # Root user setup (always runs at end)
    _header "Setting up root user configuration"
    run sudo cp -r "$SCRIPT_DIR/root" / 2>/dev/null || _fail "root config copy"
    echo -e 'Defaults env_reset,pwfeedback' | run sudo tee -a /etc/sudoers 2>/dev/null || _fail "sudoers config"
    _footer "Root user configuration"

    _header "Installation complete"
    echo ""

    if [[ $ERROR_COUNT -gt 0 ]]; then
        echo "  Completed with $ERROR_COUNT error(s):"
        for section in "${SECTIONS[@]}"; do
            if [[ -n "${SECTION_ERRORS[$section]:-}" ]]; then
                echo "    - $section: ${SECTION_ERRORS[$section]} error(s)"
            else
                echo "    - $section: ok"
            fi
        done
        echo ""
        echo "  Review warnings above and re-run failed sections with:"
        echo "    install.sh --only <section>"
        echo ""
    else
        echo "  All sections completed successfully!"
        echo ""
    fi

    echo "  Next steps:"
    echo "    - Update keyboard layout in ~/hyprtk/hypr/hyprland.conf"
    echo "    - Update screen resolution in ~/hyprtk/hypr/hyprland.conf"
    echo "    - Reboot your system"
    echo ""
    echo "=============================================================================="
}

main "$@"
