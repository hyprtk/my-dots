"""Application discovery, categorization, search, and launch for hyprtk-menu."""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · apps
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────


import os
import re
import shlex
import subprocess

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")

from gi.repository import Gio

# Map raw XDG categories to our display-sidebar categories.
CATEGORY_MAP = {
    "Utility": "Accessories",
    "Accessibility": "Accessories",
    "Archiving": "Accessories",
    "Development": "Development",
    "IDE": "Development",
    "Building": "Development",
    "Debugger": "Development",
    "Education": "Education",
    "Science": "Science",
    "Game": "Games",
    "ActionGame": "Games",
    "AdventureGame": "Games",
    "ArcadeGame": "Games",
    "BoardGame": "Games",
    "CardGame": "Games",
    "LogicGame": "Games",
    "SportGame": "Games",
    "StrategyGame": "Games",
    "Graphics": "Graphics",
    "2DGraphics": "Graphics",
    "3DGraphics": "Graphics",
    "RasterGraphics": "Graphics",
    "VectorGraphics": "Graphics",
    "Network": "Internet",
    "WebBrowser": "Internet",
    "Email": "Internet",
    "Chat": "Internet",
    "InstantMessaging": "Internet",
    "AudioVideo": "Multimedia",
    "Audio": "Multimedia",
    "Video": "Multimedia",
    "Music": "Multimedia",
    "Player": "Multimedia",
    "Office": "Office",
    "PIM": "Office",
    "Presentation": "Office",
    "Spreadsheet": "Office",
    "WordProcessor": "Office",
    "System": "System",
    "Monitor": "System",
    "TerminalEmulator": "System",
    "FileManager": "System",
    "Settings": "Settings",
}

# Display order for the sidebar. "All" / "Favorites" / "Recently Used" are
# virtual categories handled by the menu itself.
CATEGORY_ORDER = [
    "All",
    "Favorites",
    "Recently Used",
    "Accessories",
    "Development",
    "Education",
    "Games",
    "Graphics",
    "Internet",
    "Multimedia",
    "Office",
    "Science",
    "Settings",
    "System",
]


class AppEntry:
    __slots__ = (
        "id",
        "name",
        "generic_name",
        "comment",
        "keywords",
        "icon",
        "info",
        "categories",
    )

    def __init__(self, info):
        self.info = info
        self.id = info.get_id()
        self.name = info.get_name() or ""
        self.generic_name = info.get_generic_name() or ""
        self.comment = info.get_description() or ""
        self.keywords = list(info.get_keywords() or [])
        self.icon = info.get_icon()
        self.categories = self._map_categories(info.get_categories() or "")

    def _map_categories(self, raw):
        result = set()
        for chunk in raw.split(";"):
            chunk = chunk.strip()
            mapped = CATEGORY_MAP.get(chunk)
            if mapped:
                result.add(mapped)
        if not result:
            result.add("Accessories")
        return result

    def matches(self, query):
        query = query.strip().lower()
        if not query:
            return True
        haystack = " ".join(
            [self.name, self.generic_name, self.comment] + self.keywords
        ).lower()
        return query in haystack


def get_data_dirs():
    dirs = []
    data_home = os.environ.get("XDG_DATA_HOME")
    if data_home:
        dirs.append(data_home)
    data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    dirs.extend(d for d in data_dirs.split(":") if d)
    home_apps = os.path.expanduser("~/.local/share/applications")
    if home_apps not in dirs:
        dirs.append(home_apps)
    return dirs


def scan_apps():
    """Scan all XDG applications dirs for .desktop entries."""
    entries = []
    seen = set()
    for base in get_data_dirs():
        app_dir = os.path.join(base, "applications")
        if not os.path.isdir(app_dir):
            continue
        for root, _dirs, files in os.walk(app_dir):
            for filename in files:
                if not filename.endswith(".desktop"):
                    continue
                path = os.path.join(root, filename)
                if path in seen:
                    continue
                seen.add(path)
                try:
                    info = Gio.DesktopAppInfo.new_from_filename(path)
                except Exception:
                    continue
                if info is None or not info.should_show:
                    continue
                entries.append(AppEntry(info))
    entries.sort(key=lambda entry: entry.name.lower())
    return entries


def _find_terminal():
    for var in ("TERMINAL", "TERM_TERMINAL"):
        terminal = os.environ.get(var)
        if terminal:
            return terminal
    try:
        settings = Gio.Settings.new(
            "org.gnome.desktop.default-applications.terminal"
        )
        exec_ = settings.get_string("exec")
        if exec_:
            return exec_
    except Exception:
        pass
    for candidate in (
        "alacritty",
        "kitty",
        "foot",
        "xfce4-terminal",
        "wezterm",
        "konsole",
        "gnome-terminal",
    ):
        if _has_bin(candidate):
            return candidate
    return None


def _has_bin(name):
    for directory in os.environ.get("PATH", "").split(":"):
        if directory and os.path.isfile(os.path.join(directory, name)):
            return True
    return False


def _terminal_argv(term, command_argv):
    """Wrap a command's argv for a terminal emulator without a shell.

    The fallback launch path never builds a shell string: .desktop Exec= lines
    are untrusted input and would otherwise be re-parsed by `sh -c`.
    """
    if not command_argv:
        return command_argv
    name = os.path.basename(shlex.split(term)[0]).lower()
    if name == "foot":
        return shlex.split(term) + command_argv
    if name == "wezterm":
        return shlex.split(term) + ["start", "--"] + command_argv
    if name in ("gnome-terminal", "kgx", "ptyxis"):
        return shlex.split(term) + ["--"] + command_argv
    return shlex.split(term) + ["-e"] + command_argv


def _spawn(argv):
    """Detach an argv list (never a shell string)."""
    try:
        subprocess.Popen(argv, start_new_session=True)
        return True
    except Exception:
        return False


def launch_app(entry):
    """Launch an app. Returns True on success."""
    try:
        if entry.info.launch(None, None):
            return True
    except Exception:
        pass
    # Fallback: run the Exec line directly as argv (no shell).
    cmdline = entry.info.get_commandline() or ""
    cmdline = re.sub(r"%[fFuUdDnNickvm]", "", cmdline).strip()
    if not cmdline:
        return False
    argv = shlex.split(cmdline)
    if not argv:
        return False
    if entry.info.get_boolean("Terminal"):
        terminal = _find_terminal()
        if not terminal:
            return False
        argv = _terminal_argv(terminal, argv)
    return _spawn(argv)
