#!/bin/bash
# ── Cleanup ───────────────────────────────────────────
# by Kori Tk (2026)
# ─────────────────────────────────────────────────────

echo "WARNING: This will clean out YAY and PACMAN cache, unused installs, and orphans."
read -r -p "Continue? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

yay -Scc --noconfirm
sudo pacman -Qtdq 2>/dev/null | sudo pacman -Rns - --noconfirm 2>/dev/null || true
