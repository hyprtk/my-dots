#!/bin/bash
#
# install-gui.sh — Graphical installer for Hyprtk dotfiles
#
# Uses YAD (preferred) or Zenity (fallback) for a pleasant GTK wizard.
# All heavy lifting is delegated to install.sh.
#
# Usage:
#   ./install-gui.sh                    # use default config
#   ./install-gui.sh ./custom.yaml      # use custom config
#   ./install-gui.sh --help             # show help
#

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly INSTALL_SCRIPT="$SCRIPT_DIR/install.sh"
readonly DEFAULT_CONFIG="$SCRIPT_DIR/config.yaml"
readonly LOG_FILE="/tmp/archinstall-gui-$$.log"

CONFIG_FILE="${1:-$DEFAULT_CONFIG}"
GUI=""
HAS_YAD=false

# ─── Dialog toolkit abstraction ────────────────────
# Uses YAD if available, falls back to Zenity.

detect_toolkit() {
    if command -v yad &>/dev/null; then
        GUI="yad"
        HAS_YAD=true
    elif command -v zenity &>/dev/null; then
        GUI="zenity"
    else
        echo "Neither YAD nor Zenity found. Attempting to install YAD..."
        if command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm yad 2>/dev/null || {
                echo "pacman failed, trying yay..."
                if command -v yay &>/dev/null; then
                    yay -S --noconfirm yad 2>/dev/null || {
                        echo "yay failed too. Attempting to install Zenity as fallback..."
                        sudo pacman -S --noconfirm zenity 2>/dev/null || {
                            echo "yay -S --noconfirm zenity" | yay -S --noconfirm zenity 2>/dev/null || {
                                echo "Failed to install YAD or Zenity. Install manually:"
                                echo "  sudo pacman -S yad    (recommended)"
                                echo "  sudo pacman -S zenity (minimal)"
                                exit 1
                            }
                        }
                    }
                else
                    sudo pacman -S --noconfirm zenity 2>/dev/null || {
                        echo "Failed to install Zenity. Install manually:"
                        echo "  sudo pacman -S yad    (recommended)"
                        echo "  sudo pacman -S zenity (minimal)"
                        exit 1
                    }
                fi
            }
        else
            echo "pacman not found. Cannot install YAD or Zenity automatically."
            exit 1
        fi
        # Re-check after installation
        if command -v yad &>/dev/null; then
            GUI="yad"
            HAS_YAD=true
        elif command -v zenity &>/dev/null; then
            GUI="zenity"
        else
            echo "Installation claimed success but YAD/Zenity still not found."
            exit 1
        fi
    fi
}

dlg_info() {
    local title="$1" text="$2" w="${3:-480}" h="${4:-200}"
    if $HAS_YAD; then
        yad --info --title="$title" --width="$w" --height="$h" \
            --text="$text" --button="OK:0" --center --fixed 2>/dev/null
    else
        zenity --info --title="$title" --width="$w" --text="$text" 2>/dev/null
    fi
}

dlg_question() {
    local title="$1" text="$2" w="${3:-480}" h="${4:-200}" ok="${5:-Proceed}" cancel="${6:-Cancel}"
    if $HAS_YAD; then
        yad --question --title="$title" --width="$w" --height="$h" \
            --text="$text" --button="$ok:0" --button="$cancel:1" \
            --center --fixed 2>/dev/null
    else
        zenity --question --title="$title" --width="$w" --text="$text" \
            --ok-label="$ok" --cancel-label="$cancel" 2>/dev/null
    fi
}

dlg_file() {
    local title="$1" filename="$2"
    if $HAS_YAD; then
        yad --file --title="$title" --filename="$filename" \
            --file-filter="YAML configs | *.yaml *.yml" --center 2>/dev/null
    else
        zenity --file-selection --title="$title" --filename="$filename" \
            --file-filter="YAML configs (config*.yaml config*.yml) | config*.yaml config*.yml" 2>/dev/null
    fi
}

