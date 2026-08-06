from __future__ import annotations

import os
import subprocess
from pathlib import Path

from gi.repository import Adw, Gio, GLib, Gtk

from .. import paths
from ..widgets import get_children, remove_all_children


class WallpaperPage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(title="Wallpaper", **kwargs)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        # current wallpaper display
        self._current_img = Gtk.Picture()
        self._current_img.set_size_request(-1, 200)
        self._current_img.add_css_class("preview-frame")
        self._current_img.set_content_fit(Gtk.ContentFit.CONTAIN)
        box.append(self._current_img)

        # wallpaper directory chooser
        dir_row = Adw.ActionRow(title="Wallpaper Directory")
        self._dir_label = Gtk.Label(label=str(paths.WALLPAPER_DIRS[0]))
        self._dir_label.set_ellipsize(3)
        dir_row.add_suffix(self._dir_label)
        dir_btn = Gtk.Button(label="Choose")
        dir_btn.add_css_class("flat")
        dir_btn.connect("clicked", self._choose_dir)
        dir_row.add_suffix(dir_btn)
        box.append(dir_row)

        # apply button
        apply_btn = Gtk.Button(label="Apply Wallpaper")
        apply_btn.add_css_class("suggested-action")
        apply_btn.connect("clicked", self._apply_selected)
        box.append(apply_btn)

        # thumbnail flow box
        self._flow = Gtk.FlowBox()
        self._flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._flow.set_column_spacing(8)
        self._flow.set_row_spacing(8)
        self._flow.set_homogeneous(True)
        self._flow.set_min_children_per_line(2)
        self._flow.set_max_children_per_line(2)

        scroll = Gtk.ScrolledWindow()
        scroll.set_child(self._flow)
        scroll.set_vexpand(True)
        scroll.set_min_content_height(300)
        box.append(scroll)

        toolbar.set_content(box)
        self.set_child(toolbar)

        self._wallpaper_dir = Path(str(paths.WALLPAPER_DIRS[0]))
        self._selected_path: Path | None = None
        self._load_current()
        self._load_thumbnails()

    def _load_current(self):
        wal_file = paths.WAL_CACHE / "wal"
        if wal_file.exists():
            wp = wal_file.read_text().strip()
            if wp and os.path.isfile(wp):
                self._current_img.set_filename(wp)
                return
        fallback = paths.HYPRTK / "assets" / "Wallpapers" / "default.png"
        if fallback.exists():
            self._current_img.set_filename(str(fallback))

    def _load_thumbnails(self):
        remove_all_children(self._flow)

        if not self._wallpaper_dir.exists():
            return

        images = sorted(
            p for p in self._wallpaper_dir.iterdir()
            if p.suffix.lower() in paths.IMAGE_EXTS
        )[:100]

        for img_path in images:
            btn = Gtk.Button()
            btn.add_css_class("flat")
            btn.set_size_request(160, 120)

            pic = Gtk.Picture()
            pic.set_filename(str(img_path))
            pic.set_size_request(150, 100)
            pic.set_content_fit(Gtk.ContentFit.COVER)
            btn.set_child(pic)

            btn._wallpaper_path = img_path
            btn.connect("clicked", self._on_thumb_click, img_path)
            self._flow.append(btn)

    def _on_thumb_click(self, btn, path: Path):
        self._selected_path = path
        self._current_img.set_filename(str(path))

    def _choose_dir(self, btn):
        dialog = Gtk.FileDialog()
        dialog.set_title("Select Wallpaper Directory")
        folder = Gio.File.new_for_path(str(self._wallpaper_dir))
        dialog.select_folder(self.get_root(), None, self._on_dir_chosen)

    def _on_dir_chosen(self, dialog, result):
        try:
            folder = dialog.select_folder_finish(result)
            if folder:
                self._wallpaper_dir = Path(folder.get_path())
                self._dir_label.set_text(str(self._wallpaper_dir))
                self._load_thumbnails()
        except GLib.Error:
            pass

    def _apply_selected(self, btn):
        if not self._selected_path:
            return
        script = str(paths.WALLPAPER_COLORS_SH)
        if not os.path.isfile(script):
            return
        subprocess.Popen(
            ["bash", script, str(self._selected_path)],
            start_new_session=True,
        )
        self._load_current()
        # refresh app CSS after pywal finishes
        GLib.timeout_add(3000, self._refresh_app_css)

    def _refresh_app_css(self):
        from ..app import _build_app_css
        from gi.repository import Gdk

        provider = Gtk.CssProvider()
        provider.load_from_data(_build_app_css().encode())
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1,
        )
        return False
