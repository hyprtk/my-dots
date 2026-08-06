from __future__ import annotations

import os
import subprocess
from pathlib import Path

from gi.repository import Adw, Gtk

from .. import paths
from ..widgets import remove_all_children


class RofiPage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(title="Rofi Themes", **kwargs)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        # active variant indicator
        self._active_label = Gtk.Label(label="Active variant: ...")
        self._active_label.set_xalign(0)
        self._active_label.add_css_class("heading")
        box.append(self._active_label)

        # variant list
        self._variant_list = Gtk.ListBox()
        self._variant_list.set_selection_mode(Gtk.SelectionMode.NONE)
        scroll = Gtk.ScrolledWindow()
        scroll.set_child(self._variant_list)
        scroll.set_vexpand(True)
        box.append(scroll)

        # apply button
        apply_btn = Gtk.Button(label="Sync Rofi to Waybar Theme")
        apply_btn.add_css_class("suggested-action")
        apply_btn.connect("clicked", self._sync_to_waybar)
        box.append(apply_btn)

        toolbar.set_content(box)
        self.set_child(toolbar)

        self._refresh()

    def _refresh(self):
        self._load_active()
        self._load_variants()

    def _load_active(self):
        link = paths.ROFI_VARIANT_LINK
        if link.is_symlink():
            target = os.readlink(str(link))
            name = Path(target).stem
            self._active_label.set_text(f"Active variant: {name}")
        else:
            self._active_label.set_text("Active variant: (none)")

    def _load_variants(self):
        remove_all_children(self._variant_list)

        variants_dir = paths.ROFI_VARIANTS
        if not variants_dir.exists():
            return

        for f in sorted(variants_dir.glob("*.rasi")):
            row = Adw.ActionRow(title=f.stem)
            row.set_activatable(True)
            row.add_css_class("sidebar-row")
            row._variant_path = f

            # show active indicator
            link = paths.ROFI_VARIANT_LINK
            if link.is_symlink() and os.readlink(str(link)) == str(f):
                badge = Gtk.Label(label="Active")
                badge.add_css_class("success")
                row.add_suffix(badge)

            row.connect("activated", self._on_variant_click)
            self._variant_list.append(row)

    def _on_variant_click(self, row):
        variant_path = row._variant_path
        link = paths.ROFI_VARIANT_LINK
        link.unlink(missing_ok=True)
        os.symlink(str(variant_path), str(link))
        self._refresh()

    def _sync_to_waybar(self, btn):
        sync_script = str(paths.SYNC_ROFI_SH)
        if os.path.isfile(sync_script):
            subprocess.Popen(["bash", sync_script], start_new_session=True)
            self._refresh()
