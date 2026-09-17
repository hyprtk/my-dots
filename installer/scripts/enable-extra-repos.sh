#!/bin/bash
# ── Enable the extra package repositories the dotfiles need ─────────────────
# Wraps pkgmanager.sh's hyprtk_enable_extra_repos so 1-install.sh can run it
# under the spinner (which uses a `bash -c` subshell, so it cannot call the
# exported function directly). Idempotent and best-effort per family.
set -u

_PKGDIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=installer/scripts/pkgmanager.sh
. "$_PKGDIR/pkgmanager.sh"

hyprtk_enable_extra_repos
echo "extra repositories checked for $HYPRTK_PM"
