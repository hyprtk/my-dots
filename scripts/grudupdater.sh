#!/bin/bash
#
# GRUB Updater - Kiro distribution
# Updates GRUB configuration after dotfile installation
#
echo "  Running GRUB updater..."
if command -v grub-mkconfig &>/dev/null; then
    sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
    echo "  GRUB configuration updated."
else
    echo "  WARNING: grub-mkconfig not found. Skipping GRUB update."
fi
