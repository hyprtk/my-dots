#!/usr/bin/env bash

MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

OPCODE_CONFIG="$HOME/.config/opencode/opencode.jsonc"

echo -e "${MAGENTA}==> Checking Ollama...${NC}"
if ! systemctl is-active --quiet ollama; then
  echo -e "${RED}  Ollama service is not running${NC}"
  echo -e "${YELLOW}  Run: sudo systemctl start ollama${NC}"
  exit 1
fi
echo -e "${GREEN}  Service: active${NC}"

# Get installed models
declare -A installed
installed_names=""
while read -r line; do
  name=$(echo "$line" | awk '{print $1}')
  size=$(echo "$line" | awk '{print $3}')
  if [ -n "$name" ]; then
    installed["$name"]="$size"
    installed_names="$installed_names $name"
  fi
done < <(ollama list 2>/dev/null | tail -n +2)

echo
echo -e "${MAGENTA}==> Installed models ($(ollama list 2>/dev/null | tail -n +2 | wc -l)):${NC}"
if [ -z "$installed_names" ]; then
  echo -e "${YELLOW}  No models installed.${NC}"
fi

# Read opencode config models
echo
echo -e "${MAGENTA}==> Models configured in opencode:${NC}"
if [ ! -f "$OPCODE_CONFIG" ]; then
  echo -e "${YELLOW}  No opencode config found at $OPCODE_CONFIG${NC}"
else
  # Extract model name tags from the "models" block: "tag": { "name": ... }
  configured_models=$(grep -oP '^\s+"\K[^"]+(?="\s*:\s*\{)' "$OPCODE_CONFIG" | sed 's/^[[:space:]]*//')

  pull_list=""
  for model in $configured_models; do
    if [ -n "${installed[$model]}" ]; then
      echo -e "${GREEN}  \u2713 $model ${CYAN}(${installed[$model]})${NC}"
    else
      echo -e "${RED}  \u2717 $model ${YELLOW}(not pulled)${NC}"
      pull_list="$pull_list $model"
    fi
  done

  if [ -n "$pull_list" ]; then
    echo
    echo -e "${YELLOW}  Some opencode models are missing locally.${NC}"
    echo -e "${CYAN}  Pull them now? [y/N]: ${NC}"
    echo -n "  "
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
      for model in $pull_list; do
        echo -e "${MAGENTA}  Pulling $model...${NC}"
        ollama pull "$model"
      done
    fi
  fi
fi

# If no installed models at all, offer a default
if [ -z "$installed_names" ] && [ ! -f "$OPCODE_CONFIG" ]; then
  echo
  echo -e "${CYAN}  Pull a default model?${NC}"
  echo -e "${WHITE}  1) llama3.2 (2GB)${NC}"
  echo -e "${WHITE}  2) phi3:3.8b (2.4GB)${NC}"
  echo -e "${WHITE}  3) tinyllama (0.6GB)${NC}"
  echo -e "${WHITE}  4) Skip${NC}"
  echo -n "  Pick [1-4]: "
  read -r choice
  case "$choice" in
    1) ollama pull llama3.2 ;;
    2) ollama pull phi3:3.8b-mini-4k-instruct-q4_K_M ;;
    3) ollama pull tinyllama ;;
  esac
fi

echo
echo -e "${MAGENTA}==> Checking Open WebUI...${NC}"
if systemctl is-active --quiet open-webui; then
  echo -e "${GREEN}  Service: active${NC}"
  if curl -s -o /dev/null --max-time 3 http://localhost:8080 > /dev/null 2>&1; then
    echo -e "${GREEN}  Web UI:   http://localhost:8080${NC}"
  else
    echo -e "${YELLOW}  Web UI:   service running but not responding yet${NC}"
  fi
else
  echo -e "${RED}  Service: not running${NC}"
fi

echo
echo -e "${MAGENTA}==> Ollama-to-Open-WebUI connection:${NC}"
if systemctl is-active --quiet open-webui; then
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:11434/api/tags 2>/dev/null)
  if [ "$code" = "200" ]; then
    echo -e "${GREEN}  Ollama API reachable at http://localhost:11434${NC}"
    echo -e "${GREEN}  All installed models are available in Open WebUI.${NC}"
  else
    echo -e "${YELLOW}  Could not verify Ollama API (HTTP $code).${NC}"
  fi
fi

echo
echo -e "${CYAN}========================================${NC}"
echo -e "${MAGENTA}  Summary${NC}"
echo -e "${CYAN}========================================${NC}"
ollama list 2>/dev/null | tail -n +2 | while read -r line; do
  name=$(echo "$line" | awk '{print $1}')
  size=$(echo "$line" | awk '{print $3}')
  echo -e "${WHITE}  $name ${CYAN}($size)${NC}"
done
echo -e "${CYAN}========================================${NC}"
