#!/bin/bash
# Color definitions for professional headers
# Color scheme: cyan, magenta, white, yellow, red

# Guard: only define if not already defined (prevent readonly errors on re-source)
if [[ -z "$_COLORS_LOADED" ]]; then
    _COLORS_LOADED=1
    
    # ANSI Color Codes
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[0;33m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_MAGENTA='\033[0;35m'
    readonly COLOR_CYAN='\033[0;36m'
    readonly COLOR_WHITE='\033[0;37m'
    readonly COLOR_RESET='\033[0m'

    # Bold variants
    readonly COLOR_BOLD_RED='\033[1;31m'
    readonly COLOR_BOLD_GREEN='\033[1;32m'
    readonly COLOR_BOLD_YELLOW='\033[1;33m'
    readonly COLOR_BOLD_BLUE='\033[1;34m'
    readonly COLOR_BOLD_MAGENTA='\033[1;35m'
    readonly COLOR_BOLD_CYAN='\033[1;36m'
    readonly COLOR_BOLD_WHITE='\033[1;37m'

    # Background colors
    readonly BG_RED='\033[41m'
    readonly BG_GREEN='\033[42m'
    readonly BG_YELLOW='\033[43m'
    readonly BG_BLUE='\033[44m'
    readonly BG_MAGENTA='\033[45m'
    readonly BG_CYAN='\033[46m'
    readonly BG_WHITE='\033[47m'
fi

# Helper functions for colored output
print_cyan() {
    echo -e "${COLOR_CYAN}$1${COLOR_RESET}"
}

print_magenta() {
    echo -e "${COLOR_MAGENTA}$1${COLOR_RESET}"
}

print_yellow() {
    echo -e "${COLOR_YELLOW}$1${COLOR_RESET}"
}

print_red() {
    echo -e "${COLOR_RED}$1${COLOR_RESET}"
}

print_white() {
    echo -e "${COLOR_WHITE}$1${COLOR_RESET}"
}

print_bold_white() {
    echo -e "${COLOR_BOLD_WHITE}$1${COLOR_RESET}"
}

print_bold_cyan() {
    echo -e "${COLOR_BOLD_CYAN}$1${COLOR_RESET}"
}

print_bold_magenta() {
    echo -e "${COLOR_BOLD_MAGENTA}$1${COLOR_RESET}"
}

print_bold_yellow() {
    echo -e "${COLOR_BOLD_YELLOW}$1${COLOR_RESET}"
}

print_bold_red() {
    echo -e "${COLOR_BOLD_RED}$1${COLOR_RESET}"
}

# Warning message (red)
print_warning() {
    echo -e "${COLOR_BOLD_RED}[WARNING] $1${COLOR_RESET}"
}

# Error message (red background)
print_error() {
    echo -e "${COLOR_BOLD_RED}${BG_WHITE}[ERROR] $1${COLOR_RESET}"
}

# Success message (green)
print_success() {
    echo -e "${COLOR_BOLD_GREEN}[SUCCESS] $1${COLOR_RESET}"
}

# Info message (cyan)
print_info() {
    echo -e "${COLOR_BOLD_CYAN}[INFO] $1${COLOR_RESET}"
}

# Notification message (yellow)
print_notify() {
    echo -e "${COLOR_BOLD_YELLOW}[NOTIFY] $1${COLOR_RESET}"
}
