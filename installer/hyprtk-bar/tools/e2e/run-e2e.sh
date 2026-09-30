#!/bin/bash
# ── hyprtk-bar · E2E runner (host entry point) ─────────────────────────
# Builds the Arch test image (once) and runs the full L0–L5 suite inside it for
# BOTH GTK stacks, writing tools/e2e/report/e2e-output.html.
#
# Usage:
#   tools/e2e/run-e2e.sh                 # full suite, both stacks, all layers
#   tools/e2e/run-e2e.sh --build         # force a rebuild of the image
#   tools/e2e/run-e2e.sh --stack 4       # only GTK4
#   tools/e2e/run-e2e.sh --layer 2       # only the settings-apply matrix
#   tools/e2e/run-e2e.sh -- -k arcmenu   # extra args go to pytest
#
# Environment: PODMAN (default podman), E2E_IMAGE (default hyprtk-bar-e2e).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PODMAN="${PODMAN:-podman}"
IMAGE="${E2E_IMAGE:-hyprtk-bar-e2e}"

BUILD=0
PASSTHRU=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --build) BUILD=1; shift ;;
        --)      shift; PASSTHRU+=(-- "$@"); break ;;
        *)       PASSTHRU+=("$1"); shift ;;
    esac
done

if [ "$BUILD" = 1 ] || ! "$PODMAN" image exists "$IMAGE" >/dev/null 2>&1; then
    echo "== building $IMAGE =="
    "$PODMAN" build -t "$IMAGE" -f "$HERE/Containerfile" "$HERE"
fi

mkdir -p "$HERE/report"

echo "== running suite in $IMAGE =="
exec "$PODMAN" run --rm \
    -v "$REPO":/work:Z \
    -v "$HERE/report":/work/tools/e2e/report:Z \
    -w /work \
    "$IMAGE" \
    bash tools/e2e/in-container.sh "${PASSTHRU[@]+"${PASSTHRU[@]}"}"
