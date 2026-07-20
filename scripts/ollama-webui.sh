#!/usr/bin/env bash

# requires: yay

set -e

MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m'

echo -e "${MAGENTA}==> Installing ollama...${NC}"
sudo pacman -S --noconfirm ollama

echo -e "${MAGENTA}==> Enabling ollama service...${NC}"
sudo systemctl enable --now ollama

echo -e "${CYAN}==> Installing open-webui from AUR...${NC}"
yay -S --noconfirm open-webui

echo -e "${MAGENTA}==> Enabling open-webui service...${NC}"
sudo systemctl enable --now open-webui

echo
echo -e "${CYAN}========================================${NC}"
echo -e "${MAGENTA}  Ollama + Open WebUI installed${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "${WHITE}  API:     http://localhost:11434${NC}"
echo -e "${WHITE}  Web UI:  http://localhost:8080${NC}"
echo -e "${CYAN}========================================${NC}"
echo
echo -e "${WHITE}  To pull a model:  ollama pull llama3.2${NC}"
echo -e "${WHITE}  Or use the Web UI to download models${NC}"
echo -e "${WHITE}  Check status:    systemctl status ollama open-webui${NC}"
echo
