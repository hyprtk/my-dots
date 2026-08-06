from __future__ import annotations

import os
import subprocess
from pathlib import Path

from gi.repository import Adw, GLib, Gtk

from .. import paths
from ..widgets import remove_all_children
from ..colors import get_color_name, parse_wal_colors
from ..widgets.color_grid import ColorGrid


class PywalPage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(title="Pywal Colors", **kwargs)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        # section title
        title = Gtk.Label(label="Current Pywal Palette")
        title.add_css_class("heading")
        title.set_xalign(0)
        box.append(title)

        # color grid
        self._grid = ColorGrid()
        self._grid.connect_color_selected(self._on_color_selected)
        box.append(self._grid)

        # selected color detail
        self._detail_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self._detail_label = Gtk.Label(label="Click a color to inspect")
        self._detail_label.set_xalign(0)
        self._detail_box.append(self._detail_label)
        box.append(self._detail_box)

        # color scheme section
        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        box.append(sep)

        scheme_label = Gtk.Label(label="Colorscheme Files")
        scheme_label.add_css_class("heading")
        scheme_label.set_xalign(0)
        box.append(scheme_label)

        self._scheme_list = Gtk.ListBox()
        self._scheme_list.set_selection_mode(Gtk.SelectionMode.NONE)
        scroll = Gtk.ScrolledWindow()
        scroll.set_child(self._scheme_list)
        scroll.set_vexpand(True)
        box.append(scroll)

        # re-run wal button
        rerun_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self._wal_dir_label = Gtk.Label(label=str(paths.WALLPAPER_DIRS[0]))
        self._wal_dir_label.set_ellipsize(3)
        rerun_box.append(self._wal_dir_label)

        choose_dir_btn = Gtk.Button(label="Dir")
        choose_dir_btn.add_css_class("flat")
        choose_dir_btn.connect("clicked", self._choose_wal_dir)
        rerun_box.append(choose_dir_btn)

        rerun_btn = Gtk.Button(label="Re-run wal")
        rerun_btn.add_css_class("suggested-action")
        rerun_btn.connect("clicked", self._rerun_wal)
        rerun_box.append(rerun_btn)

        refresh_btn = Gtk.Button(label="Refresh")
        refresh_btn.add_css_class("flat")
        refresh_btn.connect("clicked", lambda b: self._refresh())
        rerun_box.append(refresh_btn)
        box.append(rerun_box)

        toolbar.set_content(box)
        self.set_child(toolbar)

        self._wal_dir = Path(str(paths.WALLPAPER_DIRS[0]))
        # refresh colors each time page is shown
        self.connect("map", lambda w: self._refresh())

    def _refresh(self):
        colors = parse_wal_colors()
        if colors:
            self._grid.set_colors(colors)
        self._load_schemes()

    def _load_schemes(self):
        remove_all_children(self._scheme_list)

        # pywal stores cached schemes in ~/.cache/wal/schemes/
        schemes_dir = paths.WAL_CACHE / "schemes"
        if not schemes_dir.exists():
            return

        for f in sorted(schemes_dir.iterdir())[:30]:
            row = Adw.ActionRow(title=f.name)
            row.set_activatable(True)
            row.add_css_class("sidebar-row")
            row._scheme_path = f
            row.connect("activated", self._on_scheme_click)
            self._scheme_list.append(row)

    def _on_scheme_click(self, row):
        scheme_path = row._scheme_path
        subprocess.Popen(
            ["wal", "--theme", str(scheme_path)],
            start_new_session=True,
        )
        self._refresh()

    def _on_color_selected(self, index: int, key: str):
        colors = parse_wal_colors()
        val = colors.get(key, "N/A")
        name = get_color_name(index)
        self._detail_label.set_text(f"{name} ({key}): {val}")

    def _choose_wal_dir(self, btn):
        dialog = Gtk.FileDialog()
        dialog.set_title("Select Wallpaper Directory for wal")
        dialog.select_folder(self.get_root(), None, self._on_dir_chosen)

    def _on_dir_chosen(self, dialog, result):
        try:
            folder = dialog.select_folder_finish(result)
            if folder:
                self._wal_dir = Path(folder.get_path())
                self._wal_dir_label.set_text(str(self._wal_dir))
        except Exception:
            pass

    def _rerun_wal(self, btn):
        subprocess.Popen(
            ["wal", "-i", str(self._wal_dir)],
            start_new_session=True,
        )
        # wait for wal to finish before refreshing
        GLib.timeout_add(2000, self._do_refresh)

    def _do_refresh(self):
        self._refresh()
        return False  # don't repeat
