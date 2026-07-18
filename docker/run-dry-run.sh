#!/bin/bash
#
# Run the Hyprtk-On-Arch deep docker dry run in an Alacritty window.
#
# Usage:  ./docker/run-dry-run.sh [--no-build]
#
# Prerequisites:
#   - Docker installed and running
#   - alacritty installed
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE_NAME="hyprtk-on-arch-dryrun"

log() { echo "[DRY-RUN LAUNCHER] $*"; }

# Check prerequisites
if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is not installed."
    echo "Install it with:  sudo pacman -S docker"
    echo "Then:             sudo systemctl enable --now docker"
    echo "Then:             sudo usermod -aG docker $USER"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "ERROR: Docker daemon is not running or user lacks permissions."
    echo "Try:  sudo systemctl start docker"
    echo "Or:   sudo usermod -aG docker \$USER && newgrp docker"
    exit 1
fi

if ! command -v alacritty &>/dev/null; then
    echo "WARNING: Alacritty not found. Running in current terminal instead."
    RUN_IN_PLACE=1
else
    RUN_IN_PLACE=0
fi

# Build the Docker image
if [ "${1:-}" != "--no-build" ]; then
    log "Building Docker image: $IMAGE_NAME ..."
    docker build -t "$IMAGE_NAME" "$SCRIPT_DIR" -f "$SCRIPT_DIR/docker/Dockerfile" 2>&1
    echo ""
    log "Build complete."
else
    log "Skipping build (--no-build flag)."
fi

# Define the docker run command
DOCKER_CMD="docker run --rm \
    -v \"$SCRIPT_DIR:/opt/hyprtk-on-arch:ro\" \
    -e TERM=\"$TERM\" \
    $IMAGE_NAME"

if [ "$RUN_IN_PLACE" -eq 0 ]; then
    log "Opening Alacritty window for dry run..."
    echo ""
    alacritty \
        --title "Hyprtk-On-Arch — Dry Run" \
        -e bash -c "echo 'Building image...'; docker build -t \"$IMAGE_NAME\" \"$SCRIPT_DIR\" -f \"$SCRIPT_DIR/docker/Dockerfile\" 2>&1; echo ''; echo '==============================================='; echo '  Starting Deep Docker Dry Run'; echo '==============================================='; echo ''; $DOCKER_CMD; echo ''; echo 'Press Enter to close this window.'; read"
else
    log "Running dry run in current terminal..."
    echo ""
    eval "$DOCKER_CMD"
fi
