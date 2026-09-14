#    _               _              
#   | |__   __ _ ___| |__  _ __ ___ 
#   | '_ \ / _` / __| '_ \| '__/ __|
#  _| |_) | (_| \__ \ | | | | | (__ 
# (_)_.__/ \__,_|___/_| |_|_|  \___|
# 
# Forked by Corrie Tilcock (2024)
# -----------------------------------------------------
# ~/.bashrc
# -----------------------------------------------------

# If not running interactively, don't do anything
[[ $- != *i* ]] && return
PS1='[\u@\h \W]\$ '

# -----------------------------------------------------
# ALIASES
# -----------------------------------------------------

alias c='clear'
alias nf='neofetch'
alias pf='pfetch'
alias ls='exa -al'
alias shutdown='systemctl poweroff'
alias v='nvim'
alias ts='~/hyprtk/installer/scripts/snapshot.sh'
alias matrix='cmatrix'
alias wifi='nmtui'
alias od='~/private/onedrive.sh'
alias winclass="xprop | grep 'CLASS'"
alias dot="cd ~/hyprtk"

# -----------------------------------------------------
# Window Managers
# -----------------------------------------------------

alias Qtile='startx'

# -----------------------------------------------------
# GIT
# -----------------------------------------------------

alias gs="git status"
alias ga="git add"
alias gc="git commit -m"
alias gp="git push"
alias gpl="git pull"
alias gst="git stash"
alias gsp="git stash; git pull"
alias gcheck="git checkout"

# -----------------------------------------------------
# SCRIPTS
# -----------------------------------------------------

alias wallp='~/hyprtk/installer/scripts/updatewal.sh'
alias ChatGPT='python ~/mychatgpt/mychatgpt.py'
alias chat='python ~/mychatgpt/mychatgpt.py'

# -----------------------------------------------------
# VIRTUAL MACHINE
# -----------------------------------------------------

alias vm='~/private/launchvm.sh'
alias vmstart='virsh --connect qemu:///system start win11'
alias vmstop='virsh --connect qemu:///system destroy win11'

# -----------------------------------------------------
# EDIT CONFIG FILES
# -----------------------------------------------------

alias confb='nvim ~/hyprtk/configs/root/.bashrc'

# -----------------------------------------------------
# EDIT NOTES
# -----------------------------------------------------

alias notes='vim ~/notes.txt'

# -----------------------------------------------------
# SYSTEM
# -----------------------------------------------------

alias update-grub='~/hyprtk/installer/scripts/update-grub.sh'
alias setkb='setxkbmap gb;echo "Keyboard set back to gb."'
# Distro-aware system update
update() {
  if command -v pacman >/dev/null 2>&1; then
    sudo pacman -Syu --noconfirm && { command -v yay >/dev/null 2>&1 && yay -Syu --noconfirm; }
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get upgrade -y
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf upgrade -y
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper --non-interactive update
  elif command -v xbps-install >/dev/null 2>&1; then
    sudo xbps-install -Su
  elif command -v apk >/dev/null 2>&1; then
    sudo apk update && sudo apk upgrade
  else
    echo "Unknown package manager"
  fi
}

# -----------------------------------------------------
# SCREEN RESOLUTINS
# -----------------------------------------------------

# Qtile
alias res1='xrandr --output DisplayPort-0 --mode 2560x1440 --rate 120'
alias res2='xrandr --output DisplayPort-0 --mode 1920x1080 --rate 120'
alias res3='xrandr --output DisplayPort-0 --mode 3840x1080 --rate 120'

export PATH="/usr/lib/ccache/bin/:$PATH"

# -----------------------------------------------------
# START STARSHIP
# -----------------------------------------------------
eval "$(starship init bash)"

# -----------------------------------------------------
# PYWAL
# -----------------------------------------------------
cat ~/.cache/wal/sequences

# -----------------------------------------------------
# PFETCH
# -----------------------------------------------------
echo ""
fastfetch