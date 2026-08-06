from __future__ import annotations

import subprocess
from pathlib import Path

from gi.repository import Adw, Gtk

from .. import paths
from ..colors import parse_wal_colors
from ..widgets.color_button import ColorButton


class IconsPage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(title="Icons", **kwargs)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        # pywal auto mode
        auto_title = Gtk.Label(label="Pywal Auto-Color")
        auto_title.add_css_class("heading")
        auto_title.set_xalign(0)
        box.append(auto_title)

        auto_desc = Gtk.Label(
            label="Automatically match papirus folder color to pywal color4. "
            "Uses Euclidean distance to find the closest preset."
        )
        auto_desc.set_xalign(0)
        auto_desc.set_wrap(True)
        box.append(auto_desc)

        apply_auto_btn = Gtk.Button(label="Apply Pywal Color Match")
        apply_auto_btn.add_css_class("suggested-action")
        apply_auto_btn.connect("clicked", self._apply_auto)
        box.append(apply_auto_btn)

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        box.append(sep)

        # manual color picker
        manual_title = Gtk.Label(label="Manual Folder Color")
        manual_title.add_css_class("heading")
        manual_title.set_xalign(0)
        box.append(manual_title)

        # color grid of popular papirus colors
        color_names = [
            ("black", "#000000"), ("blue", "#2196F3"), ("bluegrey", "#607D8B"),
            ("brown", "#795548"), ("cyan", "#00BCD4"), ("green", "#4CAF50"),
            ("grey", "#9E9E9E"), ("indigo", "#3F51B5"), ("magenta", "#E91E63"),
            ("nordic", "#2E3440"), ("orange", "#FF9800"), ("pink", "#E91E63"),
            ("purple", "#9C27B0"), ("red", "#F44336"), ("teal", "#009688"),
            ("violet", "#673AB7"), ("white", "#FFFFFF"), ("yellow", "#FFEB3B"),
        ]

        self._color_buttons: dict[str, ColorButton] = {}
        grid = Gtk.Grid()
        grid.set_column_spacing(8)
        grid.set_row_spacing(8)

        for i, (name, hex_val) in enumerate(color_names):
            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            col.set_halign(Gtk.Align.CENTER)

            cb = ColorButton(hex_val)
            cb.set_size_request(40, 40)
            cb.connect_color_changed(lambda btn, h, n=name: self._apply_preset(n))
            col.append(cb)

            lbl = Gtk.Label(label=name)
            lbl.set_markup(f'<small>{name}</small>')
            col.append(lbl)

            grid.attach(col, i % 6, i // 6, 1, 1)

        box.append(grid)

        # custom hex input
        custom_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self._custom_entry = Adw.EntryRow(title="Custom hex color")
        self._custom_entry.set_text("#2196F3")
        custom_box.append(self._custom_entry)

        apply_custom_btn = Gtk.Button(label="Apply")
        apply_custom_btn.connect("clicked", self._apply_custom)
        custom_box.append(apply_custom_btn)
        box.append(custom_box)

        # current color display
        self._current_label = Gtk.Label(label="Current folder color: ...")
        self._current_label.set_xalign(0)
        box.append(self._current_label)

        self._load_current()

        toolbar.set_content(box)
        self.set_child(toolbar)

    def _load_current(self):
        color_file = paths.HYPRTK / "configs" / "papirus-icons" / "scripts" / "folder-color.txt"
        if color_file.exists():
            color = color_file.read_text().strip()
            self._current_label.set_text(f"Current folder color: {color}")

    def _apply_auto(self, btn):
        script = str(paths.CHANGE_ICONS_SH)
        if Path(script).is_file():
            subprocess.Popen(["bash", script], start_new_session=True)
            self._load_current()

    def _apply_preset(self, color_name: str):
        script = str(paths.HYPRTK / "configs" / "papirus-icons" / f"{color_name}.sh")
        if Path(script).is_file():
            subprocess.Popen(["bash", script], start_new_session=True)
            self._load_current()

    def _apply_custom(self, btn):
        hex_val = self._custom_entry.get_text().strip()
        if not hex_val.startswith("#"):
            hex_val = f"#{hex_val}"
        if len(hex_val) != 7:
            return
        # find closest named color or use papirus-folders directly
        subprocess.Popen(
            ["papirus-folders", "-C", hex_val.lstrip("#"), "--theme", "Papirus-Dark"],
            start_new_session=True,
        )
        self._current_label.set_text(f"Current folder color: {hex_val}")