dlg_checklist() {
    local title="$1" text="$2" w="$3" h="$4" col1="$5" col2="$6"
    shift 6
    if $HAS_YAD; then
        yad --list --title="$title" --text="$text" --width="$w" --height="$h" \
            --column="$col1:CHK" --column="$col2" --column="Description" \
            "$@" --separator="," --center --fixed 2>/dev/null
    else
        zenity --list --title="$title" --text="$text" --width="$w" --height="$h" \
            --checklist --column="$col1" --column="$col2" --column="Description" \
            "$@" --separator="," 2>/dev/null
    fi
}

dlg_radiolist() {
    local title="$1" text="$2" w="$3" h="$4"
    shift 4
    if $HAS_YAD; then
        yad --list --title="$title" --text="$text" --width="$w" --height="$h" \
            --column=":RD" --column="Option" --column="Notes" \
            "$@" --center --fixed 2>/dev/null
    else
        zenity --list --title="$title" --text="$text" --width="$w" --height="$h" \
            --radiolist --column="Pick" --column="GPU" --column="Notes" \
            "$@" 2>/dev/null
    fi
}

dlg_progress() {
    local title="$1" w="$2" h="$3"
    if $HAS_YAD; then
        yad --progress --title="$title" --width="$w" --height="$h" \
            --pulsate --auto-close --no-cancel --enable-log="Log:" \
            --log-expanded=false --log-height=120 \
            --center --fixed 2>/dev/null
    else
        zenity --progress --title="$title" --width="$w" --pulsate \
            --auto-close --no-cancel --text="Starting..." 2>/dev/null
    fi
}

dlg_textinfo() {
    local title="$1" filename="$2" w="${3:-650}" h="${4:-450}" ok="${5:-Close}"
    if $HAS_YAD; then
        yad --text-info --title="$title" --width="$w" --height="$h" \
            --filename="$filename" --button="$ok:0" --center --fixed 2>/dev/null
    else
        zenity --text-info --title="$title" --width="$w" --height="$h" \
            --filename="$filename" --ok-label="$ok" 2>/dev/null
    fi
}

dlg_warning() {
    local title="$1" text="$2" w="${3:-480}"
    if $HAS_YAD; then
        yad --warning --title="$title" --width="$w" --text="$text" \
            --center --fixed 2>/dev/null
    else
        zenity --warning --title="$title" --width="$w" --text="$text" 2>/dev/null
    fi
}

# ─── System info ───────────────────────────────────

get_distro() {
    local distro=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        distro="$ID"
    fi
    echo "${distro:-unknown}"
}

system_summary() {
    local distro kernel hostname de
    distro=$(get_distro)
    kernel=$(uname -r)
    hostname=$(hostname -s 2>/dev/null || echo "unknown")
    de="${XDG_CURRENT_DESKTOP:-unknown}"

    echo "Distribution:  $distro"
    echo "Hostname:      $hostname"
    echo "Kernel:        $kernel"
    echo "Desktop:       $de"
    echo "Config:        $(basename "$CONFIG_FILE")"
}

# ─── Step 1: Welcome ───────────────────────────────

step_welcome() {
    dlg_info "Arch Linux Dotfiles Installer" \
"<b><big>Arch Linux Dotfiles Provisioner</big></b>

<i>Hyprland + XFCE4 desktop environment setup</i>

$(system_summary | sed 's/^/  /')

<b>This wizard will guide you through:</b>
  - Package installation  (official + AUR)
  - Dotfile symlinks      (configs, themes, icons)
  - System services       (Bluetooth, Samba, Cockpit)
  - Theming               (SDDM, GRUB, pywal16)
  - Shell setup           (ZSH + plugins)

<i>Root access will be required during installation.</i>" 520 320
}

# ─── Step 2: Config selection ──────────────────────

step_config() {
    local chosen
    chosen=$(dlg_file "Select Configuration File" "$CONFIG_FILE")
    if [[ -n "$chosen" ]]; then
        CONFIG_FILE="$chosen"
    fi
}

