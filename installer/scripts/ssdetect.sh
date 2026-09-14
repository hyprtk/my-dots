#!/bin/bash
#
#                                                      
#  
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

# Define the scripts to run
NVIDIA_SCRIPT="$HOME/hyprtk/installer/scripts/screenshot.sh"
AMDINTEL_SCRIPT="$HOME/hyprtk/installer/scripts/sshot.sh"

# Check if NVIDIA GPU is available
if nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null | grep -q .; then
    echo "NVIDIA GPU detected. Running GPU script..."
    if [ -x "$NVIDIA_SCRIPT" ]; then
        bash "$NVIDIA_SCRIPT"
    else
        echo "Error: GPU script '$NVIDIA_SCRIPT' not found or not executable."
        exit 1
    fi
else
    echo "No NVIDIA GPU detected. Running AMDINTEL script..."
    if [ -x "$AMDINTEL_SCRIPT" ]; then
        bash "$AMDINTEL_SCRIPT"
    else
        echo "Error: CPU script '$AMDINTEL_SCRIPT' not found or not executable."
        exit 1
    fi
fi

hyprctl dispatch 'hl.dsp.submap("reset")'