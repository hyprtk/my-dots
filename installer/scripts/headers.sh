#!/bin/bash
# Professional ASCII art headers and footers
# Color scheme: cyan, magenta, white, yellow, red

# Get the directory of this script (uses _HEADERS_DIR to avoid clobbering caller's SCRIPT_DIR)
_HEADERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_HEADERS_DIR/colors.sh"

# Main header for the installer
print_main_header() {
    clear
    echo ""
    echo -e "${COLOR_BOLD_CYAN}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD_MAGENTA}                                   hyprtk${COLOR_RESET}"
    echo -e "${COLOR_BOLD_WHITE}                       Unified Hyprland & XFCE Installer${COLOR_RESET}"
    echo -e "${COLOR_CYAN}                               by Kori Tk (2026)${COLOR_RESET}"
    echo -e "${COLOR_BOLD_CYAN}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
}

# Section header
print_section_header() {
    local title="$1"
    local width=78
    local padding=$(( (width - ${#title}) / 2 ))
    
    echo ""
    echo -e "${COLOR_BOLD_CYAN}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD_MAGENTA}$(printf '%*s' $padding '')$title${COLOR_RESET}"
    echo -e "${COLOR_BOLD_CYAN}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
}

# Subsection header
print_subsection_header() {
    local title="$1"
    local width=78
    local padding=$(( (width - ${#title} - 6) / 2 ))
    
    echo ""
    echo -e "${COLOR_BOLD_CYAN}──────────────────────────────────────────────────────────────────────────────${COLOR_RESET}"
    echo -e "${COLOR_BOLD_CYAN}$(printf '%*s' $padding '')-> $title${COLOR_RESET}"
    echo -e "${COLOR_BOLD_CYAN}──────────────────────────────────────────────────────────────────────────────${COLOR_RESET}"
    echo ""
}

# Info box
print_info_box() {
    local message="$1"
    local width=78
    local padding=$(( (width - ${#message}) / 2 ))
    
    echo ""
    echo -e "${COLOR_BOLD_CYAN}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD_WHITE}$(printf '%*s' $(( (width - 4) / 2 )) '')INFO${COLOR_RESET}"
    echo -e "${COLOR_BOLD_WHITE}$(printf '%*s' $(( (width - 4) / 2 )) '')────${COLOR_RESET}"
    echo -e "${COLOR_WHITE}$(printf '%*s' $padding '')$message${COLOR_RESET}"
    echo -e "${COLOR_BOLD_CYAN}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
}

# Warning box
print_warning_box() {
    local message="$1"
    local width=78
    local padding=$(( (width - ${#message}) / 2 ))
    
    echo ""
    echo -e "${COLOR_BOLD_RED}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD_YELLOW}$(printf '%*s' $(( (width - 13) / 2 )) '')⚠ WARNING ⚠${COLOR_RESET}"
    echo -e "${COLOR_BOLD_YELLOW}$(printf '%*s' $(( (width - 13) / 2 )) '')───────────${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}$(printf '%*s' $padding '')$message${COLOR_RESET}"
    echo -e "${COLOR_BOLD_RED}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
}

# Success box
print_success_box() {
    local message="$1"
    local width=78
    local padding=$(( (width - ${#message}) / 2 ))
    
    echo ""
    echo -e "${COLOR_BOLD_GREEN}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD_GREEN}$(printf '%*s' $(( (width - 12) / 2 )) '')✓ SUCCESS ✓${COLOR_RESET}"
    echo -e "${COLOR_BOLD_GREEN}$(printf '%*s' $(( (width - 12) / 2 )) '')────────────${COLOR_RESET}"
    echo -e "${COLOR_WHITE}$(printf '%*s' $padding '')$message${COLOR_RESET}"
    echo -e "${COLOR_BOLD_GREEN}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
}

# Main footer
print_main_footer() {
    echo ""
    echo -e "${COLOR_BOLD_MAGENTA}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD_WHITE}                           Installation Complete!${COLOR_RESET}"
    echo -e "${COLOR_CYAN}                      by Kori Tk (2026)${COLOR_RESET}"
    echo -e "${COLOR_BOLD_MAGENTA}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
}

# Distro detection header
print_distro_header() {
    local distro="$1"
    local width=78
    local padding=$(( (width - ${#distro}) / 2 ))
    
    echo ""
    echo -e "${COLOR_BOLD_CYAN}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD_YELLOW}$(printf '%*s' $(( (width - 16) / 2 )) '')DETECTED DISTRO${COLOR_RESET}"
    echo -e "${COLOR_BOLD_YELLOW}$(printf '%*s' $(( (width - 16) / 2 )) '')──────────────${COLOR_RESET}"
    echo -e "${COLOR_BOLD_WHITE}$(printf '%*s' $padding '')$distro${COLOR_RESET}"
    echo -e "${COLOR_BOLD_CYAN}══════════════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
}

# Progress indicator
print_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    local width=78
    local bar_width=50
    local progress=$(( (current * bar_width) / total ))
    local remaining=$(( bar_width - progress ))
    
    echo -ne "${COLOR_BOLD_CYAN}║${COLOR_RESET}"
    echo -ne "${COLOR_WHITE} $description${COLOR_RESET}"
    echo -ne "$(printf '%*s' $(( width - ${#description} - 3 )) '')"
    echo -e "${COLOR_BOLD_CYAN}║${COLOR_RESET}"
    
    echo -ne "${COLOR_BOLD_CYAN}║${COLOR_RESET}"
    echo -ne "${COLOR_GREEN}$(printf '█%.0s' $(seq 1 $progress))${COLOR_RESET}"
    echo -ne "${COLOR_WHITE}$(printf '░%.0s' $(seq 1 $remaining))${COLOR_RESET}"
    echo -ne "$(printf '%*s' 6 '')"
    echo -e "${COLOR_BOLD_CYAN}║${COLOR_RESET}"
}

# Status indicator
print_status() {
    local status="$1"
    local message="$2"
    
    case $status in
        "ok")
            echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} $message"
            ;;
        "warning")
            echo -e "  ${COLOR_YELLOW}⚠${COLOR_RESET} $message"
            ;;
        "error")
            echo -e "  ${COLOR_RED}✗${COLOR_RESET} $message"
            ;;
        "info")
            echo -e "  ${COLOR_CYAN}ℹ${COLOR_RESET} $message"
            ;;
    esac
}