# ─── Step 3: Section selection ─────────────────────

step_sections() {
    local items=()
    items+=("TRUE"  "detect"   "Detect OS, print system information")
    items+=("TRUE"  "packages" "Install packages + GPU drivers (pacman, AUR)")
    items+=("TRUE"  "symlinks" "Dotfiles, wallpapers, fonts, GTK/XFCE configs")
    items+=("TRUE"  "services" "Bluetooth, Samba, Cockpit, SDDM")
    items+=("TRUE"  "theming"  "SDDM/GRUB theme, pywal16, Matuwall")
    items+=("TRUE"  "shell"    "ZSH, oh-my-zsh, plugins, chsh")

    local result
    result=$(dlg_checklist "Select Sections" \
        "Choose what to install (all selected by default):" \
        640 380 "Run" "Section" \
        "${items[@]}")

    if [[ -z "$result" ]]; then
        # Default: all sections
        SKIP_SECTIONS=()
        ONLY_SECTIONS=()
        return
    fi

    ONLY_SECTIONS=()
    SKIP_SECTIONS=()
    local selected="$result"
    for s in detect packages symlinks services theming shell; do
        if [[ ",$selected," == *",$s,"* ]]; then
            ONLY_SECTIONS+=("$s")
        else
            SKIP_SECTIONS+=("$s")
        fi
    done
}

# ─── Step 4: GPU selection (if packages active) ───

step_gpu() {
    local run_gpu=false
    if [[ ${#ONLY_SECTIONS[@]} -gt 0 ]]; then
        for s in "${ONLY_SECTIONS[@]}"; do
            [[ "$s" == "packages" ]] && run_gpu=true && break
        done
    else
        run_gpu=true
    fi
    for s in "${SKIP_SECTIONS[@]}"; do
        [[ "$s" == "packages" ]] && run_gpu=false && break
    done
    $run_gpu || return

    local gpu
    gpu=$(dlg_radiolist "Graphics Card" \
        "Select your graphics hardware for driver installation:" \
        500 280 \
        FALSE "Intel"          "Integrated Intel graphics + vulkan" \
        TRUE  "AMD"            "amdgpu + vulkan-radeon (recommended)" \
        FALSE "Nvidia"         "nvidia-open-dkms + proprietary drivers" \
        FALSE "Virtualization" "QEMU/virt + VMware guest tools")

    case "$gpu" in
        Intel*)          export GPU_CHOICE=1 ;;
        AMD*)            export GPU_CHOICE=2 ;;
        Nvidia*)         export GPU_CHOICE=3 ;;
        Virtualization*) export GPU_CHOICE=4 ;;
        *)               export GPU_CHOICE=2 ;;
    esac
}

# ─── Step 5: Confirmation ──────────────────────────

