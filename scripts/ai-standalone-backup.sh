#!/usr/bin/env bash

MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

SRC_DIR="$HOME/Projects/AI-Projects/ai-standalone"
OLLAMA_SRC="/var/lib/ollama"
OLLAMA_HOME="$HOME/.ollama"
OWUI_ETC="/etc/open-webui"
OWUI_DATA="/var/lib/open-webui"
OPCODE="$HOME/.config/opencode"
SERVICE_DIR="/usr/lib/systemd/system"

err=0

mkdir -p "$SRC_DIR"/{ollama,open-webui,opencode}

# ---- helpers ----
check() {
  if [ $? -eq 0 ]; then echo -e "  ${GREEN}\u2713${NC} $1"; else echo -e "  ${RED}\u2717${NC} $1" && err=1; fi
}
title() { echo; echo -e "${MAGENTA}==> $1${NC}"; }

# ---- source info ----
title "Source system info"
{
  echo "hostname: $(hostname)"
  echo "date: $(date -Iseconds)"
  echo "os: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
  echo "kernel: $(uname -r)"
  ollama --version 2>/dev/null
  open-webui --version 2>/dev/null
} > "$SRC_DIR/source-info.txt"
check "source-info.txt written"

# ---- 1. Ollama models (from /var/lib/ollama) ----
title "Backing up Ollama models (from /var/lib/ollama)"
echo -e "  ${YELLOW}This is the large one (~$(du -sh "$OLLAMA_SRC" | cut -f1))${NC}"

mkdir -p "$SRC_DIR/ollama/blobs" "$SRC_DIR/ollama/manifests"

sudo rsync -a --info=progress2 "$OLLAMA_SRC/blobs/" "$SRC_DIR/ollama/blobs/"
check "ollama blobs ($(ls "$SRC_DIR/ollama/blobs" 2>/dev/null | wc -l) files)"

sudo rsync -a "$OLLAMA_SRC/manifests/" "$SRC_DIR/ollama/manifests/"
check "ollama manifests ($(find "$SRC_DIR/ollama/manifests" -type f 2>/dev/null | wc -l) files)"

sudo chown -R "$USER:$USER" "$SRC_DIR/ollama"

# ---- 2. Ollama config ----
title "Backing up Ollama config"
[ -f "$OLLAMA_HOME/config.json" ] && cp "$OLLAMA_HOME/config.json" "$SRC_DIR/ollama/" && check "config.json" || echo -e "  ${YELLOW}skip (not found)${NC}"
[ -f "$OLLAMA_HOME/id_ed25519" ] && cp "$OLLAMA_HOME/id_ed25519" "$SRC_DIR/ollama/" && check "id_ed25519"
[ -f "$OLLAMA_HOME/id_ed25519.pub" ] && cp "$OLLAMA_HOME/id_ed25519.pub" "$SRC_DIR/ollama/" && check "id_ed25519.pub"

# ---- 3. Ollama service ----
title "Backing up Ollama service"
cp "$SERVICE_DIR/ollama.service" "$SRC_DIR/ollama/"
check "ollama.service"

# ---- 4. Open WebUI ----
title "Backing up Open WebUI config"
mkdir -p "$SRC_DIR/open-webui"
[ -d "$OWUI_ETC" ] && sudo cp -r "$OWUI_ETC/." "$SRC_DIR/open-webui/etc/" && sudo chown -R "$USER:$USER" "$SRC_DIR/open-webui/etc" && check "/etc/open-webui/"
[ -d "$OWUI_DATA" ] && sudo rsync -a "$OWUI_DATA/" "$SRC_DIR/open-webui/data/" && sudo chown -R "$USER:$USER" "$SRC_DIR/open-webui/data" && check "/var/lib/open-webui/"

cp "$SERVICE_DIR/open-webui.service" "$SRC_DIR/open-webui/"
check "open-webui.service"

# ---- 5. OpenCode ----
title "Backing up OpenCode config"
mkdir -p "$SRC_DIR/opencode/config"
rsync -a --exclude=node_modules "$OPCODE/" "$SRC_DIR/opencode/config/"
check "opencode config (no node_modules)"
rsync -a "$OPCODE/node_modules/" "$SRC_DIR/opencode/config/node_modules/"
check "opencode node_modules"

# ---- 6. Package list ----
title "Package list"
pacman -Q | grep -E '^(ollama|open-webui)' > "$SRC_DIR/packages.txt"
check "packages.txt ($(wc -l < "$SRC_DIR/packages.txt") packages)"

# ---- 7. Generate restore.sh ----
title "Generating restore.sh"
cat > "$SRC_DIR/restore.sh" << 'RESTORE'
#!/usr/bin/env bash

set -e

MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_OLLAMA="/var/lib/ollama"
DEST_OWUI_ETC="/etc/open-webui"
DEST_OWUI_DATA="/var/lib/open-webui"
DEST_OPCODE="$HOME/.config/opencode"
DEST_SERVICE="/usr/lib/systemd/system"

err=0

check() {
  if [ $? -eq 0 ]; then echo -e "  ${GREEN}\u2713${NC} $1"; else echo -e "  ${RED}\u2717${NC} $1" && err=1; fi
}
title() { echo; echo -e "${MAGENTA}==> $1${NC}"; }

echo -e "${CYAN}========================================${NC}"
echo -e "${MAGENTA}  AI Standalone Restore${NC}"
echo -e "${WHITE}  Source: $(cat "$BACKUP_DIR/source-info.txt" 2>/dev/null | head -1 | cut -d' ' -f2-)${NC}"
echo -e "${CYAN}========================================${NC}"

# ---- Install packages ----
title "Installing packages"
if command -v pacman &>/dev/null; then
  sudo pacman -S --noconfirm ollama open-webui
  check "packages installed"
elif command -v yay &>/dev/null; then
  yay -S --noconfirm ollama open-webui
  check "packages installed (yay)"
elif command -v apt &>/dev/null; then
  echo -e "  ${YELLOW}Debian/Ubuntu detected — installing from GitHub releases${NC}"
  echo -e "  ${YELLOW}Please install ollama + open-webui manually, then re-run this script.${NC}"
  exit 1
else
  echo -e "  ${RED}Unsupported package manager${NC}"
  exit 1
fi

# ---- Stop services before copying ----
title "Stopping services"
sudo systemctl stop ollama open-webui 2>/dev/null || true
check "services stopped"

# ---- Restore Ollama models ----
title "Restoring Ollama models"
echo -e "  ${YELLOW}Copying $(ls "$BACKUP_DIR/ollama/blobs" 2>/dev/null | wc -l) blobs (~$(du -sh "$BACKUP_DIR/ollama/blobs" | cut -f1))${NC}"
sudo mkdir -p "$DEST_OLLAMA"/{blobs,manifests}
sudo rsync -a --info=progress2 "$BACKUP_DIR/ollama/blobs/" "$DEST_OLLAMA/blobs/"
check "ollama blobs"
sudo rsync -a "$BACKUP_DIR/ollama/manifests/" "$DEST_OLLAMA/manifests/"
check "ollama manifests"
sudo chown -R ollama:ollama "$DEST_OLLAMA"

# ---- Restore Ollama config ----
title "Restoring Ollama config"
mkdir -p "$HOME/.ollama"
[ -f "$BACKUP_DIR/ollama/config.json" ] && cp "$BACKUP_DIR/ollama/config.json" "$HOME/.ollama/" && check "config.json"
[ -f "$BACKUP_DIR/ollama/id_ed25519" ] && cp "$BACKUP_DIR/ollama/id_ed25519" "$HOME/.ollama/" && check "id_ed25519"
[ -f "$BACKUP_DIR/ollama/id_ed25519.pub" ] && cp "$BACKUP_DIR/ollama/id_ed25519.pub" "$HOME/.ollama/" && check "id_ed25519.pub"
chmod 600 "$HOME/.ollama/id_ed25519" 2>/dev/null || true

# ---- Restore Open WebUI ----
title "Restoring Open WebUI"
[ -d "$BACKUP_DIR/open-webui/etc" ] && sudo cp -r "$BACKUP_DIR/open-webui/etc/." "$DEST_OWUI_ETC/" && sudo chown -R open-webui:open-webui "$DEST_OWUI_ETC" && check "/etc/open-webui/"
[ -d "$BACKUP_DIR/open-webui/data" ] && sudo mkdir -p "$DEST_OWUI_DATA" && sudo rsync -a "$BACKUP_DIR/open-webui/data/" "$DEST_OWUI_DATA/" && sudo chown -R open-webui:open-webui "$DEST_OWUI_DATA" && check "/var/lib/open-webui/"

# ---- Restore OpenCode ----
title "Restoring OpenCode"
mkdir -p "$DEST_OPCODE"
rsync -a "$BACKUP_DIR/opencode/config/" "$DEST_OPCODE/"
check "opencode config"

# ---- Restore service files ----
title "Restoring service files"
[ -f "$BACKUP_DIR/ollama/ollama.service" ] && sudo cp "$BACKUP_DIR/ollama/ollama.service" "$DEST_SERVICE/" && sudo systemctl daemon-reload && check "ollama.service"
[ -f "$BACKUP_DIR/open-webui/open-webui.service" ] && sudo cp "$BACKUP_DIR/open-webui/open-webui.service" "$DEST_SERVICE/" && sudo systemctl daemon-reload && check "open-webui.service"

