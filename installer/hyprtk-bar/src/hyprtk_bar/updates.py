"""Package-update indicator: polls updates.sh and shows the pending count.

Replaces the old waybar ``custom/updates`` module — a Nerd Font glyph with the
pending-update count, colored by threshold (green/yellow/red), a hover tooltip,
and a left-click that runs the update installer (which self-launches in a
detected terminal). Both scripts are distro-agnostic: they detect the package
manager and query/apply updates accordingly. The count, CSS class and tooltip
come from the script's waybar-style JSON output.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · updates
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import json
import logging
import os
import shlex
import threading

from . import compat  # noqa: E402
from .compat import GLib, Gtk  # noqa: E402

from .config import icon_size_for, resolve_script, SCRIPTS_DIR  # noqa: E402
from .popup import bind_hover_tooltip  # noqa: E402
from . import proc  # noqa: E402
from .widgets import Glyph, HoverButton  # noqa: E402

log = logging.getLogger("hyprtk_bar.updates")

_GLYPH = "\uf0ab"  # updates icon

# The updates script runs AUTOMATICALLY on a timer, so it must come from one of
# the bar/repo-owned locations — never an arbitrary path from a config.
_ALLOWED_SCRIPT_ROOTS = (
    os.path.expanduser("~/hyprtk/installer/scripts"),
    os.path.expanduser("~/.local/share/hyprtk-bar"),
    os.path.expanduser("~/.local/bin"),
    str(SCRIPTS_DIR),
)


def _allowed_script(path: str):
    """Return the resolved script path when it's an existing file in a
    bar/repo-owned root, else None."""
    try:
        resolved = os.path.realpath(path)
    except OSError:
        return None
    if not os.path.isfile(resolved):
        return None
    if resolved.startswith(os.path.expanduser("~/hyprtk/installer/scripts") + os.sep):
        return resolved
    for root in _ALLOWED_SCRIPT_ROOTS[1:]:
        if resolved == root or resolved.startswith(root + os.sep):
            return resolved
    return None


# Characters that give a string shell semantics. The install command is run as
# argv (never via a shell), so any of these means we cannot faithfully exec it —
# reject and fall back to the bundled installer rather than risk injection.
_SHELL_META = set(";&|`$(){}<>\n\\")


def _install_argv(command: str):
    """Parse a configured install command into a safe argv list, else None.

    Requires no shell metacharacters and at least one element resolving to an
    allowlisted script; the script element is rewritten to its absolute real
    path and ``argv[0]`` is resolved on PATH.
    """
    if not command or any(ch in _SHELL_META for ch in command):
        return None
    try:
        parts = shlex.split(command)
    except ValueError:
        return None
    if not parts:
        return None
    found = False
    for i, token in enumerate(parts):
        expanded = os.path.expanduser(token)
        if "/" in expanded:
            script = _allowed_script(expanded)
            if script:
                parts[i] = script
                found = True
    if not found:
        return None
    parts[0] = proc.resolve_binary(parts[0]) or parts[0]
    return parts


class Updates(HoverButton):
    """Pending-update count with a hover tooltip; click runs the installer."""

    def __init__(self, cfg: dict, ipc=None):
        super().__init__("updates", vertical=False, spacing=6)
        u = cfg.get("updates") or {}
        self._interval = max(5, int(u.get("interval", 60)))
        # The timer-run script is allowlisted (never an arbitrary config path).
        # Defaults to the bundled distro-agnostic updates.sh, falling back to
        # the full-dotfiles copy — so the module works standalone on any distro.
        configured = os.path.expanduser(
            u.get("script") or str(resolve_script("updates.sh", "installer", "scripts", "updates.sh"))
        )
        self._script = _allowed_script(configured or "")
        if not self._script:
            if os.path.exists(configured):
                # Present but outside the allowlist — a real misconfiguration.
                log.warning(
                    "updates: refusing non-allowlisted script %r; polling disabled",
                    configured,
                )
            else:
                # Not installed at all (standalone install without the dotfiles)
                # — expected, so stay quiet and just show the module as "?".
                log.info("updates: no script at %r; polling disabled", configured)
            self._interval = 3600
        configured_install = u.get(
            "install_command",
            str(resolve_script("installupdates.sh", "installer", "scripts", "installupdates.sh")),
        ) or ""
        # The install command comes from user config, so it is never run through
        # a shell: it is parsed to argv and only accepted when it contains no
        # shell metacharacters AND at least one element resolves to an
        # allowlisted script (so a legit wrapper like
        # `alacritty -e ~/hyprtk/.../installupdates.sh` is fine, but a
        # synced/malicious config cannot smuggle in extra commands on
        # left-click). Empty/unsafe falls back to the bundled installer.
        self._install_argv = _install_argv(configured_install)
        if not self._install_argv:
            if configured_install:
                log.warning(
                    "updates: refusing install command %r; using bundled installer",
                    configured_install,
                )
            self._install_argv = _install_argv(
                str(resolve_script("installupdates.sh", "installer", "scripts", "installupdates.sh"))
            ) or []
        font_cfg = cfg.get("font") or {}
        self._glyph = Glyph(_GLYPH, "accent-icon")
        self._glyph.set_pixel_size(
            icon_size_for(font_cfg.get("size", 16), font_cfg.get("icon_size", 0))
        )
        compat.pack_start(self.box, self._glyph, False, False, 0)

        self._label = Gtk.Label(label="")
        compat.add_class(self._label, "updates-value")
        compat.pack_start(self.box, self._label, False, False, 0)

        self._tip = ""
        self._busy = False
        self._update()
        self._tick_id = GLib.timeout_add_seconds(self._interval, self._tick)
        bind_hover_tooltip(self, cfg, lambda: self._tip)

    def apply_font(self, font_size, icon_size=0) -> None:
        self._glyph.set_pixel_size(icon_size_for(font_size, icon_size))

    def shutdown(self) -> None:
        """Stop the poll timer so a rebuilt module doesn't keep running pacman."""
        if self._tick_id is not None:
            GLib.source_remove(self._tick_id)
            self._tick_id = None

    def _tick(self) -> bool:
        self._update()
        return GLib.SOURCE_CONTINUE

    def _update(self) -> None:
        # One check at a time: the script can outrun _interval (a slow package
        # manager), and stacking worker threads would spawn overlapping
        # pacman/checkupdates and apply results out of order.
        if self._busy:
            return
        self._busy = True
        # Run the (potentially slow) update check on a worker thread so the bar
        # never stalls waiting for pacman/checkupdates on the UI thread.
        def _work():
            try:
                text, css, tooltip = self._query()
            except Exception:
                log.exception("updates check failed")
                text, css, tooltip = "?", "green", ""
            GLib.idle_add(self._apply, text, css, tooltip)

        threading.Thread(target=_work, daemon=True).start()

    def _apply(self, text: str, css: str, tooltip: str) -> None:
        self._busy = False
        self._label.set_text(text)
        ctx = compat.style_context(self._label)
        if css == "red":
            ctx.add_class("high")
            ctx.remove_class("warn")
        elif css == "yellow":
            ctx.add_class("warn")
            ctx.remove_class("high")
        else:
            ctx.remove_class("high")
            ctx.remove_class("warn")
        self._tip = tooltip or f"{text} update(s)"
        return GLib.SOURCE_REMOVE

    def _query(self) -> tuple[str, str, str]:
        if not self._script:
            return "?", "green", ""
        out = proc.run_checked([self._script], timeout=30).strip()
        try:
            data = json.loads(out)
            return (
                str(data.get("text", "0")),
                str(data.get("class", "green")),
                str(data.get("tooltip", "")),
            )
        except (ValueError, TypeError):
            return "?", "green", ""

    def _on_button_press(self, _widget, event):
        if event.button == 1 and self._install_argv:
            # Validated to an argv list at construction; no shell involved.
            proc.spawn_argv(self._install_argv)
        return True