step_confirm() {
    local sections
    if [[ ${#ONLY_SECTIONS[@]} -gt 0 ]]; then
        sections="<b>Only:</b> ${ONLY_SECTIONS[*]}"
    elif [[ ${#SKIP_SECTIONS[@]} -gt 0 ]]; then
        sections="<b>All except:</b> ${SKIP_SECTIONS[*]}"
    else
        sections="<b>All sections</b>"
    fi

    dlg_question "Confirm Installation" \
"<b><big>Ready to provision your system</big></b>

$(system_summary | sed 's/^/  /')

${sections}

<b>This will modify system files, install packages,
and overwrite existing dotfiles.</b>

<i>Log: ${LOG_FILE}</i>" 520 300 "Install" "Cancel"
}

# ─── Step 6: Run installation ──────────────────────

step_run() {
    local args=()
    args+=("-c" "$CONFIG_FILE")
    args+=("-y")
    if [[ ${#ONLY_SECTIONS[@]} -gt 0 ]]; then
        local IFS=','; args+=("--only" "${ONLY_SECTIONS[*]}")
    elif [[ ${#SKIP_SECTIONS[@]} -gt 0 ]]; then
        local IFS=','; args+=("--skip" "${SKIP_SECTIONS[*]}")
    fi

    # Feed progress from install.sh into the progress dialog
    # YAD mode: pipe to yad --progress with --enable-log
    # Zenity mode: simpler progress pipe

    if $HAS_YAD; then
        (
            "$INSTALL_SCRIPT" "${args[@]}" 2>&1 | tee "$LOG_FILE" | \
                sed -n '/^#/!s/^/# /p'
            echo "# Installation complete"
        ) | yad --progress \
            --title="Installing Arch Linux Dotfiles" \
            --width=580 --height=400 \
            --pulsate --auto-close --no-cancel \
            --enable-log="Progress:" --log-expanded=true \
            --log-height=240 \
            --center --fixed 2>/dev/null
    else
        (
            "$INSTALL_SCRIPT" "${args[@]}" 2>&1 | tee "$LOG_FILE" | \
                while IFS= read -r line; do
                    if [[ "$line" =~ ^[[:space:]]*(Installing|Configuring|Linking|Creating|Setting|Removing|Checking|Generating|Enabling) ]]; then
                        echo "# ${line//  /}"
                    fi
                done
        ) | zenity --progress \
            --title="Installing Arch Linux Dotfiles" \
            --width=550 --pulsate --auto-close --no-cancel \
            --text="Starting installation..." 2>/dev/null
    fi

    local rc=${PIPESTATUS[0]}
    return $rc
}

# ─── Step 7: Results ───────────────────────────────

step_results() {
    local has_errors=false
    if grep -qi 'fail\|error\|WARN' "$LOG_FILE" 2>/dev/null; then
        has_errors=true
    fi

    if $has_errors; then
        dlg_warning "Installation Completed with Warnings" \
"<b>Installation finished, but with warnings.</b>

Review the log for details."

        dlg_textinfo "Installation Log" "$LOG_FILE" 700 500 "View Log"

        dlg_question "Re-run Failed Sections" \
"<b>Would you like to re-run only the failed sections?</b>

  install.sh --only <section>

This avoids re-running everything." 450 150 "Not Now" "Re-run"
        if [[ $? -eq 1 ]]; then
            # User wants to re-run - extract failed sections from the log
            local failed=""
            for s in detect packages symlinks services theming shell; do
                if grep -q "Section '$s' completed with errors" "$LOG_FILE" 2>/dev/null; then
                    failed+="${failed:+,}$s"
                fi
            done
            if [[ -n "$failed" ]]; then
                exec "$INSTALL_SCRIPT" -c "$CONFIG_FILE" -y --only "$failed"
            fi
        fi
    else
        dlg_info "Installation Complete!" \
"<b><big>Installation completed successfully!</big></b>

All selected sections finished without errors.

<b>Next steps:</b>
  - Update keyboard in ~/hyprtk/hypr/hyprland.conf
  - Update resolution in ~/hyprtk/hypr/hyprland.conf
  - Reboot your system

<i>Log: ${LOG_FILE}</i>" 500 280

        dlg_question "Reboot" \
"<b>Installation complete.</b>

Reboot now to start using your new desktop?" 400 150 "Reboot Later" "Reboot Now"
        if [[ $? -eq 1 ]]; then
            sudo reboot
        fi
    fi
}

# ─── Main ──────────────────────────────────────────

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        echo "Usage: $0 [config-file]"
        echo ""
        echo "Launches a graphical installer using YAD (preferred) or Zenity."
        echo "If no config file is given, defaults to config.yaml"
        exit 0
    fi

    detect_toolkit

    if [[ -n "${1:-}" && -f "${1:-}" ]]; then
        CONFIG_FILE="$1"
    fi

    step_welcome || exit
    step_sections
    step_gpu
    step_confirm || exit

    rm -f "$LOG_FILE"

    if ! step_run; then
        dlg_warning "Installation Interrupted" \
"<b>The installation process was interrupted.</b>

Check the log for details:
${LOG_FILE}" 480 150
        exit 1
    fi

    step_results
}

main "$@"