# ---- Start services ----
title "Starting services"
sudo systemctl enable --now ollama
check "ollama started"

# Wait for ollama to be ready
echo -e "  ${YELLOW}Waiting for Ollama API...${NC}"
for i in $(seq 1 30); do
  if curl -s -o /dev/null http://localhost:11434/api/tags 2>/dev/null; then
    echo -e "  ${GREEN}Ollama API ready${NC}"
    break
  fi
  sleep 1
done

sudo systemctl enable --now open-webui
check "open-webui started"

echo
echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}  Restore complete!${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "${WHITE}  Ollama API:  http://localhost:11434${NC}"
echo -e "${WHITE}  Open WebUI:  http://localhost:8080${NC}"
echo -e "${WHITE}  OpenCode:    ~/.config/opencode/${NC}"
echo
echo -e "${YELLOW}  Open WebUI may take ~30s to start.${NC}"
echo -e "${YELLOW}  If models don't appear, run: ollama list${NC}"
echo

exit $err
RESTORE

chmod +x "$SRC_DIR/restore.sh"
check "restore.sh generated"

# ---- 8. Verification ----
title "Verifying backup integrity"
echo
echo -e "${WHITE}  Checking file counts and sizes...${NC}"

echo -e "${CYAN}  Ollama models:${NC}"
echo "    blobs:     $(ls "$SRC_DIR/ollama/blobs" 2>/dev/null | wc -l) files ($(du -sh "$SRC_DIR/ollama/blobs" | cut -f1))"
echo "    manifests: $(find "$SRC_DIR/ollama/manifests" -type f 2>/dev/null | wc -l) files"

echo -e "${CYAN}  Ollama config:${NC}"
for f in config.json id_ed25519 id_ed25519.pub; do
  [ -f "$SRC_DIR/ollama/$f" ] && echo "    $f: $(stat --format='%s' "$SRC_DIR/ollama/$f") bytes" || echo "    $f: missing"
done

echo -e "${CYAN}  Open WebUI:${NC}"
[ -d "$SRC_DIR/open-webui/etc" ] && echo "    etc: $(find "$SRC_DIR/open-webui/etc" -type f | wc -l) files" || echo "    etc: empty"
[ -d "$SRC_DIR/open-webui/data" ] && echo "    data: $(find "$SRC_DIR/open-webui/data" -type f | wc -l) files ($(du -sh "$SRC_DIR/open-webui/data" | cut -f1))" || echo "    data: empty"

echo -e "${CYAN}  OpenCode:${NC}"
echo "    config: $(find "$SRC_DIR/opencode/config" -type f -not -path '*/node_modules/*' | wc -l) files ($(du -sh "$SRC_DIR/opencode/config" --exclude=node_modules | cut -f1))"
echo "    node_modules: $(find "$SRC_DIR/opencode/config/node_modules" -type f 2>/dev/null | wc -l) files ($(du -sh "$SRC_DIR/opencode/config/node_modules" | cut -f1))"

# Compare blob counts to source
src_blobs=$(ls "$OLLAMA_SRC/blobs" 2>/dev/null | wc -l)
dst_blobs=$(ls "$SRC_DIR/ollama/blobs" 2>/dev/null | wc -l)
if [ "$src_blobs" = "$dst_blobs" ]; then
  echo -e "  ${GREEN}\u2713 Blob count matches source ($src_blobs)${NC}"
else
  echo -e "  ${RED}\u2717 Blob count mismatch: source=$src_blobs backup=$dst_blobs${NC}"
  err=1
fi

src_manifests=$(find "$OLLAMA_SRC/manifests" -type f 2>/dev/null | wc -l)
dst_manifests=$(find "$SRC_DIR/ollama/manifests" -type f 2>/dev/null | wc -l)
if [ "$src_manifests" = "$dst_manifests" ]; then
  echo -e "  ${GREEN}\u2713 Manifest count matches source ($src_manifests)${NC}"
else
  echo -e "  ${RED}\u2717 Manifest count mismatch: source=$src_manifests backup=$dst_manifests${NC}"
  err=1
fi

echo
echo -e "${CYAN}========================================${NC}"
echo -e "${MAGENTA}  Backup complete${NC}"
echo -e "${WHITE}  Location: $SRC_DIR${NC}"
echo -e "${WHITE}  Total:    $(du -sh "$SRC_DIR" | cut -f1)${NC}"
echo -e "${WHITE}  To restore anywhere:${NC}"
echo -e "${CYAN}    cd $SRC_DIR && ./restore.sh${NC}"
echo -e "${CYAN}========================================${NC}"

exit $err
