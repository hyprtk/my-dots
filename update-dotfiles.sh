#!/bin/bash
# Check if we are in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Not a git repository."
    exit 1
fi

# Fetch latest updates from remote
git fetch origin

# Compare local HEAD with origin/main
LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse origin/main)

if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
    echo "New updates available. Pulling..."
    git pull origin main
    echo "Update complete."
else
    echo "Repository is up to date."
fi   