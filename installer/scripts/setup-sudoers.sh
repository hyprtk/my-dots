#!/bin/bash
# ── hyprtk-bar least-privilege sudo ───────────────────────────────────────
# Installs /etc/sudoers.d/hyprtk-bar granting the desktop user passwordless
# access ONLY to the exact commands the bar invokes non-interactively:
#   - dmidecode (the system monitor's DIMM readout)
#   - hyprtk-system-kill (killing SYSTEM-owned processes from the monitor's
#     Apps page — user-owned processes are killed directly, never via sudo)
# Never NOPASSWD: ALL.
#
# Usage (as the desktop user, or as root):
#   sudo bash setup-sudoers.sh
#
# Idempotent. The helper is installed to /usr/local/bin and the drop-in is
# validated with visudo before it is kept.
# ──────────────────────────────────────────────────────────────────────────

set -euo pipefail

SUDOERS_D="/etc/sudoers.d/hyprtk-bar"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_SRC="$SCRIPT_DIR/hyprtk-system-kill"
HELPER_DST="/usr/local/bin/hyprtk-system-kill"

if [ "$(id -u)" -ne 0 ]; then
    echo "error: this script must run as root (e.g. sudo bash setup-sudoers.sh)" >&2
    exit 1
fi

# Resolve the desktop user: the sudo invoker, a pkexec caller, else $USER.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
elif [ -n "${PKEXEC_UID:-}" ]; then
    TARGET_USER="$(id -nu "$PKEXEC_UID" 2>/dev/null || true)"
else
    TARGET_USER="${USER:-$(id -un)}"
fi
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    echo "error: cannot determine the desktop user (run it via sudo as that user)" >&2
    exit 1
fi

# Install the scoped system-kill helper (the bar invokes it via sudo -n).
if [ -f "$HELPER_SRC" ]; then
    install -m 0755 "$HELPER_SRC" "$HELPER_DST"
    echo "ok: installed $HELPER_DST"
else
    echo "warn: $HELPER_SRC not found; skipping helper install (system-process kill unavailable)"
fi

CONTENT="# hyprtk-bar: passwordless sudo for the desktop user.
# Least privilege: only the system monitor's dmidecode DIMM readout and the
# scoped hyprtk-system-kill helper run via sudo -n (see monitor_data.py /
# setup-sudoers.sh). Everything else uses pkexec, which still prompts.
#
# Extend this list ONLY with the exact commands the bar actually invokes
# non-interactively; never grant NOPASSWD: ALL.
${TARGET_USER} ALL=(root) NOPASSWD: /usr/bin/dmidecode
${TARGET_USER} ALL=(root) NOPASSWD: ${HELPER_DST}"

umask 0377
printf '%s\n' "$CONTENT" > "$SUDOERS_D"
chown root:root "$SUDOERS_D"
chmod 440 "$SUDOERS_D"

if ! visudo -c -f "$SUDOERS_D" >/dev/null 2>&1; then
    echo "error: sudoers validation failed; removing invalid drop-in" >&2
    rm -f "$SUDOERS_D"
    exit 1
fi

echo "ok: scoped passwordless sudo configured for '$TARGET_USER' ($SUDOERS_D)"

if sudo -u "$TARGET_USER" sudo -n dmidecode -t 17 < /dev/null >/dev/null 2>&1; then
    echo "ok: passwordless dmidecode verified for '$TARGET_USER'"
else
    echo "warn: could not verify passwordless dmidecode for '$TARGET_USER'"
fi

if [ -x "$HELPER_DST" ] && sudo -u "$TARGET_USER" sudo -n "$HELPER_DST" 2>/dev/null; then
    echo "ok: passwordless hyprtk-system-kill verified for '$TARGET_USER'"
else
    echo "warn: could not verify passwordless hyprtk-system-kill (expected: rejects an empty pid)"
fi