from __future__ import annotations

import os
import subprocess
from pathlib import Path

from gi.repository import Adw, Gtk

from .. import paths
from ..widgets import remove_all_children


class WaybarPage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(title="Waybar Themes", **kwargs)
        self._active_theme = ""

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        # active theme indicator
        self._active_label = Gtk.Label(label="Active theme: ...")
        self._active_label.set_xalign(0)
        self._active_label.add_css_class("heading")
        box.append(self._active_label)

        # theme list
        self._theme_list = Gtk.ListBox()
        self._theme_list.set_selection_mode(Gtk.SelectionMode.NONE)
        scroll = Gtk.ScrolledWindow()
        scroll.set_child(self._theme_list)
        scroll.set_vexpand(True)
        box.append(scroll)

        # launch button
        launch_btn = Gtk.Button(label="Apply & Restart Waybar")
        launch_btn.add_css_class("suggested-action")
        launch_btn.connect("clicked", self._launch_waybar)
        box.append(launch_btn)

        toolbar.set_content(box)
        self.set_child(toolbar)

        self._refresh()

    def _refresh(self):
        self._load_active()
        self._load_themes()

    def _load_active(self):
        cache = paths.THEME_STYLE_CACHE
        self._active_theme = ""
        if cache.exists():
            content = cache.read_text().strip()
            if ";" in content:
                parts = content.split(";")
                self._active_theme = Path(parts[0]).name
            else:
                self._active_theme = content
            self._active_label.set_text(f"Active theme: {self._active_theme}")
        else:
            self._active_label.set_text("Active theme: (none)")

    def _load_themes(self):
        remove_all_children(self._theme_list)

        themes_dir = paths.WAYBAR_THEMES
        if not themes_dir.exists():
            return

        for d in sorted(themes_dir.iterdir()):
            if not d.is_dir():
                continue
            config_sh = d / "config.sh"
            style_css = d / "style.css"
            if not style_css.exists():
                continue

            name = d.name
            # read theme_name from config.sh if available
            display_name = name
            if config_sh.exists():
                for line in config_sh.read_text().splitlines():
                    if "theme_name" in line and "=" in line:
                        display_name = line.split("=", 1)[1].strip().strip("'\"")
                        break

            if display_name == name:
                row = Adw.ActionRow(title=display_name)
            else:
                row = Adw.ActionRow(title=display_name)
            row.set_activatable(True)
            row.add_css_class("sidebar-row")
            row._theme_dir = d

            # check if active
            if name == self._active_theme:
                badge = Gtk.Label(label="Active")
                badge.add_css_class("success")
                row.add_suffix(badge)

            row.connect("activated", self._on_theme_click)
            self._theme_list.append(row)

    def _on_theme_click(self, row):
        theme_dir = row._theme_dir
        theme_name = theme_dir.name

        # launch.sh expects: /THEME;/THEME (relative to themes/ dir, with leading /)
        cache = paths.THEME_STYLE_CACHE
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(f"/{theme_name};/{theme_name}")

        # sync rofi
        sync_script = str(paths.SYNC_ROFI_SH)
        if os.path.isfile(sync_script):
            subprocess.Popen(["bash", sync_script], start_new_session=True)

        self._refresh()

    def _launch_waybar(self, btn):
        launch_script = str(paths.WAYBAR_LAUNCH_SH)
        if os.path.isfile(launch_script):
            subprocess.Popen(["bash", launch_script], start_new_session=True)
