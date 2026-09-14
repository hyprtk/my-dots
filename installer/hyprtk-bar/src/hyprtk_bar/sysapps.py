"""System-preferred application resolvers for quick links.

Quick links fall back to the session's preferred apps when their command is
left empty ("System default"): the default terminal, file manager and web
browser are resolved from environment variables, XDG/GNOME settings and a
candidate list — so a standalone install works on any distro without hardcoding
alacritty/thunar/firefox.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · sysapps
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import os
import subprocess

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import Gio, GLib  # noqa: E402

from . import proc  # noqa: E402


def _bare_command(line: str) -> str:
    """First whitespace token of a command line, as a bare binary name."""
    if not line:
        return ""
    return line.split()[0].rsplit("/", 1)[-1]


def _command_from_desktop(desktop_id: str) -> str:
    """Resolve a ``.desktop`` id to its bare launch command."""
    try:
        info = Gio.DesktopAppInfo.new(desktop_id)
        line = info.get_commandline() if info is not None else None
    except (TypeError, GLib.Error):
        line = None
    if line:
        line = " ".join(t for t in line.split() if not t.startswith("%"))
    return _bare_command(line or "")


def default_browser_command() -> str:
    try:
        out = subprocess.run(
            ["xdg-settings", "get", "default-web-browser"],
            capture_output=True,
            text=True,
            timeout=2,
        ).stdout.strip()
        if out.endswith(".desktop"):
            cmd = _command_from_desktop(out)
            if cmd:
                return cmd
    except (subprocess.SubprocessError, OSError):
        pass
    for name in ("brave", "firefox", "chromium", "google-chrome",
                 "librewolf", "vivaldi", "epiphany"):
        if proc.resolve_binary(name):
            return name
    return ""


def default_terminal_command() -> str:
    for var in ("TERMINAL", "TERM_TERMINAL"):
        value = os.environ.get(var)
        if value:
            return _bare_command(value)
    try:
        settings = Gio.Settings.new("org.gnome.desktop.default-applications.terminal")
        exec_ = settings.get_string("exec")
        if exec_:
            return _bare_command(exec_)
    except (TypeError, GLib.Error):
        pass
    for name in ("alacritty", "kitty", "foot", "wezterm", "xfce4-terminal",
                 "gnome-terminal", "konsole", "xterm"):
        if proc.resolve_binary(name):
            return name
    return ""


def default_filemanager_command() -> str:
    try:
        out = subprocess.run(
            ["xdg-mime", "query", "default", "inode/directory"],
            capture_output=True,
            text=True,
            timeout=2,
        ).stdout.strip()
    except (subprocess.SubprocessError, OSError):
        out = ""
    if out.endswith(".desktop"):
        cmd = _command_from_desktop(out)
        if cmd:
            return cmd
    for name in ("thunar", "nautilus", "nemo", "dolphin", "pcmanfm", "caja"):
        if proc.resolve_binary(name):
            return name
    return ""
